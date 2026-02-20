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
    var resolvedUrl: String?
    var markedAsCompleted = false

    // Navigation Callbacks
    var onNextEpisode: (() -> Void)?
    var onPreviousEpisode: (() -> Void)?
    var onEpisodeSelected: ((PlayerEpisode) -> Void)?
    var onDismiss: (() -> Void)?

    // Data
    var allEpisodes: [PlayerEpisode] = []
    var currentEpisode: PlayerEpisode?
    var pendingStartTime: Double?
    var isFileLoaded = false

    // MPV Properties
    var mpv: OpaquePointer?
    var renderContext: OpaquePointer?
    let displayLayer = AVSampleBufferDisplayLayer()
    let videoContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }()

    let renderQueue = DispatchQueue(label: "hiyoku.mpv.render", qos: .userInitiated)
    let eventQueue = DispatchQueue(label: "hiyoku.mpv.events", qos: .utility)

    var isRunning = false
    var isPaused = true
    var duration: Double = 0
    var position: Double = 0
    var lastSavedTime: TimeInterval = 0

    let bgraFormatCString: [CChar] = Array("bgra\0".utf8CString)
    var dimensionsArray = [Int32](repeating: 0, count: 2)
    var renderParams = [mpv_render_param](
        repeating: mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        count: 5
    )

    var formatDescription: CMVideoFormatDescription?
    var videoSize: CGSize = .zero
    var pixelBufferPool: CVPixelBufferPool?
    var poolDimensions: (width: Int, height: Int)?

    let playPauseButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        b.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        return b
    }()

    lazy var playPauseBackgroundView = createControlBackground(cornerRadius: 30)
    lazy var previousBackgroundView = createControlBackground(cornerRadius: 25)
    lazy var nextBackgroundView = createControlBackground(cornerRadius: 25)
    lazy var closeBackgroundView = createControlBackground(cornerRadius: 22)
    lazy var sliderBackgroundView = createControlBackground(cornerRadius: 20)
    lazy var speedBackgroundView = createControlBackground(cornerRadius: 14)
    lazy var lockBackgroundView = createControlBackground(cornerRadius: 14)
    lazy var skipBackgroundView = createControlBackground(
        cornerRadius: 14,
        color: .systemBlue.withAlphaComponent(0.8),
        borderColor: .systemBlue.withAlphaComponent(0.3)
    )
    lazy var speedIndicatorBackgroundView = createControlBackground(cornerRadius: 18)

    lazy var previousButton = createSystemButton(symbol: "backward.end.fill", action: #selector(previousTapped))
    lazy var nextButton = createSystemButton(symbol: "forward.end.fill", action: #selector(nextTapped))
    let closeButton: UIButton = {
        let b = UIButton(type: .close)
        return b
    }()

    let sliderView: ReaderSliderView = {
        let slider = ReaderSliderView()
        slider.backgroundColor = .clear
        return slider
    }()

    let watchedTimeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .left
        return l
    }()

    let totalTimeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    lazy var speedButton: UIButton = {
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

    lazy var listButton = createSystemButton(symbol: "list.bullet", action: #selector(listTapped))
    lazy var listBackgroundView = createControlBackground(cornerRadius: 22)
    lazy var lockButton: UIButton = {
        let b = createSystemButton(symbol: "lock.open.fill", size: 16, action: #selector(lockTapped))
        return b
    }()

    lazy var settingsButton = createSystemButton(symbol: "gearshape.fill", action: #selector(settingsTapped))
    lazy var settingsBackgroundView = createControlBackground(cornerRadius: 22)

    let showTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .left
        return l
    }()

    let episodeNumberLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .left
        return l
    }()

    lazy var titleStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [showTitleLabel, episodeNumberLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }()

    lazy var gutterUnlockButton: UIButton = {
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

    lazy var skipIntroButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("\(Int(skipIntroButtonDuration))s", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.tintColor = .white
        b.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(skipLongPressed(_:)))
        b.addGestureRecognizer(longPress)
        return b
    }()

    let speedIndicatorLabel: UILabel = {
        let l = UILabel()
        l.text = "2x ▶▶"
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    var isLocked = false
    var isSeeking = false
    var isUIVisible = true
    var autoHideTimer: Timer?
    var originalSpeed: Double = 1
    var isSpeedBoosted = false
    var currentPlaybackSpeed: Double = 1

    enum VerticalAdjustMode {
        case brightness
        case volume
    }

    enum SkipDirection {
        case backward
        case forward
    }

    // MARK: - HUD Structures
    struct VerticalHUD {
        let container: UIView
        let percentLabel: UILabel
        let fillView: UIView
        let borderView: UIView
        let iconView: UIImageView
        let fillAreaGuide: UILayoutGuide
        let defaultIcon: String
        let zeroIcon: String?
        let slashView: UIView?

        init(
            container: UIView,
            percentLabel: UILabel,
            fillView: UIView,
            borderView: UIView,
            iconView: UIImageView,
            fillAreaGuide: UILayoutGuide,
            defaultIcon: String,
            zeroIcon: String? = nil,
            slashView: UIView? = nil
        ) {
            self.container = container
            self.percentLabel = percentLabel
            self.fillView = fillView
            self.borderView = borderView
            self.iconView = iconView
            self.fillAreaGuide = fillAreaGuide
            self.defaultIcon = defaultIcon
            self.zeroIcon = zeroIcon
            self.slashView = slashView
        }
    }

    var verticalAdjustMode: VerticalAdjustMode?
    var verticalAdjustStartPoint: CGPoint = .zero
    var verticalAdjustStartBrightness: CGFloat = 0
    var verticalAdjustStartVolume: Double = 100
    var volumeHUDHideWorkItem: DispatchWorkItem?
    var brightnessHUDHideWorkItem: DispatchWorkItem?

    lazy var verticalPanGesture: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handleVerticalPan(_:)))
        g.delegate = self
        return g
    }()

    let volumeHUDContainer = UIView()
    let brightnessHUDContainer = UIView()
    let volumeHUDPercentLabel = UILabel()
    let brightnessHUDPercentLabel = UILabel()
    let volumeHUDFill = UIView()
    let brightnessHUDFill = UIView()
    let volumeHUDBorder = UIView()
    let brightnessHUDBorder = UIView()
    let volumeHUDFillAreaGuide = UILayoutGuide()
    let brightnessHUDFillAreaGuide = UILayoutGuide()
    var volumeHUDIconView = UIImageView()
    var brightnessHUDIconView = UIImageView()
    let brightnessHUDSlashView = UIView()
    var volumeHUDFillHeight: NSLayoutConstraint?
    var brightnessHUDFillHeight: NSLayoutConstraint?
    var volumeHUD: VerticalHUD!
    var brightnessHUD: VerticalHUD!

    // Double tap skip properties
    var doubleTapLeftGesture: UITapGestureRecognizer!
    var doubleTapRightGesture: UITapGestureRecognizer!
    var twoFingerTapGesture: UITapGestureRecognizer!
    lazy var leftSkipFeedbackView = createSkipFeedbackView(direction: .backward)
    lazy var rightSkipFeedbackView = createSkipFeedbackView(direction: .forward)

    // SkipIntroButton duration
    var skipIntroButtonDuration: Int = {
        let saved = UserDefaults.standard.integer(forKey: "Player.skipIntroButtonDuration")
        return saved == 0 ? 85 : saved
    }() {
        didSet {
            UserDefaults.standard.set(skipIntroButtonDuration, forKey: "Player.skipIntroButtonDuration")
            skipIntroButton.setTitle("\(skipIntroButtonDuration)s", for: .normal)
        }
    }

    var doubleTapSkipDuration: Double {
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
    lazy var subtitleButton = createSystemButton(symbol: "captions.bubble.fill", action: #selector(subtitleTapped))
    lazy var subtitleBackgroundView = createControlBackground(cornerRadius: 22)

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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopPlayer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        overrideUserInterfaceStyle = .dark
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
        setupGestures()
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                view.transform = CGAffineTransform(translationX: 0, y: translation.y)
            }
        case .ended:
            if translation.y > 100 || velocity.y > 500 {
                onDismiss?()
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseOut) {
                    self.view.transform = .identity
                }
            }
        case .cancelled:
            UIView.animate(withDuration: 0.3) {
                self.view.transform = .identity
            }
        default: break
        }
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

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeRight
    }

    override var shouldAutorotate: Bool {
        true
    }
}
