//
//  DownloadTask.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import AidokuRunner
import AVFoundation
import Foundation
import Nuke
import UniformTypeIdentifiers
import ZIPFoundation

protocol DownloadTaskDelegate: AnyObject, Sendable {
    func taskCancelled(task: DownloadTask) async
    func taskPaused(task: DownloadTask) async
    func taskFinished(task: DownloadTask) async
    func downloadProgressChanged(download: Download) async
    func downloadFinished(download: Download) async
    func downloadCancelled(download: Download) async
}

// performs the actual download operations
actor DownloadTask: Identifiable {
    let id: String

    private let cache: DownloadCache
    private var downloads: [Download]
    private weak var delegate: DownloadTaskDelegate?

    private var currentPage: Int = 0
    private var failedPages: Int = 0
    private var pages: [Page] = []

    private(set) var running: Bool = false

    private var currentDownload: Download?
    private var currentSource: AidokuRunner.Source?

    private static let maxConcurrentPageTasks = 5
    private static let videoUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

    enum DownloadError: Error {
        case pageProcessorFailed
        case noSegmentsFound
        case videoFileCreationFailed
    }

    init(id: String, cache: DownloadCache, downloads: [Download]) {
        self.id = id
        self.cache = cache
        self.downloads = downloads
    }

    func setDelegate(delegate: DownloadTaskDelegate?) {
        self.delegate = delegate
    }

    func resume() {
        guard !running else { return }
        running = true
        Task {
            await next()
        }
    }

    func pause() async {
        running = false
        for (i, download) in downloads.enumerated() where download.status == .queued || download.status == .downloading {
            downloads[i].status = .paused
        }
        Task {
            await delegate?.taskPaused(task: self)
        }
    }

    func cancel(manga: MangaIdentifier? = nil, chapter: ChapterIdentifier? = nil) {
        running = false

        if let chapter {
            guard let index = downloads.firstIndex(where: { $0.chapterIdentifier == chapter }) else { return }
            // cancel specific chapter download
            downloads[index].status = .cancelled
            if index == 0 {
                pages = []
                currentPage = 0
                failedPages = 0
            }
            let download = downloads[index]
            Task {
                let directoryToClean = DirectoryManager.shared.directoryForDownload(download)

                if download.type == .video {
                    await DirectoryManager.shared.cleanupJunkFiles(in: directoryToClean)
                }

                DirectoryManager.shared.removeDirectory(at: directoryToClean)
                await delegate?.downloadCancelled(download: download)
                downloads.removeAll { $0 == download }
                // Resume if there are more downloads
                if !downloads.isEmpty {
                    running = true
                    await next()
                }
            }
        } else if let manga {
            Task {
                var cancelled: IndexSet = []
                for i in downloads.indices where downloads[i].mangaIdentifier == manga {
                    if i == 0 {
                        pages = []
                        currentPage = 0
                        failedPages = 0
                    }
                    downloads[i].status = .cancelled
                    if downloads[i].type == .video {
                        let directoryToClean = DirectoryManager.shared.directoryForDownload(downloads[i])
                        await DirectoryManager.shared.cleanupJunkFiles(in: directoryToClean)
                        DirectoryManager.shared.removeDirectory(at: directoryToClean)
                    }

                    await delegate?.downloadCancelled(download: downloads[i])
                    cancelled.insert(i)
                }
                downloads.remove(atOffsets: cancelled)
                await DirectoryManager.shared.cleanupTemporaryDirectories(for: manga.sourceKey)
                // Resume if there are more downloads
                if !downloads.isEmpty {
                    running = true
                    await next()
                }
            }
        } else {
            // cancel all downloads in task
            var manga: Set<MangaIdentifier> = []
            for i in downloads.indices {
                if downloads[i].type == .video {
                    let directoryToClean = DirectoryManager.shared.directoryForDownload(downloads[i])
                    Task {
                        await DirectoryManager.shared.cleanupJunkFiles(in: directoryToClean)
                        DirectoryManager.shared.removeDirectory(at: directoryToClean)
                    }
                }
                downloads[i].status = .cancelled
                manga.insert(downloads[i].mangaIdentifier)
            }
            downloads.removeAll()
            // remove cached tmp directories
            Task {
                for manga in manga {
                    await DirectoryManager.shared.cleanupTemporaryDirectories(for: manga.sourceKey)
                }
                pages = []
                currentPage = 0
                failedPages = 0
                await delegate?.taskCancelled(task: self)
            }
        }
    }

    func add(download: Download) {
        guard !downloads.contains(where: { $0 == download }) else { return }
        downloads.append(download)
    }
}

