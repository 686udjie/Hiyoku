//
//  PlayerInfoView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import NukeUI

struct PlayerInfoView: View {
    @StateObject private var viewModel: ViewModel

    @State private var showingCoverView = false
    @State private var descriptionExpanded = false
    @State private var openEpisode: PlayerEpisode?
    @State private var errorMessage: String?

    @State private var episodesLoaded = false

    private var path: NavigationCoordinator

    @Namespace private var transitionNamespace

    init(
        bookmark: PlayerLibraryItem? = nil,
        searchItem: SearchItem? = nil,
        module: ScrapingModule? = nil,
        path: NavigationCoordinator
    ) {
        self.path = path
        if let bookmark = bookmark {
            self._viewModel = StateObject(wrappedValue: ViewModel(bookmark: bookmark))
        } else if let searchItem = searchItem, let module = module {
            self._viewModel = StateObject(wrappedValue: ViewModel(searchItem: searchItem, module: module))
        } else {
            fatalError("PlayerInfoView requires either bookmark or searchItem+module")
        }
    }

    var body: some View {
        let list = List {
            headerView

            if viewModel.isLoadingEpisodes {
                loadingEpisodesView
            } else if viewModel.episodes.isEmpty {
                emptyStateView
            } else {
                ForEach(viewModel.sortedEpisodes.indices, id: \.self) { index in
                    let episode = viewModel.sortedEpisodes[index]
                    viewForEpisode(episode, index: index)
                }

                bottomSeparator
            }
        }
        .environment(\.defaultMinListRowHeight, 10)
        .transition(.opacity)
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationBarTitleDisplayMode(.inline)
        .scrollBackgroundHiddenPlease()

        list
            .fullScreenCover(isPresented: $showingCoverView) {
                PlayerCoverPageView(posterUrl: viewModel.posterUrl, title: viewModel.title)
            }
            .fullScreenCover(item: $openEpisode, content: { episode in
                if let module = viewModel.module {
                    Player(
                        module: module,
                        episode: episode
                    )
                    .ignoresSafeArea()
                    .navigationTransitionZoom(sourceID: episode, in: transitionNamespace)
                    .preferredColorScheme(.dark)
                }
            })
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    bookmarkButton
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .task {
                guard !episodesLoaded else { return }
                await viewModel.loadEpisodes()
                episodesLoaded = true
            }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("No episodes available")
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var loadingEpisodesView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading episodes...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var headerView: some View {
        ZStack {
            PlayerDetailsHeaderView(
                module: viewModel.module,
                contentUrl: viewModel.contentUrl,
                title: viewModel.title,
                posterUrl: viewModel.posterUrl,
                description: viewModel.description,
                episodes: $viewModel.episodes,
                isLoadingEpisodes: $viewModel.isLoadingEpisodes,
                sourceName: viewModel.sourceName,
                descriptionExpanded: $descriptionExpanded,
                bookmarked: $viewModel.isBookmarked,
                showingCoverView: $showingCoverView,
                episodeSortOption: $viewModel.episodeSortOption,
                episodeSortAscending: $viewModel.episodeSortAscending,
                onWatchButtonPressed: {
                    if let firstEpisode = viewModel.sortedEpisodes.first {
                        Task {
                            await playEpisode(firstEpisode)
                        }
                    }
                }
            )
            .environmentObject(path)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .listRowInsets(.zero)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var bottomSeparator: some View {
        VStack {
            ListDivider() // final, full width separator
            Color.clear.frame(height: 28) // padding for bottom of list
        }
        .padding(.top, {
            if #available(iOS 16.0, *) { 0 } else { 0.5 }
        }())
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
    }

    private var bookmarkButton: some View {
        Button {
            viewModel.toggleBookmark()
        } label: {
            Image(systemName: viewModel.isBookmarked ? "bookmark.fill" : "bookmark")
                .foregroundColor(viewModel.isBookmarked ? .yellow : .primary)
        }
    }

    @ViewBuilder
    private func viewForEpisode(_ episode: PlayerEpisode, index: Int) -> some View {
        EpisodeCellView(episode: episode) {
            Task {
                await playEpisode(episode)
            }
        }
        .equatable()
        .listRowInsets(.zero)
        .listRowBackground(Color.clear)
        .matchedTransitionSourcePlease(id: episode, in: transitionNamespace)
    }
    @MainActor
    private func playEpisode(_ episode: PlayerEpisode) async {
        guard let module = viewModel.module, !episode.url.isEmpty else {
            errorMessage = "Episode ID is not available"
            return
        }

        let streamInfos = await JSController.shared.fetchPlayerStreams(episodeId: episode.url, module: module)

        if let streamInfo = streamInfos.first, !streamInfo.url.isEmpty {
            openEpisode = episode
        } else {
            errorMessage = "Unable to find video stream for this episode"
        }
    }
}

private struct EpisodeCellView: View, Equatable {
    let episode: PlayerEpisode
    var onPressed: (() -> Void)?

    var body: some View {
        Button {
            onPressed?()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Episode \(episode.number)")
                        .font(.system(.callout).weight(.semibold))
                        .foregroundStyle(.primary)

                    if !episode.title.isEmpty {
                        Text(episode.title)
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if let scanlator = episode.scanlator {
                    Text(scanlator)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }

    static nonisolated func == (lhs: EpisodeCellView, rhs: EpisodeCellView) -> Bool {
        lhs.episode == rhs.episode
    }
}
