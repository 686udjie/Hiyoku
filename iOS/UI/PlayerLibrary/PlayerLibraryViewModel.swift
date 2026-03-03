//
//  PlayerLibraryViewModel.swift
//  Hiyoku
//
//  Created by 686udjie on 01/03/2026.
//

import UIKit
import Combine
import CoreData
import AidokuRunner

@MainActor
class PlayerLibraryViewModel: ObservableObject {
    struct PlayerLibraryItemInfo: Hashable, Identifiable {
        let id: UUID
        let item: PlayerLibraryItem
        var unread: Int = 0
        var downloads: Int = 0
        var hasUpdatedEpisodes = false

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(unread)
            hasher.combine(downloads)
            hasher.combine(hasUpdatedEpisodes)
            hasher.combine(item)
        }

        static func == (lhs: PlayerLibraryItemInfo, rhs: PlayerLibraryItemInfo) -> Bool {
            lhs.id == rhs.id &&
            lhs.unread == rhs.unread &&
            lhs.downloads == rhs.downloads &&
            lhs.hasUpdatedEpisodes == rhs.hasUpdatedEpisodes &&
            lhs.item == rhs.item
        }
    }

    enum SortMethod: Int, CaseIterable {
        case alphabetical = 0
        case dateAdded

        var title: String {
            switch self {
            case .alphabetical: NSLocalizedString("TITLE", comment: "")
            case .dateAdded: NSLocalizedString("DATE_ADDED", comment: "")
            }
        }

        var ascendingTitle: String {
            switch self {
            case .alphabetical: NSLocalizedString("DESCENDING", comment: "")
            case .dateAdded: NSLocalizedString("OLDEST_FIRST", comment: "")
            }
        }

        var descendingTitle: String {
            switch self {
            case .alphabetical: NSLocalizedString("ASCENDING", comment: "")
            case .dateAdded: NSLocalizedString("NEWEST_FIRST", comment: "")
            }
        }
    }

    enum PinType: String, CaseIterable {
        case none
        case unread
        case updatedEpisodes

        var title: String {
            switch self {
            case .none: NSLocalizedString("PIN_DISABLED")
            case .unread: NSLocalizedString("PIN_UNREAD")
            case .updatedEpisodes: NSLocalizedString("PIN_UPDATED_EPISODES")
            }
        }
    }

    struct BadgeType: OptionSet {
        let rawValue: Int

        static let unwatched = BadgeType(rawValue: 1 << 0)
        static let downloaded = BadgeType(rawValue: 1 << 1)
    }

    enum FilterMethod: Int, Codable, CaseIterable {
        case downloaded
        case hasUnread
        case source

        var title: String {
            switch self {
            case .downloaded: NSLocalizedString("DOWNLOADED", comment: "")
            case .hasUnread: NSLocalizedString("FILTER_HAS_UNREAD", comment: "")
            case .source: NSLocalizedString("SOURCES", comment: "")
            }
        }

        var image: UIImage? {
            switch self {
            case .downloaded: UIImage(systemName: "arrow.down.circle")
            case .hasUnread: UIImage(systemName: "eye.slash")
            case .source: UIImage(systemName: "globe")
            }
        }
    }

    @Published var items: [PlayerLibraryItemInfo] = []
    @Published var pinnedItems: [PlayerLibraryItemInfo] = []

    var originalItems: [PlayerLibraryItem] = []
    @Published var sourceKeys: [String] = [] // Source names or IDs
    var categories: [String] = []
    let core = LibraryCore(prefix: "PlayerLibrary")
    var currentCategory: String? {
        didSet {
            core.saveCurrentCategory(currentCategory)
        }
    }

    var sortMethod: SortMethod = .dateAdded
    var sortAscending: Bool = false
    var pinType: PinType = .none
    var badgeType: BadgeType = []

    var filters: [LibraryFilter<FilterMethod>] = [] {
        didSet {
            core.saveFilters(filters)
        }
    }

    var searchQuery: String = ""
    private var itemCategories: [String: [String]] = LibraryCore(prefix: "PlayerLibrary").loadItemCategories()

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.currentCategory = core.loadCurrentCategory()
        if let sortMethod = SortMethod(rawValue: core.loadSortOption()) {
            self.sortMethod = sortMethod
        }
        self.sortAscending = core.loadSortAscending()
        self.pinType = core.loadPinType(defaultValue: .none)
        if core.unreadBadgeEnabled() {
            badgeType.insert(.unwatched)
        }
        if core.downloadedBadgeEnabled() {
            badgeType.insert(.downloaded)
        }

        self.filters = core.loadFilters()

        PlayerLibraryManager.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.originalItems = items
                Task { @MainActor in
                    await self?.loadLibrary()
                }
            }
            .store(in: &cancellables)
    }

    func saveSettings() {
        core.saveSort(methodRawValue: sortMethod.rawValue, ascending: sortAscending)
    }

    private func saveItemCategories() {
        core.saveItemCategories(itemCategories)
    }

    func getPinType() -> PinType {
        core.loadPinType(defaultValue: .none)
    }

    func refreshCategories() async {
        categories = core.loadCategoriesList()
        _ = core.validateCurrentCategory(categories: categories, currentCategory: &currentCategory)
    }

    func isCategoryLocked() -> Bool {
        core.isCategoryLocked(currentCategory: currentCategory)
    }

    func categories(for item: PlayerLibraryItem) -> [String] {
        itemCategories[item.id.uuidString] ?? []
    }

    func toggleCategory(for item: PlayerLibraryItem, category: String) async {
        var itemValues = itemCategories[item.id.uuidString] ?? []
        if let index = itemValues.firstIndex(of: category) {
            itemValues.remove(at: index)
        } else {
            itemValues.append(category)
        }
        itemCategories[item.id.uuidString] = itemValues
        saveItemCategories()
        await loadLibrary()
    }

    func setSort(method: SortMethod, ascending: Bool) async {
        if sortMethod != method || sortAscending != ascending {
            sortMethod = method
            sortAscending = ascending
            saveSettings()
            await loadLibrary()
        }
    }

    func toggleFilter(method: FilterMethod, value: String? = nil) async {
        core.toggleFilter(filters: &filters, method: method, value: value)
        await loadLibrary()
    }

    func filterState(for method: FilterMethod, value: String? = nil) -> UIMenuElement.State {
        core.filterState(filters: filters, method: method, value: value)
    }

    func refreshLibrary() async {
        await loadLibrary()
    }
    // MARK: - Targeted Updates
    func updateDownloadCount(for identifier: MangaIdentifier) async {
        let title = findItemTitle(for: identifier)
        let newCount = await LibraryCellUI.fetchDownloadCount(for: identifier, title: title)
        await updateCount(for: identifier, newCount: newCount, keyPath: \.downloads)
    }
    func updateUnreadCount(for identifier: MangaIdentifier) async {
        let newCount = await LibraryCellUI.fetchUnreadCount(for: identifier)
        await updateCount(for: identifier, newCount: newCount, keyPath: \.unread)
    }
    private func findItemTitle(for identifier: MangaIdentifier) -> String? {
        items.first {
            $0.item.moduleId.uuidString == identifier.sourceKey &&
            $0.item.sourceUrl.normalizedModuleHref() == identifier.mangaKey
        }?.item.title ?? pinnedItems.first {
            $0.item.moduleId.uuidString == identifier.sourceKey &&
            $0.item.sourceUrl.normalizedModuleHref() == identifier.mangaKey
        }?.item.title
    }
    private func updateCount<T: Equatable>(for identifier: MangaIdentifier, newCount: T, keyPath: WritableKeyPath<PlayerLibraryItemInfo, T>) async {
        var didUpdate = false
        // Update pinned items
        for (i, item) in pinnedItems.enumerated() {
            if item.item.moduleId.uuidString == identifier.sourceKey &&
               item.item.sourceUrl.normalizedModuleHref() == identifier.mangaKey {
                if pinnedItems[i][keyPath: keyPath] != newCount {
                    pinnedItems[i][keyPath: keyPath] = newCount
                    didUpdate = true
                }
            }
        }
        // Update regular items
        for (i, item) in items.enumerated() {
            if item.item.moduleId.uuidString == identifier.sourceKey &&
               item.item.sourceUrl.normalizedModuleHref() == identifier.mangaKey {
                if items[i][keyPath: keyPath] != newCount {
                    items[i][keyPath: keyPath] = newCount
                    didUpdate = true
                }
            }
        }

        // Re-sort if needed
        if didUpdate && pinType == .unread {
            await loadLibrary()
        }
    }

    // MARK: - Batch Actions

    func markEpisodes(items: [PlayerLibraryItem], watched: Bool) async {
        for item in items {
            let episodes = await fetchEpisodes(for: item)
            for episode in episodes {
                if watched {
                    let data = PlayerHistoryManager.EpisodeHistoryData(
                        playerTitle: item.title, episodeId: episode.url,
                        episodeNumber: Double(episode.number), episodeTitle: episode.title,
                        sourceUrl: episode.url, moduleId: item.moduleId.uuidString,
                        progress: 100, total: 100, watchedDuration: 0, date: Date()
                    )
                    await PlayerHistoryManager.shared.setProgress(data: data)
                } else {
                    await PlayerHistoryManager.shared.removeHistory(
                        episodeId: episode.url, moduleId: item.moduleId.uuidString
                    )
                }
            }
        }
    }

    func downloadBatch(items: [PlayerLibraryItem], unwatchedOnly: Bool) async {
        for item in items {
            let episodes = await fetchEpisodes(for: item)
            var targets = episodes
            if unwatchedOnly {
                let history = await CoreDataManager.shared.getPlayerReadingHistory(
                    sourceId: item.moduleId.uuidString,
                    mangaId: item.sourceUrl.normalizedModuleHref()
                )
                let watched = Set(history.filter {
                    $0.value.progress > 0 && $0.value.progress == $0.value.total
                }.keys)
                targets = episodes.filter { !watched.contains($0.url) }
            }
            guard let module = ModuleManager.shared.modules.first(where: { $0.id == item.moduleId }),
                  !targets.isEmpty else { continue }
            await DownloadManager.shared.downloadVideo(
                seriesTitle: item.title, episodes: targets,
                sourceKey: module.id.uuidString,
                seriesKey: item.sourceUrl.normalizedModuleHref(),
                posterUrl: item.imageUrl
            )
        }
    }

    private func fetchEpisodes(for item: PlayerLibraryItem) async -> [PlayerEpisode] {
        guard let module = ModuleManager.shared.modules.first(where: { $0.id == item.moduleId }) else {
            return []
        }
        return await JSController.shared.fetchPlayerEpisodes(contentUrl: item.sourceUrl, module: module)
    }

    func loadLibrary() async {
        let counts = await PlayerLibraryManager.shared.fetchLibraryCounts(for: originalItems)
        let itemInfos = originalItems.map { item in
            let itemCount = counts[item.id] ?? PlayerLibraryManager.ItemCounts(unread: 0, downloads: 0, hasUpdatedEpisodes: false)
            return PlayerLibraryItemInfo(
                id: item.id,
                item: item,
                unread: itemCount.unread,
                downloads: itemCount.downloads,
                hasUpdatedEpisodes: itemCount.hasUpdatedEpisodes
            )
        }

        var filtered = itemInfos

        if let currentCategory {
            filtered = filtered.filter {
                (itemCategories[$0.item.id.uuidString] ?? []).contains(currentCategory)
            }
        }

        if !searchQuery.isEmpty {
            filtered = filtered.filter { $0.item.title.localizedCaseInsensitiveContains(searchQuery) }
        }

        for filter in filters {
            let condition: (PlayerLibraryItemInfo) -> Bool
            switch filter.type {
            case .downloaded:
                condition = { $0.downloads > 0 }
            case .hasUnread:
                condition = { $0.unread > 0 }
            case .source:
                condition = { $0.item.moduleName == filter.value }
            }

            filtered = filtered.filter { itemInfo in
                let matches = condition(itemInfo)
                return filter.exclude ? !matches : matches
            }
        }

        filtered.sort { lhs, rhs in
            switch sortMethod {
            case .alphabetical:
                return sortAscending ? lhs.item.title < rhs.item.title : lhs.item.title > rhs.item.title
            case .dateAdded:
                return sortAscending ? lhs.item.dateAdded < rhs.item.dateAdded : lhs.item.dateAdded > rhs.item.dateAdded
            }
        }

        switch pinType {
        case .none:
            self.pinnedItems = []
            self.items = filtered
        case .unread:
            self.pinnedItems = filtered.filter { $0.unread > 0 }
            self.items = filtered.filter { $0.unread == 0 }
        case .updatedEpisodes:
            self.pinnedItems = filtered.filter { $0.hasUpdatedEpisodes }
            self.items = filtered.filter { !$0.hasUpdatedEpisodes }
        }
        let uniqueSources = Set(originalItems.map { $0.moduleName })
        self.sourceKeys = Array(uniqueSources).sorted()
    }

    func search(query: String) async {
        self.searchQuery = query
        await loadLibrary()
    }
}
