//
//  PlayerViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import UIKit
import AVFoundation
import Libmpv

class PlayerViewController: UIViewController, UIGestureRecognizerDelegate {

    let module: ScrapingModule
    var videoUrl: String
    var videoTitle: String
    var headers: [String: String]
    private var resolvedUrl: String?

    // Navigation Callbacks
    var onNextEpisode: (() -> Void)?
    var onPreviousEpisode: (() -> Void)?

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

    private lazy var playPauseBackgroundView = createBlurBackground(cornerRadius: 30)
    private lazy var previousBackgroundView = createBlurBackground(cornerRadius: 25)
    private lazy var nextBackgroundView = createBlurBackground(cornerRadius: 25)
    private lazy var closeBackgroundView = createBlurBackground(cornerRadius: 22)
    private lazy var sliderBackgroundView = createBlurBackground(cornerRadius: 20)
    private lazy var speedBackgroundView = createBlurBackground(cornerRadius: 14)
    private lazy var lockBackgroundView = createBlurBackground(cornerRadius: 14)
    private lazy var skipBackgroundView = createBlurBackground(
        cornerRadius: 14,
        color: .systemBlue.withAlphaComponent(0.8),
        borderColor: .systemBlue.withAlphaComponent(0.3)
    )

    private lazy var previousButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        b.setImage(UIImage(systemName: "backward.end.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        b.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        return b
    }()

    private lazy var nextButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        b.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        b.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        return b
    }()

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

    private lazy var lockButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        b.setImage(UIImage(systemName: "lock.open.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        b.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        return b
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

    private lazy var skipButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("\(Int(skipDuration))s", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.tintColor = .white
        b.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(skipLongPressed(_:)))
        b.addGestureRecognizer(longPress)
        return b
    }()

    private var isLocked = false
    private var isSeeking = false
    private var isUIVisible = true
    private var autoHideTimer: Timer?

    private var skipDuration: Double {
        get { UserDefaults.standard.double(forKey: "player_skip_duration") == 0 ? 85 : UserDefaults.standard.double(forKey: "player_skip_duration") }
        set { UserDefaults.standard.set(newValue, forKey: "player_skip_duration") }
    }

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

    deinit {
        stopPlayer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableSwipeGestures()
        resetAutoHideTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pause()
        autoHideTimer?.invalidate()
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

        if !videoUrl.isEmpty {
            prepareAndPlay()
        }
    }
    // Player always appears in dark mode
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        overrideUserInterfaceStyle = .dark
        setNeedsStatusBarAppearanceUpdate()
    }
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
}

// MARK: - UI Setup
extension PlayerViewController {
    private func setupUI() {
        view.backgroundColor = .black
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoContainer)

        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        displayLayer.videoGravity = .resizeAspect
        videoContainer.layer.addSublayer(displayLayer)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        videoContainer.addGestureRecognizer(tapGesture)

        // Add all backgrounds and stand-alone views to videoContainer
        [playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
         closeBackgroundView, sliderBackgroundView, speedBackgroundView,
         lockBackgroundView, skipBackgroundView, gutterUnlockButton,
         watchedTimeLabel, totalTimeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            videoContainer.addSubview($0)
        }

        // Setup control islands
        centerInParent(playPauseButton, parent: playPauseBackgroundView, size: CGSize(width: 44, height: 44))
        centerInParent(previousButton, parent: previousBackgroundView, size: CGSize(width: 44, height: 44))
        centerInParent(nextButton, parent: nextBackgroundView, size: CGSize(width: 44, height: 44))
        centerInParent(closeButton, parent: closeBackgroundView, size: CGSize(width: 30, height: 30))
        centerInParent(speedButton, parent: speedBackgroundView, size: CGSize(width: 44, height: 28))
        centerInParent(lockButton, parent: lockBackgroundView, size: CGSize(width: 36, height: 28))
        centerInParent(skipButton, parent: skipBackgroundView, size: CGSize(width: 44, height: 28))

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

            gutterUnlockButton.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -16),
            gutterUnlockButton.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            gutterUnlockButton.widthAnchor.constraint(equalToConstant: 50),
            gutterUnlockButton.heightAnchor.constraint(equalToConstant: 50),

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
            skipBackgroundView.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
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

    private func createBlurBackground(cornerRadius: CGFloat, color: UIColor = .tertiarySystemFill,
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

    private func setSpeed(_ speed: Double) {
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
        }

        interactionEnabledViews.forEach { $0.isUserInteractionEnabled = isUIVisible }

        if isUIVisible {
            resetAutoHideTimer()
        } else {
            autoHideTimer?.invalidate()
        }
    }

    private var controlViews: [UIView] {
        [
            playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
            closeBackgroundView, sliderBackgroundView, watchedTimeLabel,
            totalTimeLabel, speedBackgroundView, lockBackgroundView, skipBackgroundView
        ]
    }

    private var interactionEnabledViews: [UIView] {
        [
            playPauseBackgroundView, previousBackgroundView, nextBackgroundView,
            closeBackgroundView, sliderBackgroundView, speedBackgroundView,
            lockBackgroundView, skipBackgroundView
        ]
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
        let newPos = currentPos + skipDuration
        setProperty("time-pos", "\(newPos)")
        resetAutoHideTimer()
    }

    @objc private func skipLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let configVC = SkipConfigViewController()
            configVC.currentValue = Int(skipDuration)
            configVC.onSave = { [weak self] newValue in
                guard let self = self else { return }
                self.skipDuration = Double(newValue)
                self.skipButton.setTitle("\(newValue)s", for: .normal)
            }

            let alert = UIAlertController(title: "Change intro length", message: nil, preferredStyle: .alert)
            alert.setValue(configVC, forKey: "contentViewController")
            alert.addAction(UIAlertAction(title: "Done", style: .default, handler: nil))

            present(alert, animated: true, completion: nil)
        }
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

    func loadVideo(url: String, headers: [String: String] = [:]) {
        self.videoUrl = url
        self.headers = headers
        self.resolvedUrl = nil
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
                guard self.videoUrl == urlToResolve else { return }
                self.resolvedUrl = resolved
                self.startMpvPlayback()
            }
        }
    }

    func updateTitle(_ title: String) {
        self.videoTitle = title
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

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            throw NSError(domain: "MPV", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to initialize mpv"])
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
        let cmd = ["loadfile", urlToPlay, "replace"]
        withCStringArray(cmd) { ptr in
            mpv_command(handle, ptr)
        }
        isRunning = true
        isPaused = false
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
        if name == "time-pos" { position = value } else if name == "duration" { duration = value }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateTimeLabels()
            if name == "time-pos" && self.duration > 0 && !self.isSeeking {
                self.sliderView.currentValue = CGFloat(value / self.duration)
            } else if name == "speed" {
                self.speedButton.setTitle(self.formatSpeed(value), for: .normal)
            }
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