extension DownloadTask {
    private func next() async {
        guard running else { return }

        // done with all downloads
        if downloads.isEmpty {
            running = false
            await delegate?.taskFinished(task: self)
            return
        }

        // attempt to download first chapter in the queue
        if let download = downloads.first {
            let source = SourceManager.shared.source(for: download.chapterIdentifier.sourceKey)
            if source == nil && download.type != .video {
                downloads.removeFirst()
                await next()
                return
            }

            // if chapter already downloaded, skip
            let directory = cache.directory(for: download.chapterIdentifier)
            if directory.exists || directory.appendingPathExtension("cbz").exists {
                downloads.removeFirst()
                await delegate?.downloadFinished(download: download)
                return await next()
            }

            // download has been cancelled or failed, skip
            if download.status != .queued && download.status != .downloading && download.status != .paused {
                downloads.removeFirst()
                await delegate?.downloadCancelled(download: download)
                return await next()
            }

            Task {
                if download.type == .video {
                    await self.downloadVideo()
                } else if let source = source {
                    await self.download(from: source)
                }
            }
        }
    }

    struct NetworkPage {
        let url: URL
        let context: PageContext?
        let targetPath: URL
    }

    // perform download
    private func download(from source: AidokuRunner.Source) async {
        guard running && !downloads.isEmpty else { return }

        let download = downloads[0]
        downloads[0].status = .downloading

        currentDownload = download
        currentSource = source

        _ = SourceManager.shared.source(for: download.chapterIdentifier.sourceKey)?.name ?? download.chapterIdentifier.sourceKey
        let mangaTitle = download.manga.title
        let chapterTitle = download.chapter.title ?? "Chapter \(download.chapter.chapterNumber ?? 0)"

        let entryDirectory = DirectoryManager.shared.mangaEntryDirectory(
            sourceKey: download.chapterIdentifier.sourceKey,
            mangaTitle: mangaTitle
        )

        // Step 1: Create the entry folder first
        do {
            try DirectoryManager.shared.createDirectory(at: entryDirectory)
        } catch {
            LogManager.logger.error("Failed to create manga entry directory: (error)")
            failedPages = 1
            await handleChapterDownloadFinish(download: download)
            return
        }

        // Step 2: Create and validate cache directory before starting downloads
        let cacheDirectory = DirectoryManager.shared.mangaTempDirectory(
            sourceKey: download.chapterIdentifier.sourceKey,
            mangaTitle: mangaTitle
        )

        do {
            try DirectoryManager.shared.createDirectory(at: cacheDirectory)

            // Double-check that directory exists
            guard DirectoryManager.shared.directoryExists(at: cacheDirectory) else {
                LogManager.logger.error("Failed to validate cache directory exists: (cacheDirectory.path)")
                failedPages = 1
                await handleChapterDownloadFinish(download: download)
                return
            }
        } catch {
            LogManager.logger.error("Failed to create cache directory: (error)")
            failedPages = 1
            await handleChapterDownloadFinish(download: download)
            return
        }

        _ = DirectoryManager.shared.mangaChapterDirectory(
            sourceKey: download.chapterIdentifier.sourceKey,
            mangaTitle: mangaTitle,
            chapterTitle: chapterTitle
        )
        if pages.isEmpty {
            pages = ((try? await source.getPageList(
                manga: download.manga,
                chapter: download.chapter
            )) ?? []).map {
                $0.toOld(sourceId: source.key, chapterId: download.chapterIdentifier.chapterKey)
            }
            guard running && downloads.first == download else { return }
            downloads[0].total = pages.count
        }

        var networkPages: [NetworkPage] = []

        for (i, page) in pages.enumerated() {
            let pageNumber = String(format: "%03d", i + 1)
            let targetPath = cacheDirectory.appendingPathComponent(pageNumber)

            guard DirectoryManager.shared.directoryExists(at: cacheDirectory) else {
                LogManager.logger.error("Cache directory disappeared during download: \(cacheDirectory.path)")
                failedPages += 1
                await incrementProgress(for: download.chapterIdentifier, failed: true)
                continue
            }

            if let urlString = page.imageURL, let url = URL(string: urlString) {
                // add pages that require network requests to a concurrent queue
                networkPages.append(.init(
                    url: url,
                    context: page.context,
                    targetPath: targetPath
                ))
            } else {
                currentPage += 1
                do {
                    if let base64 = page.base64, let data = Data(base64Encoded: base64) {
                        try data.write(to: targetPath.appendingPathExtension("png"))
                    } else if let text = page.text, let data = text.data(using: .utf8) {
                        try data.write(to: targetPath.appendingPathExtension("txt"))
                    } else if let image = page.image {
                        let data = image.pngData()
                        try data?.write(to: targetPath.appendingPathExtension("png"))
                    }
                } catch {
                    failedPages += 1
                }
                await incrementProgress(for: download.chapterIdentifier, failed: false)
            }

            if page.hasDescription {
                var description = page.description
                if description == nil {
                    description = try? await source.getPageDescription(page: page.toNew())
                }
                if let description {
                    let data = description.data(using: .utf8)
                    try? data?.write(to: targetPath.appendingPathExtension("desc.txt"))
                }
            }
        }

        let pageInterceptor: PageInterceptorProcessor? = source.features.processesPages ? PageInterceptorProcessor(source: source) : nil

        let downloadStrategy = UserDefaults.standard.bool(forKey: "Downloads.parallel") ? downloadPagesConcurrently : downloadPagesSerially

        await downloadStrategy(networkPages, cacheDirectory, pageInterceptor)

        // handle completion of the current download
        if networkPages.isEmpty && currentPage == pages.count {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await handleChapterDownloadFinish(download: download)
        }
    }

