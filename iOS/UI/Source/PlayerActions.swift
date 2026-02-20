//
//  PlayerActions.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit
import SwiftUI

// MARK: - Player Actions Extension
extension PlayerViewController {
    @objc internal func playPauseTapped() {
        togglePause()
    }

    @objc internal func nextTapped() {
        onNextEpisode?()
    }

    @objc internal func previousTapped() {
        onPreviousEpisode?()
    }

    @objc internal func closeTapped() {
        PlayerPresenter.shared.dismiss()
    }

    @objc internal func lockTapped() {
        isLocked = true
        if isUIVisible {
            toggleUIVisibility()
        }
    }

    @objc internal func unlockTapped() {
        isLocked = false
        UIView.animate(withDuration: 0.3) {
            self.gutterUnlockButton.alpha = 0
        }
        toggleUIVisibility()
    }

    @objc internal func skipTapped() {
        guard mpv != nil else { return }
        let currentPos = position
        let newPos = currentPos + Double(skipIntroButtonDuration)
        setProperty("time-pos", "\(newPos)")
        resetAutoHideTimer()
    }

    @objc internal func skipLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        presentSkipDurationPicker()
    }

    @objc internal func listTapped() {
        guard allEpisodes.count > 1 else { return }

        let listVC = EpisodeListViewController()
        listVC.episodes = allEpisodes
        listVC.currentEpisode = currentEpisode

        let alert = UIAlertController(title: "Select Episode", message: nil, preferredStyle: .alert)
        alert.setValue(listVC, forKey: "contentViewController")

        let doneAction = UIAlertAction(title: "Done", style: .default) { [weak self, weak listVC] _ in
            guard let self = self, let selectedEpisode = listVC?.getSelectedEpisode() else { return }
            self.onEpisodeSelected?(selectedEpisode)
        }

        alert.addAction(doneAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    @objc internal func settingsTapped() {
        self.pause()

        let settingsView = PlayerSettingsView { [weak self] in
            self?.play()
        }
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [
                UISheetPresentationController.Detent.medium(),
                UISheetPresentationController.Detent.large()
            ]
            sheet.prefersGrabberVisible = true
        }

        if let topController = PlayerPresenter.findTopViewController() {
            topController.present(hostingController, animated: true)
        } else {
            self.present(hostingController, animated: true)
        }
    }

    @objc internal func sliderValueChanged() {
        guard mpv != nil, duration > 0 else { return }
        let seekPos = sliderView.currentValue * CGFloat(duration)
        setProperty("time-pos", String(format: "%f", seekPos))
    }

    @objc internal func sliderTouchDown() {
        isSeeking = true
        autoHideTimer?.invalidate()
    }

    @objc internal func sliderTouchUp() {
        isSeeking = false
        resetAutoHideTimer()
    }

    @objc internal func subtitleTapped() {
        subtitlesEnabled.toggle()
        SubtitleSettingsManager.shared.update { $0.enabled = subtitlesEnabled }
        loadSubtitleSettings()
    }

    @objc internal func subtitleSettingsDidChange() {
        DispatchQueue.main.async {
            self.loadSubtitleSettings()
        }
    }

    func play() {
        setProperty("pause", "no")
    }

    func pause() {
        setProperty("pause", "yes")
        saveProgress()
    }

    func togglePause() {
        if isPaused { play() } else { pause() }
    }

    func setSpeed(_ speed: Double) {
        currentPlaybackSpeed = speed
        setProperty("speed", "\(speed)")
        speedButton.setTitle(formatSpeed(speed), for: .normal)
        resetAutoHideTimer()
    }

    func loadVideo(url: String, headers: [String: String] = [:], subtitleUrl: String? = nil) {
        self.videoUrl = url
        self.headers = headers
        self.resolvedUrl = nil
        if let subUrl = subtitleUrl {
            self.subtitleUrl = subUrl
            subtitlesLoader.load(from: subUrl)
        }
        if isViewLoaded {
            prepareAndPlay()
        }
    }

    func prepareAndPlay() {
        let urlToResolve = videoUrl
        let currentHeaders = headers

        Task {
            let resolved: String
            if urlToResolve.contains(".m3u8") {
                resolved = (try? await M3U8Extractor.shared.resolveBestStreamUrl(url: urlToResolve,
                                                                                 headers: currentHeaders)) ?? urlToResolve
            } else {
                resolved = urlToResolve
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                // Ensure we are still trying to play the same video
                guard self.videoUrl == urlToResolve else {
                    return
                }
                self.resolvedUrl = resolved
                self.startMpvPlayback()
            }
        }
    }

    func updatePlayerMetadata() {
        showTitleLabel.text = videoTitle
        if let current = currentEpisode {
            episodeNumberLabel.text = "Episode \(current.number)"
        } else {
            episodeNumberLabel.text = ""
        }

        listButton.isEnabled = allEpisodes.count > 1
        listButton.tintColor = allEpisodes.count > 1 ? .white : .secondaryLabel
    }

    func updateTitle(_ title: String) {
        self.videoTitle = title
        updatePlayerMetadata()
    }

    func showError(message: String) {
        let dismissAction = UIAlertAction(title: "OK", style: .default) { _ in
            PlayerPresenter.shared.dismiss()
        }
        presentAlert(title: "Video Error", message: message, actions: [dismissAction])
    }

    private func presentSkipDurationPicker() {
        self.pause()

        let pickerVC = SkipDurationPickerViewController()
        pickerVC.selectedDuration = skipIntroButtonDuration

        let alert = UIAlertController(title: "Change intro length", message: nil, preferredStyle: .alert)
        alert.setValue(pickerVC, forKey: "contentViewController")

        let doneAction = UIAlertAction(title: "Done", style: .default) { [weak self, weak pickerVC] _ in
            guard let self = self, let pickerVC = pickerVC else { return }
            self.skipIntroButtonDuration = pickerVC.getSelectedDuration()
            self.play()
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.play()
        })
        alert.addAction(doneAction)

        present(alert, animated: true)
    }

    func configure(episodes: [PlayerEpisode], current: PlayerEpisode, title: String) {
        self.allEpisodes = episodes
        self.currentEpisode = current
        self.updateTitle(title)
    }
}
