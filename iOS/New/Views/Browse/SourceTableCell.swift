//
//  SourceTableCell.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import SwiftUI
import AidokuRunner

struct SourceTableCell: View {
    let source: AidokuRunner.Source

    private var isPlayerSource: Bool {
        if let module = ModuleManager.shared.modules.first(where: { $0.id.uuidString == source.key }) {
            return module.isPlayerModule
        }
        return false
    }

    private var sourceTypeTag: String {
        isPlayerSource ? "player" : "reader"
    }

    var body: some View {
        HStack(spacing: 12) {
            SourceIconView(sourceId: source.key, imageUrl: source.imageUrl)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(source.name)
                    Text("v\(source.version)")
                        .foregroundStyle(.secondary)

                    if source.contentRating != .safe {
                        let (text, background) = if source.contentRating == .containsNsfw {
                            ("17+", Color.orange.opacity(0.3))
                        } else {
                            ("18+", Color.red.opacity(0.3))
                        }

                        Text(text)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                            .padding(.vertical, 3)
                            .padding(.horizontal, 5)
                            .background(background)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.leading, 3)
                    }
                }
                HStack(spacing: 4) {
                    Text(
                        (source.languages.count > 1 || source.languages.first == "multi")
                            ? NSLocalizedString("MULTI_LANGUAGE")
                            : Locale.current.localizedString(forIdentifier: source.languages[0]) ?? ""
                    )
                    .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(sourceTypeTag)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