    private func downloadPagesConcurrently(
        _ networkPages: [NetworkPage],
        _ cacheDirectory: URL,
        _ pageInterceptor: PageInterceptorProcessor?
    ) async {
        guard let source = currentSource else { return }
        guard let download = currentDownload else { return }

        await withTaskGroup(of: Void.self) { taskGroup in
            for pageGroup in networkPages.chunked(into: Self.maxConcurrentPageTasks) {
                for page in pageGroup {
                    taskGroup.addTask {
                        let (data, path) = await self.downloadPage(page, source: source, pageInterceptor: pageInterceptor)

                        guard cacheDirectory.exists else { return }
                        await self.writeDownloadedData(data: data, path: path, for: download)
                    }
                }
            }
        }
    }

    private func downloadPagesSerially(
        _ networkPages: [NetworkPage],
        _ cacheDirectory: URL,
        _ pageInterceptor: PageInterceptorProcessor?
    ) async {
        for page in networkPages {
            guard cacheDirectory.exists else { return }
            guard let source = self.currentSource else { return }
            let (data, path) = await self.downloadPage(page, source: source, pageInterceptor: pageInterceptor)
            guard let download = self.currentDownload else { return }
            await self.writeDownloadedData(data: data, path: path, for: download)
        }
    }

    private func writeDownloadedData(data: Data?, path: URL?, for download: Download) async {
        guard let data, let path else {
            LogManager.logger.error("Failed to download page data")
            await incrementProgress(for: download.chapterIdentifier, failed: true)
            return
        }

        do {
            try data.write(to: path)
            await incrementProgress(for: download.chapterIdentifier, failed: false)
        } catch {
            LogManager.logger.error("Failed to write page data: \(error)")
            await incrementProgress(for: download.chapterIdentifier, failed: true)
        }
    }

    // fetch a single page's data
    private func downloadPage(
        _ page: NetworkPage,
        source: AidokuRunner.Source,
        pageInterceptor: PageInterceptorProcessor?
    ) async -> (Data?, URL?) {
        let urlRequest = await source.getModifiedImageRequest(
            url: page.url,
            context: page.context
        )

        let result = try? await URLSession.shared.data(for: urlRequest)

        var resultData: Data?
        var resultPath: URL?

        if let pageInterceptor {
                let image = result.flatMap { PlatformImage(data: $0.0) } ?? .mangaPlaceholder
                do {
                    let container = ImageContainer(image: image, data: result?.0)
                    let request = ImageRequest(
                        urlRequest: urlRequest,
                        userInfo: [.contextKey: page.context ?? [:]]
                    )
                    let newImage = try await pageInterceptor.processAsync(
                        container,
                        context: .init(
                            request: request,
                            response: .init(
                                container: container,
                                request: request,
                                urlResponse: result?.1 ?? (request.url ?? request.urlRequest?.url).flatMap {
                                    HTTPURLResponse(
                                        url: $0,
                                        statusCode: 404,
                                        httpVersion: nil,
                                        headerFields: nil
                                    )
                                }
                            ),
                            isCompleted: true
                        )
                    )
                    guard let newImage else {
                        throw DownloadError.pageProcessorFailed
                    }
                    resultData = newImage.pngData()
                    resultPath = page.targetPath.appendingPathExtension("png")
                } catch {
                }
            } else if let (data, res) = result {
                let fileExtention = self.guessFileExtension(response: res, defaultValue: "png")
                resultData = data
                resultPath = page.targetPath.appendingPathExtension(fileExtention)
            } else {
            }

            return (resultData, resultPath)
        }

