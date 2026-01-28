//
//  DownloadedPlayerView.swift
//  Hiyoku
//
//  Created by 686udjie on 01/27/26.
//

import SwiftUI
import AidokuRunner
import CoreData

struct DownloadedPlayerView: View {
    @StateObject private var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var path: NavigationCoordinator

    init(video: DownloadedVideoInfo) {
        self._viewModel = StateObject(wrappedValue: .init(video: video))
    }

    var body: some View {
        Group {
            if viewModel.episodes.isEmpty {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("LOADING_ELLIPSIS"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyStateView
                }
            } else {
                episodesList
            }
        }
        .navigationTitle(viewModel.video.displayTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        openPlayerView()
                    } label: {
                        Label(NSLocalizedString("VIEW_SERIES"), systemImage: "play.tv")
                    }

                    Button {
                        Task {
                            let identifier = MangaIdentifier(sourceKey: viewModel.video.sourceId, mangaKey: viewModel.video.mangaId)
                            if let url = await DownloadManager.shared.getMangaDirectoryUrl(identifier: identifier) {
                                await MainActor.run {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    } label: {
                        Label(NSLocalizedString("VIEW_FILES"), systemImage: "folder")
                    }

                    if !viewModel.episodes.isEmpty {
                        Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                            Label(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), systemImage: "trash")
                        }
                    }
                } label: {
                    MoreIcon()
                }
            }
        }
        .task {
            await viewModel.loadEpisodes()
            await viewModel.loadHistory()
        }
        .alert(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), isPresented: $viewModel.showingDeleteAllConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) { }
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.deleteAllEpisodes()
            }
        } message: {
            Text(NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM"))
        }
    }

    private var emptyStateView: some View {
        UnavailableView(
            NSLocalizedString("NO_DOWNLOADS"),
            systemImage: "arrow.down.circle",
            description: Text(NSLocalizedString("NO_DOWNLOADS_TEXT"))
        )
        .ignoresSafeArea()
    }

    private var episodesList: some View {
        List {
            Section {
                videoInfoHeader
            }

            Section {
                ForEach(viewModel.episodes) { episode in
                    Button {
                        playVideo(episode: episode)
                    } label: {
                        EpisodeRow(episode: episode, history: viewModel.watchHistory[episode.videoKey])
                    }
                    .foregroundStyle(.primary)
                    .contextMenu {
                        Button {
                            showShareSheet(episode: episode)
                        } label: {
                            Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .onDelete(perform: delete)
            } header: {
                HStack {
                    Text(NSLocalizedString("DOWNLOADED_VIDEOS"))
                    Spacer()
                    Button(action: viewModel.toggleSortOrder) {
                        Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                            .imageScale(.small)
                    }
                }
            }
        }
    }

    private var videoInfoHeader: some View {
        HStack(spacing: 12) {
            MangaCoverView(
                source: SourceManager.shared.source(for: viewModel.video.sourceId),
                coverImage: viewModel.video.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.video.displayTitle)
                    .font(.callout)
                    .lineLimit(2)

                Text(formatVideoSubtitle())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if viewModel.video.isInLibrary {
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical.fill")
                            .imageScale(.small)
                        Text(NSLocalizedString("IN_LIBRARY"))
                            .font(.footnote)
                    }
                    .foregroundStyle(.tint)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        let episodes = offsets.map { viewModel.episodes[$0] }
        for episode in episodes {
            viewModel.deleteEpisode(episode)
        }
    }

    private func formatVideoSubtitle() -> String {
        var components: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        components.append(formatter.string(from: Date()))
        components.append(viewModel.video.formattedSize)
        return components.joined(separator: " • ")
    }

    private func openPlayerView() {
        let module = ModuleManager.shared.modules.first { module in
            module.id.uuidString == viewModel.video.sourceId ||
            module.metadata.sourceName == viewModel.video.sourceId
        }

        guard let module = module else { return }

        let bookmark = PlayerLibraryManager.shared.items.first(where: {
            $0.moduleId == module.id && (
                $0.sourceUrl == viewModel.video.seriesId ||
                $0.title == viewModel.video.displayTitle
            )
        })

        if let bookmark = bookmark {
            let vc = PlayerInfoViewController(bookmark: bookmark, path: path)
            path.push(vc)
        } else {
            // simulate a search item
            let searchItem = SearchItem(
                title: viewModel.video.displayTitle,
                imageUrl: viewModel.video.coverUrl ?? "",
                href: viewModel.video.seriesId // seriesId is the URL/Key
            )
            let vc = PlayerInfoViewController(searchItem: searchItem, module: module, path: path)
            path.push(vc)
        }
    }

    private func playVideo(episode: DownloadedVideoItemInfo) {
        let identifier = ChapterIdentifier(
            sourceKey: viewModel.video.sourceId,
            mangaKey: viewModel.video.mangaId,
            chapterKey: episode.videoKey
        )
        Task {
            if let localUrl = await DownloadManager.shared.getDownloadedFileUrl(for: identifier) {
                await MainActor.run {
                    let module = ModuleManager.shared.modules.first { module in
                        module.id.uuidString == viewModel.video.sourceId ||
                        module.metadata.sourceName == viewModel.video.sourceId
                    }
                    guard let module = module else { return }

                    let player = PlayerViewController(
                        module: module,
                        videoUrl: localUrl.path,
                        videoTitle: "\(viewModel.video.displayTitle) - \(episode.displayTitle)"
                    )
                    path.present(player, animated: true)
                }
            }
        }
    }

    private func showShareSheet(episode: DownloadedVideoItemInfo) {
        let identifier = ChapterIdentifier(
            sourceKey: viewModel.video.sourceId,
            mangaKey: viewModel.video.mangaId,
            chapterKey: episode.videoKey
        )
        Task {
            if let url = await DownloadManager.shared.getDownloadedFileUrl(for: identifier) {
                let activityViewController = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )
                guard let sourceView = path.rootViewController?.view else { return }
                activityViewController.popoverPresentationController?.sourceView = sourceView
                activityViewController.popoverPresentationController?.sourceRect = CGRect(
                    x: UIScreen.main.bounds.width - 30,
                    y: 60,
                    width: 0,
                    height: 0
                )
                path.present(activityViewController)
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: DownloadedVideoItemInfo
    let history: (progress: Int, total: Int?)?

    var isRead: Bool {
        if let history = history, let total = history.total {
            return history.progress >= total - 1 // Close enough to finished
        }
        return false
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isRead ? .secondary : .primary)

                if let subtitle = formatEpisodeSubtitle() {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func formatEpisodeSubtitle() -> String? {
        var components: [String] = []
        if let downloadDate = episode.downloadDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            components.append(formatter.string(from: downloadDate))
        }
        // video duration or progress
        if let history = history {
            let progressText = formatDuration(TimeInterval(history.progress))
            components.append("\(NSLocalizedString("PLAYER_PROGRESS")): \(progressText)")
        }

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

extension DownloadedPlayerView {
    @MainActor
    class ViewModel: ObservableObject {
        let video: DownloadedVideoInfo
        @Published var episodes: [DownloadedVideoItemInfo] = []
        @Published var isLoading = true
        @Published var showingDeleteAllConfirmation = false
        @Published var sortAscending = true
        @Published var watchHistory: [String: (progress: Int, total: Int?)] = [:]

        init(video: DownloadedVideoInfo) {
            self.video = video
            NotificationCenter.default.addObserver(
                forName: .downloadRemoved,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { [weak self] in
                    await self?.loadEpisodes()
                }
            }
        }

        func loadEpisodes() async {
            isLoading = true
            let identifier = MangaIdentifier(sourceKey: video.sourceId, mangaKey: video.mangaId)
            var items = await DownloadManager.shared.getDownloadedVideoItems(for: identifier)

            items.sort { lhs, rhs in
                if sortAscending {
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                } else {
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedDescending
                }
            }

            await MainActor.run {
                withAnimation {
                    self.episodes = items
                    self.isLoading = false
                }
            }
        }

        func loadHistory() async {
            let moduleId = video.sourceId
            let map: [String: (progress: Int, total: Int?)] = await CoreDataManager.shared.container
                .performBackgroundTask { context in
                    var results: [String: (progress: Int, total: Int?)] = [:]
                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PlayerHistory")
                fetchRequest.predicate = NSPredicate(format: "moduleId == %@", moduleId)
                do {
                    let historyObjects = try context.fetch(fetchRequest)
                    for obj in historyObjects {
                        if let episodeId = obj.value(forKey: "episodeId") as? String,
                           let progress = obj.value(forKey: "progress") as? Int16 {
                            let total = obj.value(forKey: "total") as? Int16
                            results[episodeId] = (
                                progress: Int(progress),
                                total: total.map(Int.init)
                            )
                        }
                    }
                } catch {
                    print("Error fetching history: \(error)")
                }
                return results
                }
            await MainActor.run {
                self.watchHistory = map
            }
        }

        func toggleSortOrder() {
            sortAscending.toggle()
            Task {
                await loadEpisodes()
            }
        }

        func confirmDeleteAll() {
            showingDeleteAllConfirmation = true
        }

        func deleteAllEpisodes() {
            Task {
                let identifier = MangaIdentifier(sourceKey: video.sourceId, mangaKey: video.mangaId)
                await DownloadManager.shared.deleteChapters(for: identifier)
                await MainActor.run {
                    self.episodes = []
                }
            }
        }

        func deleteEpisode(_ episode: DownloadedVideoItemInfo) {
            Task {
                let id = ChapterIdentifier(
                    sourceKey: video.sourceId,
                    mangaKey: video.mangaId,
                    chapterKey: episode.videoKey
                )
                await DownloadManager.shared.deleteChapter(for: id)
                await loadEpisodes()
            }
        }
    }
}
