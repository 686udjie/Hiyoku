//
//  DownloadManager.swift
//  Aidoku
//
//  Created by Skitty on 5/2/22.
//

import AidokuRunner
import Foundation
import ZIPFoundation

// global class to manage downloads
actor DownloadManager {
    static let shared = DownloadManager()

    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Downloads", isDirectory: true)
    private static let videoExtensions: Set<String> = ["mp4", "mkv", "mov", "avi"]

    @MainActor
    private let cache: DownloadCache = .init()
    private let queue: DownloadQueue

    // for UI
    private var downloadedMangaCache: [DownloadedMangaInfo] = []
    private var lastCacheUpdate: Date = .distantPast
    private let cacheValidityDuration: TimeInterval = 60 // 1 minute

    init() {
        self.queue = DownloadQueue(cache: cache)
        if !Self.directory.exists {
            Self.directory.createDirectory()
        }
        Task {
            await self.queue.setOnCompletion { @Sendable [weak self] in
                Task { @MainActor in
                    await self?.invalidateDownloadedMangaCache()
                }
            }
        }
    }

    func loadQueueState() async {
        await queue.loadQueueState()

        // fetch loaded downloads to notify ui about
        let downloads = await queue.queue.flatMap(\.value)
        if !downloads.isEmpty {
            NotificationCenter.default.post(name: .downloadsQueued, object: downloads)
        }
    }

    func getDownloadedPages(for chapter: ChapterIdentifier) async -> [AidokuRunner.Page] {
        let directory = cache.directory(for: chapter)

        let archiveURL = directory.appendingPathExtension("cbz")
        if archiveURL.exists {
            return LocalFileManager.shared.readPages(from: archiveURL)
        } else {
            var descriptionFiles: [URL] = []

            var pages = directory.contents
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                .compactMap { url -> AidokuRunner.Page? in
                    guard !url.lastPathComponent.hasPrefix(".") else {
                        return nil
                    }
                    if url.pathExtension == "txt" {
                        // add description file to list
                        if url.lastPathComponent.hasSuffix("desc.txt") {
                            descriptionFiles.append(url)
                            return nil
                        }
                        // otherwise, load file as text
                        let text: String? = try? String(contentsOf: url)
                        guard let text else { return nil }
                        return AidokuRunner.Page(content: .text(text))
                    } else if LocalFileManager.allowedImageExtensions.contains(url.pathExtension) {
                        // load file as image
                        return AidokuRunner.Page(content: .url(url: url, context: nil))
                    } else {
                        return nil
                    }
                }

            // load descriptions from files
            for descriptionFile in descriptionFiles {
                guard
                    let index = descriptionFile
                        .deletingPathExtension()
                        .lastPathComponent
                        .split(separator: ".", maxSplits: 1)
                        .first
                        .flatMap({ Int($0) }),
                    index > 0,
                    index <= pages.count
                else { break }
                pages[index - 1].hasDescription = true
                pages[index - 1].description = try? String(contentsOf: descriptionFile)
            }

            return pages
        }
    }

    @MainActor
    func isChapterDownloaded(chapter: ChapterIdentifier) -> Bool {
        cache.isChapterDownloaded(identifier: chapter)
    }

    @MainActor
    func hasDownloadedChapter(from identifier: MangaIdentifier) -> Bool {
        cache.hasDownloadedChapter(from: identifier)
    }

    func downloadsCount(for identifier: MangaIdentifier) async -> Int {
        let keys = await getDownloadedChapterKeys(for: identifier)
        return keys.count
    }

    func hasQueuedDownloads(type: DownloadType? = nil) async -> Bool {
        await queue.hasQueuedDownloads(type: type)
    }

    @MainActor
    func getDownloadStatus(for chapter: ChapterIdentifier) -> DownloadStatus {
        let downloaded = isChapterDownloaded(chapter: chapter)
        if downloaded {
            return .finished
        } else {
            return .none
        }
    }

    func getMangaDirectoryUrl(identifier: MangaIdentifier) async -> URL? {
        let directory = await cache.getMangaDirectory(for: identifier)
        let path = directory.path
        return URL(string: "shareddocuments://\(path)")
    }

    func getCompressedFile(for chapter: ChapterIdentifier) -> URL? {
        let chapterDirectory = cache.directory(for: chapter)
        let chapterFile = chapterDirectory.appendingPathExtension("cbz")
        if chapterFile.exists {
            return chapterFile
        }
        // otherwise we can compress it ourselves
        let tmpFile = FileManager.default.temporaryDirectory?.appendingPathComponent(chapterFile.lastPathComponent)
        guard let tmpFile else { return nil }
        do {
            try FileManager.default.zipItem(at: chapterDirectory, to: tmpFile, shouldKeepParent: false)
            return tmpFile
        } catch {
            return nil
        }
    }
}

