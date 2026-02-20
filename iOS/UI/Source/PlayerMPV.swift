//
//  PlayerMPV.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit
import CoreData
import AVFoundation
import Libmpv

// MARK: - MPV Core Extension
extension PlayerViewController {
    func setupMPV() throws {
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

    func startMpvPlayback() {
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

    func setProperty(_ name: String, _ value: String) {
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

        let handle = mpv
        let context = renderContext
        self.mpv = nil
        self.renderContext = nil

        DispatchQueue.global(qos: .userInitiated).async {
            if let context = context {
                mpv_render_context_free(context)
            }
            if let handle = handle {
                mpv_destroy(handle)
            }
        }
        pixelBufferPool = nil
    }

    func getMPVDoubleProperty(_ name: String) -> Double? {
        guard let handle = mpv else { return nil }
        var val = Double(0)
        let status = mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &val)
        guard status >= 0 else { return nil }
        return val
    }
}
