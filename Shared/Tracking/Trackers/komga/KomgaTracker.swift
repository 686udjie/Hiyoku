//
//  KomgaTracker.swift
//  Aidoku
//
//  Created by Skitty on 9/15/25.
//

import AidokuRunner
import Foundation

final class KomgaTracker: EnhancedTracker, PageTracker {
    let id = "komga"
    let name = NSLocalizedString("KOMGA")
    let icon = PlatformImage(named: "komga")

    let isLoggedIn = true

    private let api = KomgaApi()

    private let idSeparator: Character = "|"

    func getTrackerInfo() -> TrackerInfo {
        .init(supportedStatuses: [], scoreType: .tenPoint, scoreOptions: [])
    }

    func register(trackId: String, sourceId: String?, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? {
        guard !isPlayerSource(sourceId) else { return nil }
        guard let highestChapterRead else { return nil }

        let (sourceKey, seriesId) = try getIdParts(from: trackId)

        let state = try? await api.getState(sourceKey: sourceKey, seriesId: seriesId)
        if state?.lastReadVolume == nil || highestChapterRead > state?.lastReadChapter ?? 0 {
            try await api.update(
                sourceKey: sourceKey,
                seriesId: seriesId,
                update: .init(lastReadVolume: Int(floor(highestChapterRead)))
            )
        }

        return nil
    }

    func update(trackId: String, sourceId: String?, update: TrackUpdate) async throws {
        guard !isPlayerSource(sourceId) else { return }
        let (sourceKey, seriesId) = try getIdParts(from: trackId)
        try await api.update(
            sourceKey: sourceKey,
            seriesId: seriesId,
            update: update
        )
    }

    func getState(trackId: String, sourceId: String?) async throws -> TrackState {
        guard !isPlayerSource(sourceId) else { throw KomgaTrackerError.getStateFailed }
        let (sourceKey, seriesId) = try getIdParts(from: trackId)
        if let state = try await api.getState(sourceKey: sourceKey, seriesId: seriesId) {
            return state
        } else {
            throw KomgaTrackerError.getStateFailed
        }
    }

    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] {
        let state = try await api.getState(sourceKey: manga.sourceKey, seriesId: manga.key)
        if state != nil {
            return [.init(id: "\(manga.sourceKey)\(idSeparator)\(manga.key)", tracked: true)]
        } else {
            return []
        }
    }

    func getUrl(trackId: String, sourceId: String?) async -> URL? {
        nil // url is the same as the series url, so it's not necessary to provide
    }

    func canRegister(sourceKey: String, mangaKey: String) -> Bool {
        sourceKey.hasPrefix("komga")
    }

    func setProgress(trackId: String, chapter: AidokuRunner.Chapter, progress: ChapterReadProgress) async throws {
        let (sourceKey, _) = try getIdParts(from: trackId)
        try await api.updateReadProgress(
            sourceKey: sourceKey,
            bookId: chapter.key,
            progress: progress
        )
    }

    func getProgress(trackId: String, chapters: [AidokuRunner.Chapter]) async throws -> [String: ChapterReadProgress] {
        let (sourceKey, seriesId) = try getIdParts(from: trackId)
        return try await api.getSeriesReadProgress(sourceKey: sourceKey, seriesId: seriesId)
    }

    func logout() {
        fatalError("logout not implemented for komga tracker")
    }
}

extension KomgaTracker {
    private func getIdParts(from id: String) throws -> (sourceKey: String, seriesId: String) {
        let split = id.split(separator: idSeparator, maxSplits: 2).map(String.init)
        guard split.count == 2 else { throw KomgaTrackerError.invalidId }
        return (sourceKey: split[0], seriesId: split[1])
    }

    private func isPlayerSource(_ sourceId: String?) -> Bool {
        guard let sourceId = sourceId else { return false }
        return SourceManager.shared.source(for: sourceId) == nil
    }
}

enum KomgaTrackerError: Error {
    case invalidId
    case getStateFailed
    case notLoggedIn
}
