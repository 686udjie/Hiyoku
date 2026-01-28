//
//  DownloadsView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 7/21/25.
//

import SwiftUI
import Combine
import Foundation

extension DownloadsView {
    @MainActor
    class ViewModel: ObservableObject {
        @Published var downloadedEntries: [any DownloadedEntry] = []
        @Published var isLoading = true
        @Published var totalSize: String = ""
        @Published var totalCount = 0
        @Published var showingDeleteAllConfirmation = false
        @Published var showingMigrateNotice = false

        // Non-reactive state for background updates
        private var backgroundUpdateInProgress = false
        private var lastUpdateId = UUID()
        private var updateDebouncer: Timer?
        private var cancellables = Set<AnyCancellable>()
        struct SourceGroup {
            let sourceId: String
            let sourceName: String
            let iconUrl: URL?
            let entries: [any DownloadedEntry]
        }

        init() {
            setupNotificationObservers()
        }
    }
}

extension DownloadsView.ViewModel {
    // Group entries by source
    var groupedEntries: [DownloadsView.ViewModel.SourceGroup] {
        let grouped = Dictionary(grouping: downloadedEntries) { $0.sourceId }
        return grouped
            .sorted { $0.key < $1.key }
            .map {
                let info = getSourceInfo($0.key)
                return SourceGroup(
                    sourceId: $0.key,
                    sourceName: info.name,
                    iconUrl: info.icon,
                    entries: $0.value
                )
            }
    }

    func loadDownloadedManga() async {
        withAnimation(.easeInOut(duration: 0.2)) {
            isLoading = true
        }

        let manga = await DownloadManager.shared.getAllDownloadedManga()
        let videos = await DownloadManager.shared.getAllDownloadedVideos()
        let formattedSize = await DownloadManager.shared.getFormattedTotalDownloadedSize()
        let shouldMigrate = await DownloadManager.shared.checkForOldMetadata()

        var entries: [any DownloadedEntry] = []
        entries.append(contentsOf: manga)
        entries.append(contentsOf: videos)

        withAnimation(.easeInOut(duration: 0.3)) {
            downloadedEntries = entries
            totalSize = formattedSize
            totalCount = entries.count
            isLoading = false
            showingMigrateNotice = shouldMigrate
        }
    }

    /// Background update that preserves user navigation and minimizes UI disruption
    private func performBackgroundUpdate() async {
        // Prevent concurrent background updates
        guard !backgroundUpdateInProgress else { return }
        backgroundUpdateInProgress = true
        defer { backgroundUpdateInProgress = false }

        let updateId = UUID()
        lastUpdateId = updateId

        // Fetch new data in background
        let newManga = await DownloadManager.shared.getAllDownloadedManga()
        let newVideos = await DownloadManager.shared.getAllDownloadedVideos()
        let newFormattedSize = await DownloadManager.shared.getFormattedTotalDownloadedSize()

        await MainActor.run {
            // Check if this update is still relevant (not superseded by another)
            guard updateId == lastUpdateId else { return }

            // Perform selective updates using intelligent diffing
            updateDataSelectively(
                newManga: newManga,
                newVideos: newVideos,
                newTotalSize: newFormattedSize
            )
        }
    }

    /// Intelligently update only changed data to preserve navigation state
    private func updateDataSelectively(
        newManga: [DownloadedMangaInfo],
        newVideos: [DownloadedVideoInfo],
        newTotalSize: String
    ) {
        let oldEntries = downloadedEntries
        var newEntries: [any DownloadedEntry] = []
        newEntries.append(contentsOf: newManga)
        newEntries.append(contentsOf: newVideos)

        // Update totals immediately as they don't affect navigation
        totalSize = newTotalSize
        totalCount = newEntries.count

        // Simplified equality check for unified list
        if oldEntries.count != newEntries.count {
            withAnimation(.easeInOut(duration: 0.3)) {
                downloadedEntries = newEntries
            }
        } else {
            // Check if contents are different (basic check by ID and properties)
            // Since DownloadedEntry is not Equatable (it's a protocol), we do a manual check
            var changed = false
            for (old, new) in zip(oldEntries, newEntries) {
                if old.id != new.id || old.totalSize != new.totalSize || old.unitCount != new.unitCount {
                    changed = true
                    break
                }
            }
            if changed {
                withAnimation(.easeInOut(duration: 0.3)) {
                    downloadedEntries = newEntries
                }
            }
        }
    }

