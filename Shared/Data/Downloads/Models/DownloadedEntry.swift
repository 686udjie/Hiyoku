//
//  DownloadedEntry.swift
//  Hiyoku
//
//  Created by 686udjie on 01/27/26.
//

import Foundation

/// A unified protocol for downloaded manga and videos
protocol DownloadedEntry: Identifiable, Hashable {
   var id: String { get }
   var sourceId: String { get }
   var mangaId: String { get }
   var title: String? { get }
   var coverUrl: String? { get }
   var totalSize: Int64 { get }
   var unitCount: Int { get }
   var type: DownloadType { get }
   var isInLibrary: Bool { get }
}

extension DownloadedEntry {
   var displayTitle: String {
       title ?? mangaId
   }

   var formattedSize: String {
       ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
   }
}

extension DownloadedMangaInfo: DownloadedEntry {
   var unitCount: Int { chapterCount }
   var type: DownloadType { .manga }
}

extension  DownloadedVideoInfo: DownloadedEntry {
   var mangaId: String { seriesId }
   var unitCount: Int { videoCount }
   var type: DownloadType { .video }
}
