//
//  PlayerUI.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

// MARK: - Player UI Extension
extension PlayerViewController {
    var controlScale: CGFloat {
        traitCollection.userInterfaceIdiom == .pad ? 1.45 : 1
    }

    func setupUI() {
        let scale = controlScale
        let metrics = ControlMetrics(scale: scale)

        configureVideoContainer()
        configureOverlayGradients()
        configureGestures()
        addOverlayViews()

        setupVerticalAdjustHUDs()
        applyModernStyling()
        applyControlSymbolSizes()
        subtitleBottomPadding = 10 * scale

        setupControlIslands(metrics: metrics, scale: scale)
        setupSpeedIndicator()
        setupSliderView(metrics: metrics)
        setupConstraints(metrics: metrics, scale: scale)
        updateControlCornerRadii(metrics: metrics)
        setupControlTargets()
        updateSliderWidthForTimeLabels()
    }

    private func configureVideoContainer() {
        view.backgroundColor = .black
        videoContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoContainer.frame = view.bounds
        view.addSubview(videoContainer)

        systemVolumeView.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(systemVolumeView)
        NSLayoutConstraint.activate([
            systemVolumeView.widthAnchor.constraint(equalToConstant: 0),
            systemVolumeView.heightAnchor.constraint(equalToConstant: 0),
            systemVolumeView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            systemVolumeView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor)
        ])

