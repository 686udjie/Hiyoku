//
//  PlayerCoverPageView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import NukeUI

struct PlayerCoverPageView: View {
    @Binding var posterUrl: String
    let title: String
    let isInLibrary: Bool
    let libraryItemId: UUID?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var libraryManager = PlayerLibraryManager.shared

    @State private var showImagePicker = false
    @State private var uploadedCover: UIImage?
    @State private var hasEditedCover = false

    init(posterUrl: Binding<String>, title: String, isInLibrary: Bool, libraryItemId: UUID?) {
        self._posterUrl = posterUrl
        self.title = title
        self.isInLibrary = isInLibrary
        self.libraryItemId = libraryItemId
    }

    var body: some View {
        NavigationView {
            VStack {
                view(coverImage: posterUrl)

                if isInLibrary, currentItem != nil {
                    HStack {
                        Button {
                            showImagePicker = true
                        } label: {
                            Text(NSLocalizedString("UPLOAD_CUSTOM_COVER"))
                        }
                        .buttonStyle(.bordered)

                        if hasEditedCover {
                            Button {
                                Task {
                                    await resetCover()
                                }
                            } label: {
                                Text(NSLocalizedString("RESET_COVER"))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(NSLocalizedString("COVER"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $uploadedCover)
                .ignoresSafeArea()
        }
        .onChange(of: uploadedCover) { newImage in
            guard let newImage else { return }
            Task {
                await uploadCover(newImage)
            }
        }
        .onAppear {
            hasEditedCover = currentItem?.hasCustomCover ?? false
        }
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
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .coverContextMenu(imageUrl: coverImage, cornerRadius: 8)
            .padding(16)
            Spacer()
        }
    }

    private var currentItem: PlayerLibraryItem? {
        guard let libraryItemId else { return nil }
        return libraryManager.items.first(where: { $0.id == libraryItemId })
    }

    private func uploadCover(_ image: UIImage) async {
        guard let item = currentItem else { return }
        if let newUrl = await libraryManager.setCover(item: item, cover: image) {
            await MainActor.run {
                posterUrl = newUrl
                hasEditedCover = true
            }
        }
    }

    private func resetCover() async {
        guard let item = currentItem else { return }
        if let newUrl = await libraryManager.resetCover(item: item) {
            await MainActor.run {
                posterUrl = newUrl
                hasEditedCover = false
            }
        }
    }

}
