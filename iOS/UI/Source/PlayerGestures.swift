//
//  PlayerGestures.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

// MARK: - Player Gestures Extension
extension PlayerViewController {
    @objc internal func handleVerticalPan(_ gesture: UIPanGestureRecognizer) {
        guard !isLocked else { return }
        let point = gesture.location(in: videoContainer)
        let width = max(1, videoContainer.bounds.width)
        let height = max(1, videoContainer.bounds.height)

        switch gesture.state {
        case .began:
            verticalAdjustStartPoint = point
            if point.x < width / 2 {
                verticalAdjustMode = .brightness
                verticalAdjustStartBrightness = UIScreen.main.brightness
                showVerticalAdjustHUD(mode: .brightness)
                setVerticalAdjustHUDValue(verticalAdjustStartBrightness, mode: .brightness)
            } else {
                verticalAdjustMode = .volume
                verticalAdjustStartVolume = getMPVDoubleProperty("volume") ?? 100
                showVerticalAdjustHUD(mode: .volume)
                setVerticalAdjustHUDValue(CGFloat(verticalAdjustStartVolume / 100), mode: .volume)
            }

        case .changed:
            guard let mode = verticalAdjustMode else { return }
            let translation = gesture.translation(in: videoContainer)
            let delta = (-translation.y / height) * 1.2

            switch mode {
            case .brightness:
                let newBrightness = max(0, min(1, verticalAdjustStartBrightness + delta))
                UIScreen.main.brightness = newBrightness
                setVerticalAdjustHUDValue(newBrightness, mode: .brightness)
            case .volume:
                let newVolume = max(0, min(100, verticalAdjustStartVolume + (delta * 100)))
                setProperty("volume", String(format: "%.0f", newVolume))
                setVerticalAdjustHUDValue(CGFloat(newVolume / 100), mode: .volume)
            }

        case .ended, .cancelled, .failed:
            if let mode = verticalAdjustMode {
                hideVerticalAdjustHUD(mode: mode, delay: 1)
            }
            verticalAdjustMode = nil

        default:
            break
        }
    }

    @objc func handleTap() {
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

    @objc func handleDoubleTapLeft() {
        skipBackward()
    }

    @objc func handleDoubleTapRight() {
        skipForward()
    }

    @objc func handleTwoFingerTap() {
        guard UserDefaults.standard.bool(forKey: "Player.twoFingerTapToPause") else { return }
        playPauseTapped()
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
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

        if gestureRecognizer === verticalPanGesture {
            if isLocked { return false }
            if isUIVisible {
                for v in interactionEnabledViews {
                    let frame = v.convert(v.bounds, to: videoContainer)
                    if frame.contains(location) {
                        return false
                    }
                }
            }
        }

        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.y) > abs(velocity.x) && (abs(velocity.x) < 40 || abs(velocity.y) > abs(velocity.x) * 3)
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
        let newPos = max(Double.zero, currentPos - doubleTapSkipDuration)
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
}
