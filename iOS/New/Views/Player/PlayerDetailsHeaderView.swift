//
//  PlayerDetailsHeaderView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import NukeUI
import UIKit
import SafariServices

struct PlayerDetailsHeaderView: View {
    let module: ScrapingModule?
    let contentUrl: String?

    let title: String
    let posterUrl: String
    let description: String?
    @Binding var episodes: [PlayerEpisode]
    @Binding var isLoadingEpisodes: Bool
    let sourceName: String?
    @Binding var descriptionExpanded: Bool
    @Binding var bookmarked: Bool
    @Binding var showingCoverView: Bool
    @Binding var episodeSortOption: EpisodeSortOption
    @Binding var episodeSortAscending: Bool
    var onTrackerButtonPressed: (() -> Void)?
    var onWatchButtonPressed: (() -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator

    @State private var watchButtonText = NSLocalizedString("LOADING_ELLIPSIS")
    @State private var watchButtonDisabled = true
    @State private var longHeldBookmark = false
    @State private var isTracking = false
    @State private var hasAvailableTrackers = false

    @ObservedObject private var libraryManager = PlayerLibraryManager.shared

    static let coverWidth: CGFloat = 114

    init(
        module: ScrapingModule?,
        contentUrl: String?,
        title: String,
        posterUrl: String,
        description: String?,
        episodes: Binding<[PlayerEpisode]>,
        isLoadingEpisodes: Binding<Bool>,
        sourceName: String?,
        descriptionExpanded: Binding<Bool>,
        bookmarked: Binding<Bool>,
        showingCoverView: Binding<Bool>,
        episodeSortOption: Binding<EpisodeSortOption>,
        episodeSortAscending: Binding<Bool>,
        onTrackerButtonPressed: (() -> Void)? = nil,
        onWatchButtonPressed: (() -> Void)? = nil
    ) {
        self.module = module
        self.contentUrl = contentUrl
        self.title = title
        self.posterUrl = posterUrl
        self.description = description
        self._episodes = episodes
        self._isLoadingEpisodes = isLoadingEpisodes
        self.sourceName = sourceName
        self._descriptionExpanded = descriptionExpanded
        self._bookmarked = bookmarked
        self._showingCoverView = showingCoverView
        self._episodeSortOption = episodeSortOption
        self._episodeSortAscending = episodeSortAscending
        self.onTrackerButtonPressed = onTrackerButtonPressed
        self.onWatchButtonPressed = onWatchButtonPressed
        self._isTracking = State(initialValue: TrackerManager.shared.isTracking(
            sourceId: module?.id.uuidString ?? "",
            mangaId: contentUrl ?? ""
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                        Button {
                            showingCoverView = true
                        } label: {
                        // 2:3 aspect ratio
                        PlayerCoverView(
                            posterUrl: posterUrl,
                            width: Self.coverWidth,
                            height: Self.coverWidth * 3/2
                        )
                        .id(posterUrl)
                        }
                    .buttonStyle(DarkOverlayButtonStyle())
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    Text(title)
                        .lineLimit(4)
                        .font(.system(.title2).weight(.semibold))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.75)
                        .contentTransitionDisabledPlease()
                        .padding(.bottom, 4)

                    if let sourceName {
                        HStack(spacing: 6) {
                            LabelView(
                                text: sourceName,
                                background: Color(red: 0.25, green: 0.55, blue: 1).opacity(0.3)
                            )
                        }
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }

                    buttonsView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 174)
            .padding(.bottom, 14)
            .padding(.horizontal, 20)

            if let description = description, !description.isEmpty {
                ExpandableTextView(text: description, expanded: $descriptionExpanded)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 20)
                    .foregroundStyle(.secondary)
            }

            tagsView

            Button {
                onWatchButtonPressed?()
            } label: {
                Text(watchButtonText)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(11)
            .foregroundStyle(.white)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
            .allowsHitTesting(!watchButtonDisabled)

            // Episodes list header (match ChapterListHeaderView layout)
            if !episodes.isEmpty || isLoadingEpisodes {
                episodesHeaderView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            // separator
            if !episodes.isEmpty {
                ListDivider()
            }
        }
        .animation(.default, value: descriptionExpanded)
        .animation(.default, value: bookmarked)
        .animation(nil, value: episodes.count)
        .animation(nil, value: isLoadingEpisodes)
        .foregroundStyle(.primary)
        .textCase(.none)
        .padding(.top, 10)
        .onAppear {
            updateWatchButton()
        }
        .onChange(of: episodes.count) { _ in
            updateWatchButton()
        }
        .onChange(of: isLoadingEpisodes) { _ in
            updateWatchButton()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateTrackers)) { _ in
            isTracking = TrackerManager.shared.isTracking(
                sourceId: module?.id.uuidString ?? "",
                mangaId: contentUrl ?? ""
            )
        }
        .task {
            updateWatchButton()
            if let module = module, let contentUrl = contentUrl {
                hasAvailableTrackers = await TrackerManager.shared.hasAvailableTrackers(sourceKey: module.id.uuidString, mangaKey: contentUrl)
            }
        }
    }

