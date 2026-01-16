//
//  Player.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import UIKit

struct Player: UIViewControllerRepresentable {
    let module: ScrapingModule
    let episode: PlayerEpisode
    let episodes: [PlayerEpisode]
    let title: String
    var streamUrl: String?
    var streamHeaders: [String: String] = [:]
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    final class Coordinator {
        var videoPlayerController: PlayerViewController?
        var hasLoaded = false
        var parent: Player?
        var currentEpisodeId: String?
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }

    private func onEpisodeSelect(_ episode: PlayerEpisode) {
        onEpisodeSelected?(episode)
    }

    var onEpisodeSelected: ((PlayerEpisode) -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        let initialUrl = streamUrl ?? ""
        let videoPlayerController = PlayerViewController(
            module: module,
            videoUrl: initialUrl,
            videoTitle: "Episode \(episode.number): \(episode.title)",
            headers: streamHeaders
        )

        videoPlayerController.configure(episodes: episodes, current: episode, title: title)
        videoPlayerController.onNextEpisode = onNext
        videoPlayerController.onPreviousEpisode = onPrevious
        videoPlayerController.onEpisodeSelected = { [weak coordinator = context.coordinator] episode in
             coordinator?.parent?.onEpisodeSelect(episode)
        }

        context.coordinator.currentEpisodeId = episode.url

        // Only load if not provided (fallback)
        if streamUrl == nil || streamUrl?.isEmpty == true {
            Task {
                await loadStream(context: context, videoPlayerController: videoPlayerController)
            }
        }

        return videoPlayerController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let videoPlayerController = uiViewController as? PlayerViewController else { return }

        // Update callbacks
        videoPlayerController.onNextEpisode = onNext
        videoPlayerController.onPreviousEpisode = onPrevious

        // Update configuration
        videoPlayerController.configure(episodes: episodes, current: episode, title: title)

        // manual streamUrl injection
        if let newUrl = streamUrl, !newUrl.isEmpty, newUrl != videoPlayerController.videoUrl {
            videoPlayerController.loadVideo(url: newUrl, headers: streamHeaders)
            videoPlayerController.updateTitle("Episode \(episode.number): \(episode.title)")
        } else if streamUrl == nil || streamUrl?.isEmpty == true {
        // Check if episode changed for internal loading
            if context.coordinator.currentEpisodeId != episode.url {
                context.coordinator.currentEpisodeId = episode.url
                Task {
                    await loadStream(context: context, videoPlayerController: videoPlayerController)
                }
            }
        }

        // Player always appears in dark mode
        videoPlayerController.overrideUserInterfaceStyle = .dark
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        if let videoPlayerController = uiViewController as? PlayerViewController {
            videoPlayerController.stopPlayer()
        }
        coordinator.videoPlayerController = nil
        coordinator.hasLoaded = false
    }

    private func loadStream(context: Context, videoPlayerController: PlayerViewController) async {
        guard !episode.url.isEmpty else {
            await MainActor.run {
                showError(message: "Episode ID is not available", in: videoPlayerController)
            }
            return
        }

        let streamInfos = await JSController.shared.fetchPlayerStreams(episodeId: episode.url, module: module)
        await MainActor.run {
            if let streamInfo = streamInfos.first, !streamInfo.url.isEmpty {
                videoPlayerController.loadVideo(url: streamInfo.url, headers: streamInfo.headers)
                context.coordinator.videoPlayerController = videoPlayerController
                context.coordinator.hasLoaded = true
            } else {
                showError(message: "Unable to find video stream for this episode", in: videoPlayerController)
            }
        }
    }

    private func showError(message: String, in viewController: UIViewController) {
        viewController.showError(message: message)
    }
}