// MARK: File Management

extension DownloadManager {
    /// Download all chapters for a manga.
    func downloadAll(manga: AidokuRunner.Manga) async {
        let allChapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceKey, mangaId: manga.key)

        var chaptersToDownload: [AidokuRunner.Chapter] = []

        for chapter in allChapters {
            guard !chapter.locked else { continue }
            let downloaded = await isChapterDownloaded(chapter: chapter.identifier)
            if !downloaded {
                chaptersToDownload.append(chapter.toNew())
            }
        }

        await download(manga: manga, chapters: chaptersToDownload.reversed())
    }

    /// Download unread chapters for a manga.
    func downloadUnread(manga: AidokuRunner.Manga) async {
        let readingHistory = await CoreDataManager.shared.getReadingHistory(sourceId: manga.sourceKey, mangaId: manga.key)
        let allChapters = await CoreDataManager.shared.getChapters(sourceId: manga.sourceKey, mangaId: manga.key)

        var chaptersToDownload: [AidokuRunner.Chapter] = []

        for chapter in allChapters {
            guard !chapter.locked else { continue }
            let isUnread = readingHistory[chapter.id] == nil || readingHistory[chapter.id]?.page != -1
            guard isUnread else { continue }
            let downloaded = await isChapterDownloaded(chapter: chapter.identifier)
            if !downloaded {
                chaptersToDownload.append(chapter.toNew())
            }
        }

        await download(manga: manga, chapters: chaptersToDownload.reversed())
    }

    /// Download given chapters from a manga.
    func download(manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter]) async {
        let downloads = await queue.add(chapters: chapters, manga: manga, autoStart: true)
        NotificationCenter.default.post(
            name: .downloadsQueued,
            object: downloads
        )
        // Invalidate cache since new downloads may affect the list
        invalidateDownloadedMangaCache()
    }

    /// Download episodes for a video series
    func downloadVideo(seriesTitle: String, episodes: [PlayerEpisode], sourceKey: String, seriesKey: String, posterUrl: String?) async {
        let sourceName = if let source = SourceManager.shared.source(for: sourceKey) {
            source.name
        } else if let module = await MainActor.run(body: { ModuleManager.shared.modules.first { $0.id.uuidString == sourceKey } }) {
            module.metadata.sourceName
        } else {
            sourceKey
        }
        guard let module = await MainActor.run(body: { ModuleManager.shared.modules.first { $0.id.uuidString == sourceKey } }) else {
            return
        }

        var downloads: [Download] = []
        for episode in episodes {
            let identifier = ChapterIdentifier(sourceKey: sourceKey, mangaKey: seriesKey.normalizedModuleHref(), chapterKey: episode.url)
            let downloaded = await isChapterDownloaded(chapter: identifier)
            guard !downloaded else { continue }
            let (streamInfos, _) = await JSController.shared.fetchPlayerStreams(episodeId: episode.url, module: module)
            let streamUrl = streamInfos.first?.url ?? episode.url // Fallback to episode URL if no stream found

            let manga = AidokuRunner.Manga(sourceKey: sourceKey, key: seriesKey.normalizedModuleHref(), title: seriesTitle, cover: posterUrl)
            let chapter = AidokuRunner.Chapter(key: episode.url, title: episode.title, chapterNumber: Float(episode.number))

            let download = Download.from(
                manga: manga,
                chapter: chapter,
                type: .video,
                videoUrl: streamUrl,
                posterUrl: posterUrl,
                headers: streamInfos.first?.headers,
                sourceName: sourceName
            )
            downloads.append(download)
        }
        guard !downloads.isEmpty else { return }
        let queuedDownloads = await queue.add(downloads: downloads, autoStart: true)
        NotificationCenter.default.post(
            name: .downloadsQueued,
            object: queuedDownloads
        )
        invalidateDownloadedMangaCache()
    }

    /// Remove downloads for specified chapters.
    func delete(chapters: [ChapterIdentifier]) async {
        for chapter in chapters {
            let directory = cache.directory(for: chapter)
            let archiveURL = directory.appendingPathExtension("cbz")
            directory.removeItem()
            archiveURL.removeItem()
            await cache.remove(chapter: chapter)

            // check if all chapters have been removed (then remove manga directory)
            let manga = chapter.mangaIdentifier
            let hasRemainingChapters = cache.directory(for: manga)
                .contents
                .contains {
                    ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp")
                }
            if !hasRemainingChapters {
                await deleteChapters(for: manga)
            }

            NotificationCenter.default.post(name: .downloadRemoved, object: chapter)
        }
        // Invalidate cache for UI
        invalidateDownloadedMangaCache()
    }

    /// Remove all downloads from a manga.
    func deleteChapters(for manga: MangaIdentifier) async {
        await queue.cancelDownloads(for: manga)
        let directory = await cache.getMangaDirectory(for: manga)
        directory.removeItem()
        await cache.remove(manga: manga)

        // remove source directory if there are no more manga folders
        let sourceDirectory = await cache.getSourceDirectory(sourceKey: manga.sourceKey)
        let hasRemainingManga = sourceDirectory.exists && !sourceDirectory.contents.contains(where: { !$0.lastPathComponent.hasPrefix(".") })
        if !hasRemainingManga {
            sourceDirectory.removeItem()
        }

        NotificationCenter.default.post(name: .downloadsRemoved, object: manga)
        // Invalidate cache for UI
        invalidateDownloadedMangaCache()
    }

    /// Remove all downloads.
    func deleteAll() async {
        await cache.removeAll()
    }
}

