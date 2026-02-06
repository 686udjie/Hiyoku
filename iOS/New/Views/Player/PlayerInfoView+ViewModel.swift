//
//  PlayerInfoView+ViewModel.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Combine
import SwiftUI
import CoreData
import AidokuRunner

extension PlayerInfoView {
    struct InlineEpisodeHistory: Equatable {
        let progress: Int
        let total: Int?
    }

    @MainActor
    class ViewModel: ObservableObject {
        private let libraryManager = PlayerLibraryManager.shared
        private let moduleManager = ModuleManager.shared

        private var bookmark: PlayerLibraryItem?
        private var searchItem: SearchItem?
        private(set) var module: ScrapingModule?
        @Published var episodes: [PlayerEpisode] = [] {
            didSet {
                recomputeSortedEpisodes()
                Task { await loadDownloadStatus() }
            }
        }
        @Published private(set) var sortedEpisodes: [PlayerEpisode] = []
        @Published var isLoadingEpisodes = false
        @Published var initialDataLoaded = false
        @Published var isBookmarked = false
        @Published var episodeProgress: [String: InlineEpisodeHistory] = [:]

        // Edit Mode
        @Published var editMode = EditMode.inactive
        @Published var selectedEpisodes = Set<String>()

        @Published var downloadTracker: DownloadStatusTracker?
        var downloadStatus: [String: DownloadStatus] {
            downloadTracker?.downloadStatus ?? [:]
        }
        var downloadProgress: [String: Float] {
            downloadTracker?.downloadProgress ?? [:]
        }

        private var cancellables = Set<AnyCancellable>()

        // Cached computed properties to avoid expensive lookups during rendering
        let title: String
        let posterUrl: String

        // Episode sorting/filtering
        @Published var episodeSortOption: EpisodeSortOption = .sourceOrder {
            didSet { recomputeSortedEpisodes() }
        }
        @Published var episodeSortAscending = true {
            didSet { recomputeSortedEpisodes() }
        }

        var contentUrl: String? {
            if let bookmark = currentBookmark, !bookmark.sourceUrl.isEmpty {
                return bookmark.sourceUrl
            }
            if let href = searchItem?.href, !href.isEmpty {
                return href
            }
            return nil
        }

        var description: String? {
            nil
        }

        var sourceName: String? {
            if let bookmark = bookmark {
                return bookmark.moduleName
            } else if let module = module {
                return module.metadata.sourceName
            }
            return nil
        }
        var currentSourceId: String? {
            module?.id.uuidString
        }
        var currentMangaId: String? {
            contentUrl?.normalizedModuleHref()
        }

        var bookmarkId: UUID? {
            if let bookmark = bookmark {
                return bookmark.id
            } else if let searchItem = searchItem, let module = module {
                return libraryManager.getLibraryItemId(for: searchItem, module: module)
            }
            return nil
        }

        var currentBookmark: PlayerLibraryItem? {
            if let bookmark = bookmark {
                return bookmark
            } else if searchItem != nil, module != nil, let bookmarkId = bookmarkId {
                return libraryManager.items.first(where: { $0.id == bookmarkId })
            }
            return nil
        }

        init(bookmark: PlayerLibraryItem) {
            self.bookmark = bookmark
            self.isBookmarked = true
            if let module = moduleManager.modules.first(where: {
                $0.id == bookmark.moduleId
            }) {
                self.module = module
            }

        // Cache expensive computed properties
            self.title = bookmark.title
            self.posterUrl = libraryManager.items.first(where: {
                $0.id == bookmark.id
            })?.imageUrl ?? bookmark.imageUrl

        setupBookmarkObserver()
            // Don't call recomputeSortedEpisodes() here since episodes is empty initially
        }

