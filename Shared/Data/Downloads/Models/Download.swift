//
//  Download.swift
//  Aidoku
//
//  Created by Skitty on 5/14/22.
//

import AidokuRunner
import Foundation

enum DownloadStatus: Int, Codable {
    case none = 0
    case queued
    case downloading
    case paused
    case cancelled
    case finished
    case failed
}

enum DownloadType: Int, Codable {
    case manga = 0
    case video
}

struct Download: Equatable, Sendable, Codable {
    var mangaIdentifier: MangaIdentifier { chapterIdentifier.mangaIdentifier }
    let chapterIdentifier: ChapterIdentifier

    var status: DownloadStatus = .queued
    var type: DownloadType = .manga

    var progress: Int = 0
    var total: Int = 0

    var manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter

    // Video info
    var videoUrl: String?
    var posterUrl: String?
    var headers: [String: String]?
    var sourceName: String?

    static func == (lhs: Download, rhs: Download) -> Bool {
        lhs.chapterIdentifier == rhs.chapterIdentifier
    }

    static func from(
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        status: DownloadStatus = .queued,
        type: DownloadType = .manga,
        videoUrl: String? = nil,
        posterUrl: String? = nil,
        headers: [String: String]? = nil,
        sourceName: String? = nil
    ) -> Download {
        Download(
            chapterIdentifier: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
            status: status,
            type: type,
            progress: 0,
            total: 0,
            manga: manga,
            chapter: chapter,
            videoUrl: videoUrl,
            posterUrl: posterUrl,
            headers: headers,
            sourceName: sourceName
        )
    }
}

extension Download: Identifiable {
    var id: ChapterIdentifier { chapterIdentifier }
}