        private func incrementProgress(for id: ChapterIdentifier, failed: Bool = false) async {
            guard let downloadIndex = downloads.firstIndex(where: { $0.chapterIdentifier == id }) else {
                return
            }
            currentPage += 1
            downloads[downloadIndex].progress = currentPage
            let download = downloads[downloadIndex]
            Task {
                await delegate?.downloadProgressChanged(download: download)
            }
            if failed {
                failedPages += 1
            }
            if currentPage == pages.count {
                await handleChapterDownloadFinish(download: download)
            }
        }

        private func handleChapterDownloadFinish(download: Download) async {
            let directoryToClean: URL
            if download.type == .video {
                directoryToClean = getFinalDirectory(for: download)
            } else {
                let mangaTitle = download.manga.title
                directoryToClean = DirectoryManager.shared.mangaTempDirectory(
                    sourceKey: download.chapterIdentifier.sourceKey,
                    mangaTitle: mangaTitle
                )

                await DirectoryManager.shared.cleanupMangaTempFolders(
                    sourceKey: download.chapterIdentifier.sourceKey,
                    mangaTitle: mangaTitle
                )
            }

            if download.type == .video {
                let isFailure = failedPages > 0
                if isFailure {
                    await DirectoryManager.shared.cleanupJunkFiles(in: directoryToClean)
                    DirectoryManager.shared.removeDirectory(at: directoryToClean)
                    await notifyDownloadCancelled(download: download)
                } else {
                    await finalizeDownload(download: download, tmpDirectory: directoryToClean)
                    await notifyDownloadFinished(download: download)
                }

                resetTaskProgress()
                await next()
                return
            }

            if failedPages == pages.count {
                // the entire chapter failed to download, skip adding to cache and cancel
                DirectoryManager.shared.removeDirectory(at: directoryToClean)
                if let downloadIndex = downloads.firstIndex(where: { $0 == download }) {
                    downloads[downloadIndex].status = .cancelled
                    downloads.remove(at: downloadIndex)
                    await delegate?.downloadCancelled(download: download)
                }
                resetTaskProgress()
                await next()
                return
            }

            await finalizeDownload(download: download, tmpDirectory: directoryToClean)
            await notifyDownloadFinished(download: download)
            resetTaskProgress()
            await next()
        }

