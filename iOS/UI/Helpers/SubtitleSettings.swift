//
//  SubtitleSettingsManager.swift
//  Hiyoku
//
//  Created by 686udjie on 18/01/26.
//

import UIKit

extension Notification.Name {
    static let subtitleSettingsDidChange = Notification.Name("subtitleSettingsDidChange")
}

struct SubtitleSettings {
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "SubtitleSettings.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "SubtitleSettings.enabled") }
    }
    var fontSize: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "SubtitleSettings.fontSize")
            return val == 0 ? 20 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "SubtitleSettings.fontSize") }
    }
    var shadowRadius: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "SubtitleSettings.shadowRadius")
            return val == 0 ? 1 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "SubtitleSettings.shadowRadius") }
    }
    var backgroundEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "SubtitleSettings.backgroundEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "SubtitleSettings.backgroundEnabled") }
    }
    var bottomPadding: CGFloat {
        get {
            let val = UserDefaults.standard.double(forKey: "SubtitleSettings.bottomPadding")
            return val == 0 ? 20 : val
        }
        set { UserDefaults.standard.set(newValue, forKey: "SubtitleSettings.bottomPadding") }
    }
    var subtitleDelay: Double {
        get { UserDefaults.standard.double(forKey: "SubtitleSettings.subtitleDelay") }
        set { UserDefaults.standard.set(newValue, forKey: "SubtitleSettings.subtitleDelay") }
    }

}

class SubtitleSettingsManager: ObservableObject {
    static let shared = SubtitleSettingsManager()

    var settings: SubtitleSettings {
        get { SubtitleSettings() }
        set {
            update { current in
                current.enabled = newValue.enabled
                current.fontSize = newValue.fontSize
                current.shadowRadius = newValue.shadowRadius
                current.backgroundEnabled = newValue.backgroundEnabled
                current.bottomPadding = newValue.bottomPadding
                current.subtitleDelay = newValue.subtitleDelay
            }
        }
    }
    func update(_ updateBlock: (inout SubtitleSettings) -> Void) {
        var currentSettings = SubtitleSettings()
        updateBlock(&currentSettings)
        NotificationCenter.default.post(name: .subtitleSettingsDidChange, object: nil)
    }
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        // defaults
        UserDefaults.standard.register(defaults: [
             "SubtitleSettings.enabled": true,
             "SubtitleSettings.fontSize": 20,
             "SubtitleSettings.shadowRadius": 1,
             "SubtitleSettings.backgroundEnabled": true,
             "SubtitleSettings.bottomPadding": 20,
             "SubtitleSettings.subtitleDelay": 0
        ])
    }
    @objc private func defaultsChanged() {
        NotificationCenter.default.post(name: .subtitleSettingsDidChange, object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
