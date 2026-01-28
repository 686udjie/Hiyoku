//
//  MangaView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 4/29/25.
//

import AidokuRunner
import Combine
import SwiftUI

extension MangaView {
    @MainActor
    class ViewModel: ObservableObject {
        weak var source: AidokuRunner.Source?

        @Published var manga: AidokuRunner.Manga
        @Published var chapters: [AidokuRunner.Chapter] = []
        @Published var otherDownloadedChapters: [AidokuRunner.Chapter] = []

        @Published var readingHistory: [String: (page: Int, date: Int)] = [:]
        var downloadStatus: [String: DownloadStatus] {
            downloadTracker.downloadStatus
        }
        var downloadProgress: [String: Float] {
            downloadTracker.downloadProgress
        }

        @Published private var downloadTracker: DownloadStatusTracker

        @Published var bookmarked = false

        @Published var nextChapter: AidokuRunner.Chapter?
        @Published var readingInProgress = false
        @Published var allChaptersLocked = false
        @Published var allChaptersRead = false
        @Published var initialDataLoaded = false

        @Published var chapterSortOption: ChapterSortOption = .sourceOrder {
            didSet { resortChapters() }
        }
        @Published var chapterSortAscending = false {
            didSet { resortChapters() }
        }

        @Published var chapterFilters: [ChapterFilterOption] = [] {
            didSet { refilterChapters() }
        }
        @Published var chapterLangFilter: String? {
            didSet { refilterChapters() }
        }
        @Published var chapterScanlatorFilter: [String] = [] {
            didSet { refilterChapters() }
        }

        @Published var chapterTitleDisplayMode: ChapterTitleDisplayMode

        @Published var error: Error?

        private var fetchedDetails = false
        private var cancellables = Set<AnyCancellable>()