        init(searchItem: SearchItem, module: ScrapingModule) {
            self.searchItem = searchItem
            self.module = module
            self.isBookmarked = libraryManager.isInLibrary(searchItem, module: module)

        // Cache expensive computed properties
            self.title = searchItem.title
            self.posterUrl = searchItem.imageUrl

        setupBookmarkObserver()
            // Don't call recomputeSortedEpisodes() here since episodes is empty initially
        }

        private func setupBookmarkObserver() {
            libraryManager.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
            setupDownloadTracker()
        }
        private func setupDownloadTracker() {
            guard let sourceId = currentSourceId, let mangaId = currentMangaId else { return }
            if downloadTracker == nil || downloadTracker?.sourceId != sourceId || downloadTracker?.mangaId != mangaId {
                let tracker = DownloadStatusTracker(sourceId: sourceId, mangaId: mangaId)
                self.downloadTracker = tracker
                tracker.objectWillChange.sink { [weak self] _ in
                    self?.objectWillChange.send()
                }.store(in: &cancellables)
            }
        }

        func refresh() async {
            guard let module = module, let sourceId = currentSourceId, let mangaId = currentMangaId else {
                return
            }

            await fetchHistory()

            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                CoreDataManager.shared.hasLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)
            }

            let fetchedEpisodes = await JSController.shared.fetchPlayerEpisodes(
                contentUrl: mangaId,
                module: module
            )

            if !fetchedEpisodes.isEmpty {
                let now = Date()
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    _ = CoreDataManager.shared.getOrCreateManga(
                        AidokuRunner.Manga(
                            sourceKey: sourceId,
                            key: mangaId,
                            title: self.title,
                            cover: self.posterUrl,
                            url: URL(string: mangaId)
                        ),
                        sourceId: sourceId,
                        context: context
                    )

                    let chaptersToSave = fetchedEpisodes.map { $0.toChapter() }
                    CoreDataManager.shared.setChapters(
                        chaptersToSave,
                        sourceId: sourceId,
                        mangaId: mangaId,
                        context: context
                    )

                    if inLibrary,
                       let libraryObject = CoreDataManager.shared.getLibraryManga(
                            sourceId: sourceId,
                            mangaId: mangaId,
                            context: context
                       )
                    {
                        libraryObject.lastUpdated = now
                        if !UserDefaults.standard.bool(forKey: UserDefaultsKey.General.incognitoMode) {
                            libraryObject.lastOpened = now.addingTimeInterval(1)
                        }
                    }

                    try? context.save()
                }

