//
//  PlayerInfoView+ViewModel.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Combine
import SwiftUI
import CoreData

extension PlayerInfoView {
    struct InlineEpisodeHistory: Equatable {
        let progress: Int
        let total: Int?
    }

    @MainActor
    class ViewModel: ObservableObject {
        private let libraryManager = PlayerLibraryManager.shared
        private let moduleManager = ModuleManager.shared

        private var bookmark: PlayerLibraryItem?
        private var searchItem: SearchItem?
        private(set) var module: ScrapingModule?
        @Published var episodes: [PlayerEpisode] = [] {
            didSet { recomputeSortedEpisodes() }
        }
        @Published private(set) var sortedEpisodes: [PlayerEpisode] = []
        @Published var isLoadingEpisodes = false
        @Published var isBookmarked = false
        @Published var episodeProgress: [String: InlineEpisodeHistory] = [:]

        private var cancellables = Set<AnyCancellable>()

        // Cached computed properties to avoid expensive lookups during rendering
        let title: String
        let posterUrl: String

        // Episode sorting/filtering
        @Published var episodeSortOption: EpisodeSortOption = .sourceOrder {
            didSet { recomputeSortedEpisodes() }
        }
        @Published var episodeSortAscending = true {
            didSet { recomputeSortedEpisodes() }
        }

        var contentUrl: String? {
            if let bookmark = currentBookmark, !bookmark.sourceUrl.isEmpty {
                return bookmark.sourceUrl
            }
            if let href = searchItem?.href, !href.isEmpty {
                return href
            }
            return nil
        }

        var description: String? {
            nil
        }

        var sourceName: String? {
            if let bookmark = bookmark {
                return bookmark.moduleName
            } else if let module = module {
                return module.metadata.sourceName
            }
            return nil
        }

        var bookmarkId: UUID? {
            if let bookmark = bookmark {
                return bookmark.id
            } else if let searchItem = searchItem, let module = module {
                return libraryManager.getLibraryItemId(for: searchItem, module: module)
            }
            return nil
        }

        var currentBookmark: PlayerLibraryItem? {
            if let bookmark = bookmark {
                return bookmark
            } else if searchItem != nil, module != nil, let bookmarkId = bookmarkId {
                return libraryManager.items.first(where: { $0.id == bookmarkId })
            }
            return nil
        }

        init(bookmark: PlayerLibraryItem) {
            self.bookmark = bookmark
            self.isBookmarked = true
            if let module = moduleManager.modules.first(where: { $0.id == bookmark.moduleId }) {
                self.module = module
            }

        // Cache expensive computed properties
            self.title = bookmark.title
            self.posterUrl = libraryManager.items.first(where: { $0.id == bookmark.id })?.imageUrl ?? bookmark.imageUrl

        setupBookmarkObserver()
            // Don't call recomputeSortedEpisodes() here since episodes is empty initially
        }

        init(searchItem: SearchItem, module: ScrapingModule) {
            self.searchItem = searchItem
            self.module = module
            self.isBookmarked = libraryManager.isInLibrary(searchItem, module: module)

        // Cache expensive computed properties
            self.title = searchItem.title
            self.posterUrl = searchItem.imageUrl

        setupBookmarkObserver()
            // Don't call recomputeSortedEpisodes() here since episodes is empty initially
        }

        private func setupBookmarkObserver() {
            libraryManager.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        func refresh() async {
            await loadEpisodes()
        }

        func loadEpisodes() async {
            isLoadingEpisodes = true

            guard let module = module else {
                episodes = []
                sortedEpisodes = []
                isLoadingEpisodes = false
                return
            }

            let playerUrl: String
            if let bookmark = bookmark, !bookmark.sourceUrl.isEmpty {
                playerUrl = bookmark.sourceUrl.normalizedModuleHref()
            } else if let searchItem = searchItem, !searchItem.href.isEmpty {
                playerUrl = searchItem.href.normalizedModuleHref()
            } else if let bookmark = bookmark {
                if let url = await searchForPlayerUrl(title: bookmark.title, module: module) {
                    await loadEpisodesFromUrl(url, module: module)
                } else {
                    await MainActor.run {
                        self.episodes = []
                        self.sortedEpisodes = []
                        self.isLoadingEpisodes = false
                    }
                }
                return
            } else {
                episodes = []
                sortedEpisodes = []
                isLoadingEpisodes = false
                return
            }

            await loadEpisodesFromUrl(playerUrl, module: module)
        }
        private func loadEpisodesFromUrl(_ playerUrl: String, module: ScrapingModule) async {
            let normalizedUrl = playerUrl.normalizedModuleHref()
            let episodes = await JSController.shared.fetchPlayerEpisodes(contentUrl: normalizedUrl, module: module)
            self.episodes = episodes
            self.isLoadingEpisodes = false
            await fetchHistory()
        }
        func fetchHistory() async {
            guard let module = module else { return }
            let map: [String: InlineEpisodeHistory] = await CoreDataManager.shared.container.performBackgroundTask { context in
                var results: [String: InlineEpisodeHistory] = [:]
                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "PlayerHistory")
                fetchRequest.predicate = NSPredicate(format: "moduleId == %@", module.id.uuidString)
                do {
                    let historyObjects = try context.fetch(fetchRequest)
                    for obj in historyObjects {
                        if let episodeId = obj.value(forKey: "episodeId") as? String,
                           let progress = obj.value(forKey: "progress") as? Int16 {
                            let total = obj.value(forKey: "total") as? Int16
                            results[episodeId] = InlineEpisodeHistory(
                                progress: Int(progress),
                                total: total.map(Int.init)
                            )
                        }
                    }
                } catch {
                    print("Error fetching history in ViewModel: \(error)")
                }
                return results
            }
            await MainActor.run {
                self.episodeProgress = map
            }
        }

        private func searchForPlayerUrl(title: String, module: ScrapingModule) async -> String? {
            let searchResults = await JSController.shared.fetchJsSearchResults(keyword: title, module: module)
            let match = searchResults.first { item in
                item.title.lowercased() == title.lowercased() ||
                item.title.lowercased().contains(title.lowercased()) ||
                title.lowercased().contains(item.title.lowercased())
            } ?? searchResults.first

        guard let match = match else {
                return nil
        }

        let fullUrl = match.href.absoluteUrl(withBaseUrl: module.metadata.baseUrl)
            if let bookmark = self.bookmark, bookmark.sourceUrl.isEmpty {
                self.libraryManager.updateItemSourceUrl(itemId: bookmark.id, sourceUrl: fullUrl)
        }

        return fullUrl
        }

        func toggleBookmark() {
            guard let module = module else { return }

            if let searchItem = searchItem {
                libraryManager.toggleInLibrary(for: searchItem, module: module)
                isBookmarked = libraryManager.isInLibrary(searchItem, module: module)
            } else if let bookmark = bookmark {
                let tempSearchItem = SearchItem(title: bookmark.title, imageUrl: bookmark.imageUrl, href: bookmark.sourceUrl)
                libraryManager.toggleInLibrary(for: tempSearchItem, module: module)
                isBookmarked = libraryManager.isInLibrary(tempSearchItem, module: module)
            }
        }

        private func recomputeSortedEpisodes() {
            // Only recompute if we have episodes to avoid unnecessary work
            guard !episodes.isEmpty else {
                sortedEpisodes = []
                return
            }

            let sorted = episodes.sorted { lhs, rhs in
                episodeSortAscending ? lhs.number < rhs.number : lhs.number > rhs.number
            }
            self.sortedEpisodes = sorted
        }
    }
}