        init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga) {
            self.source = source
            self.manga = manga
            self.downloadTracker = DownloadStatusTracker(sourceId: manga.sourceKey, mangaId: manga.key)

            let key = "Manga.chapterDisplayMode.\(manga.uniqueKey)"
            self.chapterTitleDisplayMode = .init(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default

            setupDownloadTracker()
            setupNotifications()
        }

        private func setupNotifications() {
            NotificationCenter.default.publisher(for: .updateMangaDetails)
                .sink { [weak self] output in
                    guard
                        let self,
                        let manga = output.object as? AidokuRunner.Manga,
                        manga.sourceKey == self.manga.sourceKey,
                        manga.key == self.manga.key
                    else {
                        return
                    }
                    self.manga = manga
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .addToLibrary)
                .sink { [weak self] output in
                    guard
                        let self,
                        let manga = output.object as? Manga,
                        manga.key == self.manga.sourceKey + "." + self.manga.key
                    else {
                        return
                    }
                    Task {
                        await self.loadBookmarked()
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .migratedManga)
                .sink { [weak self] output in
                    guard
                        let self,
                        let migration = output.object as? (from: Manga, to: Manga),
                        migration.from.id == self.manga.key && migration.from.sourceId == manga.sourceKey,
                        let newSource = SourceManager.shared.source(for: migration.to.sourceId)
                    else { return }
                    self.source = newSource
                    self.source = newSource
                    self.manga = migration.to.toNew()
                    self.setupDownloadTracker()
                }
                .store(in: &cancellables)

            // history
            NotificationCenter.default.publisher(for: .updateHistory)
                .sink { [weak self] _ in
                    Task {
                        await self?.loadHistory()
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historyAdded)
                .sink { [weak self] output in
                    guard
                        let self,
                        let chapters = output.object as? [Chapter]
                    else { return }
                    let date = Int(Date().timeIntervalSince1970)
                    for chapter in chapters where chapter.mangaIdentifier == self.manga.identifier {
                        self.readingHistory[chapter.id] = (page: -1, date: date)
                    }
                    self.updateReadButton()
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historyRemoved)
                .sink { [weak self] output in
                    guard let self else { return }
                    if let chapters = output.object as? [Chapter] {
                        for chapter in chapters where chapter.mangaIdentifier == self.manga.identifier {
                            self.readingHistory.removeValue(forKey: chapter.id)
                        }
                    } else if
                        let manga = output.object as? Manga,
                        manga.identifier == self.manga.identifier
                    {
                        self.readingHistory = [:]
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .historySet)
                .sink { [weak self] output in
                    guard
                        let self,
                        let item = output.object as? (chapter: Chapter, page: Int),
                        item.chapter.mangaIdentifier == self.manga.identifier,
                        self.readingHistory[item.chapter.id]?.page != -1
                    else {
                        return
                    }
                    self.readingHistory[item.chapter.id] = (
                        page: item.page,
                        date: Int(Date().timeIntervalSince1970)
                    )
                    self.updateReadButton()
                }
                .store(in: &cancellables)

            // tracking
            NotificationCenter.default.publisher(for: .syncTrackItem)
                .sink { [weak self] output in
                    guard let self, let item = output.object as? TrackItem else { return }
                    Task {
                        if let tracker = TrackerManager.getTracker(id: item.trackerId) {
                            await TrackerManager.shared.syncProgressFromTracker(
                                tracker: tracker,
                                trackId: item.id,
                                manga: self.manga,
                                chapters: self.chapters
                            )
                        }
                    }
                }
                .store(in: &cancellables)

            // other downloaded chapters maintenance
            NotificationCenter.default.publisher(for: .downloadRemoved)
                .sink { [weak self] output in
                    self?.handleDownloadRemoved(output)
                }
                .store(in: &cancellables)
        }
    }
}

extension MangaView.ViewModel {
    func markOpened() async {
        if !UserDefaults.standard.bool(forKey: UserDefaultsKey.General.incognitoMode) {
            await MangaUpdateManager.shared.viewAllUpdates(of: manga)
        }
    }

    // fetch complete info for manga, called when view appears
    func fetchDetails() async {
        guard !fetchedDetails else { return }
        fetchedDetails = true

        if let cachedManga = CoreDataManager.shared.getManga(sourceId: self.manga.sourceKey, mangaId: self.manga.key) {
            self.manga = self.manga.copy(from: cachedManga.toNewManga())
        }

        let filters = CoreDataManager.shared.getMangaChapterFilters(
            sourceId: manga.sourceKey,
            mangaId: manga.key
        )
        chapterSortOption = .init(flags: filters.flags)
        chapterSortAscending = filters.flags & ChapterFlagMask.sortAscending != 0
        chapterFilters = ChapterFilterOption.parseOptions(flags: filters.flags)
        chapterLangFilter = filters.language
        chapterScanlatorFilter = filters.scanlators ?? []

        await loadBookmarked()
        await loadHistory()
        await fetchData()
    }

    // fetches manga data, from coredata if in library or from source if not
    func fetchData() async {
        let mangaId = manga.key
        let sourceKey = manga.sourceKey
        // Always try to load from DB first
        let dbChapters: [AidokuRunner.Chapter] = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getChapters(
                sourceId: sourceKey,
                mangaId: mangaId,
                context: context
            ).map {
                $0.toNewChapter()
            }
        }

        if !dbChapters.isEmpty {
            var newManga = self.manga
            newManga.chapters = dbChapters
            withAnimation {
                self.manga = newManga
                self.chapters = filteredChapters()
            }
        }

        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.hasLibraryManga(sourceId: sourceKey, mangaId: mangaId, context: context)
        }

        // If not in library, try to update from source
        if !inLibrary, let source {
            // load new data from source
            await source.partialMangaPublisher?.sink { @Sendable newManga in
                Task { @MainActor in
                    withAnimation {
                        self.manga = self.manga.copy(from: newManga)
                        self.chapters = self.filteredChapters()
                    }
                }
            }
            do {
                let newManga = try await source.getMangaUpdate(
                    manga: manga,
                    needsDetails: true,
                    needsChapters: true
                )

                // Cache fetched data to Core Data
                if newManga.chapters != nil {
                    let mangaToSave = self.manga
                    await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                        _ = CoreDataManager.shared.getOrCreateManga(mangaToSave, sourceId: sourceKey, context: context)
                        if let chapters = mangaToSave.chapters {
                            CoreDataManager.shared.setChapters(
                                chapters,
                                sourceId: sourceKey,
                                mangaId: mangaId,
                                context: context
                            )
                        }
                        try? context.save()
                    }
                }

                withAnimation {
                    manga = newManga
                    chapters = filteredChapters()
                }
            } catch {
                // only show error if we have no chapters
                if self.chapters.isEmpty {
                    withAnimation {
                        self.manga.chapters = []
                        self.chapters = []
                        self.error = error
                    }
                }
            }
            await source.partialMangaPublisher?.removeSink()
        }
        await fetchDownloadedChapters()
        await loadDownloadStatus()
        updateReadButton()
        initialDataLoaded = true
    }

