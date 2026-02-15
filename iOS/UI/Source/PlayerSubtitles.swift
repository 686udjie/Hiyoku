//
//  PlayerSubtitles.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

// MARK: - Player Subtitles Extension
extension PlayerViewController {
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

    internal func updateSubtitlePosition() {
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

    func updateSubtitles(for time: Double) {
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
}
