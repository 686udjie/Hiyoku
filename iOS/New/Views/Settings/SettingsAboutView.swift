//
//  SettingsAboutView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text(NSLocalizedString("VERSION"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? NSLocalizedString("UNKNOWN")
                    Text(version)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SettingView(setting: .init(
                    title: NSLocalizedString("GITHUB_REPO"),
                    value: .link(.init(url: "https://github.com/686udjie/Hiyoku"))
                ))
                SettingView(setting: .init(
                    title: NSLocalizedString("DISCORD_SERVER"),
                    value: .link(.init(url: "https://discord.gg/mY5CJfTnun", external: true))
                ))
                SettingView(setting: .init(
                    title: NSLocalizedString("SKITTY_KOFI"),
                    value: .link(.init(url: "https://ko-fi.com/skittyblock", external: true))
                ))
                HStack {
                    Text(NSLocalizedString("CRANCI_LTC"))
                    Spacer()
                    Text("LS6K2JbPHuB1SnWsm3tqYyK1CovmNcjqoi")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(NSLocalizedString("ABOUT"))
    }
}