    func fetchDownloadedChapters() async {
        let downloadedChapters = await DownloadManager.shared.getDownloadedChapters(for: manga.identifier)
            .filter { chapter in
                !(manga.chapters ?? chapters).contains(where: { $0.key.directoryName == chapter.chapterId.directoryName })
            }
            .map { $0.toChapter() }
            .sorted { (lhs: AidokuRunner.Chapter, rhs: AidokuRunner.Chapter) in
                // Primary sort: by chapter number if both have it
                if let lhsChapter = lhs.chapterNumber, let rhsChapter = rhs.chapterNumber {
                    if lhsChapter != rhsChapter {
                        return lhsChapter > rhsChapter
                    }
                    // If chapter numbers are equal, sort by volume number
                    if let lhsVolume = lhs.volumeNumber, let rhsVolume = rhs.volumeNumber {
                        return lhsVolume > rhsVolume
                    }
                }

                // Secondary sort: by volume number if only one has chapter number
                if let lhsVolume = lhs.volumeNumber, let rhsVolume = rhs.volumeNumber {
                    return lhsVolume > rhsVolume
                }

                // Final fallback: alphabetical comparison of display titles
                let lhsTitle = lhs.title?.lowercased() ?? ""
                let rhsTitle = rhs.title?.lowercased() ?? ""
                return lhsTitle.localizedStandardCompare(rhsTitle) == .orderedDescending
            }
        withAnimation {
            otherDownloadedChapters = downloadedChapters
        }
    }

    func syncTrackerProgress() async {
        // sync progress from page trackers
        await TrackerManager.shared.syncPageTrackerHistory(
            manga: manga,
            chapters: chapters
        )

        // sync progress from regular trackers if auto sync enabled
        if UserDefaults.standard.bool(forKey: "Tracking.autoSyncFromTracker") {
            let trackItems: [TrackItem] = await CoreDataManager.shared.container.performBackgroundTask { @Sendable [manga] context in
                CoreDataManager.shared.getTracks(
                    sourceId: manga.sourceKey,
                    mangaId: manga.key,
                    context: context
                ).map { $0.toItem() }
            }
            for trackItem in trackItems {
                guard let tracker = TrackerManager.getTracker(id: trackItem.trackerId) else { continue }
                await TrackerManager.shared.syncProgressFromTracker(
                    tracker: tracker,
                    trackId: trackItem.id,
                    manga: manga,
                    chapters: chapters
                )
            }
        }
    }

    // refresh manga and chapter data from source, updating db
    func refresh() async {
        guard Reachability.getConnectionType() != .none, let source else {
            return
        }

        let sourceKey = source.key
        let mangaKey = manga.key

        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.hasLibraryManga(sourceId: sourceKey, mangaId: mangaKey, context: context)
        }

        do {
            let oldManga = self.manga
            let newManga = try await source.getMangaUpdate(
                manga: oldManga,
                needsDetails: true,
                needsChapters: true
            )

            let now = Date()
            // always update manga in db
            await CoreDataManager.shared.container.performBackgroundTask { [chapterLangFilter, chapterScanlatorFilter] context in
                // ensure manga object exists and update it
                let mangaObject = CoreDataManager.shared.getOrCreateManga(
                    newManga,
                    sourceId: sourceKey,
                    context: context
                )
                mangaObject.load(from: newManga)

                if let chapters = newManga.chapters {
                    let newChapters = CoreDataManager.shared.setChapters(
                        chapters,
                        sourceId: sourceKey,
                        mangaId: mangaKey,
                        context: context
                    )

                    // specific updates if in library
                    if inLibrary,
                       let libraryObject = CoreDataManager.shared.getLibraryManga(
                            sourceId: sourceKey,
                            mangaId: mangaKey,
                            context: context
                       )
                    {
                        // add manga updates
                        for chapter in newChapters
                        where
                            chapterLangFilter != nil ? chapter.lang == chapterLangFilter : true
                            && !chapterScanlatorFilter.isEmpty ? chapterScanlatorFilter.contains(chapter.scanlator ?? "") : true
                        {
                            CoreDataManager.shared.createMangaUpdate(
                                sourceId: sourceKey,
                                mangaId: mangaKey,
                                chapterObject: chapter,
                                context: context
                            )
                        }
                        libraryObject.lastChapter = chapters.compactMap { $0.dateUploaded }.max()
                        libraryObject.lastUpdated = now

                        if !UserDefaults.standard.bool(forKey: UserDefaultsKey.General.incognitoMode) {
                            libraryObject.lastOpened = now.addingTimeInterval(1) // ensure item isn't re-pinned, since it's already open
                        }
                    }

                    try? context.save()
                }
            }

            if inLibrary && newManga.chapters != nil {
                await markOpened()
            }

            NotificationCenter.default.post(name: .updateManga, object: newManga.identifier)

            await loadHistory()

            withAnimation {
                manga = newManga
                chapters = filteredChapters()
            }

            // ensure downloaded chapters are in the correct section if they were added/removed from the main list
            await fetchDownloadedChapters()
        } catch {
            withAnimation {
                self.manga.chapters = []
                self.chapters = []
                self.error = error
            }
        }

