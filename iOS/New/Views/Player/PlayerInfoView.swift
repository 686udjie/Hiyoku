//
//  PlayerInfoView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/08/26.
//

import Foundation
import SwiftUI
import NukeUI
import AidokuRunner
import SafariServices

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
        if #available(iOS 26.0, *) {
            mainContent
                .toolbar {
                    toolbarContentBase
                    if viewModel.editMode == .active {
                        ToolbarItem(placement: .bottomBar) {
                            toolbarMarkMenu
                        }
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            toolbarDownloadButton
                        }
                    }
                }
        } else {
            mainContent
                .toolbar {
                    toolbarContentBase
                    ToolbarItemGroup(placement: .bottomBar) {
                        if viewModel.editMode == .active {
                            HStack {
                                toolbarMarkMenu
                                Spacer()
                                toolbarDownloadButton
                            }
                        }
                    }
                }
        }
    }

    private var mainContent: some View {
        configuredList
            .fullScreenCover(isPresented: $showingCoverView) {
                PlayerCoverPageView(posterUrl: viewModel.posterUrl, title: viewModel.title)
            }
            .environment(\.editMode, $viewModel.editMode)
            .fullScreenCover(item: $playerSession,
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
            .navigationBarBackButtonHidden(viewModel.editMode == .active)
            .onChange(of: viewModel.editMode) { mode in
                let controller = path.rootViewController as? UINavigationController ??
                                 path.rootViewController?.navigationController
                guard let navigationController = controller else { return }
                if mode == .active {
                    navigationController.setDismissGesturesEnabled(false)
                    UIView.animate(withDuration: 0.3) {
                        navigationController.isToolbarHidden = false
                        navigationController.toolbar.alpha = 1
                        if #available(iOS 26.0, *) {
                            navigationController.tabBarController?.isTabBarHidden = true
                        }
                    }
                } else {
                    navigationController.setDismissGesturesEnabled(true)
                    UIView.animate(withDuration: 0.3) {
                        navigationController.toolbar.alpha = 0
                        if #available(iOS 26.0, *) {
                            navigationController.tabBarController?.isTabBarHidden = false
                        }
                    } completion: { _ in
                        navigationController.isToolbarHidden = true
                    }
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
                await viewModel.fetchEpisodes()
                episodesLoaded = true
            }
    }

    @ToolbarContentBuilder
    private var toolbarContentBase: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 8) {
                PlayerRightNavbarButton(
                    viewModel: viewModel,
                    editMode: $viewModel.editMode,
                    onOpenWebView: openWebView
                )
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            if viewModel.editMode == .active {
                let allSelected = viewModel.selectedEpisodes.count == viewModel.episodes.count
                Button {
                    if allSelected {
                        viewModel.deselectAll()
                    } else {
                        viewModel.selectAll()
                    }
                } label: {
                    if allSelected {
                        Text(String(localized: "DESELECT_ALL"))
                    } else {
                        Text(String(localized: "SELECT_ALL"))
                    }
                }
                .disabled(viewModel.episodes.isEmpty)
            }
        }
    }

    private var configuredList: some View {
        List(selection: $viewModel.selectedEpisodes) {
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

    private func openWebView() {
        guard let rawUrlString = viewModel.contentUrl else { return }
        let normalized = rawUrlString.normalizedModuleHref()
        let finalUrlString: String
        if normalized.starts(with: "http") {
            finalUrlString = normalized
        } else if let baseUrl = viewModel.module?.metadata.baseUrl {
            finalUrlString = normalized.absoluteUrl(withBaseUrl: baseUrl)
        } else {
            return
        }

        guard let url = URL(string: finalUrlString),
              url.scheme == "http" || url.scheme == "https" else { return }

        let safariViewController = SFSafariViewController(url: url)
        safariViewController.modalPresentationStyle = .pageSheet
        path.present(safariViewController, animated: true)
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

    private var toolbarMarkMenu: some View {
        Menu(String(localized: "MARK")) {
            let title = if viewModel.selectedEpisodes.count == 1 {
                String(localized: "1_EPISODE")
            } else {
                String(format: String(localized: "%d_EPISODES"), viewModel.selectedEpisodes.count)
            }
            Section(title) {
                Button {
                    let markEpisodes = viewModel.selectedEpisodes.compactMap { id in
                        viewModel.episodes.first(where: { $0.url == id })
                    }
                    Task {
                        await viewModel.markUnwatched(episodes: markEpisodes)
                    }
                    withAnimation {
                        viewModel.editMode = .inactive
                    }
                } label: {
                    Label(String(localized: "UNWATCHED"), systemImage: "eye.slash")
                }
                Button {
                    let markEpisodes = viewModel.selectedEpisodes.compactMap { id in
                        viewModel.episodes.first(where: { $0.url == id })
                    }
                    Task {
                        await viewModel.markWatched(episodes: markEpisodes)
                    }
                    withAnimation {
                        viewModel.editMode = .inactive
                    }
                } label: {
                    Label(String(localized: "WATCHED"), systemImage: "eye")
                }
            }
        }
        .disabled(viewModel.selectedEpisodes.isEmpty)
    }

    private var toolbarDownloadButton: some View {
        let allQueued = !viewModel.selectedEpisodes.isEmpty && !viewModel.selectedEpisodes.contains {
            viewModel.downloadStatus[$0] != .queued
        }
        let allDownloaded = !viewModel.selectedEpisodes.isEmpty && !viewModel.selectedEpisodes.contains {
            viewModel.downloadStatus[$0] != .finished
        }

        if allQueued {
            return AnyView(Button(String(localized: "CANCEL")) {
                let episodes = viewModel.episodes.filter { viewModel.selectedEpisodes.contains($0.url) }
                Task {
                    await viewModel.cancelDownloads(for: episodes)
                    withAnimation { viewModel.editMode = .inactive }
                }
            })
        } else if allDownloaded {
            return AnyView(Button(String(localized: "REMOVE")) {
                let episodes = viewModel.episodes.filter { viewModel.selectedEpisodes.contains($0.url) }
                Task {
                    await viewModel.deleteEpisodes(episodes)
                    withAnimation { viewModel.editMode = .inactive }
                }
            })
        } else {
            return AnyView(Button(String(localized: "DOWNLOAD")) {
                Task {
                    await viewModel.downloadSelectedEpisodes()
                    withAnimation { viewModel.editMode = .inactive }
                }
            }
            .disabled(viewModel.selectedEpisodes.isEmpty))
        }
    }
}

// MARK: - UI Components

extension PlayerInfoView {
    @ViewBuilder
    private func viewForEpisode(_ episode: PlayerEpisode, index: Int) -> some View {
        let history = viewModel.episodeProgress[episode.url]
        let read = history?.progress == history?.total && history?.total != nil && history?.total != 0
        let downloadStatus = viewModel.downloadStatus[episode.url, default: .none]
        let downloadProgress = viewModel.downloadProgress[episode.url]

        EpisodeCellView(
            episode: episode,
            history: history,
            read: read,
            downloadStatus: downloadStatus,
            downloadProgress: downloadProgress,
            isEditing: viewModel.editMode == .active
        ) {
            handleEpisodeTap(episode)
        }
        .equatable()
        .contextMenu {
            contextMenuContent(for: episode, at: index, isRead: read)
        }
        .listRowInsets(.zero)
        .tag(episode.url)
        .matchedTransitionSourcePlease(id: episode, in: transitionNamespace)
    }

    private func handleEpisodeTap(_ episode: PlayerEpisode) {
        if viewModel.editMode == .active {
            if viewModel.selectedEpisodes.contains(episode.url) {
                viewModel.selectedEpisodes.remove(episode.url)
            } else {
                viewModel.selectedEpisodes.insert(episode.url)
            }
        } else {
            Task {
                await playEpisode(episode)
            }
        }
    }
}

// MARK: - Context Menu

extension PlayerInfoView {
    @ViewBuilder
    private func contextMenuContent(
        for episode: PlayerEpisode,
        at index: Int,
        isRead: Bool
    ) -> some View {
        if viewModel.editMode == .inactive {
            Section {
                let status = viewModel.downloadStatus[episode.url, default: .none]
                if status == .finished {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteEpisodes([episode]) }
                    } label: {
                        Label(String(localized: "REMOVE_DOWNLOAD"), systemImage: "trash")
                    }
                } else if status == .downloading || status == .queued {
                    Button(role: .destructive) {
                        Task { await viewModel.cancelDownloads(for: [episode]) }
                    } label: {
                        Label(String(localized: "CANCEL_DOWNLOAD"), systemImage: "xmark")
                    }
                } else {
                    Button {
                        Task { await viewModel.downloadEpisode(episode) }
                    } label: {
                        Label(String(localized: "DOWNLOAD"), systemImage: "arrow.down.circle")
                    }
                }
                Divider()
                if isRead {
                    Button {
                        Task { await viewModel.markUnwatched(episodes: [episode]) }
                    } label: {
                        Label(String(localized: "MARK_UNWATCHED"), systemImage: "eye.slash")
                    }
                } else {
                    Button {
                        Task { await viewModel.markWatched(episodes: [episode]) }
                    } label: {
                        Label(String(localized: "MARK_WATCHED"), systemImage: "eye")
                    }
                }
                if index < viewModel.sortedEpisodes.count - 1 {
                    markPreviousMenu(startingAt: index)
                }
            }
        }
    }
}

