//
//  HistoryView.swift
//  Aidoku
//
//  Created by Skitty on 7/30/25.
//

import AidokuRunner
import LocalAuthentication
import SwiftUI
import SwiftUIIntrospect
import UIKit

struct HistoryView: View {
    @StateObject private var viewModel = ViewModel()

    enum HistoryKind: String, CaseIterable {
        case reader = "Reader"
        case player = "Player"
    }

    @State private var selectedKind: HistoryKind
    @State private var searchText = ""
    @State private var entryToDelete: HistoryEntry?
    @State private var playerEntryToDelete: PlayerHistoryManager.PlayerHistoryItem?
    @State private var showClearHistoryConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showPlayerDeleteConfirm = false

    @State private var triggerLoadMoreVisibleCheck = false
    @State private var loadTask: Task<(), Never>?

    @State private var locked = UserDefaults.standard.bool(forKey: "History.lockHistory")

    @State private var listSelection: String? // fix for list highlighting being buggy

    @EnvironmentObject private var path: NavigationCoordinator

    init(initialKind: HistoryKind = .reader) {
        self._selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        let base = mainContent
        let step1 = base
            .customSearchable(
                text: $searchText,
                stacked: false,
                onSubmit: {
                    Task {
                        await viewModel.search(query: searchText, delay: false)
                    }
                },
                onCancel: {
                    Task {
                        await viewModel.search(query: searchText, delay: false)
                    }
                }
            )
        let step2 = step1
            .onChange(of: searchText) { newValue in
                Task {
                    await viewModel.search(query: newValue, delay: true)
                }
            }
            .animation(.default, value: viewModel.unifiedEntries)
        let step3 = step2
            .navigationTitle(NSLocalizedString("HISTORY"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if UserDefaults.standard.bool(forKey: "History.lockHistory") {
                        SwiftUI.Button {
                            if locked {
                                Task {
                                    await unlock()
                                }
                            } else {
                                locked = true
                                UserDefaults.standard.set(true, forKey: "History.lockHistory")
                                NotificationCenter.default.post(name: .historyLockSetting, object: nil)
                            }
                        } label: {
                            Image(systemName: locked ? "lock" : "lock.open")
                        }
                    }
                    SwiftUI.Button {
                        showClearHistoryConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        let step4 = step3
            .confirmationDialogOrAlert(NSLocalizedString("CLEAR_READ_HISTORY"),
                                       isPresented: $showClearHistoryConfirm,
                                       titleVisibility: Visibility.visible) {
                SwiftUI.Button(NSLocalizedString("CLEAR"), role: .destructive) {
                    viewModel.clearHistory()
                    Task {
                        await viewModel.clearPlayerHistory()
                    }
                }
            } message: {
                Text(NSLocalizedString("CLEAR_READ_HISTORY_TEXT"))
            }
            .confirmationDialogOrAlert(NSLocalizedString("CLEAR_READ_HISTORY"),
                                       isPresented: $showDeleteConfirm,
                                       titleVisibility: Visibility.visible) {
                SwiftUI.Button(NSLocalizedString("REMOVE"), role: .destructive) {
                    if let entryToDelete {
                        Task {
                            await viewModel.removeHistory(entry: entryToDelete)
                        }
                    }
                }
                SwiftUI.Button(NSLocalizedString("REMOVE_ALL_MANGA_HISTORY"), role: .destructive) {
                    if let entryToDelete {
                        Task {
                            await viewModel.removeHistory(entry: entryToDelete, all: true)
                        }
                    }
                }
            } message: {
                Text(NSLocalizedString("CLEAR_READ_HISTORY_TEXT"))
            }
            .confirmationDialogOrAlert("Remove", isPresented: $showPlayerDeleteConfirm, titleVisibility: Visibility.visible) {
                SwiftUI.Button("Remove", role: .destructive) {
                    if let playerEntryToDelete {
                        Task {
                            await viewModel.removePlayerHistory(item: playerEntryToDelete)
                        }
                    }
                }
            } message: {
                Text("This will remove the selected player history entry.")
            }
        let step5 = step4
            .onReceive(NotificationCenter.default.publisher(for: .historyLockSetting)) { _ in
                locked = UserDefaults.standard.bool(forKey: "History.lockHistory")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                locked = UserDefaults.standard.bool(forKey: "History.lockHistory")
            }
            .onAppear {
                Task { await viewModel.loadPlayerHistory() }
            }
            .onChange(of: searchText) { _ in
                Task { await viewModel.search(query: searchText, delay: false) }
            }
        return AnyView(step5)
    }

    @ViewBuilder
    private var mainContent: some View {
        if locked {
            lockedView
        } else if viewModel.unifiedEntries.isEmpty && viewModel.loadingState == .complete {
            UnavailableView(
                NSLocalizedString("NO_HISTORY"),
                systemImage: "book.fill",
                description: Text(NSLocalizedString("NO_HISTORY_TEXT"))
            )
            .ignoresSafeArea()
        } else {
            listView
        }
    }

    private var lockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("HISTORY_LOCKED"))
                .fontWeight(.medium)

            SwiftUI.Button(NSLocalizedString("VIEW_HISTORY")) {
                Task {
                    await unlock()
                }
            }
        }
        .padding(.top, -52) // slight offset to account for search bar and make the view more centered
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List(selection: $listSelection) {
            let grouped = Dictionary(grouping: viewModel.unifiedEntries, by: { $0.daysAgo })
            let days = grouped.keys.sorted()
            ForEach(days, id: \.self) { day in
                Section(header: headerView(daysAgo: day)) {
                    ForEach(grouped[day] ?? []) { entry in
                        historyRow(entry: entry)
                    }
                }
            }

            loadMoreView
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.defaultMinListHeaderHeight, 1) // for ios 15
        .listSectionSpacingPlease(10)
        .scrollBackgroundHiddenPlease()
        .scrollDismissesKeyboardImmediately()
        .background(Color(uiColor: .systemBackground))
    }

