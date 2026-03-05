//
//  PlayerPlaybackEngine.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit
import CoreData
import AVFoundation

// MARK: - Playback Engine
extension PlayerViewController {
    func setupPlaybackEngine() throws {
        let newPlayer = AVPlayer()
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        playerLayer.player = newPlayer

        observePlayerState(newPlayer)
        addPeriodicTimeObserver(newPlayer)

        isRunning = true
        isPaused = true
        updatePlayPauseButton()
    }

    func startPlaybackSession() {
        guard let avPlayer = player else { return }
        guard let urlToPlay = resolvedUrl, let mediaURL = makeMediaURL(from: urlToPlay) else {
            showError(message: "Failed to resolve media URL")
            return
        }

        Task {
            // Check for history before playing.
            let startTime = await getSavedProgress()

            await MainActor.run { [weak self] in
                guard let self = self else { return }

                self.pendingStartTime = (startTime != nil && startTime! > 5) ? startTime : nil
                self.isRunning = true
                self.isPaused = true
                self.isFileLoaded = false

                let item = self.buildPlayerItem(for: mediaURL)
                self.observeCurrentItem(item)
                avPlayer.replaceCurrentItem(with: item)
                avPlayer.pause()
                self.updatePlayPauseButton()
            }
        }
    }

    private func getSavedProgress() async -> Double? {
        guard let current = currentEpisode else { return nil }
        return await PlayerHistoryManager.shared.getProgress(episodeId: current.url, moduleId: module.id.uuidString)
    }

    func saveProgress() {
        guard let current = currentEpisode, position > 0, duration > 0 else { return }

        let data = PlayerHistoryManager.EpisodeHistoryData(
            playerTitle: self.videoTitle,
            episodeId: current.url,
            episodeNumber: Double(current.number),
            episodeTitle: current.title,
            sourceUrl: current.url,
            moduleId: module.id.uuidString,
            progress: Int(position),
            total: Int(duration),
            watchedDuration: 0,
            date: Date()
        )

        Task {
            await PlayerHistoryManager.shared.setProgress(data: data)
        }

        // Trigger tracker update if threshold is met.
        if !markedAsCompleted {
            let thresholdString = UserDefaults.standard.string(forKey: "Player.historyThreshold") ?? "80"
            let threshold = (Double(thresholdString) ?? 80) / 100
            let progress = position / duration

            if progress >= threshold {
                markedAsCompleted = true
                Task {
                    let sourceId = module.id.uuidString
                    if let mangaId = mangaId {
                        let episode = current.toTrackableEpisode(sourceId: sourceId, mangaId: mangaId)
                        await TrackerManager.shared.setCompleted(episode: episode, sourceId: sourceId, mangaId: mangaId)
                    }
                }
            }
        }
    }

    func setProperty(_ name: String, _ value: String) {
        guard let avPlayer = player else { return }

        switch name {
        case "pause":
            if value == "yes" {
                avPlayer.pause()
                isPaused = true
                updatePlayPauseButton()
            } else {
                avPlayer.playImmediately(atRate: Float(currentPlaybackSpeed))
                isPaused = false
                updatePlayPauseButton()
            }

        case "time-pos":
            guard let seconds = Double(value), seconds.isFinite else { return }
            let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard let self = self else { return }
                self.position = max(0, seconds)
                DispatchQueue.main.async {
                    self.updateTimeLabels()
                    if self.duration > 0 && !self.isSeeking {
                        self.sliderView.currentValue = CGFloat(self.position / self.duration)
                    }
                    self.updateSubtitles(for: self.position)
                }
            }

        case "speed":
            guard let speed = Double(value), speed > 0 else { return }
            currentPlaybackSpeed = speed
            if !isPaused {
                avPlayer.rate = Float(speed)
            }
            DispatchQueue.main.async {
                self.speedButton.setTitle(self.formatSpeed(speed), for: .normal)
            }

        case "volume":
            guard let level = Double(value), level.isFinite else { return }
            avPlayer.volume = Float(max(0, min(100, level)) / 100)

        case "http-header-fields":
            // HTTP headers are applied when creating AVURLAsset in buildPlayerItem(for:).
            break

        default:
            break
        }
    }

    func stopPlayer() {
        guard player != nil || isRunning else { return }

        saveProgress()
        isRunning = false

        if let token = timeObserverToken, let avPlayer = player {
            avPlayer.removeTimeObserver(token)
        }
        timeObserverToken = nil
        playerItemStatusObserver = nil
        timeControlStatusObserver = nil

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func getPlayerDoubleProperty(_ name: String) -> Double? {
        guard let avPlayer = player else { return nil }
        switch name {
        case "volume":
            return Double(avPlayer.volume * 100)
        case "time-pos":
            return CMTimeGetSeconds(avPlayer.currentTime())
        case "duration":
            guard let item = avPlayer.currentItem else { return nil }
            let seconds = CMTimeGetSeconds(item.duration)
            return seconds.isFinite ? seconds : nil
        default:
            return nil
        }
    }

    private func observePlayerState(_ avPlayer: AVPlayer) {
        timeControlStatusObserver = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            guard let self = self else { return }
            let paused = player.timeControlStatus != .playing
            DispatchQueue.main.async {
                self.isPaused = paused
                self.updatePlayPauseButton()
            }
        }
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        playerItemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] playerItem, _ in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch playerItem.status {
                case .readyToPlay:
                    self.isFileLoaded = true

                    let itemDuration = CMTimeGetSeconds(playerItem.duration)
                    if itemDuration.isFinite && itemDuration > 0 {
                        self.duration = itemDuration
                    }

                    if let start = self.pendingStartTime {
                        let target = CMTime(seconds: start, preferredTimescale: 600)
                        playerItem.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            guard let self = self else { return }
                            self.pendingStartTime = nil
                            self.play()
                        }
                    } else {
                        self.play()
                    }

                case .failed:
                    self.showError(message: playerItem.error?.localizedDescription ?? "Failed to load media")

                case .unknown:
                    break

                @unknown default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func addPeriodicTimeObserver(_ avPlayer: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }

            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }

            self.position = seconds

            if let item = avPlayer.currentItem {
                let itemDuration = CMTimeGetSeconds(item.duration)
                if itemDuration.isFinite && itemDuration > 0 {
                    self.duration = itemDuration
                }
            }

            let now = Date().timeIntervalSince1970
            if now - self.lastSavedTime > 15 {
                self.lastSavedTime = now
                self.saveProgress()
            }

            self.updateTimeLabels()
            if self.duration > 0 && !self.isSeeking {
                self.sliderView.currentValue = CGFloat(seconds / self.duration)
            }
            self.updateSubtitles(for: seconds)
        }
    }

    @objc private func handlePlaybackEnded() {
        isPaused = true
        updatePlayPauseButton()
        saveProgress()
    }

    private func buildPlayerItem(for url: URL) -> AVPlayerItem {
        let options: [String: Any]
        if headers.isEmpty {
            options = [:]
        } else {
            options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        }

        let asset = AVURLAsset(url: url, options: options)
        return AVPlayerItem(asset: asset)
    }

    private func makeMediaURL(from raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }

        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded), url.scheme != nil {
            return url
        }

        return URL(fileURLWithPath: raw)
    }
}
