//
//  PlayerInfoView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import SwiftUI
import NukeUI

class PlayerSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var episode: PlayerEpisode
    init(episode: PlayerEpisode) { self.episode = episode }
}

struct PlayerInfoView: View {
    @StateObject private var viewModel: ViewModel

    @State private var showingCoverView = false
    @State private var descriptionExpanded = false
    @State private var playerSession: PlayerSession?
    @State private var currentStreamUrl: String?
    @State private var currentStreamHeaders: [String: String]?
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
        configuredList
            .fullScreenCover(isPresented: $showingCoverView) {
                PlayerCoverPageView(posterUrl: viewModel.posterUrl, title: viewModel.title)
            }
            .fullScreenCover(item: $playerSession) { session in
                if let module = viewModel.module {
                    PlayerSessionWrapper(
                        session: session,
                        module: module,
                        episodes: viewModel.sortedEpisodes,
                        title: viewModel.title,
                        currentStreamUrl: $currentStreamUrl,
                        currentStreamHeaders: $currentStreamHeaders,
                        namespace: transitionNamespace
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    bookmarkButton
                }
            }
            .alert("Error", isPresented: errorBinding) {
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

    private var configuredList: some View {
        List {
            headerView

            if viewModel.isLoadingEpisodes {
                loadingEpisodesView
            } else if viewModel.episodes.isEmpty {
                emptyStateView
            } else {
                ForEach(viewModel.sortedEpisodes.indices, id: \.self) { index in
                    viewForEpisode(viewModel.sortedEpisodes[index], index: index)
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
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
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
            ListDivider()
            Color.clear.frame(height: 28)
        }
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

        let (streamInfos, subtitleUrl) = await JSController.shared.fetchPlayerStreams(episodeId: episode.url, module: module)

        if let streamInfo = streamInfos.first, !streamInfo.url.isEmpty {
            currentStreamUrl = streamInfo.url
            currentStreamHeaders = streamInfo.headers
            let updatedEpisode = PlayerEpisode(
                id: episode.id,
                number: episode.number,
                title: episode.title,
                url: episode.url,
                dateUploaded: episode.dateUploaded,
                scanlator: episode.scanlator,
                language: episode.language,
                subtitleUrl: subtitleUrl ?? episode.subtitleUrl
            )

            if let session = playerSession {
                session.episode = updatedEpisode
            } else {
                playerSession = PlayerSession(episode: updatedEpisode)
            }
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

struct PlayerSessionWrapper: View {
    @ObservedObject var session: PlayerSession
    let module: ScrapingModule
    let episodes: [PlayerEpisode]
    let title: String
    @Binding var currentStreamUrl: String?
    @Binding var currentStreamHeaders: [String: String]?
    let namespace: Namespace.ID

    var body: some View {
        Player(
            module: module,
            episode: session.episode,
            episodes: episodes,
            title: title,
            streamUrl: currentStreamUrl,
            streamHeaders: currentStreamHeaders ?? [:],
            onNext: { navigateToEpisode(offset: 1) },
            onPrevious: { navigateToEpisode(offset: -1) },
            onEpisodeSelected: { switchToEpisode($0) }
        )
        .ignoresSafeArea()
        .navigationTransitionZoom(sourceID: session.episode, in: namespace)
        .preferredColorScheme(.dark)
    }

    private func navigateToEpisode(offset: Int) {
        guard let currentIndex = episodes.firstIndex(where: { $0.url == session.episode.url }) else { return }
        let newIndex = currentIndex + offset
        guard newIndex >= 0 && newIndex < episodes.count else { return }
        switchToEpisode(episodes[newIndex])
    }

    private func switchToEpisode(_ episode: PlayerEpisode) {
        session.episode = episode
        currentStreamUrl = nil
        currentStreamHeaders = nil
    }
}