        playerLayer.videoGravity = .resizeAspect
        videoContainer.layer.addSublayer(playerLayer)
    }

    private func configureGestures() {
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
    }

    private func addOverlayViews() {
        // Add all backgrounds and stand-alone views to videoContainer
        let overlayViews: [UIView] = [
            topOverlayView,
            bottomOverlayView,
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
    }

    private func setupControlIslands(metrics: ControlMetrics, scale: CGFloat) {
        let buttonPadding: CGFloat = traitCollection.userInterfaceIdiom == .pad ? (6 * scale) : 0
        let extraUtilityPadding: CGFloat = traitCollection.userInterfaceIdiom == .pad ? (10 * scale) : 0
        func padded(_ size: CGSize, extra: CGFloat = 0) -> CGSize {
            let total = buttonPadding + extra
            return CGSize(width: size.width + (total * 2), height: size.height + (total * 2))
        }
        // Setup control islands
        centerInParent(
            playPauseButton,
            parent: playPauseBackgroundView,
            size: padded(CGSize(width: metrics.playPauseIconSize, height: metrics.playPauseIconSize))
        )
        centerInParent(
            previousButton,
            parent: previousBackgroundView,
            size: padded(CGSize(width: metrics.secondaryIconSize, height: metrics.secondaryIconSize))
        )
        centerInParent(
            nextButton,
            parent: nextBackgroundView,
            size: padded(CGSize(width: metrics.secondaryIconSize, height: metrics.secondaryIconSize))
        )
        centerInParent(
            closeButton,
            parent: closeBackgroundView,
            size: padded(CGSize(width: metrics.utilityIconSize, height: metrics.utilityIconSize))
        )
        centerInParent(
            listButton,
            parent: listBackgroundView,
            size: padded(CGSize(width: metrics.utilityIconSize, height: metrics.utilityIconSize), extra: extraUtilityPadding)
        )
        centerInParent(
            speedButton,
            parent: speedBackgroundView,
            size: padded(CGSize(width: 44 * scale, height: 28 * scale))
        )
        centerInParent(
            lockButton,
            parent: lockBackgroundView,
            size: padded(CGSize(width: 36 * scale, height: 28 * scale), extra: extraUtilityPadding)
        )
        centerInParent(
            skipIntroButton,
            parent: skipBackgroundView,
            size: padded(CGSize(width: 44 * scale, height: 28 * scale))
        )
        centerInParent(
            settingsButton,
            parent: settingsBackgroundView,
            size: padded(CGSize(width: metrics.utilityIconSize, height: metrics.utilityIconSize), extra: extraUtilityPadding)
        )
        centerInParent(
            subtitleButton,
            parent: subtitleBackgroundView,
            size: padded(CGSize(width: metrics.utilityIconSize, height: metrics.utilityIconSize), extra: extraUtilityPadding)
        )
    }

    private func setupSpeedIndicator() {
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
    }

    private func setupSliderView(metrics: ControlMetrics) {
        sliderView.translatesAutoresizingMaskIntoConstraints = false
        sliderView.clipsToBounds = false
        sliderView.layer.masksToBounds = false
        videoContainer.addSubview(sliderView)
        sliderMaxWidthConstraint = nil
    }

    private func setupConstraints(metrics: ControlMetrics, scale: CGFloat) {
        let sliderWidthConstraint = sliderBackgroundView.widthAnchor.constraint(
            equalToConstant: metrics.sliderMaxWidth
        )
        sliderWidthConstraint.priority = .required
        sliderMaxWidthConstraint = sliderWidthConstraint

        NSLayoutConstraint.activate([
            topOverlayView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            topOverlayView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            topOverlayView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            topOverlayView.heightAnchor.constraint(equalToConstant: metrics.topOverlayHeight),

            bottomOverlayView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            bottomOverlayView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            bottomOverlayView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            bottomOverlayView.heightAnchor.constraint(equalToConstant: metrics.bottomOverlayHeight),

            // Main Controls
            playPauseBackgroundView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            playPauseBackgroundView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor, constant: 10 * scale),
            playPauseBackgroundView.widthAnchor.constraint(equalToConstant: metrics.playPauseSize),
            playPauseBackgroundView.heightAnchor.constraint(equalToConstant: metrics.playPauseSize),

            previousBackgroundView.trailingAnchor.constraint(equalTo: playPauseBackgroundView.leadingAnchor, constant: -metrics.mainControlSpacing),
            previousBackgroundView.centerYAnchor.constraint(equalTo: playPauseBackgroundView.centerYAnchor),
            previousBackgroundView.widthAnchor.constraint(equalToConstant: metrics.secondaryControlSize),
            previousBackgroundView.heightAnchor.constraint(equalToConstant: metrics.secondaryControlSize),

            nextBackgroundView.leadingAnchor.constraint(equalTo: playPauseBackgroundView.trailingAnchor, constant: metrics.mainControlSpacing),
            nextBackgroundView.centerYAnchor.constraint(equalTo: playPauseBackgroundView.centerYAnchor),
            nextBackgroundView.widthAnchor.constraint(equalToConstant: metrics.secondaryControlSize),
            nextBackgroundView.heightAnchor.constraint(equalToConstant: metrics.secondaryControlSize),

            // Close & Utilities
            closeBackgroundView.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: metrics.topPadding),
            closeBackgroundView.leadingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.leadingAnchor, constant: metrics.sidePadding),
            closeBackgroundView.widthAnchor.constraint(equalToConstant: metrics.utilityControlSize),
            closeBackgroundView.heightAnchor.constraint(equalToConstant: metrics.utilityControlSize),

            listBackgroundView.centerYAnchor.constraint(equalTo: closeBackgroundView.centerYAnchor),
            listBackgroundView.leadingAnchor.constraint(equalTo: closeBackgroundView.trailingAnchor, constant: metrics.utilitySpacing),
            listBackgroundView.widthAnchor.constraint(equalToConstant: metrics.utilityControlSize),
            listBackgroundView.heightAnchor.constraint(equalToConstant: metrics.utilityControlSize),

            titleStackView.centerYAnchor.constraint(equalTo: closeBackgroundView.centerYAnchor),
            titleStackView.leadingAnchor.constraint(equalTo: listBackgroundView.trailingAnchor, constant: metrics.titleSpacing),
            titleStackView.trailingAnchor.constraint(lessThanOrEqualTo: gutterUnlockButton.leadingAnchor, constant: -metrics.sidePadding),

            gutterUnlockButton.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor, constant: -metrics.topPadding),
            gutterUnlockButton.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            gutterUnlockButton.widthAnchor.constraint(equalToConstant: 50 * scale),
            gutterUnlockButton.heightAnchor.constraint(equalToConstant: 50 * scale),

            settingsBackgroundView.topAnchor.constraint(
                equalTo: videoContainer.safeAreaLayoutGuide.topAnchor,
                constant: metrics.topPadding
            ),
            settingsBackgroundView.trailingAnchor.constraint(
                equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor,
                constant: -metrics.sidePadding
            ),
            settingsBackgroundView.widthAnchor.constraint(equalToConstant: metrics.utilityControlSize),
            settingsBackgroundView.heightAnchor.constraint(equalToConstant: metrics.utilityControlSize),
            subtitleBackgroundView.centerYAnchor.constraint(equalTo: settingsBackgroundView.centerYAnchor),
            subtitleBackgroundView.trailingAnchor.constraint(equalTo: settingsBackgroundView.leadingAnchor, constant: -metrics.utilitySpacing),
            subtitleBackgroundView.widthAnchor.constraint(equalToConstant: metrics.utilityControlSize),
            subtitleBackgroundView.heightAnchor.constraint(equalToConstant: metrics.utilityControlSize),

            // Slider Area
            sliderBackgroundView.leadingAnchor.constraint(
                greaterThanOrEqualTo: videoContainer.safeAreaLayoutGuide.leadingAnchor,
                constant: metrics.sliderSidePadding
            ),
            sliderBackgroundView.trailingAnchor.constraint(
                lessThanOrEqualTo: videoContainer.safeAreaLayoutGuide.trailingAnchor,
                constant: -metrics.sliderSidePadding
            ),
            sliderBackgroundView.bottomAnchor.constraint(
                equalTo: watchedTimeLabel.topAnchor,
                constant: -8
            ),
            sliderBackgroundView.heightAnchor.constraint(equalToConstant: metrics.sliderHeight),
            sliderBackgroundView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            sliderWidthConstraint,

            sliderView.leadingAnchor.constraint(
                equalTo: sliderBackgroundView.leadingAnchor,
                constant: metrics.sliderThumbInset
            ),
            sliderView.trailingAnchor.constraint(
                equalTo: sliderBackgroundView.trailingAnchor,
                constant: -metrics.sliderThumbInset
            ),
            sliderView.centerYAnchor.constraint(equalTo: sliderBackgroundView.centerYAnchor),
            sliderView.heightAnchor.constraint(equalTo: sliderBackgroundView.heightAnchor),

            watchedTimeLabel.leadingAnchor.constraint(
                equalTo: sliderBackgroundView.leadingAnchor
            ),
            watchedTimeLabel.bottomAnchor.constraint(
                equalTo: videoContainer.safeAreaLayoutGuide.bottomAnchor,
                constant: -metrics.sliderBottomPadding
            ),

            totalTimeLabel.trailingAnchor.constraint(
                equalTo: sliderBackgroundView.trailingAnchor
            ),
            totalTimeLabel.centerYAnchor.constraint(equalTo: watchedTimeLabel.centerYAnchor),

            speedBackgroundView.trailingAnchor.constraint(equalTo: sliderBackgroundView.trailingAnchor),
            speedBackgroundView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -10),
            speedBackgroundView.heightAnchor.constraint(equalToConstant: metrics.speedRowHeight),
            speedBackgroundView.widthAnchor.constraint(greaterThanOrEqualToConstant: metrics.speedRowMinWidth),

            lockBackgroundView.trailingAnchor.constraint(equalTo: speedBackgroundView.leadingAnchor, constant: -8),
            lockBackgroundView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -10),
            lockBackgroundView.heightAnchor.constraint(equalToConstant: metrics.speedRowHeight),
            lockBackgroundView.widthAnchor.constraint(equalToConstant: metrics.lockRowWidth),

            skipBackgroundView.leadingAnchor.constraint(equalTo: sliderBackgroundView.leadingAnchor),
            skipBackgroundView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -10),
            skipBackgroundView.heightAnchor.constraint(equalToConstant: metrics.speedRowHeight),
            skipBackgroundView.widthAnchor.constraint(greaterThanOrEqualToConstant: metrics.skipRowMinWidth),

            // Skip feedback views
            leftSkipFeedbackView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor, constant: metrics.skipFeedbackInset),
            leftSkipFeedbackView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),

            rightSkipFeedbackView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -metrics.skipFeedbackInset),
            rightSkipFeedbackView.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),

            // Speed indicator
            speedIndicatorBackgroundView.topAnchor.constraint(
                equalTo: videoContainer.safeAreaLayoutGuide.topAnchor,
                constant: metrics.speedIndicatorTop
            ),
            speedIndicatorBackgroundView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            speedIndicatorBackgroundView.heightAnchor.constraint(equalToConstant: metrics.speedIndicatorHeight)
        ])
    }

    private func setupControlTargets() {
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        sliderView.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        sliderView.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        sliderView.addTarget(self, action: #selector(sliderTouchUp), for: .editingDidEnd)
    }

    private func configureOverlayGradients() {
        topOverlayView.isUserInteractionEnabled = false
        bottomOverlayView.isUserInteractionEnabled = false

        topOverlayGradient.colors = [
            UIColor.black.withAlphaComponent(0.55).cgColor,
            UIColor.black.withAlphaComponent(0.28).cgColor,
            UIColor.clear.cgColor
        ]
        topOverlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
        topOverlayGradient.endPoint = CGPoint(x: 0.5, y: 1)

        bottomOverlayGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.2).cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        bottomOverlayGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bottomOverlayGradient.endPoint = CGPoint(x: 0.5, y: 1)

        topOverlayView.layer.addSublayer(topOverlayGradient)
        bottomOverlayView.layer.addSublayer(bottomOverlayGradient)
    }

    private func applyModernStyling() {
        let scale = controlScale
        let circleControls: [UIVisualEffectView] = [
            playPauseBackgroundView, previousBackgroundView, nextBackgroundView, closeBackgroundView,
            listBackgroundView, settingsBackgroundView, subtitleBackgroundView
        ]
        circleControls.forEach {
            $0.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            $0.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
            $0.layer.borderWidth = 1
        }

        [sliderBackgroundView, speedBackgroundView, lockBackgroundView].forEach {
            $0.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.42)
            $0.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
            $0.layer.borderWidth = 1
        }
        skipBackgroundView.contentView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.72)
        skipBackgroundView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.35).cgColor
        skipBackgroundView.layer.borderWidth = 1

        [playPauseButton, previousButton, nextButton, listButton, settingsButton, subtitleButton, lockButton].forEach {
            $0.tintColor = .white
        }

        closeButton.tintColor = .white
        closeButton.backgroundColor = .clear
        speedButton.tintColor = .white
        skipIntroButton.tintColor = .white

        showTitleLabel.font = .systemFont(ofSize: 17 * scale, weight: .semibold)
        showTitleLabel.textColor = .white
        episodeNumberLabel.font = .systemFont(ofSize: 13 * scale, weight: .semibold)
        episodeNumberLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        watchedTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11 * scale, weight: .semibold)
        watchedTimeLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11 * scale, weight: .semibold)
        totalTimeLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        watchedTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        totalTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        watchedTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        speedButton.titleLabel?.font = .systemFont(ofSize: 17 * scale, weight: .semibold)
        skipIntroButton.titleLabel?.font = .systemFont(ofSize: 15 * scale, weight: .semibold)
        speedIndicatorLabel.font = .systemFont(ofSize: 16 * scale, weight: .bold)

        speedIndicatorBackgroundView.contentView.backgroundColor = UIColor.black.withAlphaComponent(0.44)
        speedIndicatorBackgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        speedIndicatorBackgroundView.layer.borderWidth = 1
    }

    private func applyControlSymbolSizes() {
        let scale = controlScale
        let symbolSize = 20 * scale
        let utilitySymbolSize = 14 * scale
        let subtitleSymbolSize = 4 * scale
        let lockSymbolSize = 10 * scale
        let playPauseSymbolSize = 32 * scale

        closeButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18 * scale, weight: .semibold),
            forImageIn: .normal
        )
        playPauseButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: playPauseSymbolSize, weight: .medium),
            forImageIn: .normal
        )
        previousButton.setPreferredSymbolConfiguration(
            createSymbolConfig(size: symbolSize),
            forImageIn: .normal
        )
        nextButton.setPreferredSymbolConfiguration(
            createSymbolConfig(size: symbolSize),
            forImageIn: .normal
        )
        previousButton.setImage(UIImage(systemName: "backward.end.fill"), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill"), for: .normal)
        listButton.setImage(
            UIImage(systemName: "list.bullet", withConfiguration: createSymbolConfig(size: utilitySymbolSize)),
            for: .normal
        )
        settingsButton.setImage(
            UIImage(systemName: "gearshape.fill", withConfiguration: createSymbolConfig(size: utilitySymbolSize)),
            for: .normal
        )
        let subtitleConfig = createSymbolConfig(size: subtitleSymbolSize)
        subtitleButton.setPreferredSymbolConfiguration(subtitleConfig, forImageIn: .normal)
        subtitleButton.setImage(
            UIImage(systemName: "captions.bubble.fill"),
            for: .normal
        )
        lockButton.setImage(
            UIImage(systemName: "lock.open.fill", withConfiguration: createSymbolConfig(size: lockSymbolSize)),
            for: .normal
        )
    }

    private func updateControlCornerRadii(metrics: ControlMetrics) {
        playPauseBackgroundView.layer.cornerRadius = metrics.playPauseSize / 2
        previousBackgroundView.layer.cornerRadius = metrics.secondaryControlSize / 2
        nextBackgroundView.layer.cornerRadius = metrics.secondaryControlSize / 2
        closeBackgroundView.layer.cornerRadius = metrics.utilityControlSize / 2
        listBackgroundView.layer.cornerRadius = metrics.utilityControlSize / 2
        settingsBackgroundView.layer.cornerRadius = metrics.utilityControlSize / 2
        subtitleBackgroundView.layer.cornerRadius = metrics.utilityControlSize / 2
        sliderBackgroundView.layer.cornerRadius = metrics.sliderHeight / 2
        speedBackgroundView.layer.cornerRadius = metrics.speedRowHeight / 2
        lockBackgroundView.layer.cornerRadius = metrics.speedRowHeight / 2
        skipBackgroundView.layer.cornerRadius = metrics.speedRowHeight / 2
        speedIndicatorBackgroundView.layer.cornerRadius = metrics.speedIndicatorHeight / 2
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
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.contentView.backgroundColor = color.withAlphaComponent(0.55)
        view.layer.borderColor = borderColor.withAlphaComponent(0.2).cgColor
        view.layer.borderWidth = 1
        return view
    }

    func createSymbolConfig(size: CGFloat, weight: UIImage.SymbolWeight = .medium) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: size, weight: weight)
    }

    func createSystemButton(symbol: String, size: CGFloat = 20, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: createSymbolConfig(size: size)), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    func createSkipFeedbackView(direction: SkipDirection) -> UIView {
        let scale = controlScale
        let container = UIView()
        container.backgroundColor = .clear
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 40 * scale, weight: .medium)
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
        label.font = .systemFont(ofSize: 16 * scale, weight: .semibold)
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
        playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    func updateTimeLabels() {
        watchedTimeLabel.text = formatTime(position)
        totalTimeLabel.text = formatTime(duration)
        updateSliderWidthForTimeLabels()
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

    func updateSliderWidthForTimeLabels() {
        let metrics = ControlMetrics(scale: controlScale)
        let safeWidth = videoContainer.safeAreaLayoutGuide.layoutFrame.width
        let maxWidth = safeWidth - (metrics.sliderSidePadding * 2)
        sliderMaxWidthConstraint?.constant = maxWidth
    }

    var controlViews: [UIView] {
        [
            topOverlayView, bottomOverlayView,
            playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
            closeBackgroundView, listBackgroundView, sliderBackgroundView, watchedTimeLabel,
            totalTimeLabel, sliderView, speedBackgroundView, lockBackgroundView, skipBackgroundView,
            titleStackView, settingsBackgroundView, subtitleBackgroundView
        ]
    }

    var interactionEnabledViews: [UIView] {
        controlViews.filter {
            !($0 is UILabel) &&
            !($0 is UIStackView) &&
            $0 !== topOverlayView &&
            $0 !== bottomOverlayView
        }
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

private extension PlayerViewController {
    struct ControlMetrics {
        let playPauseSize: CGFloat
        let playPauseIconSize: CGFloat
        let secondaryControlSize: CGFloat
        let secondaryIconSize: CGFloat
        let utilityControlSize: CGFloat
        let utilityIconSize: CGFloat
        let sliderHeight: CGFloat
        let sliderSidePadding: CGFloat
        let sliderBottomPadding: CGFloat
        let sliderThumbInset: CGFloat
        let sliderMinWidth: CGFloat
        let sliderMaxWidth: CGFloat
        let mainControlSpacing: CGFloat
        let topOverlayHeight: CGFloat
        let bottomOverlayHeight: CGFloat
        let speedRowHeight: CGFloat
        let speedRowMinWidth: CGFloat
        let lockRowWidth: CGFloat
        let skipRowMinWidth: CGFloat
        let topPadding: CGFloat
        let sidePadding: CGFloat
        let utilitySpacing: CGFloat
        let titleSpacing: CGFloat
        let skipFeedbackInset: CGFloat
        let speedIndicatorTop: CGFloat
        let speedIndicatorHeight: CGFloat

        init(scale: CGFloat) {
            let sliderScale: CGFloat = 1
            playPauseSize = 60 * scale
            playPauseIconSize = 44 * scale
            secondaryControlSize = 50 * scale
            secondaryIconSize = 44 * scale
            utilityControlSize = 44 * scale
            utilityIconSize = 30 * scale
            sliderHeight = (scale > 1) ? (36 * scale) : (28 * sliderScale)
            sliderSidePadding = (scale > 1) ? (22 * scale) : (16 * sliderScale)
            sliderBottomPadding = (scale > 1) ? (12 * scale) : (4 * sliderScale)
            sliderThumbInset = 14 * sliderScale
            sliderMinWidth = 200 * sliderScale
            sliderMaxWidth = 560 * sliderScale
            mainControlSpacing = 22 * scale
            topOverlayHeight = 160 * scale
            bottomOverlayHeight = 210 * scale
            speedRowHeight = 34 * scale
            speedRowMinWidth = 54 * scale
            lockRowWidth = 40 * scale
            skipRowMinWidth = 60 * scale
            topPadding = 12 * scale
            sidePadding = 16 * scale
            utilitySpacing = 12 * scale
            titleSpacing = 14 * scale
            skipFeedbackInset = 48 * scale
            speedIndicatorTop = 14 * scale
            speedIndicatorHeight = 38 * scale
        }
    }
}
