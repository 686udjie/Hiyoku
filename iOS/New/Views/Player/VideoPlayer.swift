//
//  VideoPlayer.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import UIKit

struct VideoPlayer: UIViewControllerRepresentable {
    let module: ScrapingModule
    let episode: PlayerEpisode

    final class Coordinator {
        var videoPlayerController: VideoPlayerViewController?
        var hasLoaded = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let videoPlayerController = VideoPlayerViewController(
            module: module,
            videoUrl: "",
            videoTitle: "Episode \(episode.number): \(episode.title)"
        )

        Task {
            await loadStream(context: context, videoPlayerController: videoPlayerController)
        }

        return videoPlayerController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        if let videoPlayerController = uiViewController as? VideoPlayerViewController {
            videoPlayerController.stopPlayer()
        }
        coordinator.videoPlayerController = nil
        coordinator.hasLoaded = false
    }

    private func loadStream(context: Context, videoPlayerController: VideoPlayerViewController) async {
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