        updateReadButton()
    }

    private func loadDownloadStatus() async {
        await MainActor.run {
             let allChapters = chapters + otherDownloadedChapters
             downloadTracker.loadStatus(for: allChapters.map { $0.key })
        }
    }

    private func loadBookmarked() async {
        let sourceKey = manga.sourceKey
        let mangaId = manga.key
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.hasLibraryManga(
                sourceId: sourceKey,
                mangaId: mangaId,
                context: context
            )
        }
        bookmarked = inLibrary
    }

    private func loadHistory() async {
        readingHistory = await CoreDataManager.shared.getReadingHistory(
            sourceId: manga.sourceKey,
            mangaId: manga.key
        )
    }

    private func setupDownloadTracker() {
        if downloadTracker.sourceId != manga.sourceKey || downloadTracker.mangaId != manga.key {
            self.downloadTracker = DownloadStatusTracker(sourceId: manga.sourceKey, mangaId: manga.key)
        }

        // Connect tracker to view model updates
        // We need to re-subscribe whenever downloadTracker changes, but simply assigning to @Published downloadTracker 
        // won't automatically clean up old subscriptions if we did it manually. 
        // However, since we are in the ViewModel and downloadTracker is @Published,
        // we can set up the subscription to the property itself (binding to the new value).
        // BUT, earlier code was subscribing to `downloadTracker.objectWillChange`.
        // If we replace `downloadTracker`, the old subscription might detach or persist depending on how it was done.
        // The original init code did: 
        // downloadTracker.objectWillChange.sink { ... }.store(in: &cancellables)
        // If we replace the object, the old sink is still attached to the OLD object (which is now deallocated?),
        // but we need a sink on the NEW object.

        // Actually, simpler: just observe $downloadTracker (publisher of the property) OR the `downloadTracker` object manually.
        // Since `downloadTracker` is @Published, we can just sink on `$downloadTracker`.
        // Wait, `downloadTracker` is a `DownloadStatusTracker`, which is likely an `ObservableObject`.
        // If we want the ViewModel to objectWillChange when tracker changes, we need to observe the tracker.

        // Let's clear any existing tracker subscription if we are being rigorous, 
        // but easier is to just ensure we subscribe to the new one.

        downloadTracker.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

extension MangaView.ViewModel {
    // mark given chapters as read in coredata
    func markRead(chapters: [AidokuRunner.Chapter]) async {
        // only mark chapters that are readable as read
        let chapters = chapters.filter { !$0.locked || downloadStatus[$0.key] == .finished }

        await HistoryManager.shared.addHistory(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            chapters: chapters
        )
        let date = Int(Date().timeIntervalSince1970)
        for chapter in chapters {
            readingHistory[chapter.key] = (page: -1, date: date)
        }
        updateReadButton()
    }

    // remove coredata history for given chapters
    func markUnread(chapters: [AidokuRunner.Chapter]) async {
        await HistoryManager.shared.removeHistory(
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            chapterIds: chapters.map { $0.key }
        )
        for chapter in chapters {
            readingHistory[chapter.key] = nil
        }
        updateReadButton()
    }

    private func resortChapters() {
        withAnimation {
            chapters = sortedChapters()
        }
        if bookmarked {
            Task {
                await saveFilters()
            }
        }
    }

    private func refilterChapters() {
        withAnimation {
            chapters = filteredChapters()
        }
        if bookmarked {
            Task {
                await saveFilters()
            }
        }
    }

    private func sortedChapters() -> [AidokuRunner.Chapter] {
        guard let chapters = manga.chapters, !chapters.isEmpty else {
            return []
        }
        return switch chapterSortOption {
            case .sourceOrder:
                chapterSortAscending ? chapters.reversed() : chapters
            case .chapter:
                if chapterSortAscending {
                    chapters.sorted(by: { $0.chapterNumber ?? -1 < $1.chapterNumber ?? -1 })
                } else {
                    chapters.sorted(by: { $0.chapterNumber ?? -1 > $1.chapterNumber ?? -1 })
                }
            case .uploadDate:
                if chapterSortAscending {
                    chapters.sorted(by: { $0.dateUploaded ?? .distantPast < $1.dateUploaded ?? .distantPast })
                } else {
                    chapters.sorted(by: { $0.dateUploaded ?? .distantPast > $1.dateUploaded ?? .distantPast })
                }
        }
    }

    private func filteredChapters() -> [AidokuRunner.Chapter] {
        var chapters = sortedChapters()

        // filter by language and scanlators
        if chapterLangFilter != nil || !chapterScanlatorFilter.isEmpty {
            chapters = chapters.filter { chapter in
                let cond1 = if let chapterLangFilter {
                    chapter.language == chapterLangFilter
                } else {
                    true
                }
                let cond2 = if !chapterScanlatorFilter.isEmpty  {
                    chapterScanlatorFilter.contains(where: (chapter.scanlators ?? []).contains)
                } else {
                    true
                }
                return cond1 && cond2
            }
        }

        for filter in chapterFilters {
            switch filter.type {
                case .downloaded:
                    chapters = chapters.filter {
                        let downloaded = !DownloadManager.shared.isChapterDownloaded(
                            chapter: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                        )
                        return filter.exclude ? downloaded : !downloaded
                    }
                case .unread:
                    chapters = chapters.filter {
                        let isCompleted = self.readingHistory[$0.id]?.0 == -1
                        return filter.exclude ? isCompleted : !isCompleted
                    }
                case .locked:
                    chapters = chapters.filter {
                        filter.exclude ? !$0.locked : $0.locked
                    }
            }
        }

        return chapters
    }

    enum ChapterResult {
        case none
        case allRead
        case allLocked
        case chapter(AidokuRunner.Chapter)
    }

    private func getNextChapter() -> ChapterResult {
        guard !chapters.isEmpty else { return .none }
        // get first chapter not completed
        let chapter = (chapterSortAscending ? chapters : chapters.reversed()).first(
            where: { (!$0.locked || downloadStatus[$0.key] == .finished) && readingHistory[$0.id]?.page ?? 0 != -1 }
        )
        if let chapter {
            return .chapter(chapter)
        }
        if !chapters.contains(where: { !$0.locked }) {
            return .allLocked
        }
        return .allRead
    }

    private func updateReadButton() {
        let nextChapter = getNextChapter()
        switch nextChapter {
            case .none:
                return
            case .allRead:
                allChaptersRead = true
                allChaptersLocked = false
            case .allLocked:
                allChaptersLocked = true
            case .chapter(let nextChapter):
                allChaptersRead = false
                allChaptersLocked = false
                readingInProgress = readingHistory[nextChapter.id]?.date ?? 0 > 0
                self.nextChapter = nextChapter
        }
    }

    private func generateChapterFlags() -> Int {
        var flags: Int = 0
        if chapterSortAscending {
            flags |= ChapterFlagMask.sortAscending
        }
        flags |= chapterSortOption.rawValue << 1
        for filter in chapterFilters {
            switch filter.type {
                case .downloaded:
                    flags |= ChapterFlagMask.downloadFilterEnabled
                    if filter.exclude {
                        flags |= ChapterFlagMask.downloadFilterExcluded
                    }
                case .unread:
                    flags |= ChapterFlagMask.unreadFilterEnabled
                    if filter.exclude {
                        flags |= ChapterFlagMask.unreadFilterExcluded
                    }
                case .locked:
                    flags |= ChapterFlagMask.lockedFilterEnabled
                    if filter.exclude {
                        flags |= ChapterFlagMask.lockedFilterExcluded
                    }
            }
        }
        return flags
    }

    private func saveFilters() async {
        let manga = manga.toOld()
        manga.chapterFlags = generateChapterFlags()
        manga.langFilter = chapterLangFilter
        manga.scanlatorFilter = chapterScanlatorFilter
        await CoreDataManager.shared.updateMangaDetails(manga: manga)
    }

    private func handleDownloadRemoved(_ notification: Notification) {
        var chapterKey: String?
        if let identifier = notification.object as? ChapterIdentifier {
            chapterKey = identifier.chapterKey
        } else if let download = notification.object as? Download {
            chapterKey = download.chapterIdentifier.chapterKey
        }

        if let chapterKey, let index = otherDownloadedChapters.firstIndex(where: { $0.key == chapterKey }) {
            withAnimation {
                _ = otherDownloadedChapters.remove(at: index)
            }
        }
    }
}
