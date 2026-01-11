//
//  PlayerCoverPageView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import NukeUI

struct PlayerCoverPageView: View {
    let posterUrl: String
    let title: String

    @Environment(\.dismiss) private var dismiss

    init(posterUrl: String, title: String) {
        self.posterUrl = posterUrl
        self.title = title
    }

    var body: some View {
        NavigationView {
            VStack {
                view(coverImage: posterUrl)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(NSLocalizedString("COVER"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func view(coverImage: String) -> some View {
        VStack(alignment: .center) {
            Spacer()
            LazyImage(url: URL(string: coverImage)) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if state.error != nil {
                    Color.gray.opacity(0.3)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                } else {
                    Color.gray.opacity(0.3)
                        .overlay(
                            ProgressView()
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
    }
}
