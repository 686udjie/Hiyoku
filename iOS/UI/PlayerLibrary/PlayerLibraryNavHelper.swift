//
//  PlayerLibraryNavHelper.swift
//  Hiyoku
//
//  Created by 686udjie on 01/03/2026.
//

import UIKit
import AidokuRunner
import CoreData
import SwiftUI

@MainActor
class PlayerLibraryNavHelper {
    static func openPlayerView(
        for bookmark: PlayerLibraryItem,
        module: ScrapingModule,
        from viewController: UIViewController,
        onRefresh: @escaping () async -> Void
    ) async {
        let episodes = (await JSController.shared.fetchPlayerEpisodes(contentUrl: bookmark.sourceUrl, module: module))
            .sorted { $0.number < $1.number }
        guard !episodes.isEmpty else {
            presentError(message: "No episodes available", from: viewController)
            return
        }

        let history = await getEpisodeHistory(
            sourceId: module.id.uuidString,
            episodeIds: Set(episodes.map(\.url))
        )
        guard let selectedEpisode = resolveEpisodeToPlay(from: episodes, history: history) else {
            presentError(message: "Unable to select an episode to play", from: viewController)
            return
        }

        let (streamInfos, subtitleUrl) = await JSController.shared.fetchPlayerStreams(
            episodeId: selectedEpisode.url,
            module: module
        )
        guard let stream = selectStream(streamInfos) else {
            presentError(message: "Unable to find video stream for this episode", from: viewController)
            return
        }

        let episodeToPlay = PlayerEpisode(
            id: selectedEpisode.id,
            number: selectedEpisode.number,
            title: selectedEpisode.title,
            url: selectedEpisode.url,
            dateUploaded: selectedEpisode.dateUploaded,
            scanlator: selectedEpisode.scanlator,
            language: selectedEpisode.language,
            subtitleUrl: subtitleUrl ?? selectedEpisode.subtitleUrl
        )

        PlayerPresenter.present(
            module: module,
            videoUrl: stream.url,
            videoTitle: bookmark.title,
            headers: stream.headers,
            subtitleUrl: episodeToPlay.subtitleUrl,
            episodes: episodes,
            currentEpisode: episodeToPlay,
            mangaId: bookmark.sourceUrl.normalizedModuleHref(),
            onDismiss: {
                Task {
                    await onRefresh()
                }
            },
            onNextEpisode: {
                Task { @MainActor in
                    await navigateRelativeEpisode(step: 1, module: module, episodes: episodes, title: bookmark.title)
                }
            },
            onPreviousEpisode: {
                Task { @MainActor in
                    await navigateRelativeEpisode(step: -1, module: module, episodes: episodes, title: bookmark.title)
                }
            },
            onEpisodeSelected: { episode in
                Task { @MainActor in
                    await navigateToEpisode(episode, module: module, episodes: episodes, title: bookmark.title)
                }
            }
        )
    }

    private static func resolveEpisodeToPlay(
        from episodes: [PlayerEpisode],
        history: [String: PlayerProgress]
    ) -> PlayerEpisode? {
        if let resumed = episodes.first(where: {
            guard let entry = history[$0.url], let total = entry.total, total > 0 else { return false }
            return entry.progress > 0 && entry.progress < total
        }) {
            return resumed
        }

        if let firstUnwatched = episodes.first(where: {
            guard let entry = history[$0.url], let total = entry.total, total > 0 else { return true }
            return entry.progress < total
        }) {
            return firstUnwatched
        }

        return episodes.first
    }

    private static func getEpisodeHistory(sourceId: String, episodeIds: Set<String>) async -> [String: PlayerProgress] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            guard !episodeIds.isEmpty else { return [:] }

            let request: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
            request.predicate = NSPredicate(
                format: "moduleId == %@ AND episodeId IN %@",
                sourceId,
                Array(episodeIds)
            )

