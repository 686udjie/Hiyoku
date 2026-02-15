//
//  PlayerSettingsView.swift
//  Hiyoku
//
//  Created by 686udjie on 02/15/26.
//

import SwiftUI

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
