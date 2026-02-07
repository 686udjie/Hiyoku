//
//  DownloadCache.swift
//  Aidoku
//
//  Created by Skitty on 5/13/22.
//

import Foundation

// cache of downloads directory contents on the filesystem
// TODO: should probably be reloaded every once in a while so we can recheck filesystem for user modifications
@MainActor
class DownloadCache {
    struct Directory {
        var url: URL
        var subdirectories: [String: Directory] = [:]
    }

    private var rootDirectory = Directory(url: DownloadManager.directory)
    private var loaded = false

    // create cache from filesystem
    func load() {
        rootDirectory.subdirectories = [:]

        for sourceDirectory in DownloadManager.directory.contents where sourceDirectory.isDirectory {
            let sourceDirName = sourceDirectory.lastPathComponent.directoryName
            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                let mangaDirName = mangaDirectory.lastPathComponent.directoryName
                var comicInfo = getComicInfo(in: mangaDirectory)
                var extraData = comicInfo?.extraData()
                if extraData == nil {
                    for chapterFileOrDirectory in mangaDirectory.contents {
                        if let chapterInfo = getComicInfo(in: chapterFileOrDirectory), let chapterData = chapterInfo.extraData() {
                            comicInfo = chapterInfo
                            extraData = chapterData
                            break
                        }
                    }
                }
                let actualSourceKey = extraData?.sourceKey?.directoryName ?? sourceDirName
                let actualMangaKey = extraData?.mangaKey?.directoryName ?? mangaDirName

                var chapterDirectories: [String: Directory] = [:]

                for chapterFileOrDirectory in mangaDirectory.contents {
                    let chapterFileName = if chapterFileOrDirectory.pathExtension.isEmpty {
                        chapterFileOrDirectory.lastPathComponent
                    } else {
                        chapterFileOrDirectory.deletingPathExtension().lastPathComponent
                    }
                    let chapterComicInfo = getComicInfo(in: chapterFileOrDirectory)
                    let chapterExtraData = chapterComicInfo?.extraData()
                    let actualChapterKey = chapterExtraData?.chapterKey?.directoryName ?? chapterFileName.directoryName
                    chapterDirectories[actualChapterKey] = Directory(url: chapterFileOrDirectory)
                    if actualChapterKey != chapterFileName.directoryName {
                        chapterDirectories[chapterFileName.directoryName] = Directory(url: chapterFileOrDirectory)
                    }
                }

                let mangaDirObj = Directory(
                    url: mangaDirectory,
                    subdirectories: chapterDirectories
                )
                if rootDirectory.subdirectories[actualSourceKey] == nil {
                    rootDirectory.subdirectories[actualSourceKey] = Directory(url: sourceDirectory)
                }
                rootDirectory.subdirectories[actualSourceKey]?.subdirectories[actualMangaKey] = mangaDirObj
                if actualSourceKey != sourceDirName {
                    if rootDirectory.subdirectories[sourceDirName] == nil {
                        rootDirectory.subdirectories[sourceDirName] = Directory(url: sourceDirectory)
                    }
                    rootDirectory.subdirectories[sourceDirName]?.subdirectories[actualMangaKey] = mangaDirObj
                }
                if actualMangaKey != mangaDirName {
                    rootDirectory.subdirectories[actualSourceKey]?.subdirectories[mangaDirName] = mangaDirObj
                }
            }
        }
        loaded = true
    }

    private func getComicInfo(in directory: URL) -> ComicInfo? {
        do {
            if !directory.isDirectory && directory.pathExtension == "cbz" {
                return ComicInfo.load(from: directory)
            }

            guard directory.isDirectory else { return nil }

            let xmlURL = directory.appendingPathComponent("ComicInfo.xml")
            if xmlURL.exists {
                let data = try Data(contentsOf: xmlURL)
                if let string = String(data: data, encoding: .utf8) {
                    if let comicInfo = ComicInfo.load(xmlString: string) {
                        return comicInfo
                    }
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    func add(chapter: ChapterIdentifier, url: URL? = nil) {
        if !loaded { load() }

        let sourceKey = chapter.sourceKey.directoryName
        let mangaKey = chapter.mangaKey.directoryName
        let chapterKey = chapter.chapterKey.directoryName

        let finalUrl = url ?? directory(for: chapter)
        let mangaUrl = finalUrl.deletingLastPathComponent()
        let sourceUrl = mangaUrl.deletingLastPathComponent()

        if rootDirectory.subdirectories[sourceKey] == nil {
            rootDirectory.subdirectories[sourceKey] = Directory(url: sourceUrl)
        }

        if rootDirectory.subdirectories[sourceKey]?.subdirectories[mangaKey] == nil {
            rootDirectory.subdirectories[sourceKey]?.subdirectories[mangaKey] = Directory(url: mangaUrl)
        }

        rootDirectory.subdirectories[sourceKey]?.subdirectories[mangaKey]?.subdirectories[chapterKey] = Directory(url: finalUrl)
    }

    func remove(manga: MangaIdentifier) {
        rootDirectory.subdirectories[manga.sourceKey.directoryName]?
            .subdirectories[manga.mangaKey.directoryName] = nil
    }

    func remove(chapter: ChapterIdentifier) {
        rootDirectory.subdirectories[chapter.sourceKey.directoryName]?
            .subdirectories[chapter.mangaKey.directoryName]?
            .subdirectories[chapter.chapterKey.directoryName] = nil
    }

    func removeAll() {
        DownloadManager.directory.removeItem()
        load()
    }

    func refresh() {
        loaded = false
        load()
    }
}

extension DownloadCache {
    // check if a chapter has a download directory
    func isChapterDownloaded(identifier: ChapterIdentifier) -> Bool {
        if !loaded { load() }
        guard
            let sourceDirectory = rootDirectory.subdirectories[identifier.sourceKey.directoryName],
            let mangaDirectory = sourceDirectory.subdirectories[identifier.mangaKey.directoryName]
        else {
            return false
        }
        return mangaDirectory.subdirectories[identifier.chapterKey.directoryName] != nil
    }

    // check if any chapter subdirectories exist
    func hasDownloadedChapter(from identifier: MangaIdentifier) -> Bool {
        if !loaded { load() }
        guard
            let sourceDirectory = rootDirectory.subdirectories[identifier.sourceKey.directoryName],
            let mangaDirectory = sourceDirectory.subdirectories[identifier.mangaKey.directoryName]
        else {
            return false
        }
        return mangaDirectory.subdirectories.contains { !$0.value.url.lastPathComponent.hasPrefix(".tmp") }
    }

    // MARK: Cache-aware Directory Getters

    func getSourceDirectory(sourceKey: String) -> URL {
        if !loaded { load() }
        let sk = sourceKey.directoryName
        return rootDirectory.subdirectories[sk]?.url ?? directory(sourceKey: sourceKey)
    }

    func getMangaDirectory(for identifier: MangaIdentifier) -> URL {
        if !loaded { load() }
        let sk = identifier.sourceKey.directoryName
        let mk = identifier.mangaKey.directoryName
        let url = rootDirectory.subdirectories[sk]?.subdirectories[mk]?.url ?? directory(for: identifier)
        return url
    }

    func getDirectory(for identifier: ChapterIdentifier) -> URL {
        if !loaded { load() }
        let sk = identifier.sourceKey.directoryName
        let mk = identifier.mangaKey.directoryName
        let ck = identifier.chapterKey.directoryName

        return rootDirectory.subdirectories[sk]?.subdirectories[mk]?.subdirectories[ck]?.url ?? directory(for: identifier)
    }
}

// MARK: Directory Provider
extension DownloadCache {
    nonisolated func directory(sourceKey: String) -> URL {
        DirectoryManager.shared.mangaSeriesDirectory(for: MangaIdentifier(sourceKey: sourceKey, mangaKey: ""))
    }

    nonisolated func directory(for manga: MangaIdentifier) -> URL {
        DirectoryManager.shared.mangaEntryDirectory(sourceKey: manga.sourceKey, mangaTitle: manga.mangaKey)
    }

    nonisolated func directory(for chapter: ChapterIdentifier) -> URL {
        DirectoryManager.shared.mangaChapterDirectory(
            sourceKey: chapter.sourceKey,
            mangaTitle: chapter.mangaKey,
            chapterTitle: chapter.chapterKey
        )
    }

    nonisolated func tmpDirectory(for chapter: ChapterIdentifier) -> URL {
        DirectoryManager.shared.mangaTempDirectory(sourceKey: chapter.sourceKey, mangaTitle: chapter.mangaKey)
    }

    nonisolated func readableDirectory(for chapter: ChapterIdentifier, sourceName: String?, seriesTitle: String?, episodeName: String?) -> URL {
        DirectoryManager.shared.mangaReadableDirectory(
            for: chapter,
            sourceName: sourceName,
            seriesTitle: seriesTitle,
            chapterName: episodeName
        )
    }

    nonisolated func moduleDirectory(for sourceKey: String, moduleName: String? = nil) -> URL {
        DirectoryManager.shared.animeModuleDirectory(sourceKey: sourceKey, moduleName: moduleName)
    }

    nonisolated func moduleSeriesDirectory(for sourceKey: String, moduleName: String?, seriesTitle: String) -> URL {
        DirectoryManager.shared.animeSeriesDirectory(sourceKey: sourceKey, moduleName: moduleName, seriesTitle: seriesTitle)
    }

    nonisolated func moduleEpisodeDirectory(for sourceKey: String, moduleName: String?, seriesTitle: String, episodeName: String) -> URL {
        DirectoryManager.shared.animeEpisodeDirectory(
            sourceKey: sourceKey,
            moduleName: moduleName,
            seriesTitle: seriesTitle,
            episodeName: episodeName
        )
    }
}
