//
//  PlayerViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import UIKit
import AVKit

class PlayerViewController: UIViewController {

    let module: ScrapingModule
    var videoUrl: String
    let videoTitle: String
    var headers: [String: String]
    var player: AVPlayer?
    var playerViewController: AVPlayerViewController?
    private var playerItemStatusObservation: NSKeyValueObservation?

    private let m3u8Extractor = M3U8Extractor.shared

    init(module: ScrapingModule, videoUrl: String, videoTitle: String, headers: [String: String] = [:]) {
        self.module = module
        self.videoUrl = videoUrl
        self.videoTitle = videoTitle
        self.headers = headers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = videoTitle
        if !videoUrl.isEmpty {
            setupPlayer()
        }
    }

    func loadVideo(url: String, headers: [String: String] = [:]) {
        self.videoUrl = url
        self.headers = headers
        if isViewLoaded {
            setupPlayer()
        }
    }

    private func setupPlayer() {
        // If this is called multiple times (e.g. switching qualities / reloading stream),
        // ensure we don't stack multiple child controllers or leak observers.
        stopPlayer()
        if let existingPlayerVC = playerViewController {
            existingPlayerVC.willMove(toParent: nil)
            existingPlayerVC.view.removeFromSuperview()
            existingPlayerVC.removeFromParent()
        }

        let playerViewController = AVPlayerViewController()
        self.playerViewController = playerViewController
        addChild(playerViewController)
        playerViewController.view.frame = view.bounds
        view.addSubview(playerViewController.view)
        playerViewController.didMove(toParent: self)
        loadVideo()
    }

    private func loadVideo() {
        Task {
            do {
                if videoUrl.lowercased().contains(".m3u8") || videoUrl.lowercased().contains("/hls/") {
                    do {
                        let qualities = try await m3u8Extractor.getStreamQualities(from: videoUrl, headers: headers)
                        if qualities.count > 1 {
                            let bestQuality = qualities.first!
                            let playerItem = try await m3u8Extractor.createPlayerItem(from: bestQuality.url, headers: headers)
                            await MainActor.run {
                                self.setupPlayerWithItem(playerItem)
                            }
                        } else {
                            let playerItem = try await m3u8Extractor.createPlayerItem(from: videoUrl, headers: headers)
                            await MainActor.run {
                                self.setupPlayerWithItem(playerItem)
                            }
                        }
                    } catch {
                        let playerItem = try await m3u8Extractor.createPlayerItem(from: videoUrl, headers: headers)
                        await MainActor.run {
                            self.setupPlayerWithItem(playerItem)
                        }
                    }
                } else {
                    await MainActor.run {
                        self.setupDirectPlayer()
                    }
                }
            } catch {
                await MainActor.run {
                    self.showError(message: error.localizedDescription)
                }
            }
        }
    }

    private func setupPlayerWithItem(_ playerItem: AVPlayerItem) {
        playerItemStatusObservation?.invalidate()
        player = AVPlayer(playerItem: playerItem)
        playerViewController?.player = player
        playerItemStatusObservation = playerItem.observe(\AVPlayerItem.status) { [weak self] playerItem, _ in
            guard let self = self else { return }
            Task { @MainActor in
                switch playerItem.status {
                case .readyToPlay:
                    self.player?.play()
                case .failed:
                    self.showError(message: playerItem.error?.localizedDescription ?? "Playback failed")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func setupDirectPlayer() {
        guard let url = URL(string: videoUrl) else {
            showError(message: "Invalid video URL")
            return
        }

        if videoUrl.lowercased().contains(".m3u8") || videoUrl.lowercased().contains("/hls/") {
            let finalHeaders = headers.isEmpty ? [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Referer": videoUrl
            ] : headers
            let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": finalHeaders]
            let asset = AVURLAsset(url: url, options: options)
            let playerItem = AVPlayerItem(asset: asset)
            playerItemStatusObservation?.invalidate()
            player = AVPlayer(playerItem: playerItem)
            playerItemStatusObservation = playerItem.observe(\AVPlayerItem.status) { [weak self] playerItem, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    switch playerItem.status {
                    case .readyToPlay:
                        self.player?.play()
                    case .failed:
                        self.showError(message: playerItem.error?.localizedDescription ?? "Playback failed")
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        } else {
            player = AVPlayer(url: url)
            if let playerItem = player?.currentItem {
                playerItemStatusObservation?.invalidate()
                playerItemStatusObservation = playerItem.observe(\AVPlayerItem.status) { [weak self] playerItem, _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        switch playerItem.status {
                        case .readyToPlay:
                            self.player?.play()
                        case .failed:
                            self.showError(message: playerItem.error?.localizedDescription ?? "Playback failed")
                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                    }
                }
            }
        }

        playerViewController?.player = player
    }

    private func showError(message: String) {
        let dismissAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        presentAlert(title: "Video Error", message: message, actions: [dismissAction])
    }

    func stopPlayer() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        player?.pause()
        playerViewController?.player = nil
        player = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayer()
    }

    deinit {
        stopPlayer()
    }
}