    var buttonsView: some View {
        HStack(spacing: 8) {
            Button {
                if longHeldBookmark {
                    longHeldBookmark = false
                    return
                }
                Task {
                    await toggleBookmarked()
                }
            } label: {
                Image(systemName: "bookmark.fill")
            }
            .buttonStyle(PlayerActionButtonStyle(selected: bookmarked))
            .simultaneousGesture(
                LongPressGesture()
                    .onEnded { _ in
                        longHeldBookmark = true
                    }
            )

            if hasAvailableTrackers {
                Button {
                    onTrackerButtonPressed?()
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                }
                .buttonStyle(PlayerActionButtonStyle(selected: isTracking))
            }

            Button {
                openWebView()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(PlayerActionButtonStyle(selected: false))
            .disabled(contentUrl == nil)
        }
    }

    private func openWebView() {
        guard let rawUrlString = contentUrl else { return }
        let normalized = rawUrlString.normalizedModuleHref()
        let finalUrlString: String
        if normalized.starts(with: "http") {
            finalUrlString = normalized
        } else if let baseUrl = module?.metadata.baseUrl {
            // hinaime is a special case bcs the baseurl is different from the contenturl
            // will prolly only do this for hianime bcs i use this module a lot
            if baseUrl.contains("megacloud.blog") {
                finalUrlString = "https://hianime.to" + normalized
            } else {
                finalUrlString = normalized.absoluteUrl(withBaseUrl: baseUrl)
            }
        } else {
            return
        }

        guard let url = URL(string: finalUrlString),
              url.scheme == "http" || url.scheme == "https" else { return }

        let safariViewController = SFSafariViewController(url: url)
        safariViewController.modalPresentationStyle = .pageSheet
        path.present(safariViewController, animated: true)
    }

    var tagsView: some View {
        EmptyView()
    }

    var episodesHeaderView: some View {
        HStack {
            let text = if isLoadingEpisodes {
                NSLocalizedString("LOADING_ELLIPSIS")
            } else if episodes.isEmpty {
                NSLocalizedString("NO_EPISODES")
            } else if episodes.count == 1 {
                "1 episode".lowercased()
            } else {
                "\(episodes.count) episodes".lowercased()
            }

            Text(text)
                .font(.headline)
                .transition(.scale) // match ChapterListHeaderView behavior
                .id("episodes")

            Spacer()

            if !episodes.isEmpty {
                Menu {
                    Section(NSLocalizedString("SORT_BY")) {
                        ForEach(EpisodeSortOption.allCases, id: \.self) { option in
                            Button {
                                if episodeSortOption == option {
                                    episodeSortAscending.toggle()
                                } else {
                                    episodeSortOption = option
                                    episodeSortAscending = false
                                }
                            } label: {
                                Label {
                                    Text(option.title)
                                } icon: {
                                    if episodeSortOption == option {
                                        Image(systemName: episodeSortAscending ? "chevron.up" : "chevron.down")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 21, weight: .regular))
                }
                .foregroundStyle(.tint)
            }
        }
    }

    private func updateWatchButton() {
        if isLoadingEpisodes {
            watchButtonText = NSLocalizedString("LOADING_ELLIPSIS")
            watchButtonDisabled = true
            return
        }

        if episodes.isEmpty {
            watchButtonText = NSLocalizedString("NO_EPISODES")
            watchButtonDisabled = true
            return
        }

        // Find minimum episode number without sorting (O(n) instead of O(n log n))
        let firstEpisode = episodes.min(by: { $0.number < $1.number })
        if let firstEpisode {
            watchButtonText = "Play Episode \(firstEpisode.number)"
            watchButtonDisabled = false
        } else {
            watchButtonText = NSLocalizedString("NO_EPISODES")
            watchButtonDisabled = true
        }
    }

    private func getBookmarkId() -> UUID? {
        libraryManager.items.first { $0.title == title }?.id
    }

    func toggleBookmarked() async {
        if let module = module {
            let existingItem = libraryManager.items.first { $0.title == title && $0.moduleId == module.id }

            if let item = existingItem {
                // Remove from bookmarks
                libraryManager.removeFromLibrary(item)
                bookmarked = false
            } else {
                // Add to bookmarks
                let item = PlayerLibraryItem(
                    title: title,
                    imageUrl: posterUrl,
                    sourceUrl: contentUrl ?? "",
                    moduleId: module.id,
                    moduleName: module.metadata.sourceName
                )
                libraryManager.addToLibrary(item)
                bookmarked = true
            }
        }
    }
}

struct PlayerCoverView: View {
    let posterUrl: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        LazyImage(url: URL(string: posterUrl)) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct PlayerActionButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .opacity(configuration.isPressed ? 0.4 : 1)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 40, height: 32)
            .background(selected ? Color.accentColor : Color(UIColor.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
