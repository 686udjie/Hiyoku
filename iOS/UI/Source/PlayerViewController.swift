//
//  PlayerViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import UIKit
import CoreData
import AVFoundation
import Libmpv
import SwiftUI
import AidokuRunner

class PlayerViewController: UIViewController, UIGestureRecognizerDelegate {

    let module: ScrapingModule
    var videoUrl: String
    var videoTitle: String
    var headers: [String: String]
    let mangaId: String?
    private var resolvedUrl: String?
    private var markedAsCompleted = false

    // Navigation Callbacks
    var onNextEpisode: (() -> Void)?
    var onPreviousEpisode: (() -> Void)?
    var onEpisodeSelected: ((PlayerEpisode) -> Void)?
    var onDismiss: (() -> Void)?

    // Data
    var allEpisodes: [PlayerEpisode] = []
    var currentEpisode: PlayerEpisode?
    private var pendingStartTime: Double?
    private var isFileLoaded = false

    // MPV Properties
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let videoContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }()

    private let renderQueue = DispatchQueue(label: "hiyoku.mpv.render", qos: .userInitiated)
    private let eventQueue = DispatchQueue(label: "hiyoku.mpv.events", qos: .utility)

    private var isRunning = false
    private var isPaused = true
    private var duration: Double = 0
    private var position: Double = 0
    private var lastSavedTime: TimeInterval = 0

    private let bgraFormatCString: [CChar] = Array("bgra\0".utf8CString)
    private var dimensionsArray = [Int32](repeating: 0, count: 2)
    private var renderParams = [mpv_render_param](repeating: mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                                                  count: 5)

    private var formatDescription: CMVideoFormatDescription?
    private var videoSize: CGSize = .zero
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolDimensions: (width: Int, height: Int)?

    private let playPauseButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        b.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        return b
    }()

    private lazy var playPauseBackgroundView = createControlBackground(cornerRadius: 30)
    private lazy var previousBackgroundView = createControlBackground(cornerRadius: 25)
    private lazy var nextBackgroundView = createControlBackground(cornerRadius: 25)
    private lazy var closeBackgroundView = createControlBackground(cornerRadius: 22)
    private lazy var sliderBackgroundView = createControlBackground(cornerRadius: 20)
    private lazy var speedBackgroundView = createControlBackground(cornerRadius: 14)
    private lazy var lockBackgroundView = createControlBackground(cornerRadius: 14)
    private lazy var skipBackgroundView = createControlBackground(
        cornerRadius: 14,
        color: .systemBlue.withAlphaComponent(0.8),
        borderColor: .systemBlue.withAlphaComponent(0.3)
    )
    private lazy var speedIndicatorBackgroundView = createControlBackground(cornerRadius: 18)

    private lazy var previousButton = createSystemButton(symbol: "backward.end.fill", action: #selector(previousTapped))

    private lazy var nextButton = createSystemButton(symbol: "forward.end.fill", action: #selector(nextTapped))

    private let closeButton: UIButton = {
        let b = UIButton(type: .close)
        return b
    }()

    private let sliderView: ReaderSliderView = {
        let slider = ReaderSliderView()
        slider.backgroundColor = .clear
        return slider
    }()

    private let watchedTimeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .left
        return l
    }()

    private let totalTimeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    private lazy var speedButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("1×", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.tintColor = .label
        b.showsMenuAsPrimaryAction = true
        b.menu = UIMenu(children: [
            UIAction(title: "0.5×") { [weak self] _ in self?.setSpeed(0.5) },
            UIAction(title: "1×") { [weak self] _ in self?.setSpeed(1) },
            UIAction(title: "1.25×") { [weak self] _ in self?.setSpeed(1.25) },
            UIAction(title: "1.5×") { [weak self] _ in self?.setSpeed(1.5) },
            UIAction(title: "2×") { [weak self] _ in self?.setSpeed(2) }
        ])
        return b
    }()

    private lazy var listButton = createSystemButton(symbol: "list.bullet", action: #selector(listTapped))

    private lazy var listBackgroundView = createControlBackground(cornerRadius: 22)

    private lazy var lockButton: UIButton = {
        let b = createSystemButton(symbol: "lock.open.fill", size: 16, action: #selector(lockTapped))
        return b
    }()

    init(
        module: ScrapingModule,
        videoUrl: String,
        videoTitle: String,
        headers: [String: String] = [:],
        subtitleUrl: String? = nil,
        episodes: [PlayerEpisode] = [],
        currentEpisode: PlayerEpisode? = nil,
        mangaId: String? = nil
    ) {
        self.module = module
        self.videoUrl = videoUrl
        self.videoTitle = videoTitle
        self.headers = headers
        self.subtitleUrl = subtitleUrl
        self.mangaId = mangaId
        self.allEpisodes = episodes
        self.currentEpisode = currentEpisode
        super.init(nibName: nil, bundle: nil)

        // landscape presentation
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(episodes: [PlayerEpisode], current: PlayerEpisode, title: String) {
        self.allEpisodes = episodes
        self.currentEpisode = current
        self.updateTitle(title)
    }

    private lazy var settingsButton = createSystemButton(symbol: "gearshape.fill", action: #selector(settingsTapped))

    private lazy var settingsBackgroundView = createControlBackground(cornerRadius: 22)

    private let showTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .left
        return l
    }()

    private let episodeNumberLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .left
        return l
    }()

    private lazy var titleStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [showTitleLabel, episodeNumberLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }()

    private lazy var gutterUnlockButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        b.setImage(UIImage(systemName: "lock.fill", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        b.layer.cornerRadius = 25
        b.alpha = 0
        b.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)
        return b
    }()

    private lazy var skipIntroButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("\(Int(skipIntroButtonDuration))s", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.tintColor = .white
        b.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(skipLongPressed(_:)))
        b.addGestureRecognizer(longPress)
        return b
    }()

    private let speedIndicatorLabel: UILabel = {
        let l = UILabel()
        l.text = "2x ▶▶"
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    private var isLocked = false
    private var isSeeking = false
    private var isUIVisible = true
    private var autoHideTimer: Timer?
    private var originalSpeed: Double = 1
    private var isSpeedBoosted = false
    private var currentPlaybackSpeed: Double = 1

    // Double tap skip properties
    private var doubleTapLeftGesture: UITapGestureRecognizer!
    private var doubleTapRightGesture: UITapGestureRecognizer!
    private var twoFingerTapGesture: UITapGestureRecognizer!
    private lazy var leftSkipFeedbackView = createSkipFeedbackView(direction: .backward)
    private lazy var rightSkipFeedbackView = createSkipFeedbackView(direction: .forward)

    // SkipIntroButton duration
    private var skipIntroButtonDuration: Double = {
        let saved = UserDefaults.standard.double(forKey: "Player.skipIntroButtonDuration")
        return saved == 0 ? 85 : saved
    }() {
        didSet {
            UserDefaults.standard.set(skipIntroButtonDuration, forKey: "Player.skipIntroButtonDuration")
            skipIntroButton.setTitle("\(Int(skipIntroButtonDuration))s", for: .normal)
        }
    }

    private var doubleTapSkipDuration: Double {
        get {
            let value = UserDefaults.standard.double(forKey: "Player.doubleTapSkipDuration")
            return value == 0 ? 10 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: "Player.doubleTapSkipDuration") }
    }

    private let m3u8Extractor = M3U8Extractor.shared

    // Subtitles
    var subtitleUrl: String?
    var subtitlesLoader = VTTSubtitlesLoader()
    var subtitleStackView: UIStackView!
    var subtitleLabels: [UILabel] = []
    var subtitleBottomToSliderConstraint: NSLayoutConstraint?
    var subtitleBottomPadding: CGFloat = 10 {
        didSet {
            updateSubtitlePosition()
        }
    }
    var subtitlesEnabled: Bool = true {
        didSet {
            subtitleStackView?.isHidden = !subtitlesEnabled
            // Update button state
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            let imageName = subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
            subtitleButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
        }
    }
    var subtitleDelay: Double = 0
    private lazy var subtitleButton = createSystemButton(symbol: "captions.bubble.fill", action: #selector(subtitleTapped))
    private lazy var subtitleBackgroundView = createControlBackground(cornerRadius: 22)

    deinit {
        stopPlayer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableSwipeGestures()
        resetAutoHideTimer()

        if resolvedUrl == nil {
            prepareAndPlay()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayer()
        autoHideTimer?.invalidate()
        onDismiss?()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        displayLayer.frame = videoContainer.bounds
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        do {
            try setupMPV()
        } catch {
            showError(message: "Failed to initialize player: \(error)")
        }

        listButton.isEnabled = allEpisodes.count > 1
        listButton.tintColor = allEpisodes.count > 1 ? .white : .secondaryLabel

        setupSubtitleLabel()
        loadSubtitleSettings()
        if let subUrl = subtitleUrl, !subUrl.isEmpty {
             subtitlesLoader.load(from: subUrl)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(subtitleSettingsDidChange), name: .subtitleSettingsDidChange, object: nil)
        updatePlayerMetadata()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        overrideUserInterfaceStyle = .dark
    }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    override var prefersStatusBarHidden: Bool {
        true
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var shouldAutorotate: Bool {
        true
    }
}

// MARK: - UI Setup
extension PlayerViewController {
    private func setupUI() {
        view.backgroundColor = .black
        videoContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoContainer.frame = view.bounds
        view.addSubview(videoContainer)

        displayLayer.videoGravity = .resizeAspect
        videoContainer.layer.addSublayer(displayLayer)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        videoContainer.addGestureRecognizer(tapGesture)

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
        [playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
         closeBackgroundView, listBackgroundView, sliderBackgroundView, speedBackgroundView,
         lockBackgroundView, skipBackgroundView, settingsBackgroundView, subtitleBackgroundView, gutterUnlockButton,
         watchedTimeLabel, totalTimeLabel, titleStackView, leftSkipFeedbackView, rightSkipFeedbackView,
         speedIndicatorBackgroundView].forEach {

            $0.translatesAutoresizingMaskIntoConstraints = false
            videoContainer.addSubview($0)
        }

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

    private func centerInParent(_ view: UIView, parent: UIVisualEffectView, size: CGSize, fill: Bool = false) {
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

    private func createControlBackground(cornerRadius: CGFloat, color: UIColor = .tertiarySystemFill,
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

    private func createSymbolConfig(size: CGFloat, weight: UIImage.SymbolWeight = .medium) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: size, weight: weight)
    }

    private func createSystemButton(symbol: String, size: CGFloat = 20, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: createSymbolConfig(size: size)), for: .normal)
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func createSkipFeedbackView(direction: SkipDirection) -> UIView {
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

    enum SkipDirection {
        case forward, backward
    }

    private func updatePlayPauseButton() {

        let imageName = isPaused ? "play.fill" : "pause.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }

    private func updateTimeLabels() {
        watchedTimeLabel.text = formatTime(position)
        totalTimeLabel.text = formatTime(duration)
    }
}

// MARK: - Actions & Logic
extension PlayerViewController {
    @objc private func handleTap() {
        if isLocked {
            let isVisible = gutterUnlockButton.alpha > 0
            UIView.animate(withDuration: 0.3) {
                self.gutterUnlockButton.alpha = isVisible ? 0 : 1
            }
            if !isVisible {
                resetAutoHideTimer()
            } else {
                autoHideTimer?.invalidate()
            }
        } else {
            toggleUIVisibility()
        }
    }

    @objc private func handleDoubleTapLeft() {
        skipBackward()
    }

    @objc private func handleDoubleTapRight() {
        skipForward()
    }

    @objc private func handleTwoFingerTap() {
        guard UserDefaults.standard.bool(forKey: "Player.twoFingerTapToPause") else { return }
        playPauseTapped()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard mpv != nil else { return }

        switch gesture.state {
        case .began:
            // Boost to 2x
            if !isSpeedBoosted {
                originalSpeed = currentPlaybackSpeed
                isSpeedBoosted = true
                setProperty("speed", "2")
                speedButton.setTitle(formatSpeed(2), for: .normal)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                UIView.animate(withDuration: 0.2) {
                    self.speedIndicatorBackgroundView.alpha = 1
                }
            }

        case .ended, .cancelled, .failed:
            if isSpeedBoosted {
                isSpeedBoosted = false
                setProperty("speed", "\(originalSpeed)")
                speedButton.setTitle(formatSpeed(originalSpeed), for: .normal)

                UIView.animate(withDuration: 0.2) {
                    self.speedIndicatorBackgroundView.alpha = 0
                }
            }

        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: videoContainer)
        let containerWidth = videoContainer.bounds.width

        // Handle double tap gestures
        if gestureRecognizer == doubleTapLeftGesture {
            return location.x < containerWidth / 2
        } else if gestureRecognizer == doubleTapRightGesture {
            return location.x >= containerWidth / 2
        }
        if gestureRecognizer is UILongPressGestureRecognizer {
            let skipButtonFrameInContainer = skipBackgroundView.convert(skipIntroButton.frame, to: videoContainer)
            if skipButtonFrameInContainer.contains(location) {
                return false
            }
        }

        return true
    }

    private func skipForward() {
        guard mpv != nil else { return }
        let currentPos = position
        let newPos = currentPos + doubleTapSkipDuration
        setProperty("time-pos", "\(newPos)")
        showSkipFeedback(direction: .forward)
    }

    private func skipBackward() {
        guard mpv != nil else { return }
        let currentPos = position
        let newPos = max(0, currentPos - doubleTapSkipDuration)
        setProperty("time-pos", "\(newPos)")
        showSkipFeedback(direction: .backward)
    }

    private func showSkipFeedback(direction: SkipDirection) {
        let feedbackView = direction == .forward ? rightSkipFeedbackView : leftSkipFeedbackView

        if let label = feedbackView.viewWithTag(999) as? UILabel {
            label.text = "\(Int(doubleTapSkipDuration)) seconds"
        }

        feedbackView.alpha = 0
        feedbackView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        UIView.animate(withDuration: 0.2, animations: {
            feedbackView.alpha = 1
            feedbackView.transform = .identity
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                feedbackView.alpha = 0
            }, completion: nil)
        })
    }

    private func setSpeed(_ speed: Double) {
        currentPlaybackSpeed = speed
        setProperty("speed", "\(speed)")
        speedButton.setTitle(formatSpeed(speed), for: .normal)
        resetAutoHideTimer()
    }

    private func formatSpeed(_ speed: Double) -> String {
        speed == Double(Int(speed)) ? "\(Int(speed))×" : "\(speed)×"
    }

    private func toggleUIVisibility() {
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

    @objc private func skipLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        presentSkipDurationPicker()
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

    private var controlViews: [UIView] {
        [
            playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
            closeBackgroundView, listBackgroundView, sliderBackgroundView, watchedTimeLabel,
            totalTimeLabel, speedBackgroundView, lockBackgroundView, skipBackgroundView,
            titleStackView, settingsBackgroundView, subtitleBackgroundView
        ]
    }

    private var interactionEnabledViews: [UIView] {
        controlViews.filter { !($0 is UILabel) && !($0 is UIStackView) }
    }

    private func resetAutoHideTimer() {
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

    @objc private func lockTapped() {
        isLocked = true
        if isUIVisible {
            toggleUIVisibility()
        }
    }

    @objc private func unlockTapped() {
        isLocked = false
        UIView.animate(withDuration: 0.3) {
            self.gutterUnlockButton.alpha = 0
        }
        toggleUIVisibility()
    }

    @objc private func skipTapped() {
        guard mpv != nil else { return }
        let currentPos = position
        let newPos = currentPos + skipIntroButtonDuration
        setProperty("time-pos", "\(newPos)")
        resetAutoHideTimer()
    }

    @objc private func playPauseTapped() {
        togglePause()
    }

    @objc private func nextTapped() {
        onNextEpisode?()
    }

    @objc private func previousTapped() {
        onPreviousEpisode?()
    }

    @objc private func closeTapped() {
        saveProgress()
        dismiss(animated: true)
    }

    private func formatTime(_ seconds: Double) -> String {
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

    @objc private func sliderValueChanged() {
        guard mpv != nil, duration > 0 else { return }
        let seekPos = sliderView.currentValue * CGFloat(duration)
        setProperty("time-pos", String(format: "%f", seekPos))
    }

    @objc private func sliderTouchDown() {
        isSeeking = true
        autoHideTimer?.invalidate()
    }

    @objc private func sliderTouchUp() {
        isSeeking = false
        resetAutoHideTimer()
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

    private func showError(message: String) {
        let dismissAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        presentAlert(title: "Video Error", message: message, actions: [dismissAction])
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

    private func prepareAndPlay() {
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

    private func updatePlayerMetadata() {
        showTitleLabel.text = videoTitle
        if let current = currentEpisode {
            episodeNumberLabel.text = "Episode \(current.number)"
        } else {
            episodeNumberLabel.text = ""
        }

        listButton.isEnabled = allEpisodes.count > 1
        listButton.tintColor = allEpisodes.count > 1 ? .white : .secondaryLabel
    }

    @objc private func listTapped() {
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

    func updateTitle(_ title: String) {
        self.videoTitle = title
        updatePlayerMetadata()
    }

    @objc private func settingsTapped() {
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
    // MARK: - Subtitle Logic
    func setupSubtitleLabel() {
        subtitleStackView = UIStackView()
        subtitleStackView.axis = .vertical
        subtitleStackView.alignment = .center
        subtitleStackView.distribution = .fill
        subtitleStackView.spacing = 2
        videoContainer.addSubview(subtitleStackView)
        subtitleStackView.translatesAutoresizingMaskIntoConstraints = false
        // Always pin to slider top
        subtitleBottomToSliderConstraint = subtitleStackView.bottomAnchor.constraint(equalTo: sliderBackgroundView.topAnchor, constant: -20)
        NSLayoutConstraint.activate([
            subtitleStackView.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            subtitleStackView.leadingAnchor.constraint(greaterThanOrEqualTo: videoContainer.leadingAnchor, constant: 36),
            subtitleStackView.trailingAnchor.constraint(lessThanOrEqualTo: videoContainer.trailingAnchor, constant: -36),
            subtitleBottomToSliderConstraint!
        ])
        for _ in 0..<2 {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = UIFont.systemFont(ofSize: 20)
            // Add shadow for better visibility
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOffset = CGSize(width: 1, height: 1)
            label.layer.shadowOpacity = 1
            label.layer.shadowRadius = 1
            subtitleLabels.append(label)
            subtitleStackView.addArrangedSubview(label)
        }
        updateSubtitleLabelAppearance()
    }
    func updateSubtitleLabelAppearance() {
        let settings = SubtitleSettingsManager.shared.settings
        for label in subtitleLabels {
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: CGFloat(settings.fontSize), weight: .medium)
            label.layer.shadowRadius = CGFloat(settings.shadowRadius)
            if settings.backgroundEnabled {
                label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            } else {
                label.backgroundColor = .clear
            }
        }
    }

    private func updateSubtitlePosition() {
        if isUIVisible {
            subtitleBottomToSliderConstraint?.constant = -20 - subtitleBottomPadding
        } else {
            subtitleBottomToSliderConstraint?.constant = 20
        }
    }

    func loadSubtitleSettings() {
        let settings = SubtitleSettingsManager.shared.settings
        self.subtitlesEnabled = settings.enabled
        self.subtitleDelay = settings.subtitleDelay
        self.subtitleBottomPadding = settings.bottomPadding
        updateSubtitleLabelAppearance()
    }
    @objc private func subtitleSettingsDidChange() {
        DispatchQueue.main.async {
            self.loadSubtitleSettings()
        }
    }

    @objc private func subtitleTapped() {
        subtitlesEnabled.toggle()
        SubtitleSettingsManager.shared.update { $0.enabled = subtitlesEnabled }
        loadSubtitleSettings()
    }
    func updateSubtitleStack(with lines: [String]) {
        // Hide unused labels
        for label in subtitleLabels {
            label.text = nil
            label.isHidden = true
        }
        // Populate labels
        for (index, line) in lines.enumerated() where index < subtitleLabels.count {
            subtitleLabels[index].text = line
            subtitleLabels[index].isHidden = false
        }
        subtitleStackView.isHidden = false
    }
    func clearSubtitleStack() {
        for label in subtitleLabels {
            label.text = nil
            label.isHidden = true
        }
    }
}

// MARK: - MPV Core
extension PlayerViewController {
    private func setupMPV() throws {
        guard let handle = mpv_create() else {
            throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mpv instance"])
        }
        self.mpv = handle

        setOption("vo", "libmpv")
        setOption("hwdec", "videotoolbox")
        setOption("keep-open", "yes")
        setOption("hr-seek", "yes")

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            let errorMsg = String(cString: mpv_error_string(status))
            throw NSError(domain: "MPV", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize mpv: \(errorMsg)"])
        }

        try createRenderContext()
        observeProperties()
        installWakeupHandler()
        isRunning = true
    }

    private func createRenderContext() throws {
        guard let handle = mpv else { return }

        var apiType = MPV_RENDER_API_TYPE_SW
        let status = withUnsafePointer(to: &apiType) { apiTypePtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypePtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return params.withUnsafeMutableBufferPointer { pointer in
                mpv_render_context_create(&renderContext, handle, pointer.baseAddress)
            }
        }

        guard status >= 0, renderContext != nil else {
            throw NSError(domain: "MPV", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create render context"])
        }

        mpv_render_context_set_update_callback(renderContext, { context in
            guard let context = context else { return }
            let instance = Unmanaged<PlayerViewController>.fromOpaque(context).takeUnretainedValue()
            instance.renderQueue.async {
                instance.performRenderUpdate()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func performRenderUpdate() {
        guard let context = renderContext, isRunning else { return }
        let status = mpv_render_context_update(context)
        if (UInt32(status) & MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
            renderFrame()
        }
    }

    private func renderFrame() {
        guard let context = renderContext, isRunning else { return }

        // Use native video size or default to 1080p if unknown
        let width = Int(videoSize.width > 0 ? videoSize.width : 1920)
        let height = Int(videoSize.height > 0 ? videoSize.height : 1080)

        // Create or reset pool if dimensions changed
        if pixelBufferPool == nil || poolDimensions?.width != width || poolDimensions?.height != height {
            createPixelBufferPool(width: width, height: height)
        }

        guard let pool = pixelBufferPool else { return }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }

        dimensionsArray[0] = Int32(width)
        dimensionsArray[1] = Int32(height)
        let stride = Int32(CVPixelBufferGetBytesPerRow(buffer))

        dimensionsArray.withUnsafeMutableBufferPointer { dimsPointer in
            bgraFormatCString.withUnsafeBufferPointer { formatPointer in
                withUnsafePointer(to: stride) { stridePointer in
                    renderParams[0] = mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE,
                                                       data: UnsafeMutableRawPointer(dimsPointer.baseAddress))
                    renderParams[1] = mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT,
                                                       data: UnsafeMutableRawPointer(mutating: formatPointer.baseAddress))
                    renderParams[2] = mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE,
                                                       data: UnsafeMutableRawPointer(mutating: stridePointer))
                    renderParams[3] = mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: baseAddress)
                    renderParams[4] = mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)

                    mpv_render_context_render(context, &renderParams)
                }
            }
        }

        enqueue(buffer: buffer)
    }

    private func enqueue(buffer: CVPixelBuffer) {
        updateFormatDescriptionIfNeeded(for: buffer)
        guard let formatDescription = formatDescription else { return }

        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime,
                                        decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        let result = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        if result == noErr, let sample = sampleBuffer {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.displayLayer.status == .failed {
                    self.displayLayer.flushAndRemoveImage()
                }
                self.displayLayer.enqueue(sample)
            }
        }
    }

    private func updateFormatDescriptionIfNeeded(for buffer: CVPixelBuffer) {
        let width = Int32(CVPixelBufferGetWidth(buffer))
        let height = Int32(CVPixelBufferGetHeight(buffer))
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)

        var needsRecreate = false
        if let description = formatDescription {
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            if dimensions.width != width || dimensions.height != height ||
                CMFormatDescriptionGetMediaSubType(description) != pixelFormat {
                needsRecreate = true
            }
        } else {
            needsRecreate = true
        }

        if needsRecreate {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                         formatDescriptionOut: &formatDescription)
        }
    }

    private func startMpvPlayback() {
        guard let handle = mpv else { return }
        updateHTTPHeaders()
        guard let urlToPlay = resolvedUrl else { return }
        Task {
            // check for history before playing
            let startTime = await getSavedProgress()
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.pendingStartTime = (startTime != nil && startTime! > 5) ? startTime : nil
                self.setProperty("pause", "yes")
                let cmd = ["loadfile", urlToPlay, "replace"]
                withCStringArray(cmd) { ptr in
                    _ = mpv_command(handle, ptr)
                }
                self.isRunning = true
                self.isPaused = true
                self.isFileLoaded = false
            }
        }
    }
    private func getSavedProgress() async -> Double? {
        guard let current = currentEpisode else { return nil }
        return await PlayerHistoryManager.shared.getProgress(episodeId: current.url, moduleId: module.id.uuidString)
    }
    private func saveProgress() {
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

        // Trigger tracker update if threshold is met
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

    private func setOption(_ name: String, _ value: String) {
        guard let handle = mpv else { return }
        mpv_set_option_string(handle, name, value)
    }

    private func setProperty(_ name: String, _ value: String) {
        guard let handle = mpv else { return }
        mpv_set_property_string(handle, name, value)
    }

    private func updateHTTPHeaders() {
        guard !headers.isEmpty else { return }
        let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        setProperty("http-header-fields", headerString)
    }

    private func observeProperties() {
        guard let handle = mpv else { return }
        let properties: [(String, mpv_format)] = [
            ("duration", MPV_FORMAT_DOUBLE), ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG), ("speed", MPV_FORMAT_DOUBLE),
            ("video-out-params", MPV_FORMAT_NODE)
        ]
        properties.forEach { mpv_observe_property(handle, 0, $0.0, $0.1) }
    }

    private func installWakeupHandler() {
        guard let handle = mpv else { return }
        mpv_set_wakeup_callback(handle, { userdata in
            guard let userdata = userdata else { return }
            let instance = Unmanaged<PlayerViewController>.fromOpaque(userdata).takeUnretainedValue()
            instance.processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func processEvents() {
        eventQueue.async { [weak self] in
            while let self = self, self.isRunning {
                guard let handle = self.mpv, let event = mpv_wait_event(handle, 0) else { break }
                if event.pointee.event_id == MPV_EVENT_NONE { break }
                self.handleEvent(event.pointee)
            }
        }
    }

    private func handleEvent(_ event: mpv_event) {
        if event.event_id == MPV_EVENT_FILE_LOADED {
            isFileLoaded = true
            if let start = pendingStartTime {
                let cmd = ["seek", String(start), "absolute+exact"]
                withCStringArray(cmd) { ptr in
                    mpv_command(mpv, ptr)
                }
                pendingStartTime = nil
            }
            setProperty("pause", "no")
            return
        }

        guard event.event_id == MPV_EVENT_PROPERTY_CHANGE else { return }
        let prop = event.data!.assumingMemoryBound(to: mpv_event_property.self).pointee
        let name = String(cString: prop.name)

        switch name {
        case "pause":
            isPaused = prop.data!.assumingMemoryBound(to: Int32.self).pointee != 0
            DispatchQueue.main.async { [weak self] in self?.updatePlayPauseButton() }
        case "video-out-params":
            handleVideoParams(prop)
        case "time-pos", "duration", "speed":
            if let val = getDouble(from: prop) {
                handleDoubleProperty(name, val)
            }
        default: break
        }
    }

    private func handleVideoParams(_ prop: mpv_event_property) {
        guard prop.format == MPV_FORMAT_NODE else { return }
        let node = prop.data!.assumingMemoryBound(to: mpv_node.self).pointee
        guard node.format == MPV_FORMAT_NODE_MAP else { return }
        let map = node.u.list.pointee
        var w: Int32 = 0, h: Int32 = 0
        for i in 0..<Int(map.num) {
            let key = String(cString: map.keys[i]!)
            if key == "dw" { w = Int32(map.values[i].u.int64) } else if key == "dh" { h = Int32(map.values[i].u.int64) }
        }
        if w > 0 && h > 0 {
            videoSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        }
    }

    private func handleDoubleProperty(_ name: String, _ value: Double) {
        if name == "time-pos" {
            position = value
            // Periodically save progress (every 15 seconds)
            let now = Date().timeIntervalSince1970
            if now - lastSavedTime > 15 {
                lastSavedTime = now
                saveProgress()
            }
        } else if name == "duration" { duration = value }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateTimeLabels()
            if name == "time-pos" && self.duration > 0 && !self.isSeeking {
                self.sliderView.currentValue = CGFloat(value / self.duration)
                self.updateSubtitles(for: value)
            } else if name == "speed" {
                self.speedButton.setTitle(self.formatSpeed(value), for: .normal)
            }
        }
    }

    private func updateSubtitles(for time: Double) {
        if subtitlesEnabled {
            let adjustedTime = time - subtitleDelay
            let cues = subtitlesLoader.cues.filter { adjustedTime >= $0.startTime && adjustedTime <= $0.endTime }

            if cues.isEmpty {
                clearSubtitleStack()
            } else {
                var lines: [String] = []
                let maxLines = 2
                for cue in cues {
                    if lines.count >= maxLines { break }
                    for rawLine in cue.lines {
                        if lines.count >= maxLines { break }
                        let cleaned = rawLine.strippedHTML
                        if !cleaned.isEmpty {
                            lines.append(cleaned)
                        }
                    }
                }
                updateSubtitleStack(with: lines)
            }
        } else {
            clearSubtitleStack()
        }
    }

    private func getDouble(from prop: mpv_event_property) -> Double? {
        guard prop.format == MPV_FORMAT_DOUBLE else { return nil }
        return prop.data?.assumingMemoryBound(to: Double.self).pointee
    }

    private func withCStringArray(_ args: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Void) {
        var cStrings = args.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
        cStrings.withUnsafeMutableBufferPointer { buffer in
            let ptr = buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { $0 }
            body(UnsafeMutablePointer(mutating: ptr))
        }
    }

    private func createPixelBufferPool(width: Int, height: Int) {
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes,
                                             pixelBufferAttributes as CFDictionary, &pool)

        if status == kCVReturnSuccess {
            self.pixelBufferPool = pool
            self.poolDimensions = (width, height)
        } else {
            pixelBufferPool = nil
        }
    }

    func stopPlayer() {
        if mpv == nil && !isRunning { return }
        saveProgress()
        isRunning = false
        let layer = displayLayer
        DispatchQueue.main.async {
            layer.flushAndRemoveImage()
        }
        if let context = renderContext {
            mpv_render_context_free(context)
            renderContext = nil
        }
        if let handle = mpv {
            mpv_destroy(handle)
            mpv = nil
        }
        pixelBufferPool = nil
    }
}

// MARK: - Gestures
extension PlayerViewController {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return velocity.y > velocity.x && (abs(velocity.x) < 40 || abs(velocity.y) > abs(velocity.x) * 3)
    }

    func disableSwipeGestures() {
        let gestureRecognizers = (parent?.view.gestureRecognizers ?? []) +
                                 (parent?.view.superview?.superview?.gestureRecognizers ?? [])
        for recognizer in gestureRecognizers {
            switch String(describing: type(of: recognizer)) {
            case "_UIParallaxTransitionPanGestureRecognizer":
                recognizer.isEnabled = false
            case "_UIContentSwipeDismissGestureRecognizer":
                recognizer.isEnabled = false
                recognizer.delegate = self
            default:
                break
            }
        }
    }
}

class SkipConfigViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    var currentValue: Int = 85
    var onSave: ((Int) -> Void)?

    private let pickerView = UIPickerView()
    private let values = Array(1...255)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        preferredContentSize = CGSize(width: 270, height: 160)
        pickerView.dataSource = self
        pickerView.delegate = self
        if let index = values.firstIndex(of: currentValue) {
            pickerView.selectRow(index, inComponent: 0, animated: false)
        }
        view.addSubview(pickerView)
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pickerView.topAnchor.constraint(equalTo: view.topAnchor),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        values.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        "\(values[row])s"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let newVal = values[row]
        onSave?(newVal)
    }
}
class EpisodeListViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    var episodes: [PlayerEpisode] = []
    var currentEpisode: PlayerEpisode?
    var onSelect: ((PlayerEpisode) -> Void)?

    private let pickerView = UIPickerView()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        preferredContentSize = CGSize(width: 270, height: 160)
        pickerView.dataSource = self
        pickerView.delegate = self

        if let current = currentEpisode, let index = episodes.firstIndex(where: { $0.url == current.url }) {
            pickerView.selectRow(index, inComponent: 0, animated: false)
        }

        view.addSubview(pickerView)
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pickerView.topAnchor.constraint(equalTo: view.topAnchor),
            pickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        episodes.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let episode = episodes[row]
        let prefix = "Episode \(episode.number)"
        if episode.title.isEmpty || episode.title == prefix || episode.title == "Episode \(episode.number)" {
            return prefix
        }
        return "\(prefix): \(episode.title)"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        // revamp
    }

    func getSelectedEpisode() -> PlayerEpisode? {
        let row = pickerView.selectedRow(inComponent: 0)
        guard row >= 0 && row < episodes.count else { return nil }
        return episodes[row]
    }
}
struct PlayerSettingsView: View {
    var onDismiss: () -> Void
    var body: some View {
        PlatformNavigationStack {
            List {
                ForEach(Array(Settings.playerSettings.enumerated()), id: \.offset) { _, setting in
                    SettingView(setting: setting)
                }
            }
            .navigationTitle(NSLocalizedString("PLAYER_SETTINGS"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                         if let topController = PlayerPresenter.findTopViewController() {
                            topController.dismiss(animated: true, completion: onDismiss)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}
