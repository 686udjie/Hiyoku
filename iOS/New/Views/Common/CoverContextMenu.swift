//
//  CoverContextMenu.swift
//  Hiyoku
//
//  Created by Codex on 03/15/26.
//

import SwiftUI
import Nuke

struct CoverContextMenu<AdditionalItems: View>: ViewModifier {
    let imageUrl: String
    let cornerRadius: CGFloat
    @ViewBuilder let additionalItems: () -> AdditionalItems

    func body(content: Content) -> some View {
        content
            .contentShape(
                .contextMenuPreview,
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .contextMenu {
                if let url = URL(string: imageUrl) {
                    Button {
                        if let viewController = UIApplication.shared.firstKeyWindow?.rootViewController {
                            Task {
                                let image = try await loadImage(url: url)
                                image.saveToAlbum(viewController: viewController)
                            }
                        }
                    } label: {
                        Label(NSLocalizedString("SAVE_TO_PHOTOS"), systemImage: "photo")
                    }
                }
                additionalItems()
            }
    }

    private func loadImage(url: URL) async throws -> UIImage {
        try await ImagePipeline.shared.image(for: url)
    }
}

extension View {
    func coverContextMenu(
        imageUrl: String,
        cornerRadius: CGFloat = 5
    ) -> some View {
        modifier(
            CoverContextMenu(
                imageUrl: imageUrl,
                cornerRadius: cornerRadius,
                additionalItems: { EmptyView() }
            )
        )
    }

    func coverContextMenu<AdditionalItems: View>(
        imageUrl: String,
        cornerRadius: CGFloat = 5,
        @ViewBuilder additionalItems: @escaping () -> AdditionalItems
    ) -> some View {
        modifier(
            CoverContextMenu(
                imageUrl: imageUrl,
                cornerRadius: cornerRadius,
                additionalItems: additionalItems
            )
        )
    }
}
