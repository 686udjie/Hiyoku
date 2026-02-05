//
//  DownloadStatusTracker.swift
//  Hiyoku
//
//  Created by 686udjie on 01/27/26.
//

import Foundation
import Combine
import AidokuRunner

@MainActor
class DownloadStatusTracker: ObservableObject {
    @Published var downloadStatus: [String: DownloadStatus] = [:]
    @Published var downloadProgress: [String: Float] = [:]

    let sourceId: String
    let mangaId: String
    private var cancellables = Set<AnyCancellable>()

    init(sourceId: String, mangaId: String) {
        self.sourceId = sourceId
        self.mangaId = mangaId
        setupObservers()
    }

    func loadStatus(for chapterKeys: [String]) async {
        let identifier = MangaIdentifier(sourceKey: sourceId, mangaKey: mangaId)
        let downloadedKeys = await DownloadManager.shared.getDownloadedChapterKeys(for: identifier)
        for key in chapterKeys {
            if downloadedKeys.contains(key) {
                downloadStatus[key] = .finished
                downloadProgress.removeValue(forKey: key)
                continue
            }
            let chapterIdentifier = ChapterIdentifier(
                sourceKey: sourceId,
                mangaKey: mangaId,
                chapterKey: key
            )
            let status = DownloadManager.shared.getDownloadStatus(for: chapterIdentifier)
            downloadStatus[key] = status
            if status == .finished {
                downloadProgress.removeValue(forKey: key)
            }
        }
    }

    private func setupObservers() {
        let center = NotificationCenter.default

        // Progress and status updates
        center.publisher(for: .downloadProgressed)
            .compactMap { $0.object as? Download }
            .filter { [weak self] in self?.isRelevant($0) ?? false }
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] download in
                guard let self = self else { return }
                let key = download.chapterIdentifier.chapterKey
                // im sorry ik this is shit i js don't know why ts not showing
                if self.downloadStatus[key] == .finished { return }
                self.downloadStatus[key] = .downloading
                self.downloadProgress[key] = Float(download.progress) / Float(download.total)
            }
            .store(in: &cancellables)

        center.publisher(for: .downloadsQueued)
            .compactMap { $0.object as? [Download] }
            .sink { [weak self] downloads in
                guard let self = self else { return }
                for download in downloads where isRelevant(download) {
                    let key = download.chapterIdentifier.chapterKey
                    self.downloadStatus[key] = .queued
                    self.downloadProgress[key] = 0
                }
            }
            .store(in: &cancellables)

        // Termination and removal updates
        let singleUpdates = [Notification.Name.downloadFinished, .downloadRemoved, .downloadCancelled]
        Publishers.MergeMany(singleUpdates.map { center.publisher(for: $0) })
            .sink { [weak self] in self?.handleSingleDownloadChange($0) }
            .store(in: &cancellables)

        let bulkUpdates = [Notification.Name.downloadsRemoved, .downloadsCancelled]
        Publishers.MergeMany(bulkUpdates.map { center.publisher(for: $0) })
            .sink { [weak self] in self?.handleBulkDownloadChange($0) }
            .store(in: &cancellables)
    }

    private func isRelevant(_ download: Download) -> Bool {
        download.chapterIdentifier.sourceKey == sourceId && download.chapterIdentifier.mangaKey == mangaId
    }

    private func handleSingleDownloadChange(_ notification: Notification) {
        let identifier = (notification.object as? ChapterIdentifier) ?? (notification.object as? Download)?.chapterIdentifier
        guard let identifier, identifier.sourceKey == sourceId, identifier.mangaKey == mangaId else { return }

        downloadProgress.removeValue(forKey: identifier.chapterKey)
        downloadStatus[identifier.chapterKey] = DownloadManager.shared.getDownloadStatus(for: identifier)
    }

    private func handleBulkDownloadChange(_ notification: Notification) {
        if let chapters = notification.object as? [ChapterIdentifier] {
            for chapter in chapters where chapter.sourceKey == sourceId && chapter.mangaKey == mangaId {
                downloadProgress.removeValue(forKey: chapter.chapterKey)
                downloadStatus[chapter.chapterKey] = DownloadStatus.none
            }
        } else if let manga = notification.object as? MangaIdentifier, manga.sourceKey == sourceId && manga.mangaKey == mangaId {
            downloadProgress.removeAll()
            downloadStatus.keys.forEach { downloadStatus[$0] = DownloadStatus.none }
        }
    }
}