// MARK: Queue Control

extension DownloadManager {
    func isQueuePaused() async -> Bool {
        !(await queue.isRunning())
    }

    func getDownloadQueue(type: DownloadType? = nil) async -> [String: [Download]] {
        let fullQueue = await queue.queue
        if let type = type {
            var filteredQueue: [String: [Download]] = [:]
            for (sourceId, downloads) in fullQueue {
                let filteredDownloads = downloads.filter { $0.type == type }
                if !filteredDownloads.isEmpty {
                    filteredQueue[sourceId] = filteredDownloads
                }
            }
            return filteredQueue
        }
        return fullQueue
    }

    func pauseDownloads() async {
        await queue.pause()
        NotificationCenter.default.post(name: .downloadsPaused, object: nil)
        // Invalidate cache since paused state may affect display
        invalidateDownloadedMangaCache()
    }

    func resumeDownloads() async {
        await queue.resume()
        NotificationCenter.default.post(name: .downloadsResumed, object: nil)
        // Invalidate cache since resumed state may affect display
        invalidateDownloadedMangaCache()
    }

    func cancelDownload(for chapter: ChapterIdentifier) async {
        await queue.cancelDownload(for: chapter)
        // Invalidate cache since cancelled downloads may affect display
        invalidateDownloadedMangaCache()
    }

    func cancelDownloads(for chapters: [ChapterIdentifier] = []) async {
        if chapters.isEmpty {
            await queue.cancelAll()
        } else {
            await queue.cancelDownloads(for: chapters)
        }
        // Invalidate cache since cancelled downloads may affect display
        invalidateDownloadedMangaCache()
    }

