//
//  PlayerLibraryManager.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation
import Combine
import UIKit
import AidokuRunner
import CoreData

@MainActor
class PlayerLibraryManager: ObservableObject {
    static let shared = PlayerLibraryManager()

    @Published var items: [PlayerLibraryItem] = []

    private let libraryKey = "PlayerLibrary"
    private let legacyBookmarksKey = "PlayerBookmarks"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadLibrary()
        setupNotifications()
    }

    private func loadLibrary() {
        if let data = UserDefaults.standard.data(forKey: libraryKey),
           let decoded = try? JSONDecoder().decode([PlayerLibraryItem].self, from: data) {
            items = migrateItemsIfNeeded(decoded)
            saveLibrary()
            return
        }

        if let data = UserDefaults.standard.data(forKey: legacyBookmarksKey),
           let decoded = try? JSONDecoder().decode([PlayerLibraryItem].self, from: data) {
            items = migrateItemsIfNeeded(decoded)
            saveLibrary()
            UserDefaults.standard.removeObject(forKey: legacyBookmarksKey)
        }
    }

    private func migrateItemsIfNeeded(_ items: [PlayerLibraryItem]) -> [PlayerLibraryItem] {
        items.map { item in
            var migratedItem = item
            if migratedItem.originalImageUrl == nil && !migratedItem.hasCustomCover {
                migratedItem.originalImageUrl = migratedItem.imageUrl
            }
            return migratedItem
        }
    }

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: libraryKey)
        }
    }

    func addToLibrary(_ item: PlayerLibraryItem) {
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
            saveLibrary()
        }
    }

    func removeFromLibrary(_ item: PlayerLibraryItem) {
        items.removeAll { $0.id == item.id }
        saveLibrary()
    }

    func getLibraryItemId(for searchItem: SearchItem, module: ScrapingModule) -> UUID? {
        items.first(where: {
            $0.title == searchItem.title &&
            $0.imageUrl == searchItem.imageUrl &&
            $0.moduleId == module.id
        })?.id
    }

    func toggleInLibrary(for searchItem: SearchItem, module: ScrapingModule) {
        if let existingItem = items.first(where: {
            $0.sourceUrl == searchItem.href && $0.moduleId == module.id
        }) {
            removeFromLibrary(existingItem)
        } else {
            let sourceUrl = searchItem.href.isEmpty ? "" : searchItem.href
            let newItem = PlayerLibraryItem(
                title: searchItem.title,
                imageUrl: searchItem.imageUrl,
                sourceUrl: sourceUrl,
                moduleId: module.id,
                moduleName: module.metadata.sourceName,
                originalImageUrl: searchItem.imageUrl
            )
            addToLibrary(newItem)
        }
    }

    func isInLibrary(_ searchItem: SearchItem, module: ScrapingModule) -> Bool {
        items.contains { $0.sourceUrl == searchItem.href && $0.moduleId == module.id }
    }
    func updateItemSourceUrl(itemId: UUID, sourceUrl: String) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].sourceUrl = sourceUrl
            saveLibrary()
        }
    }

    func setCover(item: PlayerLibraryItem, cover: PlatformImage) async -> String? {
        let documentsDirectory = FileManager.default.documentDirectory
        let targetDirectory = documentsDirectory.appendingPathComponent("Covers")
        let ext = if #available(iOS 17.0, *) {
            "heic"
        } else {
            "png"
        }
        var targetUrl = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        while targetUrl.exists {
            targetUrl = targetDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        }

        targetDirectory.createDirectory()

        do {
            let data = if #available(iOS 17.0, *) {
#if !os(macOS)
                cover.heicData()
#else
                cover.pngData()
#endif
            } else {
                cover.pngData()
            }
            try data?.write(to: targetUrl)
        } catch {
            return nil
        }

        let coverUrl = "aidoku-image:///Covers/\(targetUrl.lastPathComponent)"

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            if items[index].originalImageUrl == nil && !items[index].hasCustomCover {
                items[index].originalImageUrl = items[index].imageUrl
            }
            items[index].imageUrl = coverUrl
            items[index].hasCustomCover = true
            saveLibrary()
        } else {
            return nil
        }

        return coverUrl
    }

    func resetCover(item: PlayerLibraryItem) async -> String? {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            if let originalUrl = items[index].originalImageUrl {
                items[index].imageUrl = originalUrl
                items[index].originalImageUrl = nil
                items[index].hasCustomCover = false
                saveLibrary()
                return originalUrl
            }
        }
        return nil
    }
    func checkForUpdates() async {
        var moduleItems: [UUID: [PlayerLibraryItem]] = [:]
        for item in items {
            if moduleItems[item.moduleId] == nil {
                moduleItems[item.moduleId] = []
            }
            moduleItems[item.moduleId]?.append(item)
        }
        // Fetch episodes in parallel
        let updates = await withTaskGroup(of: (PlayerLibraryItem, [PlayerEpisode]).self) { group in
            for (_, items) in moduleItems {
                guard
                    let firstItem = items.first,
                    let module = ModuleManager.shared.modules.first(where: { $0.id == firstItem.moduleId })
                else { continue }
                for item in items {
                    group.addTask {
                        let fetchedEpisodes = await JSController.shared.fetchPlayerEpisodes(
                            contentUrl: item.sourceUrl,
                            module: module
                        )
                        return (item, fetchedEpisodes)
                    }
                }
            }
            var results: [(PlayerLibraryItem, [PlayerEpisode])] = []
            for await result in group where !result.1.isEmpty {
                results.append(result)
            }
            return results
        }
        guard !updates.isEmpty else { return }
        let allModules = ModuleManager.shared.modules
        await CoreDataManager.shared.container.performBackgroundTask { context in
            var hasNewUpdates = false
            for (item, fetchedEpisodes) in updates {
                guard let module = allModules.first(where: { $0.id == item.moduleId }) else { continue }
                let sourceId = module.id.uuidString
                let animeId = item.sourceUrl.normalizedModuleHref()
                // ensure anime exists
                _ = CoreDataManager.shared.getOrCreateManga(
                    AidokuRunner.Manga(
                        sourceKey: sourceId,
                        key: animeId,
                        title: item.title,
                        cover: item.imageUrl,
                        url: URL(string: item.sourceUrl)
                    ),
                    sourceId: sourceId,
                    context: context
                )
                let episodesToSave = fetchedEpisodes.map { $0.toTrackableEpisode(sourceId: sourceId, mangaId: animeId) }
                let existingEpisodes = CoreDataManager.shared.getChapters(
                    sourceId: sourceId,
                    mangaId: animeId,
                    context: context
                )
                let existingIds = Set(existingEpisodes.map { $0.id })
                let newEpisodes = CoreDataManager.shared.setChapters(
                    episodesToSave,
                    sourceId: sourceId,
                    mangaId: animeId,
                    context: context
                )
                // create update objects for new episodes
                for episode in newEpisodes where !existingIds.contains(episode.id) {
                    CoreDataManager.shared.createMangaUpdate(
                        sourceId: sourceId,
                        mangaId: animeId,
                        chapterObject: episode,
                        context: context
                    )
                    hasNewUpdates = true
                }
            }
            if hasNewUpdates {
               try? context.save()
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .updatePlayerLibrary, object: nil)
        }
    }

    private func setupNotifications() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.saveLibrary()
            }
            .store(in: &cancellables)
        #endif
    }
}