        private func finalizeDownload(download: Download, tmpDirectory: URL) async {
            do {
                let directory: URL
                if download.type == .video {
                    directory = tmpDirectory
                } else {
                    let mangaTitle = download.manga.title
                    let chapterTitle = download.chapter.title ?? "Chapter \(download.chapter.chapterNumber ?? 0)"

                    let tempDir = DirectoryManager.shared.mangaTempDirectory(
                        sourceKey: download.chapterIdentifier.sourceKey,
                        mangaTitle: mangaTitle
                    )

                    let chapterDir = DirectoryManager.shared.mangaChapterDirectory(
                        sourceKey: download.chapterIdentifier.sourceKey,
                        mangaTitle: mangaTitle,
                        chapterTitle: chapterTitle
                    )

                    try DirectoryManager.shared.createDirectory(at: chapterDir)

                    guard DirectoryManager.shared.directoryExists(at: tempDir) else {
                        LogManager.logger.error("Cache directory missing before move: \(tempDir.path)")
                        LogManager.logger.error("This indicates a race condition - cache was deleted during download")
                        return
                    }

                    let files = DirectoryManager.shared.directoryContents(at: tempDir)

                    if files.isEmpty {
                        do {
                            let manualFiles = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)

                            for fileName in manualFiles {
                                let fileURL = tempDir.appendingPathComponent(fileName)
                                let destinationPath = chapterDir.appendingPathComponent(fileName)

                            do {
                                try FileManager.default.moveItem(at: fileURL, to: destinationPath)
                            } catch {
                                LogManager.logger.error("Failed to move file: \(error)")
                            }
                            }
                        } catch {
                            LogManager.logger.error("Failed to enumerate directory contents: \(error)")
                        }
                    } else {
                        for file in files {
                            let destination = chapterDir.appendingPathComponent(file.lastPathComponent)
                            do {
                                try FileManager.default.moveItem(at: file, to: destination)
                            } catch {
                                LogManager.logger.error("Failed to move file: \(error)")
                            }
                        }
                    }

                    DirectoryManager.shared.removeDirectory(at: tempDir)

                    directory = chapterDir
                }

            await DownloadManager.shared.saveChapterMetadata(manga: download.manga, chapter: download.chapter, to: directory)

            if download.type == .manga {
                let mangaTitle = download.manga.title
                await saveCoverIfMissing(download: download, seriesTitle: mangaTitle)
            }

            await cache.add(chapter: download.chapterIdentifier, url: directory)

            if download.type == .video {
                await DirectoryManager.shared.cleanupJunkFiles(in: directory)
            }
        } catch {
            LogManager.logger.error("Failed to finalize download: \(error)")
        }
    }

    private func getFinalDirectory(for download: Download) -> URL {
        let sourceName = download.sourceName ?? download.chapterIdentifier.sourceKey
        let seriesTitle = download.manga.title

        if download.type == .video {
            return DirectoryManager.shared.animeFinalDirectory(
                for: download,
                sourceName: sourceName,
                seriesTitle: seriesTitle
            )
        } else {
            let chapterName = download.chapter.title
            return DirectoryManager.shared.mangaReadableDirectory(
                for: download.chapterIdentifier,
                sourceName: sourceName,
                seriesTitle: seriesTitle,
                chapterName: chapterName
            )
        }
    }

    private func cleanupJunkFiles(in directory: URL) {
        Task {
            await DirectoryManager.shared.cleanupJunkFiles(in: directory)
        }
    }

    private func saveCoverIfMissing(download: Download, seriesTitle: String) async {
        let coverPath = DirectoryManager.shared.coverPathForDownload(
            download,
            sourceName: download.sourceName,
            seriesTitle: seriesTitle
        )
        guard !DirectoryManager.shared.directoryExists(at: coverPath) else {
            return
        }

        let coverUrlString = download.type == .video ? download.posterUrl : download.manga.cover
        _ = download.sourceName ?? download.chapterIdentifier.sourceKey

        await DirectoryManager.shared.saveCoverImage(
            coverUrlString: coverUrlString,
            to: coverPath,
            sourceKey: download.chapterIdentifier.sourceKey
        )
    }

    private func notifyDownloadFinished(download: Download) async {
        if let index = downloads.firstIndex(where: { $0 == download }) {
            downloads[index].status = .finished
            downloads.remove(at: index)
            await delegate?.downloadFinished(download: download)
        }
    }

    private func notifyDownloadCancelled(download: Download) async {
        if let index = downloads.firstIndex(where: { $0 == download }) {
            downloads[index].status = .cancelled
            downloads.remove(at: index)
            await delegate?.downloadCancelled(download: download)
        }
    }

    private func resetTaskProgress() {
        pages = []
        currentPage = 0
        failedPages = 0
    }

    private func downloadVideo() async {
        guard running && !downloads.isEmpty else { return }
        let download = downloads[0]
        downloads[0].status = .downloading

        // Download icon first
        await saveCoverIfMissing(download: download, seriesTitle: download.manga.title)

        guard let videoUrl = download.videoUrl else {
            await finishDownloadWithError(download)
            return
        }

        let resolved = await resolveVideoUrl(videoUrl, download: download)
        let resolvedUrl = resolved.url
        let resolvedHeaders = resolved.headers
        let resolvedSubtitleUrl = resolved.subtitleUrl

        guard running && !resolvedUrl.isEmpty else {
            if !running { return }
            await finishDownloadWithError(download)
            return
        }

        let finalDirectory = getFinalDirectory(for: download)
        guard await createDirectoryIfNeeded(finalDirectory) else {
            await finishDownloadWithError(download)
            return
        }

        do {
            let segments = try await extractVideoSegments(from: resolvedUrl, headers: resolvedHeaders)
            guard running else { return }
            guard !segments.isEmpty else {
                await finishDownloadWithError(download)
                return
            }

            downloads[0].total = segments.count
            await delegate?.downloadProgressChanged(download: downloads[0])

            let segmentDirectory = finalDirectory.appendingPathComponent("segments")
            try DirectoryManager.shared.createDirectory(at: segmentDirectory)

            try await downloadSegmentsParallel(segments, segmentDirectory, resolvedHeaders, download)
            guard running else { return }

            let episodeNumber = download.chapter.chapterNumber.map { String(format: "%g", $0) } ?? "0"
            let finalVideoFile = finalDirectory.appendingPathComponent("Episode \(episodeNumber)").appendingPathExtension("mp4")

            try await mergeSegments(at: segmentDirectory, to: finalVideoFile)
            guard running else { return }

            // Downloads subtitle
            if let subtitleUrl = resolvedSubtitleUrl, let subtitleUrlObj = URL(string: subtitleUrl) {
                let extensionName = subtitleUrlObj.pathExtension.isEmpty ? "srt" : subtitleUrlObj.pathExtension
                let subtitleFile = finalDirectory
                    .appendingPathComponent("Subtitle")
                    .appendingPathExtension(extensionName)
                try? await downloadSubtitle(from: subtitleUrl, to: subtitleFile, headers: resolvedHeaders)
            }

            guard finalVideoFile.exists else {
                LogManager.logger.error("Final video file was not created: \(finalVideoFile.path)")
                await finishDownloadWithError(download)
                return
            }

            // Clean up segments directory
            await cleanupSegmentsDirectory(segmentDirectory)
            await handleChapterDownloadFinish(download: download)
        } catch {
            if !running { return }
            await finishDownloadWithError(download)
        }
    }

    private struct ResolvedVideoData {
        let url: String
        let headers: [String: String]
        let subtitleUrl: String?
    }

    private func resolveVideoUrl(_ videoUrl: String, download: Download) async -> ResolvedVideoData {
        var resolvedUrl = videoUrl
        var resolvedHeaders = download.headers ?? [:]
        var resolvedSubtitleUrl = download.subtitleUrl

        if !resolvedUrl.lowercased().hasPrefix("http") {
            let sourceKey = download.chapterIdentifier.sourceKey
            let module = await MainActor.run { ModuleManager.shared.modules.first { $0.id.uuidString == sourceKey } }

            if let module = module {
                let (streamInfos, subtitle) = await JSController.shared.fetchPlayerStreams(episodeId: videoUrl, module: module)
                resolvedUrl = streamInfos.first?.url ?? videoUrl
                resolvedHeaders = streamInfos.first?.headers ?? [:]
                resolvedSubtitleUrl = subtitle ?? download.subtitleUrl
            }
        }

        // Common video streaming headers
        resolvedHeaders["User-Agent"] = Self.videoUserAgent
        resolvedHeaders["Accept"] = "*/*"
        resolvedHeaders["Accept-Language"] = "en-US,en;q=0.9"
        resolvedHeaders["Accept-Encoding"] = "gzip, deflate, br"
        resolvedHeaders["Connection"] = "keep-alive"
        resolvedHeaders["Referer"] = resolvedUrl

        return ResolvedVideoData(url: resolvedUrl, headers: resolvedHeaders, subtitleUrl: resolvedSubtitleUrl)
    }

    private func downloadSubtitle(from urlString: String, to targetPath: URL, headers: [String: String]) async throws {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
            try data.write(to: targetPath)
        }
    }

    private func createDirectoryIfNeeded(_ url: URL) async -> Bool {
        do {
            try DirectoryManager.shared.createDirectory(at: url)
            return true
        } catch {
            LogManager.logger.error("Failed to create directory: \(error)")
            return false
        }
    }

    private func extractVideoSegments(from url: String, headers: [String: String]) async throws -> [M3U8Extractor.M3U8Segment] {
        let extractor = M3U8Extractor.shared
        let streamUrl = try await extractor.resolveBestStreamUrl(url: url, headers: headers)
        guard running else { throw DownloadError.noSegmentsFound }

        let playlist = try await extractor.fetchAndParseM3U8(url: streamUrl, headers: headers)
        guard running else { throw DownloadError.noSegmentsFound }

        let segments = playlist.segments
        guard !segments.isEmpty else { throw DownloadError.noSegmentsFound }

        return segments
    }

    private func finishDownloadWithError(_ download: Download) async {
        failedPages = 1
        await handleChapterDownloadFinish(download: download)
    }

    private func cleanupSegmentsDirectory(_ directory: URL) async {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            LogManager.logger.error("Failed to clean up segments directory: \(error)")
        }
    }

    private func downloadSegmentsParallel(
        _ segments: [M3U8Extractor.M3U8Segment],
        _ directory: URL,
        _ headers: [String: String],
        _ download: Download
    ) async throws {
        let maxConcurrent = Self.maxConcurrentPageTasks
        let totalSegments = segments.count

        for chunk in Array(segments.enumerated()).chunked(into: maxConcurrent) {
            guard running && downloads.first == download else { return }

            let isRunning = running
            let firstDownload = downloads.first

            await withTaskGroup(of: Void.self) { group in
                for (index, segment) in chunk {
                    group.addTask {
                        guard isRunning && firstDownload == download else { return }

                        await self.downloadSingleSegment(
                            segment: segment,
                            index: index,
                            directory: directory,
                            headers: headers
                        )
                        let progressValue = index + 1
                        Task { [weak self] in
                            guard let self = self else { return }
                            await self.delegate?.downloadProgressChanged(
                                download: Download(
                                    chapterIdentifier: download.chapterIdentifier,
                                    status: download.status,
                                    type: download.type,
                                    progress: progressValue,
                                    total: totalSegments,
                                    manga: download.manga,
                                    chapter: download.chapter,
                                    videoUrl: download.videoUrl,
                                    posterUrl: download.posterUrl,
                                    headers: download.headers,
                                    sourceName: download.sourceName
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    private func downloadSingleSegment(
        segment: M3U8Extractor.M3U8Segment,
        index: Int,
        directory: URL,
        headers: [String: String]
    ) async {
        guard let segmentUrl = URL(string: segment.url) else { return }
        let segmentFile = directory.appendingPathComponent(String(format: "%05d.ts", index))

        guard !segmentFile.exists else { return }

        do {
            let request = createSegmentRequest(url: segmentUrl, headers: headers)
            let (data, _) = try await URLSession.shared.data(for: request)
            try data.write(to: segmentFile)
        } catch {
            LogManager.logger.error("Failed to download segment \(index): \(error)")
        }
    }

    private func createSegmentRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)

        if headers.isEmpty {
            request.setValue(Self.videoUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        } else {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }

    private func mergeSegments(at directory: URL, to destination: URL) async throws {
        let segmentFiles = directory.contents
            .filter { $0.pathExtension == "ts" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !segmentFiles.isEmpty else {
            throw NSError(domain: "DownloadTask", code: -2, userInfo: [NSLocalizedDescriptionKey: "No segments found to merge"])
        }

        let concatenatedTsFile = directory.appendingPathComponent("concatenated.ts")
        if concatenatedTsFile.exists {
            concatenatedTsFile.removeItem()
        }

        FileManager.default.createFile(atPath: concatenatedTsFile.path, contents: nil, attributes: nil)
        let fileHandle = try FileHandle(forWritingTo: concatenatedTsFile)
        for file in segmentFiles {
            let data = try Data(contentsOf: file)
            fileHandle.write(data)
        }
        try fileHandle.close()

        let asset = AVURLAsset(url: concatenatedTsFile)

        do {
            let tracks = try await asset.load(.tracks)
            guard !tracks.isEmpty else {
                throw NSError(domain: "DownloadTask", code: -3, userInfo: [NSLocalizedDescriptionKey: "Concatenated file has no tracks"])
            }

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                throw NSError(domain: "DownloadTask", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"])
            }

            if destination.exists {
                destination.removeItem()
            }

            exportSession.outputURL = destination
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true

            await exportSession.export()

            if let error = exportSession.error {
                throw error
            }

            concatenatedTsFile.removeItem()
        } catch {
            if destination.exists {
                destination.removeItem()
            }
            try FileManager.default.moveItem(at: concatenatedTsFile, to: destination)
        }
    }
}

// MARK: Utility
extension DownloadTask {
    private nonisolated func guessFileExtension(response: URLResponse, defaultValue: String) -> String {
        if let suggestedFilename = response.suggestedFilename, !suggestedFilename.isEmpty {
            return URL(string: suggestedFilename)?.pathExtension ?? defaultValue
        }
        guard
            let mimeType = response.mimeType,
            let type = UTType(mimeType: mimeType)
        else {
            return defaultValue
        }
        return type.preferredFilenameExtension ?? defaultValue
    }
}