                await MainActor.run {
                    withAnimation {
                        self.episodes = fetchedEpisodes
                    }
                }
            } else if episodes.isEmpty {
                await MainActor.run {
                    withAnimation {
                        self.episodes = []
                        self.sortedEpisodes = []
                    }
                }
            }

            await loadDownloadStatus()
            await MainActor.run {
                setupDownloadTracker()
            }
        }

        func fetchEpisodes() async {
            guard let sourceId = currentSourceId, let mangaId = currentMangaId else {
                episodes = []
                sortedEpisodes = []
                initialDataLoaded = true
                return
            }

            await fetchHistory()

            let cachedEpisodes: [PlayerEpisode] = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                CoreDataManager.shared.getChapters(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    context: context
                ).map { chapterObject in
                    chapterObject.toNewChapter().toPlayerEpisode()
                }
            }

            if !cachedEpisodes.isEmpty {
                withAnimation {
                    self.episodes = cachedEpisodes
                }
            }

            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                CoreDataManager.shared.hasLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)
            }

            if !inLibrary, let module = module {
                await fetchEpisodesFromSource(sourceId: sourceId, mangaId: mangaId, module: module)
            }

            await loadDownloadStatus()
            await MainActor.run {
                setupDownloadTracker()
                initialDataLoaded = true
            }
        }

        private func fetchEpisodesFromSource(sourceId: String, mangaId: String, module: ScrapingModule) async {
            let fetchedEpisodes = await JSController.shared.fetchPlayerEpisodes(
                contentUrl: mangaId,
                module: module
            )

            if !fetchedEpisodes.isEmpty {
                let chaptersToSave = fetchedEpisodes.map { $0.toChapter() }
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    _ = CoreDataManager.shared.getOrCreateManga(
                        AidokuRunner.Manga(
                            sourceKey: sourceId,
                            key: mangaId,
                            title: self.title,
                            cover: self.posterUrl,
                            url: URL(string: mangaId)
                        ),
                        sourceId: sourceId,
                        context: context
                    )
                    CoreDataManager.shared.setChapters(
                        chaptersToSave,
                        sourceId: sourceId,
                        mangaId: mangaId,
                        context: context
                    )
                    try? context.save()
                }
                await MainActor.run {
                    withAnimation {
                        self.episodes = fetchedEpisodes
                    }
                }
            } else if self.episodes.isEmpty {
                await MainActor.run {
                    withAnimation {
                        self.episodes = []
                        self.sortedEpisodes = []
                    }
                }
            }
        }
        private func loadDownloadStatus() async {
            await MainActor.run {
                setupDownloadTracker()
            }
            await downloadTracker?.loadStatus(for: episodes.map { $0.url })
            await applyVideoDownloadFallbacks()
        }

        private func applyVideoDownloadFallbacks() async {
            guard let sourceId = currentSourceId else { return }
            let moduleName = module?.metadata.sourceName
            let seriesTitle = title
            let episodesToCheck = episodes.filter { downloadStatus[$0.url] != .finished }
            guard !episodesToCheck.isEmpty else { return }

            for episode in episodesToCheck {
                let isDownloaded = await DownloadManager.shared.isDownloadedVideoEpisode(
                    sourceId: sourceId,
                    moduleName: moduleName,
                    seriesTitle: seriesTitle,
                    episodeNumber: episode.number
                )
                if isDownloaded {
                    await MainActor.run {
                        downloadTracker?.downloadStatus[episode.url] = .finished
                        downloadTracker?.downloadProgress.removeValue(forKey: episode.url)
                    }
                }
            }
        }
        func getLocalEpisodeUrls(for episode: PlayerEpisode) async -> (video: URL, subtitle: URL?)? {
            guard let sourceId = currentSourceId, let mangaId = currentMangaId else { return nil }
            let chapterIdentifier = ChapterIdentifier(
                sourceKey: sourceId,
                mangaKey: mangaId,
                chapterKey: episode.url
            )
            return await DownloadManager.shared.getDownloadedFileUrls(for: chapterIdentifier)
        }
        func fetchHistory() async {
            guard let sourceId = currentSourceId else { return }
            let map: [String: InlineEpisodeHistory] = await CoreDataManager.shared.getPlayerReadingHistory(
                sourceId: sourceId,
                mangaId: currentMangaId ?? ""
            ).mapValues { history in
                InlineEpisodeHistory(
                    progress: history.progress,
                    total: history.total
                )
            }
            await MainActor.run {
                self.episodeProgress = map
            }
        }

        private func searchForPlayerUrl(title: String, module: ScrapingModule) async -> String? {
            let searchResults = await JSController.shared.fetchJsSearchResults(
                keyword: title,
                module: module
            )
            let match = searchResults.first { item in
                item.title.lowercased() == title.lowercased() ||
                item.title.lowercased().contains(title.lowercased()) ||
                title.lowercased().contains(item.title.lowercased())
            } ?? searchResults.first

        guard let match = match else {
                return nil
        }

        let fullUrl = match.href.absoluteUrl(withBaseUrl: module.metadata.baseUrl)
            if let bookmark = self.bookmark, bookmark.sourceUrl.isEmpty {
                self.libraryManager.updateItemSourceUrl(itemId: bookmark.id, sourceUrl: fullUrl)
        }

        return fullUrl
        }

        func toggleBookmark() {
            guard let module = module else { return }

            if let searchItem = searchItem {
                libraryManager.toggleInLibrary(for: searchItem, module: module)
                isBookmarked = libraryManager.isInLibrary(searchItem, module: module)
            } else if let bookmark = bookmark {
                let tempSearchItem = SearchItem(
                    title: bookmark.title,
                    imageUrl: bookmark.imageUrl,
                    href: bookmark.sourceUrl
                )
                libraryManager.toggleInLibrary(for: tempSearchItem, module: module)
                isBookmarked = libraryManager.isInLibrary(tempSearchItem, module: module)
            }
        }

        func markWatched(episodes: [PlayerEpisode]) async {
            guard let module else { return }
            let moduleId = module.id.uuidString

            for episode in episodes {
                let historyData = PlayerHistoryManager.EpisodeHistoryData(
                    playerTitle: title,
                    episodeId: episode.url,
                    episodeNumber: Double(episode.number),
                    episodeTitle: episode.title,
                    sourceUrl: episode.url,
                    moduleId: moduleId,
                    progress: 100,
                    total: 100,
                    watchedDuration: 0,
                    date: Date()
                )
                await PlayerHistoryManager.shared.setProgress(data: historyData)
            }
            await fetchHistory()
        }

        func markUnwatched(episodes: [PlayerEpisode]) async {
            guard let module else { return }
            let moduleId = module.id.uuidString
            for episode in episodes {
                await PlayerHistoryManager.shared.removeHistory(episodeId: episode.url, moduleId: moduleId)
            }
            await fetchHistory()
        }

        func selectAll() {
            selectedEpisodes = Set(episodes.map { $0.url })
        }

        func deselectAll() {
            selectedEpisodes.removeAll()
        }

        func downloadSelectedEpisodes() async {
            guard module != nil, !selectedEpisodes.isEmpty else { return }
            let episodesToDownload = episodes.filter { selectedEpisodes.contains($0.url) }
            await downloadEpisodes(episodesToDownload)
        }

        func downloadEpisode(_ episode: PlayerEpisode) async {
            await downloadEpisodes([episode])
        }

        func cancelDownloads(for episodes: [PlayerEpisode]) async {
            guard let sourceId = currentSourceId, let mangaId = currentMangaId else { return }
            let identifiers = episodes.map {
                ChapterIdentifier(sourceKey: sourceId, mangaKey: mangaId, chapterKey: $0.url)
            }
            await DownloadManager.shared.cancelDownloads(for: identifiers)
        }

        func deleteEpisodes(_ episodes: [PlayerEpisode]) async {
            guard let sourceId = currentSourceId, let mangaId = currentMangaId else { return }
            let identifiers = episodes.map {
                ChapterIdentifier(sourceKey: sourceId, mangaKey: mangaId, chapterKey: $0.url)
            }
            await DownloadManager.shared.delete(chapters: identifiers)
        }

        private func downloadEpisodes(_ episodesToDownload: [PlayerEpisode]) async {
            guard let module, !episodesToDownload.isEmpty else { return }
            let seriesKey = (contentUrl ?? "")
                .normalizedModuleHref()
            // Filter out episodes that are already downloaded or in progress
            let filtered = episodesToDownload.filter { episode in
                let status = downloadStatus[episode.url] ?? .none
                return status != .finished && status != .downloading && status != .queued
            }
            guard !filtered.isEmpty else { return }
            await DownloadManager.shared.downloadVideo(
                seriesTitle: title,
                episodes: filtered,
                sourceKey: module.id.uuidString,
                seriesKey: seriesKey,
                posterUrl: posterUrl
            )
        }

        private func recomputeSortedEpisodes() {
            // Only recompute if we have episodes to avoid unnecessary work
            guard !episodes.isEmpty else {
                sortedEpisodes = []
                return
            }

            let sorted = episodes.sorted { lhs, rhs in
                episodeSortAscending ? lhs.number < rhs.number : lhs.number > rhs.number
            }
            self.sortedEpisodes = sorted
        }
    }
}