// MARK: - Previous Episodes Menu

extension PlayerInfoView {
    @ViewBuilder
    private func markPreviousMenu(startingAt index: Int) -> some View {
        Menu(String(localized: "MARK_PREVIOUS")) {
            let previousEpisodes = Array(viewModel.sortedEpisodes[index + 1..<viewModel.sortedEpisodes.count])
            Button {
                Task { await viewModel.markWatched(episodes: previousEpisodes) }
            } label: {
                Label(String(localized: "WATCHED"), systemImage: "eye")
            }
            Button {
                Task { await viewModel.markUnwatched(episodes: previousEpisodes) }
            } label: {
                Label(String(localized: "UNWATCHED"), systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - Episode Handling

extension PlayerInfoView {
    @MainActor
    private func playEpisode(_ episode: PlayerEpisode) async {
        guard let module = viewModel.module, !episode.url.isEmpty else {
            errorMessage = "Episode ID is not available"
            return
        }
        if let localUrl = await viewModel.getLocalEpisodeUrl(for: episode) {
             let streamInfo = StreamInfo(title: "Downloaded", url: localUrl.absoluteString, headers: [:])
             await playSelectedStream(streamInfo, subtitleUrl: nil, episode: episode)
             return
        }

        let (streamInfos, subtitleUrl) = await JSController.shared.fetchPlayerStreams(
            episodeId: episode.url,
            module: module
        )

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
}

// MARK: - Stream Selection Helpers

extension PlayerInfoView {
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
        let filtered = streams.filter {
            $0.title.lowercased().contains(preferredAudioChannel.lowercased())
        }
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
}

// MARK: - Stream Playback

extension PlayerInfoView {
    @MainActor
    private func playSelectedStream(
        _ stream: StreamInfo,
        subtitleUrl: String?,
        episode: PlayerEpisode? = nil
    ) async {
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
    let read: Bool
    let downloadStatus: DownloadStatus
    var downloadProgress: Float?
    var isEditing: Bool = false
    var onPressed: (() -> Void)?

    var downloaded: Bool {
        downloadStatus == .finished
    }

    var progress: Float? {
        downloadProgress ?? (downloadStatus == .queued || downloadStatus == .downloading ? 0 : nil)
    }

    var body: some View {
        let content = HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8 / 3) {
                Text("Episode \(episode.number)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(read ? .secondary : .primary)
                    .lineLimit(1)

                let title = episode.title
                let isRedundantTitle = title.isEmpty || title == "Episode \(episode.number)"
                if !isRedundantTitle {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let date = episode.dateUploaded {
                        Text(date, format: .dateTime.year().month().day())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if let history = history, !read {
                        if episode.dateUploaded != nil {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        let progressText = formatDuration(TimeInterval(history.progress))
                        Text("\(String(localized: "PLAYER_PROGRESS")) • \(progressText)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            } else if let progress {
                DownloadProgressView(progress: progress)
                    .frame(width: 13, height: 13)
                    .tint(.accentColor)
            }

            if let scanlator = episode.scanlator {
                Text(scanlator)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 22 / 3)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())

        if isEditing {
            content
        } else {
            Button {
                onPressed?()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .tint(.primary)
        }
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
        lhs.history?.total == rhs.history?.total &&
        lhs.read == rhs.read &&
        lhs.downloadStatus == rhs.downloadStatus &&
        lhs.downloadProgress == rhs.downloadProgress &&
        lhs.isEditing == rhs.isEditing
    }
}

private struct DownloadProgressView: UIViewRepresentable {
    var progress: Float

    func makeUIView(context: Context) -> CircularProgressView {
        let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 13, height: 13))
        progressView.radius = 13 / 2
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = UIColor(Color.accentColor)
        return progressView
    }

    func updateUIView(_ uiView: CircularProgressView, context: Context) {
        uiView.setProgress(value: progress, withAnimation: false)
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

private struct PlayerRightNavbarButton: View, Equatable {
    @ObservedObject var viewModel: PlayerInfoView.ViewModel
    @Binding var editMode: EditMode
    let onOpenWebView: () -> Void
    let isBookmarked: Bool
    let isEditing: Bool

    init(
        viewModel: PlayerInfoView.ViewModel,
        editMode: Binding<EditMode>,
        onOpenWebView: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self._editMode = editMode
        self.onOpenWebView = onOpenWebView
        self.isBookmarked = viewModel.isBookmarked
        self.isEditing = editMode.wrappedValue == .active
    }

    var body: some View {
        if editMode == .inactive {
            Menu {
                Menu(String(localized: "MARK_ALL")) {
                    Button {
                        Task {
                            await viewModel.markWatched(episodes: viewModel.episodes)
                        }
                    } label: {
                        Label(String(localized: "WATCHED"), systemImage: "eye")
                    }
                    Button {
                        Task {
                            await viewModel.markUnwatched(episodes: viewModel.episodes)
                        }
                    } label: {
                        Label(String(localized: "UNWATCHED"), systemImage: "eye.slash")
                    }
                }
                Button {
                    withAnimation {
                        editMode = .active
                    }
                } label: {
                    Label(String(localized: "SELECT_EPISODES"), systemImage: "checkmark.circle")
                }

            } label: {
                MoreIcon()
            }
        } else {
            DoneButton {
                withAnimation {
                    editMode = .inactive
                }
            }
        }
    }

    static nonisolated func == (lhs: PlayerRightNavbarButton, rhs: PlayerRightNavbarButton) -> Bool {
        lhs.isBookmarked == rhs.isBookmarked
            && lhs.isEditing == rhs.isEditing
    }
}
