//
//  PlayerPresenter.swift
//  Hiyoku
//
//  Created by 686udjie on 02/07/26.
//

import UIKit
import SwiftUI
import AidokuRunner

class PlayerPresenter {
    static let shared = PlayerPresenter()

    var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    private weak var playerVC: PlayerViewController?

    static func findTopViewController(_ viewController: UIViewController? = nil) -> UIViewController? {
        let root = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController }
            .first

        if let presented = root?.presentedViewController {
            return findTopViewController(presented)
        }

        if let navigationController = root as? UINavigationController {
            return findTopViewController(navigationController.visibleViewController ?? navigationController)
        }

        if let tabBarController = root as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return findTopViewController(selected)
        }

        return root
    }

    struct Configuration {
        let module: ScrapingModule
        let videoUrl: String
        let videoTitle: String
        var headers: [String: String] = [:]
        var subtitleUrl: String?
        var episodes: [PlayerEpisode] = []
        var currentEpisode: PlayerEpisode?
        var mangaId: String?
        var onDismiss: (() -> Void)?
        var onNextEpisode: (() -> Void)?
        var onPreviousEpisode: (() -> Void)?
        var onEpisodeSelected: ((PlayerEpisode) -> Void)?
    }

    static func present(
        module: ScrapingModule,
        videoUrl: String,
        videoTitle: String,
        headers: [String: String] = [:],
        subtitleUrl: String? = nil,
        episodes: [PlayerEpisode] = [],
        currentEpisode: PlayerEpisode? = nil,
        mangaId: String? = nil,
        onDismiss: (() -> Void)? = nil,
        onNextEpisode: (() -> Void)? = nil,
        onPreviousEpisode: (() -> Void)? = nil,
        onEpisodeSelected: ((PlayerEpisode) -> Void)? = nil
    ) {
        let config = Configuration(
            module: module,
            videoUrl: videoUrl,
            videoTitle: videoTitle,
            headers: headers,
            subtitleUrl: subtitleUrl,
            episodes: episodes,
            currentEpisode: currentEpisode,
            mangaId: mangaId,
            onDismiss: onDismiss,
            onNextEpisode: onNextEpisode,
            onPreviousEpisode: onPreviousEpisode,
            onEpisodeSelected: onEpisodeSelected
        )
        shared.present(config)
    }

    private func present(_ config: Configuration) {
        guard let topVC = Self.findTopViewController() else { return }

        let playerVC = PlayerViewController(
            module: config.module,
            videoUrl: config.videoUrl,
            videoTitle: config.videoTitle,
            headers: config.headers,
            subtitleUrl: config.subtitleUrl,
            episodes: config.episodes,
            currentEpisode: config.currentEpisode,
            mangaId: config.mangaId
        )

        playerVC.onDismiss = config.onDismiss
        playerVC.onNextEpisode = config.onNextEpisode
        playerVC.onPreviousEpisode = config.onPreviousEpisode
        playerVC.onEpisodeSelected = config.onEpisodeSelected

        self.playerVC = playerVC
        self.orientationLock = .all
        playerVC.modalPresentationStyle = .fullScreen
        topVC.present(playerVC, animated: true)
    }

    func dismiss(animated: Bool = true) {
        guard let playerVC = playerVC else { return }

        playerVC.pause()
        playerVC.stopPlayer()

        playerVC.dismiss(animated: animated) { [weak self] in
            self?.playerVC = nil
        }
    }
}