    func headerView(daysAgo: Int) -> some View {
        Text(Date.makeRelativeDate(days: daysAgo))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.primary)
            .foregroundColor(.primary) // for ios 15
            .textCase(.none)
            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 8, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
    }

    func historyRow(entry: ViewModel.UnifiedEntry) -> some View {
        Group {
            if let reader = entry.readerEntry {
                let manga = viewModel.mangaCache[reader.mangaCacheKey]
                HistoryEntryCell(
                    type: .reader(reader, manga, viewModel.chapterCache[reader.chapterCacheKey]),
                    additionalCount: entry.additionalCount
                ) {
                    if let manga {
                        path.push(MangaViewController(manga: manga, parent: path.rootViewController))
                    }
                }
                .swipeActions(edge: .trailing) {
                    SwiftUI.Button(NSLocalizedString("DELETE")) {
                        entryToDelete = reader
                        showDeleteConfirm = true
                    }
                    .tint(.red)
                }
                .id(reader.chapterCacheKey)
                .tag(reader.chapterCacheKey)
            } else if let player = entry.playerEntry {
                let posterKey = "\(player.moduleId)|\(player.playerTitle)"
                let posterUrl = viewModel.playerPosterCache[posterKey] ?? ""
                HistoryEntryCell(
                    type: .player(player, posterUrl: posterUrl),
                    additionalCount: entry.additionalCount
                ) {
                    if let vc = viewModel.makePlayerInfoViewController(for: player, path: path) {
                        path.push(vc)
                    }
                }
                .swipeActions(edge: .trailing) {
                    SwiftUI.Button("Delete") {
                        playerEntryToDelete = player
                        showPlayerDeleteConfirm = true
                    }
                    .tint(.red)
                }
                .id(player.id)
                .tag(player.id)
            }
        }
        .offsetListSeparator()
    }

    @ViewBuilder
    var loadMoreView: some View {
        VStack {
            if viewModel.loadingState != .complete {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .onReportScrollVisibilityChange(trigger: $triggerLoadMoreVisibleCheck) { visible in
                        Task {
                            await loadTask?.value
                            if visible {
                                tryLoadingMore()
                            }
                        }
                    }
                    .onChange(of: viewModel.filteredHistory) { _ in
                        // trigger check to see if the loading more view is still visible after content is added
                        Task {
                            try? await Task.sleep(nanoseconds: 10_000_000) // wait 10ms
                            triggerLoadMoreVisibleCheck = true
                        }
                    }
                    .onAppear {
                        tryLoadingMore()
                    }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // load more history entries if the loading state is idle
    func tryLoadingMore() {
        loadTask = Task {
            if viewModel.loadingState == .idle {
                await viewModel.loadMore()
            }
        }
    }

    // prompt for biometrics to unlock the view
    func unlock() async {
        let context = LAContext()
        let success: Bool

        do {
            success = try await context.evaluatePolicy(
                .defaultPolicy,
                localizedReason: NSLocalizedString("AUTH_FOR_HISTORY")
            )
        } catch {
            // The error is to be displayed to users, so we can ignore it.
            return
        }

        guard success else {
            return
        }

        locked = false
        UserDefaults.standard.set(false, forKey: "History.lockHistory")
        NotificationCenter.default.post(name: .historyLockSetting, object: nil)
    }
}

private struct HistoryEntryCell: View {
    enum EntryType {
        case reader(HistoryEntry, AidokuRunner.Manga?, AidokuRunner.Chapter?)
        case player(PlayerHistoryManager.PlayerHistoryItem, posterUrl: String)
    }

    let type: EntryType
    var additionalCount: Int = 0
    var onPressed: (() -> Void)?

    private static let coverImageWidth: CGFloat = 60
    private static let coverImageHeight: CGFloat = 84

    var body: some View {
        SwiftUI.Button {
            onPressed?()
        } label: {
            HStack(alignment: .top, spacing: 16) {
                // Cover Image
                MangaCoverView(
                    coverImage: coverUrl,
                    width: Self.coverImageWidth,
                    height: Self.coverImageHeight,
                    downsampleWidth: Self.coverImageWidth
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    // Subtitle (Details)
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // Additional Count
                    if additionalCount > 0 {
                        Text("+\(additionalCount) more")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .tint(.primary)
    }

    private var title: String {
        switch type {
        case .reader(_, let manga, _):
            return manga?.title ?? ""
        case .player(let item, _):
            return item.playerTitle
        }
    }

    private var subtitle: String {
        var components: [String] = []
        switch type {
        case .reader(let entry, _, let chapter):
            if let volumeNum = chapter?.volumeNumber, volumeNum >= 0 {
                if let chapterNum = chapter?.chapterNumber, chapterNum >= 0 {
                    components.append("Vol.\(volumeNum) Ch.\(chapterNum)")
                } else {
                    components.append("Vol.\(volumeNum)")
                }
            } else if let chapterNum = chapter?.chapterNumber, chapterNum >= 0 {
                components.append("Ch.\(chapterNum)")
            } else if let title = chapter?.title, !title.isEmpty {
                components.append(title)
            }

            if let currentPage = entry.currentPage, let totalPages = entry.totalPages, currentPage > 0 {
                if currentPage == -1 {
                    components.append("Completed")
                } else {
                    components.append("Page \(currentPage) of \(totalPages)")
                }
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            components.append(formatter.string(from: entry.date))

        case .player(let item, _):
            let episodeNumber = Int(item.episodeNumber)
            let episodePrefix = "Episode \(episodeNumber)"
            components.append(episodePrefix)
            if let title = item.episodeTitle, !title.isEmpty, title != episodePrefix {
                components.append(title)
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            components.append(formatter.string(from: item.dateWatched))
        }
        return components.joined(separator: " - ")
    }

    private var coverUrl: String {
        switch type {
        case .reader(_, let manga, _):
            return manga?.cover ?? ""
        case .player(_, let posterUrl):
            return posterUrl
        }
    }
}
