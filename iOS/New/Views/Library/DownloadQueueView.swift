//
//  DownloadQueueView.swift
//  Aidoku
//
//  Created by Skitty on 10/25/25.
//

import SwiftUI

struct DownloadQueueView: View {
    var type: DownloadType?
    @State private var queue: [(sourceId: String, downloads: [Download])] = []
    @State private var progress: [ChapterIdentifier: (progress: Int, total: Int)] = [:]
    @State private var isPaused = false

    @Environment(\.dismiss) private var dismiss

    init(type: DownloadType? = nil) {
        self.type = type
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                if isPaused {
                    Section {
                        let padding: CGFloat = if #available(iOS 26.0, *) {
                            // ios 26 uses larger list cells
                            16
                        } else {
                            12
                        }
                        HStack {
                            Text(NSLocalizedString("DOWNLOADING_PAUSED"))
                            Spacer()
                            Button(NSLocalizedString("RESUME")) {
                                Task {
                                    await DownloadManager.shared.resumeDownloads()
                                }
                            }
                            .buttonStyle(.borderless)
                            .tint(.accentColor)
                        }
                        .padding(padding)
                        .background(Color.accentColor.opacity(0.15))
                        .listRowInsets(.zero)
                        .listRowSpacing(0)
                    }
                }

                ForEach(queue, id: \.sourceId) { section in
                    let info = getSourceInfo(section.sourceId)
                    Section {
                        ForEach(section.downloads) { download in
                            HStack {
                                MangaCoverView(
                                    source: nil,
                                    coverImage: (download.type == .video ? download.posterUrl : download.manga.cover) ?? "",
                                    width: 56,
                                    height: 56 * 3/2,
                                    downsampleWidth: 56
                                )
                                .padding(.trailing, 6)

                                VStack(alignment: .leading) {
                                    Text(download.manga.title)
                                        .lineLimit(3)
                                    Text(download.type == .video ? download.chapter.title ?? "Episode" : download.chapter.formattedTitle())
                                        .foregroundStyle(.secondary)
                                        .font(.callout)
                                        .lineLimit(1)
                                    let progress = self.progress[download.chapterIdentifier]
                                    let value: Float = if let progress {
                                        Float(progress.progress) / Float(progress.total)
                                    } else {
                                        0
                                    }
                                    ProgressView(value: value)
                                        .progressViewStyle(.linear)
                                        .tint(.accentColor)
                                    if let progress {
                                        Text(String(format: NSLocalizedString("%i_OF_%i"), progress.progress, progress.total))
                                            .foregroundStyle(.secondary)
                                            .font(.footnote)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(download: download)
                                    Task {
                                        await DownloadManager.shared.cancelDownload(for: download.chapterIdentifier)
                                    }
                                } label: {
                                    Label(NSLocalizedString("CANCEL"), systemImage: "xmark")
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            SourceIconView(
                                sourceId: section.sourceId,
                                imageUrl: info.icon,
                                iconSize: 20
                            )
                            Text(info.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .contentMarginsPlease(.top, 4)
            .navigationTitle(NSLocalizedString("DOWNLOAD_QUEUE"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                if isPaused {
                                    await DownloadManager.shared.resumeDownloads()
                                } else {
                                    await DownloadManager.shared.pauseDownloads()
                                }
                            }
                        } label: {
                            if isPaused {
                                Label(
                                    NSLocalizedString("RESUME"),
                                    systemImage: "play.fill"
                                )
                            } else {
                                Label(
                                    NSLocalizedString("PAUSE"),
                                    systemImage: "pause"
                                )
                            }
                        }
                        .disabled(queue.isEmpty)
                        Button(role: .destructive) {
                            Task {
                                await DownloadManager.shared.cancelDownloads()
                            }
                        } label: {
                            Label(
                                NSLocalizedString("CANCEL_ALL_DOWNLOADS"),
                                systemImage: "xmark"
                            )
                        }
                        .disabled(queue.isEmpty)
                    } label: {
                        MoreIcon()
                    }
                }
            }
            .task {
                isPaused = await DownloadManager.shared.isQueuePaused()
                let globalQueue = await DownloadManager.shared.getDownloadQueue(type: type)
                var queue: [(String, [Download])] = []
                for queueObject in globalQueue where !queueObject.value.isEmpty {
                    queue.append((queueObject.key, queueObject.value))
                }
                self.queue = queue
                for (_, downloads) in queue {
                    for download in downloads {
                        subscribeToProgress(download: download)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadsPaused)) { _ in
                withAnimation {
                    isPaused = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadsResumed)) { _ in
                withAnimation {
                    isPaused = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadsQueued)) { output in
                guard let downloads = output.object as? [Download] else { return }
                let filteredDownloads = type != nil ? downloads.filter { $0.type == type } : downloads
                for download in filteredDownloads {
                    let index = queue.firstIndex(where: { $0.sourceId == download.chapterIdentifier.sourceKey })
                    var downloads = index != nil ? self.queue[index!].downloads : []
                    downloads.append(download)
                    withAnimation {
                        if let index {
                            queue[index].downloads = downloads
                        } else {
                            queue.append((download.chapterIdentifier.sourceKey, downloads))
                        }
                    }
                    subscribeToProgress(download: download)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadFinished)) { output in
                guard let download = output.object as? Download else { return }
                remove(download: download)
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadCancelled)) { output in
                guard let download = output.object as? Download else { return }
                remove(download: download)
            }
            .onReceive(NotificationCenter.default.publisher(for: .downloadsCancelled)) { _ in
                for (_, downloads) in queue {
                    Task {
                        for download in downloads {
                            await DownloadManager.shared.removeProgressBlock(for: download.chapterIdentifier)
                        }
                    }
                }
                withAnimation {
                    queue.removeAll()
                    isPaused = false
                }
            }
        }
    }

    private func getSourceInfo(_ sourceId: String) -> (name: String, icon: URL?) {
        if let source = SourceManager.shared.source(for: sourceId) {
            return (source.name, source.imageUrl)
        } else if let module = ModuleManager.shared.modules.first(where: { $0.id.uuidString == sourceId }) {
            return (module.metadata.sourceName, URL(string: module.metadata.iconUrl))
        } else {
            return (NSLocalizedString(sourceId, comment: ""), nil)
        }
    }

    func remove(download: Download) {
        guard
            let index = queue.firstIndex(where: { $0.sourceId == download.chapterIdentifier.sourceKey })
        else {
            return
        }
        var downloads = queue[index].downloads
        let indexToRemove = downloads.firstIndex(where: { $0 == download })
        guard let indexToRemove else { return } // nothing to remove
        downloads.remove(at: indexToRemove)
        withAnimation {
            if downloads.isEmpty {
                queue.remove(at: index)
                if queue.isEmpty {
                    isPaused = false
                }
            } else {
                queue[index].downloads = downloads
            }
        }
        Task {
            await DownloadManager.shared.removeProgressBlock(for: download.chapterIdentifier)
            progress.removeValue(forKey: download.chapterIdentifier)
        }
    }

    func subscribeToProgress(download: Download) {
        if download.total > 0 {
            progress[download.chapterIdentifier] = (download.progress, download.total)
        }
        Task {
            await DownloadManager.shared.onProgress(for: download.chapterIdentifier) { progress, total in
                Task { @MainActor in
                    self.progress[download.chapterIdentifier] = (progress, total)
                }
            }
        }
    }
}