    /// Compare manga lists efficiently to avoid unnecessary updates
    private func areMangaListsEqual(
        _ lhs: [DownloadedMangaInfo],
        _ rhs: [DownloadedMangaInfo]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }

        // Quick comparison by ID and key properties
        for (old, new) in zip(lhs, rhs) {
            if old.sourceId != new.sourceId ||
               old.mangaId != new.mangaId ||
               old.totalSize != new.totalSize ||
               old.chapterCount != new.chapterCount ||
               old.isInLibrary != new.isInLibrary {
                return false
            }
        }
        return true
    }

    /// Compare video lists efficiently
    private func areVideoListsEqual(_ lhs: [DownloadedVideoInfo], _ rhs: [DownloadedVideoInfo]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        for (old, new) in zip(lhs, rhs) {
            if old.sourceId != new.sourceId ||
               old.seriesId != new.seriesId ||
               old.totalSize != new.totalSize ||
               old.videoCount != new.videoCount ||
               old.isInLibrary != new.isInLibrary {
                return false
            }
        }
        return true
    }

    /// Debounced update to prevent excessive refreshes
    private func scheduleBackgroundUpdate() {
        updateDebouncer?.invalidate()
        updateDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task {
                await self?.performBackgroundUpdate()
            }
        }
    }

    private func setupNotificationObservers() {
        // High-priority updates that need immediate response
        let immediateUpdateNotifications: [NSNotification.Name] = [
            .downloadRemoved,
            .downloadsRemoved
        ]

        for notification in immediateUpdateNotifications {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task {
                        await self?.performBackgroundUpdate()
                    }
                }
                .store(in: &cancellables)
        }

        // Low-priority reader download updates that can be debounced
        let debouncedUpdateNotifications: [Notification.Name] = [
            Notification.Name.downloadFinished,
            Notification.Name.downloadsCancelled,
            Notification.Name.downloadsQueued,
            Notification.Name.downloadsPaused,
            Notification.Name.downloadsResumed,
            Notification.Name.addToLibrary,
            Notification.Name.removeFromLibrary,
            Notification.Name.updateLibrary,
            Notification.Name.updateHistory,
            Notification.Name.readerShowingBars,
            Notification.Name.readerHidingBars,
            Notification.Name.readerReadingMode,
            Notification.Name.readerTapZones,
            Notification.Name.readerOrientation
        ]

        for notification in debouncedUpdateNotifications {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.scheduleBackgroundUpdate()
                }
                .store(in: &cancellables)
        }
    }

    private func getSourceInfo(_ sourceId: String) -> (name: String, icon: URL?) {
        if let source = SourceManager.shared.source(for: sourceId) {
            return (source.name, source.imageUrl)
        } else if let module = ModuleManager.shared.modules.first(where: { $0.id.uuidString == sourceId }) {
            return (module.metadata.sourceName, URL(string: module.metadata.iconUrl))
        } else {
            return (sourceId, nil)
        }
    }

    func deleteAll() {
        // clear entries in ui
        withAnimation(.easeOut(duration: 0.3)) {
            downloadedEntries = []
        }

        Task {
            await DownloadManager.shared.deleteAll()
        }
    }

    func delete(entry: any DownloadedEntry) {
        if let index = downloadedEntries.firstIndex(where: { $0.id == entry.id }) {
            downloadedEntries.remove(at: index)
        }

        Task {
            let identifier = MangaIdentifier(sourceKey: entry.sourceId, mangaKey: entry.mangaId)
            await DownloadManager.shared.deleteChapters(for: identifier)
        }
    }

    func confirmDeleteAll() {
        showingDeleteAllConfirmation = true
    }

    func migrate() {
        (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
        Task {
            await DownloadManager.shared.migrateOldMetadata()
            await loadDownloadedManga()
            await (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()
        }
    }
}
