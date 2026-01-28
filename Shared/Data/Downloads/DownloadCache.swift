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
    private func load() {
        rootDirectory.subdirectories = [:]

        for sourceDirectory in DownloadManager.directory.contents where sourceDirectory.isDirectory {
            var mangaDirectoriesMap: [String: Directory] = [:]

            for mangaDirectory in sourceDirectory.contents where mangaDirectory.isDirectory {
                var chapterDirectories: [String: Directory] = [:]

                for chapterFileOrDirectory in mangaDirectory.contents {
                    let key = if chapterFileOrDirectory.pathExtension.isEmpty {
                        chapterFileOrDirectory.lastPathComponent
                    } else {
                        // this handles .cbz or other files
                        chapterFileOrDirectory.deletingPathExtension().lastPathComponent
                    }
                    chapterDirectories[key.directoryName] = Directory(url: chapterFileOrDirectory)
                }

                mangaDirectoriesMap[mangaDirectory.lastPathComponent.directoryName] = Directory(
                    url: mangaDirectory,
                    subdirectories: chapterDirectories
                )
            }
            rootDirectory.subdirectories[sourceDirectory.lastPathComponent.directoryName] = Directory(
                url: sourceDirectory,
                subdirectories: mangaDirectoriesMap
            )
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
                if
                    let string = String(data: data, encoding: .utf8),
                    let comicInfo = ComicInfo.load(xmlString: string)
                {
                    return comicInfo
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
        return rootDirectory.subdirectories[sk]?.subdirectories[mk]?.url ?? directory(for: identifier)
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
        DownloadManager.directory
            .appendingSafePathComponent(sourceKey)
    }

    nonisolated func directory(for manga: MangaIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(manga.sourceKey)
            .appendingSafePathComponent(manga.mangaKey)
    }

    nonisolated func directory(for chapter: ChapterIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(chapter.sourceKey)
            .appendingSafePathComponent(chapter.mangaKey)
            .appendingSafePathComponent(chapter.chapterKey)
    }

    nonisolated func tmpDirectory(for chapter: ChapterIdentifier) -> URL {
        DownloadManager.directory
            .appendingSafePathComponent(chapter.sourceKey)
            .appendingSafePathComponent(chapter.mangaKey)
            .appendingSafePathComponent(".tmp_\(chapter.chapterKey.directoryName)")
    }

    nonisolated func readableDirectory(for chapter: ChapterIdentifier, sourceName: String?, seriesTitle: String?, episodeName: String?) -> URL {
        let s = sourceName ?? chapter.sourceKey
        let m = seriesTitle ?? chapter.mangaKey
        let c = episodeName ?? chapter.chapterKey

        return DownloadManager.directory
            .appendingSafePathComponent(s)
            .appendingSafePathComponent(m)
            .appendingSafePathComponent(c)
    }
}
