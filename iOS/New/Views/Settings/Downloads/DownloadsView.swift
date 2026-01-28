//
//  DownloadsView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var viewModel = ViewModel()
    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        List {
            Section {
                summaryHeader
            }

            ForEach(Settings.downloadSettings, id: \.key) { setting in
                SettingView(setting: setting)
            }

            if viewModel.isLoading && viewModel.downloadedEntries.isEmpty {
                loadingView
            } else {
                groupedEntriesList
            }
        }
        .refreshable {
            await viewModel.loadDownloadedManga()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.downloadedEntries.isEmpty {
                    Menu {
                        Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                            Label(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), systemImage: "trash")
                        }
                    } label: {
                        MoreIcon()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.downloadedEntries.isEmpty)
        .navigationTitle(NSLocalizedString("DOWNLOADS"))
        .task {
            await viewModel.loadDownloadedManga()
        }
        .alert(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), isPresented: $viewModel.showingDeleteAllConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) { }
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.deleteAll()
            }
        } message: {
            let totalItems = viewModel.downloadedEntries.reduce(0) { $0 + $1.unitCount }
            Text(String(format: NSLocalizedString("%i_ITEMS_WILL_BE_REMOVED"), totalItems))
        }
        .alert(NSLocalizedString("METADATA_DETECTED"), isPresented: $viewModel.showingMigrateNotice) {
            Button(NSLocalizedString("OK"), role: .cancel) {
                viewModel.migrate()
            }
        } message: {
            Text(NSLocalizedString("METADATA_DETECTED_TEXT"))
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("TOTAL_DOWNLOADS"))
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.accentColor)
                } else {
                    Text(viewModel.totalSize)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }

            HStack {
                Text(String(format: NSLocalizedString("%i_SERIES"), viewModel.downloadedEntries.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                let unitCount = viewModel.downloadedEntries.reduce(0) { $0 + $1.unitCount }
                Text(String(format: NSLocalizedString("%i_ITEMS"), unitCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var loadingView: some View {
        Section {
            ProgressView()
                .tint(.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var groupedEntriesList: some View {
        ForEach(viewModel.groupedEntries, id: \.sourceId) { group in
            Section(header:
                HStack {
                    SourceIconView(
                        sourceId: group.sourceId,
                        imageUrl: group.iconUrl,
                        iconSize: 20
                    )
                    Text(group.sourceName)
                }
            ) {
                ForEach(group.entries, id: \.id) { entry in
                    entryRow(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(for entry: any DownloadedEntry) -> some View {
        if let mangaEntry = entry as? DownloadedMangaInfo {
            NavigationLink(destination: DownloadedMangaView(manga: mangaEntry)
                .environmentObject(path)) {
                DownloadedEntryRow(entry: mangaEntry)
            }
            .swipeActions {
                Button(role: .destructive) {
                    viewModel.delete(entry: mangaEntry)
                } label: {
                    Label(NSLocalizedString("DELETE"), systemImage: "trash")
                }
            }
        } else if let videoEntry = entry as? DownloadedVideoInfo {
            NavigationLink(destination: DownloadedPlayerView(video: videoEntry)
                .environmentObject(path)) {
                DownloadedEntryRow(entry: videoEntry)
            }
            .swipeActions {
                Button(role: .destructive) {
                    viewModel.delete(entry: videoEntry)
                } label: {
                    Label(NSLocalizedString("DELETE"), systemImage: "trash")
                }
            }
        }
    }
}

private struct DownloadedEntryRow: View {
    let entry: any DownloadedEntry

    var body: some View {
        HStack(spacing: 12) {
            MangaCoverView(
                source: SourceManager.shared.source(for: entry.sourceId),
                coverImage: entry.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayTitle)
                    .font(.callout)
                    .lineLimit(2)

                Text(formatSubtitle())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if entry.isInLibrary {
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
        .contentShape(Rectangle())
    }

    private func formatSubtitle() -> String {
        var components: [String] = []

        if entry.type == .manga {
            let label = entry.unitCount == 1 ?
                NSLocalizedString("1_CHAPTER") :
                String(format: NSLocalizedString("%i_CHAPTERS"), entry.unitCount)
            components.append(label.lowercased())
        } else {
            let label = entry.unitCount == 1 ?
                NSLocalizedString("1_VIDEO") :
                String(format: NSLocalizedString("%i_VIDEOS"), entry.unitCount)
            components.append(label.lowercased())
        }

        components.append(entry.formattedSize)

        return components.joined(separator: " • ")
    }
}

#Preview {
    PlatformNavigationStack {
        DownloadsView()
    }
}