            do {
                let objects = try context.fetch(request)
                return objects.reduce(into: [String: PlayerProgress]()) { result, object in
                    guard let episodeId = object.episodeId else { return }
                    let progress = Int(object.progress)
                    let total = object.total != 0 ? Int(object.total) : nil
                    let date = Int(object.dateWatched?.timeIntervalSince1970 ?? 0)
                    result[episodeId] = PlayerProgress(progress: progress, total: total, date: date)
                }
            } catch {
                return [:]
            }
        }
    }

    static func navigateRelativeEpisode(step: Int, module: ScrapingModule, episodes: [PlayerEpisode], title: String) async {
        guard
            let vc = PlayerPresenter.findTopViewController() as? PlayerViewController,
            let currentUrl = vc.currentEpisode?.url,
            let currentIndex = episodes.firstIndex(where: { $0.url == currentUrl })
        else {
            return
        }

        let newIndex = currentIndex + step
        guard episodes.indices.contains(newIndex) else { return }
        await navigateToEpisode(episodes[newIndex], module: module, episodes: episodes, title: title)
    }

    static func navigateToEpisode(_ episode: PlayerEpisode, module: ScrapingModule, episodes: [PlayerEpisode], title: String) async {
        guard let vc = PlayerPresenter.findTopViewController() as? PlayerViewController else { return }

        let (streamInfos, subtitleUrl) = await JSController.shared.fetchPlayerStreams(
            episodeId: episode.url,
            module: module
        )
        guard let stream = selectStream(streamInfos) else { return }

        let episodeToPlay = PlayerEpisode(
            id: episode.id,
            number: episode.number,
            title: episode.title,
            url: episode.url,
            dateUploaded: episode.dateUploaded,
            scanlator: episode.scanlator,
            language: episode.language,
            subtitleUrl: subtitleUrl ?? episode.subtitleUrl
        )

        vc.loadVideo(url: stream.url, headers: stream.headers, subtitleUrl: episodeToPlay.subtitleUrl)
        vc.updateTitle("Episode \(episodeToPlay.number): \(episodeToPlay.title)")
        vc.configure(episodes: episodes, current: episodeToPlay, title: title)
    }

    static func selectStream(_ streams: [StreamInfo]) -> StreamInfo? {
        guard !streams.isEmpty else { return nil }

        let preferredAudioChannel = UserDefaults.standard.string(forKey: "Player.preferredAudioChannel") ?? "SUB"
        let audioFiltered = streams.filter { $0.title.lowercased().contains(preferredAudioChannel.lowercased()) }
        let streamsToUse = audioFiltered.isEmpty ? streams : audioFiltered

        let targetResolution: String = {
            switch Reachability.getConnectionType() {
            case .wifi:
                return UserDefaults.standard.string(forKey: "Player.preferredResolutionWifi") ?? "auto"
            case .cellular:
                return UserDefaults.standard.string(forKey: "Player.preferredResolutionCellular") ?? "auto"
            case .none:
                return "auto"
            }
        }()
        guard targetResolution.lowercased() != "auto" else {
            return streamsToUse.first
        }

        guard let target = parseResolution(targetResolution) else {
            return streamsToUse.first
        }

        let candidates = streamsToUse.compactMap { stream -> (StreamInfo, Int)? in
            guard let resolution = parseResolution(stream.title) else { return nil }
            return (stream, resolution)
        }
        guard !candidates.isEmpty else { return streamsToUse.first }

        return candidates.min { lhs, rhs in
            let lhsDiff = abs(lhs.1 - target)
            let rhsDiff = abs(rhs.1 - target)
            return lhsDiff != rhsDiff ? lhsDiff < rhsDiff : lhs.1 > rhs.1
        }?.0
    }

    private static func parseResolution(_ text: String) -> Int? {
        let lowercased = text.lowercased()
        if lowercased.contains("4k") {
            return 2160
        }

        let pattern = "(\\d{3,4})p"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
        guard
            let match = regex.firstMatch(in: lowercased, options: [], range: range),
            match.numberOfRanges >= 2,
            let valueRange = Range(match.range(at: 1), in: lowercased)
        else {
            return nil
        }

        return Int(lowercased[valueRange])
    }

    private static func presentError(message: String, from viewController: UIViewController) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
}
