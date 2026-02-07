//
//  DownloadedVideoInfo.swift
//  Hiyoku
//
//  Created by 686udjie on 01/27/26.
//

import Foundation

struct DownloadedVideoInfo: Identifiable, Hashable {
    let id: String
    let sourceId: String
    let seriesId: String
    let title: String?
    let coverUrl: String?
    let totalSize: Int64
    let videoCount: Int
    let isInLibrary: Bool

    var displayTitle: String {
        title ?? NSLocalizedString(seriesId, comment: "")
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    init(
        sourceId: String,
        seriesId: String,
        title: String? = nil,
        coverUrl: String? = nil,
        totalSize: Int64,
        videoCount: Int,
        isInLibrary: Bool
    ) {
        self.id = "\(sourceId)_\(seriesId)"
        self.sourceId = sourceId
        self.seriesId = seriesId
        self.title = title
        self.coverUrl = coverUrl
        self.totalSize = totalSize
        self.videoCount = videoCount
        self.isInLibrary = isInLibrary
    }
}

struct DownloadedVideoItemInfo: Identifiable, Hashable {
    let id: String
    let videoKey: String
    let title: String?
    let videoNumber: Int?
    let size: Int64
    let downloadDate: Date?

    var displayTitle: String {
        if let videoNumber = videoNumber {
            let base = String(format: NSLocalizedString("EPISODE_X", comment: ""), videoNumber)
            if let title = title, !title.isEmpty, title != base {
                return "\(base) - \(title)"
            }
            return title ?? base
        }
        return title ?? NSLocalizedString(videoKey, comment: "")
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func toPlayerEpisode() -> PlayerEpisode {
        PlayerEpisode(
            number: videoNumber ?? 0,
            title: displayTitle,
            url: videoKey
        )
    }
}