    func onProgress(for chapter: ChapterIdentifier, block: @Sendable @escaping (Int, Int) -> Void) async {
        await queue.onProgress(for: chapter, block: block)
    }

    func removeProgressBlock(for chapter: ChapterIdentifier) async {
        await queue.removeProgressBlock(for: chapter)
    }
}

// MARK: - Downloads UI Support
extension DownloadManager {
    /// Get all downloaded manga with metadata from CoreData if available
    func getAllDownloadedManga() async -> [DownloadedMangaInfo] {
        // Return cached result if still valid
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) < cacheValidityDuration {
            return downloadedMangaCache
        }

        let items = await listDownloadedItems()
        let downloadedManga = items.manga

        let sortedManga = downloadedManga.sorted { lhs, rhs in
            if lhs.sourceId != rhs.sourceId {
                return lhs.sourceId < rhs.sourceId
            }
            return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        }

        downloadedMangaCache = sortedManga
        lastCacheUpdate = now

        return sortedManga
    }

    func getAllDownloadedVideos() async -> [DownloadedVideoInfo] {
        let items = await listDownloadedItems()
        return items.videos.sorted { $0.displayTitle < $1.displayTitle }
    }

    /// Fetch downloaded chapter keys
    func getDownloadedChapterKeys(for identifier: MangaIdentifier) async -> Set<String> {
        guard Self.directory.exists else { return [] }

        let seriesDirectories = findDownloadedSeriesDirectories(for: identifier)
        guard !seriesDirectories.isEmpty else { return [] }

        var keys = Set<String>()
        for seriesDir in seriesDirectories {
            let subItems = seriesDir.contents.filter { !$0.lastPathComponent.hasPrefix(".") }
            for item in subItems {
                guard item.isDirectory || item.pathExtension == "cbz" else { continue }
                if item.isDirectory {
                    guard isCompletedDownloadDirectory(item) else { continue }
                }

                let info = loadComicInfo(at: item)
                let key = info?.extraData()?.chapterKey ?? item.deletingPathExtension().lastPathComponent
                keys.insert(key)
            }
        }

        return keys
    }

    private func listDownloadedItems() async -> (manga: [DownloadedMangaInfo], videos: [DownloadedVideoInfo]) {
        var manga: [DownloadedMangaInfo] = []
        var videos: [DownloadedVideoInfo] = []

        guard Self.directory.exists else { return ([], []) }

        let sourceDirectories = Self.directory.contents.filter { $0.isDirectory }
        for sourceDir in sourceDirectories {
            let sourceId = sourceDir.lastPathComponent
            let seriesDirectories = sourceDir.contents.filter { $0.isDirectory }

            for seriesDir in seriesDirectories {
                let seriesName = seriesDir.lastPathComponent
                let subItems = seriesDir.contents.filter { !$0.lastPathComponent.hasPrefix(".") }

                let episodeDirectories = subItems.filter { $0.isDirectory && !$0.lastPathComponent.hasPrefix(".tmp") }
                var videoEpisodes: [URL] = []
                var videoTotalSize: Int64 = 0

                for episodeDir in episodeDirectories where containsCompletedVideo(in: episodeDir) {
                    videoEpisodes.append(episodeDir)
                    videoTotalSize += await calculateDirectorySize(episodeDir)
                }

                if !videoEpisodes.isEmpty {
                    let comicInfo = loadComicInfo(at: seriesDir)
                    let extraData = comicInfo?.extraData()
                    let actualSourceId = extraData?.sourceKey ?? sourceId
                    let actualSeriesId = extraData?.mangaKey ?? seriesName

                    let metadata = await getVideoMetadata(sourceId: actualSourceId, seriesId: actualSeriesId, directoryName: seriesName)
                    let coverUrl = seriesDir.appendingPathComponent("cover.jpg").exists ?
                        seriesDir.appendingPathComponent("cover.jpg").absoluteString : metadata.coverUrl

                    videos.append(DownloadedVideoInfo(
                        sourceId: actualSourceId,
                        seriesId: actualSeriesId,
                        title: metadata.title ?? seriesName,
                        coverUrl: coverUrl,
                        totalSize: videoTotalSize,
                        videoCount: videoEpisodes.count,
                        isInLibrary: metadata.isInLibrary
                    ))
                } else {
                    let chapterDirectories = subItems.filter {
                        ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp")
                    }
                    guard !chapterDirectories.isEmpty else { continue }

                    let comicInfo = loadComicInfo(at: seriesDir)
                    let extraData = comicInfo?.extraData()
                    let actualSourceId = extraData?.sourceKey ?? sourceId
                    let actualMangaId = extraData?.mangaKey ?? seriesName

                    let metadata = await getMangaMetadata(
                        sourceId: actualSourceId,
                        mangaId: actualMangaId,
                        directoryName: seriesName,
                        comicInfo: comicInfo,
                        seriesDir: seriesDir
                    )
                    let totalSize = await calculateDirectorySize(seriesDir)

                    manga.append(DownloadedMangaInfo(
                        sourceId: actualSourceId,
                        mangaId: metadata.actualMangaId,
                        directoryMangaId: seriesName,
                        title: metadata.title,
                        coverUrl: metadata.coverUrl,
                        totalSize: totalSize,
                        chapterCount: chapterDirectories.count,
                        isInLibrary: metadata.isInLibrary
                    ))
                }
            }
        }

        return (manga, videos)
    }

    private func findDownloadedSeriesDirectories(for identifier: MangaIdentifier) -> [URL] {
        guard Self.directory.exists else { return [] }

        var matches: [URL] = []
        let sourceDirectories = Self.directory.contents.filter { $0.isDirectory }
        for sourceDir in sourceDirectories {
            let seriesDirectories = sourceDir.contents.filter { $0.isDirectory }
            for seriesDir in seriesDirectories {
                if let comicInfo = loadComicInfo(at: seriesDir) {
                    let extraData = comicInfo.extraData()
                    let sourceKey = extraData?.sourceKey ?? sourceDir.lastPathComponent
                    let mangaKey = extraData?.mangaKey ?? seriesDir.lastPathComponent
                    if sourceKey == identifier.sourceKey && mangaKey == identifier.mangaKey {
                        matches.append(seriesDir)
                    }
                } else if sourceDir.lastPathComponent == identifier.sourceKey,
                          seriesDir.lastPathComponent == identifier.mangaKey {
                    matches.append(seriesDir)
                }
            }
        }

        return matches
    }

    private func isCompletedDownloadDirectory(_ directory: URL) -> Bool {
        guard directory.isDirectory else { return false }
        guard !directory.lastPathComponent.hasPrefix(".tmp") else { return false }
        let contents = directory.contents
        return contents.contains { $0.lastPathComponent == "ComicInfo.xml" }
            || contents.contains { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    private func containsCompletedVideo(in directory: URL) -> Bool {
        directory.contents.contains { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    private struct DownloadedMangaMetadata {
        let title: String?
        let coverUrl: String?
        let isInLibrary: Bool
        let actualMangaId: String
    }

    private func getMangaMetadata(
        sourceId: String,
        mangaId: String,
        directoryName: String,
        comicInfo: ComicInfo?,
        seriesDir: URL
    ) async -> DownloadedMangaMetadata {
        if let comicInfo = comicInfo {
            let extraData = comicInfo.extraData()
            let isInLibrary = await withCheckedContinuation { continuation in
                CoreDataManager.shared.container.performBackgroundTask { context in
                    let result = CoreDataManager.shared.hasLibraryManga(
                        sourceId: extraData?.sourceKey ?? sourceId,
                        mangaId: extraData?.mangaKey ?? mangaId,
                        context: context
                    )
                    continuation.resume(returning: result)
                }
            }
            return DownloadedMangaMetadata(
                title: comicInfo.series,
                coverUrl: seriesDir.appendingPathComponent("cover.jpg").absoluteString,
                isInLibrary: isInLibrary,
                actualMangaId: extraData?.mangaKey ?? mangaId
            )
        } else {
            return await withCheckedContinuation { continuation in
                CoreDataManager.shared.container.performBackgroundTask { context in
                    var mangaObject = CoreDataManager.shared.getManga(sourceId: sourceId, mangaId: mangaId, context: context)
                    var isInLibrary = CoreDataManager.shared.hasLibraryManga(sourceId: sourceId, mangaId: mangaId, context: context)

                    if mangaObject == nil {
                        let allManga = CoreDataManager.shared.getManga(context: context).filter { $0.sourceId == sourceId }
                        for candidate in allManga where candidate.id.directoryName == directoryName {
                            mangaObject = candidate
                            isInLibrary = CoreDataManager.shared.hasLibraryManga(
                                sourceId: candidate.sourceId,
                                mangaId: candidate.id,
                                context: context
                            )
                            break
                        }
                    }

                    let localCover = seriesDir.appendingPathComponent("cover.jpg")
                    continuation.resume(returning: DownloadedMangaMetadata(
                        title: mangaObject?.title,
                        coverUrl: localCover.exists ? localCover.absoluteString : mangaObject?.cover,
                        isInLibrary: isInLibrary,
                        actualMangaId: mangaObject?.id ?? mangaId
                    ))
                }
            }
        }
    }

    private struct VideoMetadata {
        let title: String?
        let coverUrl: String?
        let isInLibrary: Bool
    }

    private func getVideoMetadata(
        sourceId: String,
        seriesId: String,
        directoryName: String
    ) async -> VideoMetadata {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let libraryItem = PlayerLibraryManager.shared.items.first { item in
                    let moduleMatches = item.moduleId.uuidString == sourceId ||
                                      ModuleManager.shared.modules.first(where: { $0.id == item.moduleId })?.metadata.sourceName == sourceId
                    guard moduleMatches else { return false }
                    let normalizedUrl = item.sourceUrl.normalizedModuleHref()
                    let matches = normalizedUrl == seriesId || item.id.uuidString == seriesId || item.title == seriesId || item.title == directoryName
                    return matches
                }
                continuation.resume(returning: VideoMetadata(
                    title: libraryItem?.title,
                    coverUrl: libraryItem?.imageUrl,
                    isInLibrary: libraryItem != nil
                ))
            }
        }
    }

    func getDownloadedFileUrl(for chapter: ChapterIdentifier) async -> URL? {
        let directory = await cache.getDirectory(for: chapter)
        guard directory.exists else { return nil }

        if let file = directory.contents.first(where: { Self.videoExtensions.contains($0.pathExtension.lowercased()) }) {
            return file
        }

        return nil
    }

    func isDownloadedVideoEpisode(
        sourceId: String,
        moduleName: String?,
        seriesTitle: String,
        episodeNumber: Int
    ) async -> Bool {
        let episodeName = "Episode \(episodeNumber)"
        let directory = DirectoryManager.shared.animeEpisodeDirectory(
            sourceKey: sourceId,
            moduleName: moduleName,
            seriesTitle: seriesTitle,
            episodeName: episodeName
        )
        guard directory.exists else { return false }
        return containsCompletedVideo(in: directory)
    }

    func deleteChapter(for chapter: ChapterIdentifier) async {
        await delete(chapters: [chapter])
    }

    /// Get downloaded chapters for a specific manga
    func getDownloadedChapters(for identifier: MangaIdentifier) async -> [DownloadedChapterInfo] {
        let mangaDirectory = await cache.getMangaDirectory(for: identifier)
        guard mangaDirectory.exists else { return [] }

        let chapterDirectories = mangaDirectory.contents.filter {
            ($0.isDirectory || $0.pathExtension == "cbz") && !$0.lastPathComponent.hasPrefix(".tmp")
        }

        var chapters: [DownloadedChapterInfo] = []

        for chapterDirectory in chapterDirectories {
            let chapterId = chapterDirectory.deletingPathExtension().lastPathComponent
            let size = await calculateDirectorySize(chapterDirectory)

            // Get directory creation date as download date
            let attributes = try? FileManager.default.attributesOfItem(atPath: chapterDirectory.path)
            let downloadDate = attributes?[.creationDate] as? Date

            // Try to load metadata from the chapter directory
            let metadata = loadComicInfo(at: chapterDirectory)

            let chapterInfo = DownloadedChapterInfo(
                chapterId: chapterId,
                title: metadata?.title,
                size: size,
                downloadDate: downloadDate,
                chapter: metadata?.toChapter()
            )
            chapters.append(chapterInfo)
        }

        return chapters.sorted { ($0.chapterNumber ?? 0) < ($1.chapterNumber ?? 0) }
    }

    func getDownloadedVideoItems(for identifier: MangaIdentifier) async -> [DownloadedVideoItemInfo] {
        let seriesDirectory = await cache.getMangaDirectory(for: identifier)
        guard seriesDirectory.exists else { return [] }

        let episodeDirectories = seriesDirectory.contents.filter { $0.isDirectory && !$0.lastPathComponent.hasPrefix(".tmp") }
        var episodes: [DownloadedVideoItemInfo] = []

        for episodeDir in episodeDirectories {
            let videoKey = episodeDir.lastPathComponent
            let mp4Files = episodeDir.contents.filter { $0.pathExtension == "mp4" }
            guard !mp4Files.isEmpty else { continue }

            let size = await calculateDirectorySize(episodeDir)
            let attributes = try? FileManager.default.attributesOfItem(atPath: episodeDir.path)
            let downloadDate = attributes?[.creationDate] as? Date

            let info = loadComicInfo(at: episodeDir)
            let actualVideoKey = info?.extraData()?.chapterKey ?? videoKey

            let episodeInfo = DownloadedVideoItemInfo(
                id: "\(identifier.sourceKey)_\(identifier.mangaKey)_\(actualVideoKey)",
                videoKey: actualVideoKey,
                title: info?.title,
                videoNumber: info?.number.flatMap { Int($0) },
                size: size,
                downloadDate: downloadDate
            )
            episodes.append(episodeInfo)
        }

        return episodes.sorted { ($0.videoNumber ?? 0) < ($1.videoNumber ?? 0) }
    }

    /// Save chapter metadata to ComicInfo.xml.
    func saveChapterMetadata(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter, to directory: URL) {
        let xml = ComicInfo.load(manga: manga, chapter: chapter).export()
        guard let data = xml.data(using: .utf8) else { return }
        do {
            let metadataURL = directory.appendingPathComponent("ComicInfo.xml")
            try data.write(to: metadataURL)
        } catch {
            LogManager.logger.error("Failed to save chapter metadata: \(error)")
        }
    }

    /// Load chapter/episode metadata from a directory or archive.
    private func loadComicInfo(at url: URL) -> ComicInfo? {
        do {
            if url.pathExtension == "cbz" {
                return ComicInfo.load(from: url)
            }

            if url.isDirectory {
                let xmlURL = url.appendingPathComponent("ComicInfo.xml")
                if xmlURL.exists {
                    let data = try Data(contentsOf: xmlURL)
                    if let string = String(data: data, encoding: .utf8) {
                        return ComicInfo.load(xmlString: string)
                    }
                }

                for subdirectory in url.contents where subdirectory.isDirectory || subdirectory.pathExtension == "cbz" {
                    if let info = loadComicInfo(at: subdirectory) {
                        return info
                    }
                }
            }
            return nil
        } catch {
            LogManager.logger.error("Failed to load metadata at \(url.path): \(error)")
            return nil
        }
    }

    /// Calculate the total size of a directory in bytes.
    private func calculateDirectorySize(_ directory: URL) async -> Int64 {
        guard directory.exists else { return 0 }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var totalSize: Int64 = 0

                if directory.isDirectory {
                    if let enumerator = FileManager.default.enumerator(
                        at: directory,
                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        for case let fileURL as URL in enumerator {
                            do {
                                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                                if resourceValues.isRegularFile == true {
                                    totalSize += Int64(resourceValues.fileSize ?? 0)
                                }
                            } catch {
                                // Skip files that can't be accessed
                                continue
                            }
                        }
                    }
                } else {
                    let resourceValues = try? directory.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if let resourceValues, resourceValues.isRegularFile == true {
                        totalSize = Int64(resourceValues.fileSize ?? 0)
                    }
                }

                continuation.resume(returning: totalSize)
            }
        }
    }

    /// Get formatted total download size string
    func getFormattedTotalDownloadedSize() async -> String {
        let totalSize = if Self.directory.exists {
            await calculateDirectorySize(Self.directory)
        } else {
            Int64(0)
        }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// Invalidate the downloaded manga cache (call when downloads are added/removed)
    private func invalidateDownloadedMangaCache() {
        lastCacheUpdate = .distantPast
    }
}

