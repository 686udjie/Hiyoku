//
//  PlayerInfoView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import Foundation
import SwiftUI
import NukeUI

class PlayerSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var episode: PlayerEpisode
    init(episode: PlayerEpisode) { self.episode = episode }
}

struct PlayerInfoView: View {
    @StateObject private var viewModel: ViewModel

    @AppStorage("Player.askForStreamResolution") private var askForStreamResolution = false
    @AppStorage("Player.preferredResolutionWifi") private var preferredResolutionWifi = "auto"
    @AppStorage("Player.preferredResolutionCellular") private var preferredResolutionCellular = "auto"
    @AppStorage("Player.preferredAudioChannel") private var preferredAudioChannel = "SUB"

    @State private var showingCoverView = false
    @State private var descriptionExpanded = false
    @State private var playerSession: PlayerSession?
    @State private var currentStreamUrl: String?
    @State private var currentStreamHeaders: [String: String]?
    @State private var errorMessage: String?
    @State private var showingStreamSelection = false
    @State private var availableStreams: [StreamInfo] = []
    @State private var tempSubtitleUrl: String?
    @State private var selectedEpisodeForStream: PlayerEpisode?

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
            .fullScreenCover(
                item: $playerSession,
                onDismiss: {
                    Task {
                        await viewModel.fetchHistory()
                    }
                },
                content: { session in
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
            )
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

            .confirmationDialog("Select Resolution", isPresented: $showingStreamSelection, titleVisibility: .visible) {
                 ForEach(availableStreams, id: \.url) { stream in
                     Button(stream.title) {
                         Task {
                             await playSelectedStream(stream, subtitleUrl: tempSubtitleUrl)
                         }
                     }
                 }
                 Button("Cancel", role: .cancel) {}
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
        let history = viewModel.episodeProgress[episode.url]
        EpisodeCellView(episode: episode, history: history) {
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

        guard !streamInfos.isEmpty else {
            errorMessage = "Unable to find video stream for this episode"
            return
        }

        if askForStreamResolution, streamInfos.count > 1 {
            availableStreams = streamInfos
            tempSubtitleUrl = subtitleUrl
            selectedEpisodeForStream = episode
            showingStreamSelection = true
            return
        }

        if let selectedStream = selectStream(streamInfos) {
            await playSelectedStream(selectedStream, subtitleUrl: subtitleUrl, episode: episode)
        } else if let firstStream = streamInfos.first {
            await playSelectedStream(firstStream, subtitleUrl: subtitleUrl, episode: episode)
        }
    }

    private func selectStream(_ streams: [StreamInfo]) -> StreamInfo? {
        guard !streams.isEmpty else { return nil }
        guard !askForStreamResolution else { return streams.first }

        let audioFiltered = filterByAudioPreference(streams)
        let resolutionPreference = getResolutionPreference()
        guard resolutionPreference.lowercased() != "auto" else {
            return audioFiltered.first
        }
        return selectBestResolution(from: audioFiltered, target: resolutionPreference) ?? audioFiltered.first
    }
    private func filterByAudioPreference(_ streams: [StreamInfo]) -> [StreamInfo] {
        let filtered = streams.filter { $0.title.lowercased().contains(preferredAudioChannel.lowercased()) }
        return filtered.isEmpty ? streams : filtered
    }
    private func getResolutionPreference() -> String {
        switch Reachability.getConnectionType() {
        case .wifi: return preferredResolutionWifi
        case .cellular: return preferredResolutionCellular
        case .none: return "auto"
        }
    }
    private func selectBestResolution(from streams: [StreamInfo], target: String) -> StreamInfo? {
        guard let targetResolution = parseResolution(target) else { return nil }
        let candidates = streams.compactMap { stream -> (stream: StreamInfo, resolution: Int)? in
            parseResolution(stream.title).map { (stream, $0) }
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { lhs, rhs in
            let lDiff = abs(lhs.resolution - targetResolution)
            let rDiff = abs(rhs.resolution - targetResolution)
            return lDiff != rDiff ? lDiff < rDiff : lhs.resolution > rhs.resolution
        }?.stream
    }
    private func parseResolution(_ text: String) -> Int? {
        let lower = text.lowercased()
        if lower.contains("4k") {
            return 2160
        }
        let pattern = "(\\d{3,4})p"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range) else { return nil }
        guard match.numberOfRanges >= 2, let valueRange = Range(match.range(at: 1), in: lower) else { return nil }
        return Int(lower[valueRange])
    }

    @MainActor
    private func playSelectedStream(_ stream: StreamInfo, subtitleUrl: String?, episode: PlayerEpisode? = nil) async {
        guard let episode = episode ?? selectedEpisodeForStream else { return }

        currentStreamUrl = stream.url
        currentStreamHeaders = stream.headers
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
    }
}

private struct EpisodeCellView: View, Equatable {
    let episode: PlayerEpisode
    let history: PlayerInfoView.InlineEpisodeHistory?
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

                    let title = episode.title
                    let isRedundantTitle = title == "Episode \(episode.number)" || title == "Episode \(episode.number)" || title.isEmpty
                    if !isRedundantTitle {
                        Text(title)
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 4) {
                        if let date = episode.dateUploaded {
                            Text(date, format: .dateTime.year().month().day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let history = history {
                            let progressText = formatDuration(TimeInterval(history.progress))
                            Text("\(String(localized: "PLAYER_PROGRESS")) • \(progressText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    static nonisolated func == (lhs: EpisodeCellView, rhs: EpisodeCellView) -> Bool {
        lhs.episode == rhs.episode &&
        lhs.history?.progress == rhs.history?.progress &&
        lhs.history?.total == rhs.history?.total
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
