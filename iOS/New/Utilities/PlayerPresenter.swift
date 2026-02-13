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

    static func present(
        module: ScrapingModule,
        videoUrl: String,
        videoTitle: String,
        headers: [String: String] = [:],
        subtitleUrl: String? = nil,
        episodes: [PlayerEpisode] = [],
        currentEpisode: PlayerEpisode? = nil,
        mangaId: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        guard let topVC = findTopViewController() else {
            return
        }

        let playerVC = PlayerViewController(
            module: module,
            videoUrl: videoUrl,
            videoTitle: videoTitle,
            headers: headers,
            subtitleUrl: subtitleUrl,
            episodes: episodes,
            currentEpisode: currentEpisode,
            mangaId: mangaId
        )

        playerVC.onDismiss = onDismiss

        playerVC.modalPresentationStyle = .fullScreen

        topVC.present(playerVC, animated: true)
    }
}
