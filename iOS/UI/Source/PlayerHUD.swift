//
//  PlayerHUD.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import UIKit

// MARK: - Player HUD Extension
extension PlayerViewController {
    // MARK: - Player gestures UI
    func setupVerticalAdjustHUDs() {
        // Initialize HUD structures
        volumeHUD = VerticalHUD(
            container: volumeHUDContainer,
            percentLabel: volumeHUDPercentLabel,
            fillView: volumeHUDFill,
            borderView: volumeHUDBorder,
            iconView: volumeHUDIconView,
            fillAreaGuide: volumeHUDFillAreaGuide,
            defaultIcon: "speaker.wave.2.fill",
            zeroIcon: "speaker.slash.fill"
        )
        brightnessHUD = VerticalHUD(
            container: brightnessHUDContainer,
            percentLabel: brightnessHUDPercentLabel,
            fillView: brightnessHUDFill,
            borderView: brightnessHUDBorder,
            iconView: brightnessHUDIconView,
            fillAreaGuide: brightnessHUDFillAreaGuide,
            defaultIcon: "sun.max.fill",
            slashView: brightnessHUDSlashView
        )
        let hudContainers: [UIView] = [volumeHUD.container, brightnessHUD.container]
        hudContainers.forEach {
            $0.backgroundColor = .clear
            $0.alpha = 0
        }
        NSLayoutConstraint.activate([
            volumeHUD.container.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor, constant: 30),
            volumeHUD.container.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            volumeHUD.container.widthAnchor.constraint(equalToConstant: 86),
            volumeHUD.container.heightAnchor.constraint(equalToConstant: 240),
            brightnessHUD.container.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor, constant: -30),
            brightnessHUD.container.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            brightnessHUD.container.widthAnchor.constraint(equalToConstant: 86),
            brightnessHUD.container.heightAnchor.constraint(equalToConstant: 240)
        ])
        configureVerticalAdjustHUD(volumeHUD)
        configureVerticalAdjustHUD(brightnessHUD)
    }

    func configureVerticalAdjustHUD(_ hud: VerticalHUD) {
        hud.percentLabel.translatesAutoresizingMaskIntoConstraints = false
        hud.percentLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        hud.percentLabel.textColor = .white
        hud.percentLabel.textAlignment = .center

        hud.fillView.translatesAutoresizingMaskIntoConstraints = false
        hud.fillView.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        hud.fillView.layer.cornerRadius = 18
        hud.fillView.layer.masksToBounds = true

        hud.borderView.translatesAutoresizingMaskIntoConstraints = false
        hud.borderView.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        hud.borderView.layer.cornerRadius = 18
        hud.borderView.layer.masksToBounds = true
        hud.borderView.layer.borderWidth = 1.5
        hud.borderView.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor

        hud.iconView.image = UIImage(systemName: hud.defaultIcon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        hud.iconView.translatesAutoresizingMaskIntoConstraints = false
        hud.iconView.tintColor = .white
        hud.iconView.contentMode = .scaleAspectFit

        hud.container.addSubview(hud.percentLabel)
        hud.container.addLayoutGuide(hud.fillAreaGuide)
        hud.container.addSubview(hud.borderView)
        hud.container.addSubview(hud.fillView)
        hud.container.addSubview(hud.iconView)
        if let slashView = hud.slashView {
            slashView.translatesAutoresizingMaskIntoConstraints = false
            slashView.backgroundColor = .white
            slashView.layer.cornerRadius = 1
            slashView.alpha = 0
            hud.container.addSubview(slashView)

            NSLayoutConstraint.activate([
                slashView.centerXAnchor.constraint(equalTo: hud.iconView.centerXAnchor),
                slashView.centerYAnchor.constraint(equalTo: hud.iconView.centerYAnchor),
                slashView.widthAnchor.constraint(equalToConstant: 20),
                slashView.heightAnchor.constraint(equalToConstant: 2)
            ])
            slashView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        }

        let fillHeight = hud.fillView.heightAnchor.constraint(equalToConstant: 0)
        switch hud.container {
        case volumeHUDContainer:
            volumeHUDFillHeight = fillHeight
        case brightnessHUDContainer:
            brightnessHUDFillHeight = fillHeight
        default:
            break
        }

        NSLayoutConstraint.activate([
            hud.percentLabel.topAnchor.constraint(equalTo: hud.container.topAnchor, constant: 18),
            hud.percentLabel.leadingAnchor.constraint(equalTo: hud.container.leadingAnchor, constant: 8),
            hud.percentLabel.trailingAnchor.constraint(equalTo: hud.container.trailingAnchor, constant: -8),

            hud.fillAreaGuide.topAnchor.constraint(equalTo: hud.percentLabel.bottomAnchor, constant: 14),
            hud.fillAreaGuide.centerXAnchor.constraint(equalTo: hud.container.centerXAnchor),
            hud.fillAreaGuide.widthAnchor.constraint(equalToConstant: 36),
            hud.fillAreaGuide.bottomAnchor.constraint(equalTo: hud.iconView.topAnchor, constant: -16),

            hud.borderView.topAnchor.constraint(equalTo: hud.fillAreaGuide.topAnchor),
            hud.borderView.leadingAnchor.constraint(equalTo: hud.fillAreaGuide.leadingAnchor),
            hud.borderView.trailingAnchor.constraint(equalTo: hud.fillAreaGuide.trailingAnchor),
            hud.borderView.bottomAnchor.constraint(equalTo: hud.fillAreaGuide.bottomAnchor),

            hud.fillView.centerXAnchor.constraint(equalTo: hud.fillAreaGuide.centerXAnchor),
            hud.fillView.widthAnchor.constraint(equalTo: hud.fillAreaGuide.widthAnchor),
            hud.fillView.bottomAnchor.constraint(equalTo: hud.fillAreaGuide.bottomAnchor),
            fillHeight,

            hud.iconView.bottomAnchor.constraint(equalTo: hud.container.bottomAnchor, constant: -18),
            hud.iconView.centerXAnchor.constraint(equalTo: hud.container.centerXAnchor),
            hud.iconView.widthAnchor.constraint(equalToConstant: 26),
            hud.iconView.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    func setVerticalAdjustHUDValue(_ normalizedValue: CGFloat, mode: VerticalAdjustMode) {
        let clamped = max(0, min(1, normalizedValue))
        let percent = Int(round(clamped * 100))

        let huds: [VerticalAdjustMode: VerticalHUD] = [
            .volume: volumeHUD,
            .brightness: brightnessHUD
        ]
        guard let hud = huds[mode] else { return }

        hud.percentLabel.text = "\(percent)%"
        hud.container.layoutIfNeeded()
        let maxHeight = hud.fillAreaGuide.layoutFrame.height

        // Update the actual constraint
        switch mode {
        case .volume:
            volumeHUDFillHeight?.constant = maxHeight * clamped
        case .brightness:
            brightnessHUDFillHeight?.constant = maxHeight * clamped
        }

        hud.container.layoutIfNeeded()

        let iconName = (clamped == 0 && hud.zeroIcon != nil) ? hud.zeroIcon! : hud.defaultIcon
        hud.iconView.image = UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))

        if let slashView = hud.slashView {
            UIView.animate(withDuration: 0.15) {
                slashView.alpha = clamped == 0 ? 1 : 0
            }
        }
    }

    func showVerticalAdjustHUD(mode: VerticalAdjustMode) {
        let huds: [VerticalAdjustMode: VerticalHUD] = [
            .volume: volumeHUD,
            .brightness: brightnessHUD
        ]
        let hideWorkItems: [VerticalAdjustMode: DispatchWorkItem?] = [
            .volume: volumeHUDHideWorkItem,
            .brightness: brightnessHUDHideWorkItem
        ]

        guard let hud = huds[mode],
              let workItem = hideWorkItems[mode] else { return }

        workItem?.cancel()
        UIView.animate(withDuration: 0.15) { hud.container.alpha = 1 }
    }

    func hideVerticalAdjustHUD(mode: VerticalAdjustMode, delay: TimeInterval = 0.4) {
        let huds: [VerticalAdjustMode: VerticalHUD] = [
            .volume: volumeHUD,
            .brightness: brightnessHUD
        ]
        let hideWorkItems: [VerticalAdjustMode: (DispatchWorkItem?) -> Void] = [
            .volume: { self.volumeHUDHideWorkItem = $0 },
            .brightness: { self.brightnessHUDHideWorkItem = $0 }
        ]

        guard let hud = huds[mode],
              let setWorkItem = hideWorkItems[mode] else { return }

        let work = DispatchWorkItem {
            UIView.animate(withDuration: 0.25) {
                hud.container.alpha = 0
            }
        }

        setWorkItem(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
