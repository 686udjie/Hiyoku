//
//  DirectoryManager.swift
//  Hiyoku
//
//  Created by 686udjie on 1/30/26.
//

import Foundation

/// Centralized directory management for the player and reader (Aidoku)

actor DirectoryManager {

    static let shared = DirectoryManager()

    private let baseDirectory = FileManager.default.documentDirectory.appendingPathComponent("Downloads", isDirectory: true)

    private init() {}

    // MARK: - Base Directory

    nonisolated var downloadsDirectory: URL {
        baseDirectory
    }

    // MARK: - Reader Directories

    /// source.key = folder name
    nonisolated func mangaSourceDirectory(sourceKey: String, sourceName: String? = nil) -> URL {
        baseDirectory.appendingSafePathComponent(sourceKey)
    }

    nonisolated func mangaEntryDirectory(sourceKey: String, mangaTitle: String) -> URL {
        // Source/[Entry Title]/
        baseDirectory.appendingSafePathComponent(sourceKey).appendingSafePathComponent(mangaTitle)
    }

    /// Get the cache directory within entry folder for downloads
    nonisolated func mangaTempDirectory(sourceKey: String, mangaTitle: String) -> URL {
        mangaEntryDirectory(sourceKey: sourceKey, mangaTitle: mangaTitle).appendingSafePathComponent("cache")
    }

    nonisolated func mangaChapterDirectory(sourceKey: String, mangaTitle: String, chapterTitle: String) -> URL {
        mangaEntryDirectory(sourceKey: sourceKey, mangaTitle: mangaTitle).appendingSafePathComponent(chapterTitle)
    }

    func cleanupMangaTempFolders(sourceKey: String, mangaTitle: String) {
        let entryDir = mangaEntryDirectory(sourceKey: sourceKey, mangaTitle: mangaTitle)
        let contents = directoryContents(at: entryDir)

        for item in contents where item.hasDirectoryPath {
            let folderName = item.lastPathComponent.lowercased()
            if folderName == "temp" || folderName.hasPrefix(".tmp") {
                removeDirectory(at: item)
            }
        }
    }

    nonisolated func mangaSeriesDirectory(for manga: MangaIdentifier) -> URL {
        baseDirectory
            .appendingSafePathComponent(manga.sourceKey)
            .appendingSafePathComponent(manga.mangaKey)
    }

    // MARK: - Player Directories

    nonisolated func animeModuleDirectory(sourceKey: String, moduleName: String? = nil) -> URL {
        let name = moduleName ?? sourceKey
        return baseDirectory.appendingSafePathComponent(name)
    }

    nonisolated func animeSeriesDirectory(sourceKey: String, moduleName: String? = nil, seriesTitle: String) -> URL {
        animeModuleDirectory(sourceKey: sourceKey, moduleName: moduleName)
            .appendingSafePathComponent(seriesTitle)
    }

    nonisolated func animeEpisodeDirectory(
        sourceKey: String,
        moduleName: String? = nil,
        seriesTitle: String,
        episodeName: String
    ) -> URL {
        animeSeriesDirectory(sourceKey: sourceKey, moduleName: moduleName, seriesTitle: seriesTitle)
            .appendingSafePathComponent(episodeName)
    }

    nonisolated func animeFinalDirectory(
        for download: Download,
        sourceName: String? = nil,
        seriesTitle: String? = nil,
        episodeName: String? = nil
    ) -> URL {
        let moduleName = sourceName ?? download.chapterIdentifier.sourceKey
        let title = seriesTitle ?? download.manga.title
        let episode = episodeName ?? "Episode \(download.chapter.chapterNumber.map { String(format: "%g", $0) } ?? "0")"

        return animeEpisodeDirectory(
            sourceKey: download.chapterIdentifier.sourceKey,
            moduleName: moduleName,
            seriesTitle: title,
            episodeName: episode
        )
    }

    // MARK: - Readable Directories (for user-facing paths)

    nonisolated func mangaReadableDirectory(
        for chapter: ChapterIdentifier,
        sourceName: String?,
        seriesTitle: String?,
        chapterName: String?
    ) -> URL {
        let source = sourceName ?? chapter.sourceKey
        let manga = seriesTitle ?? chapter.mangaKey
        let chapterFile = chapterName ?? chapter.chapterKey

        return baseDirectory
            .appendingSafePathComponent(source)
            .appendingSafePathComponent(manga)
            .appendingSafePathComponent(chapterFile)
    }

    // MARK: - Directory Operations

    nonisolated func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    nonisolated func removeDirectory(at url: URL) {
        guard url.hasDirectoryPath else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            LogManager.logger.error("Failed to remove directory at \(url.path): \(error)")
        }
    }

    nonisolated func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    nonisolated func directoryContents(at url: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
    }

    // MARK: - Cleanup Operations

    func cleanupJunkFiles(in directory: URL) {
        // Check if directory exists before attempting cleanup
        guard FileManager.default.fileExists(atPath: directory.path) else {
            LogManager.logger.info("Directory does not exist for cleanup: \(directory.path)")
            return
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

            for item in contents {
                let fileName = item.lastPathComponent.lowercased()

                if fileName == "segments" && item.hasDirectoryPath {
                    try? FileManager.default.removeItem(at: item)
                    continue
                }
                // clean junk
                let junkExtensions = [".tmp", ".part", ".m3u8", ".ts", ".log"]
                for ext in junkExtensions where fileName.hasSuffix(ext) {
                    try? FileManager.default.removeItem(at: item)
                    break
                }
            }
        } catch {
            LogManager.logger.error("Error cleaning up junk files in directory \(directory): \(error)")
        }
    }

    func cleanupTemporaryDirectories(for sourceKey: String) {
        let sourceDirectory = baseDirectory.appendingSafePathComponent(sourceKey)
        let contents = directoryContents(at: sourceDirectory)

        for item in contents where item.lastPathComponent.hasPrefix(".tmp") {
            removeDirectory(at: item)
        }
    }

    func cleanupAllTemporaryDirectories() {
        let contents = directoryContents(at: baseDirectory)

        for sourceDirectory in contents where sourceDirectory.hasDirectoryPath {
            let sourceKey = sourceDirectory.lastPathComponent
            cleanupTemporaryDirectories(for: sourceKey)
        }
    }

    // MARK: - Cover Image Handling

    nonisolated func mangaCoverPath(for manga: MangaIdentifier, mangaTitle: String) -> URL {
        mangaEntryDirectory(sourceKey: manga.sourceKey, mangaTitle: mangaTitle).appendingPathComponent("cover.jpg")
    }

    nonisolated func animeCoverPath(for sourceKey: String, moduleName: String?, seriesTitle: String) -> URL {
        let module = moduleName ?? sourceKey
        return baseDirectory
            .appendingSafePathComponent(module)
            .appendingSafePathComponent(seriesTitle)
            .appendingSafePathComponent("icon.jpg")
    }

    func saveCoverImage(
        coverUrlString: String?,
        to coverPath: URL,
        sourceKey: String
    ) async {
        let coverExists = FileManager.default.fileExists(atPath: coverPath.path)

        guard let coverUrlString = coverUrlString else {
            return
        }

        guard let coverUrl = URL(string: coverUrlString) else {
            return
        }

        guard !coverExists else {
            return
        }

        let source = SourceManager.shared.source(for: sourceKey)
        let request = await source?.getModifiedImageRequest(url: coverUrl, context: nil) ?? URLRequest(url: coverUrl)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            let parentDir = coverPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            try data.write(to: coverPath)
        } catch {
            LogManager.logger.error("Failed to save cover image: \(error)")
        }
    }

    // MARK: - Directory Size and Info

    nonisolated func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            } catch {
                continue
            }
        }
        return totalSize
    }

    nonisolated func formattedDirectorySize(at url: URL) -> String {
        let bytes = directorySize(at: url)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension DirectoryManager {

    nonisolated func directoryForDownload(
        _ download: Download,
        isTemporary: Bool = false,
        sourceName: String? = nil,
        seriesTitle: String? = nil,
        episodeName: String? = nil
    ) -> URL {
        switch download.type {
        case .manga:
            let mangaTitle = seriesTitle ?? download.manga.title
            if isTemporary {
                return mangaTempDirectory(
                    sourceKey: download.chapterIdentifier.sourceKey,
                    mangaTitle: mangaTitle
                )
            } else {
                let chapterTitle = download.chapter.title ?? "Chapter \(download.chapter.chapterNumber ?? 0)"
                return mangaChapterDirectory(
                    sourceKey: download.chapterIdentifier.sourceKey,
                    mangaTitle: mangaTitle,
                    chapterTitle: chapterTitle
                )
            }
        case .video:
            return animeFinalDirectory(
                for: download,
                sourceName: sourceName,
                seriesTitle: seriesTitle,
                episodeName: episodeName
            )
        }
    }

    /// find cover path for a download
    nonisolated func coverPathForDownload(
        _ download: Download,
        sourceName: String? = nil,
        seriesTitle: String? = nil
    ) -> URL {
        switch download.type {
        case .manga:
            let mangaTitle = seriesTitle ?? download.manga.title
            return mangaCoverPath(for: download.mangaIdentifier, mangaTitle: mangaTitle)
        case .video:
            let moduleName = sourceName ?? download.chapterIdentifier.sourceKey
            let title = seriesTitle ?? download.manga.title
            return animeCoverPath(
                for: download.chapterIdentifier.sourceKey,
                moduleName: moduleName,
                seriesTitle: title
            )
        }
    }
}
