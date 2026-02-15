//
//  PlayerUI.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

// MARK: - Player UI Extension
extension PlayerViewController {
    func setupUI() {
        view.backgroundColor = .black
        videoContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoContainer.frame = view.bounds
        view.addSubview(videoContainer)

        displayLayer.videoGravity = .resizeAspect
        videoContainer.layer.addSublayer(displayLayer)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        videoContainer.addGestureRecognizer(tapGesture)

        videoContainer.addGestureRecognizer(verticalPanGesture)

        // Setup double tap gestures for skip
        doubleTapLeftGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapLeft))
        doubleTapLeftGesture.numberOfTapsRequired = 2
        doubleTapLeftGesture.delegate = self
        videoContainer.addGestureRecognizer(doubleTapLeftGesture)

        doubleTapRightGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapRight))
        doubleTapRightGesture.numberOfTapsRequired = 2
        doubleTapRightGesture.delegate = self
        videoContainer.addGestureRecognizer(doubleTapRightGesture)

        // Single tap should wait for double tap to fail
        tapGesture.require(toFail: doubleTapLeftGesture)
        tapGesture.require(toFail: doubleTapRightGesture)

        // Setup two finger tap gesture
        twoFingerTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTapGesture.numberOfTouchesRequired = 2
        videoContainer.addGestureRecognizer(twoFingerTapGesture)

        // Setup long press gesture for speed boost
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.3
        longPressGesture.delegate = self
        videoContainer.addGestureRecognizer(longPressGesture)

        // Add all backgrounds and stand-alone views to videoContainer
        let overlayViews: [UIView] = [
            playPauseBackgroundView,
            previousBackgroundView,
            nextBackgroundView,
            closeBackgroundView,
            listBackgroundView,
            sliderBackgroundView,
            speedBackgroundView,
            lockBackgroundView,
            skipBackgroundView,
            settingsBackgroundView,
            subtitleBackgroundView,
            gutterUnlockButton,
            watchedTimeLabel,
            totalTimeLabel,
            titleStackView,
            leftSkipFeedbackView,
            rightSkipFeedbackView,
            speedIndicatorBackgroundView,
            volumeHUDContainer,
            brightnessHUDContainer
        ]
        overlayViews.forEach {

            $0.translatesAutoresizingMaskIntoConstraints = false
            videoContainer.addSubview($0)
        }

        setupVerticalAdjustHUDs()

        // Setup control islands
        centerInParent(playPauseButton, parent: playPauseBackgroundView, size: CGSize(width: 44, height: 44))
        centerInParent(previousButton, parent: previousBackgroundView, size: CGSize(width: 44, height: 44))
        centerInParent(nextButton, parent: nextBackgroundView, size: CGSize(width: 44, height: 44))
        centerInParent(closeButton, parent: closeBackgroundView, size: CGSize(width: 30, height: 30))
        centerInParent(listButton, parent: listBackgroundView, size: CGSize(width: 30, height: 30))
        centerInParent(speedButton, parent: speedBackgroundView, size: CGSize(width: 44, height: 28))
        centerInParent(lockButton, parent: lockBackgroundView, size: CGSize(width: 36, height: 28))
        centerInParent(skipIntroButton, parent: skipBackgroundView, size: CGSize(width: 44, height: 28))
        centerInParent(settingsButton, parent: settingsBackgroundView, size: CGSize(width: 30, height: 30))
        centerInParent(subtitleButton, parent: subtitleBackgroundView, size: CGSize(width: 30, height: 30))

        // Setup speed indicator
        speedIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        speedIndicatorBackgroundView.contentView.addSubview(speedIndicatorLabel)
        speedIndicatorBackgroundView.alpha = 0

        NSLayoutConstraint.activate([
            speedIndicatorLabel.centerXAnchor.constraint(equalTo: speedIndicatorBackgroundView.contentView.centerXAnchor),
            speedIndicatorLabel.centerYAnchor.constraint(equalTo: speedIndicatorBackgroundView.contentView.centerYAnchor),
            speedIndicatorLabel.leadingAnchor.constraint(equalTo: speedIndicatorBackgroundView.contentView.leadingAnchor, constant: 12),
            speedIndicatorLabel.trailingAnchor.constraint(equalTo: speedIndicatorBackgroundView.contentView.trailingAnchor, constant: -12)
        ])

        centerInParent(sliderView, parent: sliderBackgroundView, size: .zero, fill: true)
        NSLayoutConstraint.activate([
            // Main Controls
            playPauseBackgroundView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            playPauseBackgroundView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            playPauseBackgroundView.widthAnchor.constraint(equalToConstant: 60),
            playPauseBackgroundView.heightAnchor.constraint(equalToConstant: 60),

            previousBackgroundView.trailingAnchor.constraint(equalTo: playPauseBackgroundView.leadingAnchor, constant: -20),
            previousBackgroundView.centerYAnchor.constraint(equalTo: playPauseBackgroundView.centerYAnchor),
            previousBackgroundView.widthAnchor.constraint(equalToConstant: 50),
            previousBackgroundView.heightAnchor.constraint(equalToConstant: 50),

            nextBackgroundView.leadingAnchor.constraint(equalTo: playPauseBackgroundView.trailingAnchor, constant: 20),
            nextBackgroundView.centerYAnchor.constraint(equalTo: playPauseBackgroundView.centerYAnchor),
            nextBackgroundView.widthAnchor.constraint(equalToConstant: 50),
            nextBackgroundView.heightAnchor.constraint(equalToConstant: 50),

            // Close & Utilities
            closeBackgroundView.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeBackgroundView.leadingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeBackgroundView.widthAnchor.constraint(equalToConstant: 44),
            closeBackgroundView.heightAnchor.constraint(equalToConstant: 44),

            listBackgroundView.centerYAnchor.constraint(equalTo: closeBackgroundView.centerYAnchor),
            listBackgroundView.leadingAnchor.constraint(equalTo: closeBackgroundView.trailingAnchor, constant: 12),
            listBackgroundView.widthAnchor.constraint(equalToConstant: 44),
            listBackgroundView.heightAnchor.constraint(equalToConstant: 44),

            titleStackView.centerYAnchor.constraint(equalTo: closeBackgroundView.centerYAnchor),
            titleStackView.leadingAnchor.constraint(equalTo: listBackgroundView.trailingAnchor, constant: 16),
            titleStackView.trailingAnchor.constraint(lessThanOrEqualTo: gutterUnlockButton.leadingAnchor, constant: -16),

            gutterUnlockButton.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -16),
            gutterUnlockButton.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            gutterUnlockButton.widthAnchor.constraint(equalToConstant: 50),
            gutterUnlockButton.heightAnchor.constraint(equalToConstant: 50),

            settingsBackgroundView.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 16),
            settingsBackgroundView.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            settingsBackgroundView.widthAnchor.constraint(equalToConstant: 44),
            settingsBackgroundView.heightAnchor.constraint(equalToConstant: 44),
            subtitleBackgroundView.centerYAnchor.constraint(equalTo: settingsBackgroundView.centerYAnchor),
            subtitleBackgroundView.trailingAnchor.constraint(equalTo: settingsBackgroundView.leadingAnchor, constant: -12),
            subtitleBackgroundView.widthAnchor.constraint(equalToConstant: 44),
            subtitleBackgroundView.heightAnchor.constraint(equalToConstant: 44),

            // Slider Area
            sliderBackgroundView.leadingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            sliderBackgroundView.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            sliderBackgroundView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor, constant: -10),
            sliderBackgroundView.heightAnchor.constraint(equalToConstant: 40),

            watchedTimeLabel.trailingAnchor.constraint(equalTo: sliderBackgroundView.leadingAnchor, constant: -12),
            watchedTimeLabel.centerYAnchor.constraint(equalTo: sliderBackgroundView.centerYAnchor),

            totalTimeLabel.leadingAnchor.constraint(equalTo: sliderBackgroundView.trailingAnchor, constant: 12),
            totalTimeLabel.centerYAnchor.constraint(equalTo: sliderBackgroundView.centerYAnchor),

            speedBackgroundView.trailingAnchor.constraint(equalTo: sliderBackgroundView.trailingAnchor),
            speedBackgroundView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -8),
            speedBackgroundView.heightAnchor.constraint(equalToConstant: 28),
            speedBackgroundView.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            lockBackgroundView.trailingAnchor.constraint(equalTo: speedBackgroundView.leadingAnchor, constant: -8),
            lockBackgroundView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -8),
            lockBackgroundView.heightAnchor.constraint(equalToConstant: 28),
            lockBackgroundView.widthAnchor.constraint(equalToConstant: 36),

            skipBackgroundView.leadingAnchor.constraint(equalTo: sliderBackgroundView.leadingAnchor),
            skipBackgroundView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -8),
            skipBackgroundView.heightAnchor.constraint(equalToConstant: 28),
            skipBackgroundView.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

            // Skip feedback views
            leftSkipFeedbackView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor, constant: 40),
            leftSkipFeedbackView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),

            rightSkipFeedbackView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -40),
            rightSkipFeedbackView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),

            // Speed indicator
            speedIndicatorBackgroundView.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 16),
            speedIndicatorBackgroundView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            speedIndicatorBackgroundView.heightAnchor.constraint(equalToConstant: 36)
        ])

        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        sliderView.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        sliderView.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        sliderView.addTarget(self, action: #selector(sliderTouchUp), for: .editingDidEnd)
    }

    func centerInParent(_ view: UIView, parent: UIVisualEffectView, size: CGSize, fill: Bool = false) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.contentView.addSubview(view)
        if fill {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: parent.contentView.topAnchor),
                view.bottomAnchor.constraint(equalTo: parent.contentView.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: parent.contentView.leadingAnchor, constant: 8),
                view.trailingAnchor.constraint(equalTo: parent.contentView.trailingAnchor, constant: -8)
            ])
        } else {
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: parent.contentView.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: parent.contentView.centerYAnchor),
                view.widthAnchor.constraint(equalToConstant: size.width),
                view.heightAnchor.constraint(equalToConstant: size.height)
            ])
        }
    }

    func createControlBackground(cornerRadius: CGFloat,
                                 color: UIColor = .tertiarySystemFill,
                                 borderColor: UIColor = .tertiarySystemFill) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = cornerRadius
        view.layer.masksToBounds = true
        view.contentView.backgroundColor = color
        view.layer.borderColor = borderColor.cgColor
        view.layer.borderWidth = 1
        return view
    }

    func createSymbolConfig(size: CGFloat, weight: UIImage.SymbolWeight = .medium) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: size, weight: weight)
    }

    func createSystemButton(symbol: String, size: CGFloat = 20, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: createSymbolConfig(size: size)), for: .normal)
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    func createSkipFeedbackView(direction: SkipDirection) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        let iconName = direction == .forward ? "goforward" : "gobackward"
        let imageView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: iconConfig))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        // Add shadow/glow effect to icon
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowRadius = 4
        imageView.layer.shadowOpacity = 0.8
        imageView.layer.shadowOffset = .zero

        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.tag = 999 // Tag to identify label for updating
        // Add shadow/glow effect to text
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 4
        label.layer.shadowOpacity = 0.8
        label.layer.shadowOffset = .zero

        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(label)
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    func updatePlayPauseButton() {
        let imageName = isPaused ? "play.fill" : "pause.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }

    func updateTimeLabels() {
        watchedTimeLabel.text = formatTime(position)
        totalTimeLabel.text = formatTime(duration)
    }

    func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds.isFinite else { return "00:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%01i:%02i:%02i", hours, minutes, seconds)
        } else {
            return String(format: "%02i:%02i", minutes, seconds)
        }
    }

    func formatSpeed(_ speed: Double) -> String {
        speed == Double(Int(speed)) ? "\(Int(speed))×" : "\(speed)×"
    }

    var controlViews: [UIView] {
        [
            playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
            closeBackgroundView, listBackgroundView, sliderBackgroundView, watchedTimeLabel,
            totalTimeLabel, speedBackgroundView, lockBackgroundView, skipBackgroundView,
            titleStackView, settingsBackgroundView, subtitleBackgroundView
        ]
    }

    var interactionEnabledViews: [UIView] {
        controlViews.filter { !($0 is UILabel) && !($0 is UIStackView) }
    }

    func toggleUIVisibility() {
        isUIVisible.toggle()

        UIView.animate(withDuration: 0.3) {
            let alpha: CGFloat = self.isUIVisible ? 1 : 0
            self.controlViews.forEach { $0.alpha = alpha }
            self.updateSubtitlePosition()
            self.view.layoutIfNeeded()
        }

        interactionEnabledViews.forEach { $0.isUserInteractionEnabled = isUIVisible }

        if isUIVisible {
            resetAutoHideTimer()
        } else {
            autoHideTimer?.invalidate()
        }
    }

    func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                if let self = self, !self.isSeeking {
                    if self.isLocked {
                        if self.gutterUnlockButton.alpha > 0 {
                            UIView.animate(withDuration: 0.3) {
                                self.gutterUnlockButton.alpha = 0
                            }
                        }
                    } else if self.isUIVisible {
                        self.toggleUIVisibility()
                    }
                }
            }
        }
    }
}