extension DownloadManager {
    /// Check if there is any old metadata files that need migration.
    func checkForOldMetadata() -> Bool {
        for sourceDirectory in Self.directory.contents where sourceDirectory.isDirectory {
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                if mangaDirectory.appendingPathComponent(".manga_metadata.json").exists {
                    return true
                }
                for chapterDirectory in mangaDirectory.contents where chapterDirectory.isDirectory {
                    if chapterDirectory.appendingPathComponent(".metadata.json").exists {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Migrate old metadata files to new format.
    func migrateOldMetadata() {
        for sourceDirectory in Self.directory.contents where sourceDirectory.isDirectory {
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                let mangaMetadataUrl = mangaDirectory.appendingPathComponent(".manga_metadata.json")
                var seriesTitle: String?
                if mangaMetadataUrl.exists {
                    if
                        let data = try? Data(contentsOf: mangaMetadataUrl),
                        let metadata = try? JSONDecoder().decode(MangaMetadata.self, from: data)
                    {
                        // save series title for chapter ComicInfo
                        seriesTitle = metadata.title
                        // save cover image data as cover.png
                        if
                            let thumbnailBase64 = metadata.thumbnailBase64,
                            let imageData = Data(base64Encoded: thumbnailBase64)
                        {
                            try? imageData.write(to: mangaDirectory.appendingPathComponent("cover.png"))
                        }
                    }
                    mangaMetadataUrl.removeItem()
                }
                for chapterDirectory in mangaDirectory.contents where chapterDirectory.isDirectory {
                    let chapterMetadataUrl = chapterDirectory.appendingPathComponent(".metadata.json")
                    if chapterMetadataUrl.exists {
                        if
                            let data = try? Data(contentsOf: chapterMetadataUrl),
                            let metadata = try? JSONDecoder().decode(ChapterMetadata.self, from: data)
                        {
                            let xml = ComicInfo(
                                title: metadata.title,
                                series: seriesTitle,
                                number: metadata.chapterNumber.flatMap { String($0) },
                                volume: metadata.volumeNumber.flatMap { Int(floor($0)) }
                            ).export()
                            guard let data = xml.data(using: .utf8) else { continue }
                            try? data.write(to: chapterDirectory.appendingPathComponent("ComicInfo.xml"))
                        }
                        chapterMetadataUrl.removeItem()
                    }
                }
            }
        }
        invalidateDownloadedMangaCache()
    }

    private struct ChapterMetadata: Codable {
        let title: String?
        let chapterNumber: Float?
        let volumeNumber: Float?
        var chapter: AidokuRunner.Chapter?
    }

    private struct MangaMetadata: Codable {
        let mangaId: String?
        let title: String?
        let cover: String?
        let thumbnailBase64: String?
        let description: String?
    }
}
