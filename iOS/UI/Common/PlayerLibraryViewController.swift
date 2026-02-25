//
//  PlayerLibraryViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/05/26.
//

import UIKit
import SwiftUI
import NukeUI
import Nuke
import AidokuRunner
import Combine
import CoreData

struct PlayerLibrarySearchResult: Identifiable {
    let id = UUID()
    let title: String
    let imageUrl: String
    let href: String
    let module: ScrapingModule
}

@MainActor
class PlayerLibrarySearchViewModel: ObservableObject {
    @Published var results: [PlayerLibrarySearchResult] = []
    @Published var isLoading = false

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        Task {
            await loadPlayerContent()
        }
    }

    private func loadPlayerContent() async {
        // Show module browsing options
        let playerModules = ModuleManager.shared.modules.filter { $0.isActive }
        var allResults: [PlayerLibrarySearchResult] = []

        for module in playerModules {
            let result = PlayerLibrarySearchResult(
                title: "Browse \(module.metadata.sourceName)",
                imageUrl: module.metadata.iconUrl,
                href: "",
                module: module
            )
            allResults.append(result)
        }

        results = allResults
    }

    func search(query: String) {
        if query.isEmpty {
            Task {
                await loadPlayerContent()
            }
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            isLoading = true
            await performPlayerSearch(query: query)
            isLoading = false
        }
    }

    private func performPlayerSearch(query: String) async {
        let playerModules = ModuleManager.shared.modules.filter { $0.isActive }
        var searchResults: [PlayerLibrarySearchResult] = []

        // Search through each player module concurrently
        await withTaskGroup(of: [PlayerLibrarySearchResult].self) { group in
            for module in playerModules {
                group.addTask {
                    var moduleResults: [PlayerLibrarySearchResult] = []
                    // Use JavaScript search for player modules (same as global search)
                    let searchItems = await withCheckedContinuation { continuation in
                        JSController.shared.fetchJsSearchResults(keyword: query, module: module) { items in
                            continuation.resume(returning: items)
                        }
                    }
                    for item in searchItems {
                        let result = PlayerLibrarySearchResult(
                            title: item.title,
                            imageUrl: item.imageUrl,
                            href: item.href,
                            module: module
                        )
                        moduleResults.append(result)
                    }
                    return moduleResults
                }
            }

            for await moduleResults in group {
                searchResults.append(contentsOf: moduleResults)
            }
        }

        if !Task.isCancelled {
            results = searchResults
        }
    }
}

// MARK: - PlayerSortingTab
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

    struct ItemCounts {
        let unread: Int
        let downloads: Int
        let hasUpdatedEpisodes: Bool
    }

    struct LibraryFilter: Codable, Equatable {
        var type: FilterMethod
        var value: String?
        var exclude: Bool
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

    var sortMethod: SortMethod = .dateAdded
    var sortAscending: Bool = false
    var pinType: PinType = .none
    var badgeType: BadgeType = []

    var filters: [LibraryFilter] = [] {
        didSet {
            saveFilters()
        }
    }

    var searchQuery: String = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        if let sortMethod = SortMethod(rawValue: UserDefaults.standard.integer(forKey: "PlayerLibrary.sortOption")) {
            self.sortMethod = sortMethod
        }
        self.sortAscending = UserDefaults.standard.bool(forKey: "PlayerLibrary.sortAscending")
        self.pinType = getPinType()
        if UserDefaults.standard.bool(forKey: "PlayerLibrary.unreadChapterBadges") {
            badgeType.insert(.unwatched)
        }
        if UserDefaults.standard.bool(forKey: "PlayerLibrary.downloadedChapterBadges") {
            badgeType.insert(.downloaded)
        }

        if let filtersData = UserDefaults.standard.data(forKey: "PlayerLibrary.filters"),
           let filters = try? JSONDecoder().decode([LibraryFilter].self, from: filtersData) {
            self.filters = filters
        }

        PlayerLibraryManager.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.originalItems = items
                Task {
                    await self?.loadLibrary()
                }
            }
            .store(in: &cancellables)
    }

    func saveSettings() {
        UserDefaults.standard.set(sortMethod.rawValue, forKey: "PlayerLibrary.sortOption")
        UserDefaults.standard.set(sortAscending, forKey: "PlayerLibrary.sortAscending")
    }

    func getPinType() -> PinType {
        UserDefaults.standard.string(forKey: "PlayerLibrary.pinTitles").flatMap(PinType.init) ?? .none
    }

    private func saveFilters() {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: "PlayerLibrary.filters")
        }
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
        if let index = filters.firstIndex(where: { $0.type == method && $0.value == value }) {
            if filters[index].exclude {
                filters.remove(at: index)
            } else {
                filters[index].exclude = true
            }
        } else {
            filters.append(LibraryFilter(type: method, value: value, exclude: false))
        }
        await loadLibrary()
    }

    func filterState(for method: FilterMethod, value: String? = nil) -> UIMenuElement.State {
        if let filter = filters.first(where: { $0.type == method && $0.value == value }) {
            return filter.exclude ? .mixed : .on
        }
        return .off
    }

    func loadLibrary() async {
        let itemInfos = await fetchCounts(for: originalItems)

        var filtered = itemInfos

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
            self.pinnedItems = filtered.filter(\.hasUpdatedEpisodes)
            self.items = filtered.filter { !$0.hasUpdatedEpisodes }
        }
        let uniqueSources = Set(originalItems.map { $0.moduleName })
        self.sourceKeys = Array(uniqueSources).sorted()
    }

    func search(query: String) async {
        self.searchQuery = query
        await loadLibrary()
    }

    private func fetchCounts(for items: [PlayerLibraryItem]) async -> [PlayerLibraryItemInfo] {
        await withTaskGroup(of: PlayerLibraryItemInfo?.self) { group in
            for item in items {
                group.addTask {
                    let counts = await self.fetchCount(for: item)
                    return PlayerLibraryItemInfo(
                        id: item.id,
                        item: item,
                        unread: counts.unread,
                        downloads: counts.downloads,
                        hasUpdatedEpisodes: counts.hasUpdatedEpisodes
                    )
                }
            }

            var results: [PlayerLibraryItemInfo] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
    }

    private func fetchCount(for item: PlayerLibraryItem) async -> ItemCounts {
        guard let module = await MainActor.run(body: {
            ModuleManager.shared.modules.first(where: { $0.id == item.moduleId })
        }) else { return ItemCounts(unread: 0, downloads: 0, hasUpdatedEpisodes: false) }

        let sourceId = module.id.uuidString
        let animeId = item.sourceUrl.normalizedModuleHref()

        var unread = 0
        let episodes = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getChapters(sourceId: sourceId, mangaId: animeId, context: context)
                .compactMap { $0.id }
        }
        if !episodes.isEmpty {
            let history = await CoreDataManager.shared.getPlayerReadingHistory(sourceId: sourceId, mangaId: animeId)
            let readIds = Set(history.filter { $0.value.progress > 0 && $0.value.progress == $0.value.total }.keys)
            unread = episodes.filter { !readIds.contains($0) }.count
        }

        let sourceName = module.metadata.sourceName
        let candidates: [(String?, String?)] = [
            (sourceId, animeId),
            (sourceId, item.title),
            (sourceName, animeId),
            (sourceName, item.title)
        ]
        var downloads = 0
        for (src, key) in candidates {
            if let src = src, let key = key {
                let count = await DownloadManager.shared.downloadsCount(for: MangaIdentifier(sourceKey: src, mangaKey: key))
                if count > 0 {
                    downloads = count
                    break
                }
            }
        }

        let hasUpdatedEpisodes = await CoreDataManager.shared.container.performBackgroundTask { context in
            !CoreDataManager.shared.getUnviewedMangaUpdates(
                sourceId: sourceId,
                mangaId: animeId,
                context: context
            ).isEmpty
        }

        return ItemCounts(unread: unread, downloads: downloads, hasUpdatedEpisodes: hasUpdatedEpisodes)
    }

    func refreshLibrary() async {
        await loadLibrary()
    }
}

class PlayerLibraryViewController: BaseObservingViewController {
    private let path = NavigationCoordinator(rootViewController: nil)
    private var searchController: UISearchController!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
    private lazy var dataSource = makeDataSource()
    private var currentItems: [PlayerLibraryEntry] = []
    private lazy var emptyStackView = EmptyPageStackView()
    private var libraryObserver: AnyCancellable?
    private var downloadObservers = Set<AnyCancellable>()
    private var searchResultsObserver: AnyCancellable?

    private let viewModel = PlayerLibraryViewModel()
    private let searchViewModel = PlayerLibrarySearchViewModel()

    private var searchText = ""

    private lazy var deleteToolbarButton: UIBarButtonItem = {
        let item = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(removeSelectedFromLibrary)
        )
        item.image = UIImage(systemName: "trash")
        if #unavailable(iOS 26.0) {
            item.tintColor = .systemRed
        }
        return item
    }()

    private static let itemSpacing: CGFloat = 12
    private static let sectionSpacing: CGFloat = 6 // extra spacing betweeen sections

    private var usesListLayout: Bool {
        get {
            UserDefaults.standard.bool(forKey: "PlayerLibrary.listView")
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "PlayerLibrary.listView")
        }
    }

    private func makeBarButton(systemName: String, action: Selector?, titleKey: String) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: systemName),
            style: .plain,
            target: self,
            action: action
        )
        item.title = NSLocalizedString(titleKey)
        if #available(iOS 26.0, *) {
            item.sharesBackground = false
        }
        return item
    }

    private lazy var downloadBarButton = makeBarButton(
        systemName: "square.and.arrow.down",
        action: #selector(openDownloadQueue),
        titleKey: "DOWNLOAD_QUEUE"
    )

    private lazy var updatesBarButton = makeBarButton(
        systemName: "bell",
        action: #selector(openUpdates),
        titleKey: "MANGA_UPDATES"
    )

    private lazy var moreBarButton = makeBarButton(
        systemName: "ellipsis",
        action: nil,
        titleKey: "MORE_BARBUTTON"
    )

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        updateNavbarItems()
        updateToolbar()

        for cell in collectionView.visibleCells {
            if let cell = cell as? MangaGridCell {
                cell.setEditing(editing, animated: animated)
            } else if let cell = cell as? MangaListCell {
                cell.setEditing(editing, animated: animated)
            }
        }
    }

    override func configure() {
        super.configure()

        // Configure navigation bar to match LibraryViewController
        title = NSLocalizedString("PLAYER")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        // Create NavigationCoordinator with the navigation controller
        path.rootViewController = self.navigationController

        // Set up search controller like LibraryViewController
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search in Player"
        navigationItem.searchController = searchController

        // Configure collection view (reader-style)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.register(MangaGridCell.self, forCellWithReuseIdentifier: "MangaGridCell")
        collectionView.register(MangaListCell.self, forCellWithReuseIdentifier: "MangaListCell")
        collectionView.dataSource = dataSource
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.allowsMultipleSelection = !ProcessInfo.processInfo.isMacCatalystApp
        collectionView.allowsSelectionDuringEditing = true
        view.addSubview(collectionView)

        Task {
            await SourceManager.shared.loadSources()
            await DownloadManager.shared.loadQueueState()
            updateNavbarItems()
        }

        // Set up empty state view (add after SwiftUI view so it's on top)
        emptyStackView.isHidden = true
        emptyStackView.imageSystemName = "play.tv.fill"
        emptyStackView.title = NSLocalizedString("PLAYER_EMPTY", comment: "")
        emptyStackView.text = NSLocalizedString("PLAYER_ADD_CONTENT", comment: "")
        view.addSubview(emptyStackView)

        // Observe view model changes
        viewModel.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySnapshot(animated: true)
            }
            .store(in: &downloadObservers)

        let searchObserver = searchViewModel.$results
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySnapshot(animated: true)
            }

        searchObserver.store(in: &downloadObservers)
        searchResultsObserver = searchObserver

        toolbarItems = [
            deleteToolbarButton,
            UIBarButtonItem(systemItem: .flexibleSpace)
        ]

        applySnapshot(animated: false)
        updateMoreMenu()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.searchController = searchController
        navigationController?.navigationBar.layoutIfNeeded()
        updateNavbarItems()
        updateMoreMenu()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // hack to show search bar on initial presentation (match LibraryViewController)
        if !navigationItem.hidesSearchBarWhenScrolling {
            UIView.performWithoutAnimation {
                navigationItem.hidesSearchBarWhenScrolling = true
                navigationController?.navigationBar.layoutIfNeeded()
            }
        }
    }

    override func constrain() {
        super.constrain()

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        emptyStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func updateEmptyState() {
        let isSearching = !searchText.isEmpty
        let isEmpty = viewModel.items.isEmpty && viewModel.pinnedItems.isEmpty && !isSearching
        emptyStackView.isHidden = !isEmpty
    }

    override func observe() {
        super.observe()

        let invalidateLayout: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.collectionView.collectionViewLayout.invalidateLayout()
            }
        }

        [
            "General.portraitRows",
            "General.landscapeRows"
        ].forEach { name in
            addObserver(forName: name, using: invalidateLayout)
        }

        let refreshLibrary: (Notification) -> Void = { [weak self] _ in
            Task {
                await self?.viewModel.refreshLibrary()
            }
        }

        [
            .playerHistoryAdded,
            .playerHistoryUpdated,
            .playerHistoryRemoved,
            .downloadFinished,
            .downloadRemoved,
            .downloadCancelled,
            .downloadsRemoved,
            .downloadsCancelled,
            .downloadsQueued,
            .updatePlayerLibrary
        ].forEach { name in
            addObserver(forName: name, using: refreshLibrary)
        }

        addObserver(forName: Notification.Name("PlayerLibrary.unreadChapterBadges")) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: "PlayerLibrary.unreadChapterBadges") {
                self.viewModel.badgeType.insert(.unwatched)
            } else {
                self.viewModel.badgeType.remove(.unwatched)
            }
            self.reloadItems()
        }

        addObserver(forName: Notification.Name("PlayerLibrary.downloadedChapterBadges")) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: "PlayerLibrary.downloadedChapterBadges") {
                self.viewModel.badgeType.insert(.downloaded)
            } else {
                self.viewModel.badgeType.remove(.downloaded)
            }
            self.reloadItems()
        }

        addObserver(forName: Notification.Name("PlayerLibrary.pinTitles")) { [weak self] _ in
            guard let self else { return }
            self.viewModel.pinType = self.viewModel.getPinType()
            Task {
                await self.viewModel.refreshLibrary()
            }
        }

        let checkNavbarDownloadButton: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // We recreate the array to ensure order: [downloadBarButton, updatesBarButton, moreBarButton]
                // But check visibility first.
                self.updateNavbarItems()
            }
        }
        addObserver(forName: .downloadsQueued) { notification in
            checkNavbarDownloadButton(notification)
        }
        addObserver(forName: .downloadFinished) { notification in
            checkNavbarDownloadButton(notification)
        }
        addObserver(forName: .downloadCancelled) { notification in
            checkNavbarDownloadButton(notification)
        }
        addObserver(forName: .downloadsCancelled) { notification in
            checkNavbarDownloadButton(notification)
        }
        addObserver(forName: .downloadsPaused) { notification in
            checkNavbarDownloadButton(notification)
        }
        addObserver(forName: .downloadsResumed) { notification in
            checkNavbarDownloadButton(notification)
        }
    }
}

extension PlayerLibraryViewController {
    func updateNavbarItems() {
        if isEditing {
            LibraryEditingUI.applyEditingNavbar(
                navigationItem: navigationItem,
                collectionView: collectionView,
                totalItemCount: dataSource.snapshot().itemIdentifiers.count,
                config: .init(
                    stopEditingTarget: self,
                    stopEditingSelector: #selector(stopEditing),
                    selectAllTarget: self,
                    selectAllSelector: #selector(selectAllItems),
                    deselectAllTarget: self,
                    deselectAllSelector: #selector(deselectAllItems)
                )
            )
            return
        }

        navigationItem.leftBarButtonItem = nil

        Task { @MainActor in
            let hasDownloads = await DownloadManager.shared.hasQueuedDownloads(type: .video)
            var items: [UIBarButtonItem] = [moreBarButton, updatesBarButton]
            if hasDownloads {
                items.insert(downloadBarButton, at: 1)
            }
            navigationItem.setRightBarButtonItems(items, animated: true)
        }
    }

    func updateToolbar() {
        if isEditing {
            LibraryEditingUI.updateToolbarVisibility(
                isEditing: true,
                navigationController: navigationController,
                tabBarController: tabBarController
            )
            let hasSelectedItems = !(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
            toolbarItems?.first?.isEnabled = hasSelectedItems
        } else if !(navigationController?.isToolbarHidden ?? true) {
            LibraryEditingUI.updateToolbarVisibility(
                isEditing: false,
                navigationController: navigationController,
                tabBarController: tabBarController
            )
        }
    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
        deselectAllItems()
    }

    @objc func selectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                let cell = collectionView.cellForItem(at: indexPath)
                LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: true)
            }
        }
        updateNavbarItems()
        updateToolbar()
    }

    @objc func deselectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.deselectItem(at: indexPath, animated: false)
                let cell = collectionView.cellForItem(at: indexPath)
                LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: false)
            }
        }
        updateNavbarItems()
        updateToolbar()
    }
}

extension PlayerLibraryViewController {
    @objc private func removeSelectedFromLibrary() {
        let selectedItems = (collectionView.indexPathsForSelectedItems ?? []).compactMap { dataSource.itemIdentifier(for: $0) }
        let bookmarks = selectedItems.compactMap { $0.bookmark }
        guard !bookmarks.isEmpty else { return }

        let alert = UIAlertController(
            title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("REMOVE_FROM_LIBRARY"), style: .destructive) { _ in
            for bookmark in bookmarks {
                PlayerLibraryManager.shared.removeFromLibrary(bookmark)
            }
            self.stopEditing()
        })
        alert.popoverPresentationController?.barButtonItem = toolbarItems?.first
        present(alert, animated: true)
    }

    private func module(for bookmark: PlayerLibraryItem) -> ScrapingModule? {
        ModuleManager.shared.modules.first(where: { $0.id == bookmark.moduleId })
    }

    private func currentSourceId(for bookmark: PlayerLibraryItem) -> String {
        bookmark.moduleId.uuidString
    }

    private func currentMangaId(for bookmark: PlayerLibraryItem) -> String {
        bookmark.sourceUrl.normalizedModuleHref()
    }

    private func fetchEpisodes(for bookmark: PlayerLibraryItem) async -> [PlayerEpisode] {
        guard let module = module(for: bookmark) else { return [] }
        return await JSController.shared.fetchPlayerEpisodes(contentUrl: bookmark.sourceUrl, module: module)
    }

    private func markAllWatched(for bookmark: PlayerLibraryItem) async {
        let sourceId = currentSourceId(for: bookmark)
        let moduleId = sourceId
        let episodes = await fetchEpisodes(for: bookmark)
        for episode in episodes {
            let historyData = PlayerHistoryManager.EpisodeHistoryData(
                playerTitle: bookmark.title,
                episodeId: episode.url,
                episodeNumber: Double(episode.number),
                episodeTitle: episode.title,
                sourceUrl: episode.url,
                moduleId: moduleId,
                progress: 100,
                total: 100,
                watchedDuration: 0,
                date: Date()
            )
            await PlayerHistoryManager.shared.setProgress(data: historyData)
        }
    }

    private func markAllUnwatched(for bookmark: PlayerLibraryItem) async {
        let moduleId = currentSourceId(for: bookmark)
        let episodes = await fetchEpisodes(for: bookmark)
        for episode in episodes {
            await PlayerHistoryManager.shared.removeHistory(episodeId: episode.url, moduleId: moduleId)
        }
    }

    private func downloadEpisodes(_ episodes: [PlayerEpisode], for bookmark: PlayerLibraryItem) async {
        guard let module = module(for: bookmark), !episodes.isEmpty else { return }
        let seriesKey = bookmark.sourceUrl.normalizedModuleHref()
        await DownloadManager.shared.downloadVideo(
            seriesTitle: bookmark.title,
            episodes: episodes,
            sourceKey: module.id.uuidString,
            seriesKey: seriesKey,
            posterUrl: bookmark.imageUrl
        )
    }

    private func downloadAll(for bookmark: PlayerLibraryItem) async {
        let episodes = await fetchEpisodes(for: bookmark)
        await downloadEpisodes(episodes, for: bookmark)
    }

    private func downloadUnwatched(for bookmark: PlayerLibraryItem) async {
        let sourceId = currentSourceId(for: bookmark)
        let mangaId = currentMangaId(for: bookmark)
        let episodes = await fetchEpisodes(for: bookmark)
        guard !episodes.isEmpty else { return }

        let history = await CoreDataManager.shared.getPlayerReadingHistory(sourceId: sourceId, mangaId: mangaId)
        let watchedIds = Set(history.filter { $0.value.progress > 0 && $0.value.progress == $0.value.total }.keys)
        let unwatched = episodes.filter { !watchedIds.contains($0.url) }
        await downloadEpisodes(unwatched, for: bookmark)
    }

    @MainActor
    private func openPlayerView(for bookmark: PlayerLibraryItem, module: ScrapingModule) async {
        let episodes = (await fetchEpisodes(for: bookmark)).sorted { $0.number < $1.number }
        guard !episodes.isEmpty else {
            presentPlayerOpenError(message: "No episodes available")
            return
        }

        let history = await getEpisodeHistory(
            sourceId: module.id.uuidString,
            episodeIds: Set(episodes.map(\.url))
        )
        guard let selectedEpisode = resolveEpisodeToPlay(from: episodes, history: history) else {
            presentPlayerOpenError(message: "Unable to select an episode to play")
            return
        }

        let (streamInfos, subtitleUrl) = await JSController.shared.fetchPlayerStreams(
            episodeId: selectedEpisode.url,
            module: module
        )
        guard let stream = selectStream(streamInfos) else {
            presentPlayerOpenError(message: "Unable to find video stream for this episode")
            return
        }

        let episodeToPlay = PlayerEpisode(
            id: selectedEpisode.id,
            number: selectedEpisode.number,
            title: selectedEpisode.title,
            url: selectedEpisode.url,
            dateUploaded: selectedEpisode.dateUploaded,
            scanlator: selectedEpisode.scanlator,
            language: selectedEpisode.language,
            subtitleUrl: subtitleUrl ?? selectedEpisode.subtitleUrl
        )
        let mangaId = currentMangaId(for: bookmark)

        PlayerPresenter.present(
            module: module,
            videoUrl: stream.url,
            videoTitle: bookmark.title,
            headers: stream.headers,
            subtitleUrl: episodeToPlay.subtitleUrl,
            episodes: episodes,
            currentEpisode: episodeToPlay,
            mangaId: mangaId,
            onDismiss: { [weak self] in
                Task {
                    await self?.viewModel.refreshLibrary()
                }
            },
            onNextEpisode: { [weak self] in
                Task { @MainActor in
                    await self?.navigateRelativeEpisode(step: 1, module: module, episodes: episodes, title: bookmark.title)
                }
            },
            onPreviousEpisode: { [weak self] in
                Task { @MainActor in
                    await self?.navigateRelativeEpisode(step: -1, module: module, episodes: episodes, title: bookmark.title)
                }
            },
            onEpisodeSelected: { [weak self] episode in
                Task { @MainActor in
                    await self?.navigateToEpisode(episode, module: module, episodes: episodes, title: bookmark.title)
                }
            }
        )
    }

    private func resolveEpisodeToPlay(
        from episodes: [PlayerEpisode],
        history: [String: PlayerProgress]
    ) -> PlayerEpisode? {
        if let resumed = episodes.first(where: {
            guard let entry = history[$0.url], let total = entry.total, total > 0 else { return false }
            return entry.progress > 0 && entry.progress < total
        }) {
            return resumed
        }

        if let firstUnwatched = episodes.first(where: {
            guard let entry = history[$0.url], let total = entry.total, total > 0 else { return true }
            return entry.progress < total
        }) {
            return firstUnwatched
        }

        return episodes.first
    }

    private func getEpisodeHistory(sourceId: String, episodeIds: Set<String>) async -> [String: PlayerProgress] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            guard !episodeIds.isEmpty else { return [:] }

            let request: NSFetchRequest<PlayerHistoryObject> = PlayerHistoryObject.fetchRequest()
            request.predicate = NSPredicate(
                format: "moduleId == %@ AND episodeId IN %@",
                sourceId,
                Array(episodeIds)
            )

            do {
                let objects = try context.fetch(request)
                return objects.reduce(into: [String: PlayerProgress]()) { result, object in
                    guard let episodeId = object.episodeId else { return }
                    let progress = Int(object.progress)
                    let total = object.total != 0 ? Int(object.total) : nil
                    let date = Int(object.dateWatched?.timeIntervalSince1970 ?? 0)
                    result[episodeId] = PlayerProgress(progress: progress, total: total, date: date)
                }
            } catch {
                return [:]
            }
        }
    }

    @MainActor
    private func navigateRelativeEpisode(step: Int, module: ScrapingModule, episodes: [PlayerEpisode], title: String) async {
        guard
            let vc = PlayerPresenter.findTopViewController() as? PlayerViewController,
            let currentUrl = vc.currentEpisode?.url,
            let currentIndex = episodes.firstIndex(where: { $0.url == currentUrl })
        else {
            return
        }

        let newIndex = currentIndex + step
        guard episodes.indices.contains(newIndex) else { return }
        await navigateToEpisode(episodes[newIndex], module: module, episodes: episodes, title: title)
    }

    @MainActor
    private func navigateToEpisode(_ episode: PlayerEpisode, module: ScrapingModule, episodes: [PlayerEpisode], title: String) async {
        guard let vc = PlayerPresenter.findTopViewController() as? PlayerViewController else { return }

        let (streamInfos, subtitleUrl) = await JSController.shared.fetchPlayerStreams(
            episodeId: episode.url,
            module: module
        )
        guard let stream = selectStream(streamInfos) else { return }

        let episodeToPlay = PlayerEpisode(
            id: episode.id,
            number: episode.number,
            title: episode.title,
            url: episode.url,
            dateUploaded: episode.dateUploaded,
            scanlator: episode.scanlator,
            language: episode.language,
            subtitleUrl: subtitleUrl ?? episode.subtitleUrl
        )

        vc.loadVideo(url: stream.url, headers: stream.headers, subtitleUrl: episodeToPlay.subtitleUrl)
        vc.updateTitle("Episode \(episodeToPlay.number): \(episodeToPlay.title)")
        vc.configure(episodes: episodes, current: episodeToPlay, title: title)
    }

    private func selectStream(_ streams: [StreamInfo]) -> StreamInfo? {
        guard !streams.isEmpty else { return nil }

        let preferredAudioChannel = UserDefaults.standard.string(forKey: "Player.preferredAudioChannel") ?? "SUB"
        let audioFiltered = streams.filter { $0.title.lowercased().contains(preferredAudioChannel.lowercased()) }
        let streamsToUse = audioFiltered.isEmpty ? streams : audioFiltered

        let targetResolution: String = {
            switch Reachability.getConnectionType() {
            case .wifi:
                return UserDefaults.standard.string(forKey: "Player.preferredResolutionWifi") ?? "auto"
            case .cellular:
                return UserDefaults.standard.string(forKey: "Player.preferredResolutionCellular") ?? "auto"
            case .none:
                return "auto"
            }
        }()
        guard targetResolution.lowercased() != "auto" else {
            return streamsToUse.first
        }

        guard let target = parseResolution(targetResolution) else {
            return streamsToUse.first
        }

        let candidates = streamsToUse.compactMap { stream -> (StreamInfo, Int)? in
            guard let resolution = parseResolution(stream.title) else { return nil }
            return (stream, resolution)
        }
        guard !candidates.isEmpty else { return streamsToUse.first }

        return candidates.min { lhs, rhs in
            let lhsDiff = abs(lhs.1 - target)
            let rhsDiff = abs(rhs.1 - target)
            return lhsDiff != rhsDiff ? lhsDiff < rhsDiff : lhs.1 > rhs.1
        }?.0
    }

    private func parseResolution(_ text: String) -> Int? {
        let lowercased = text.lowercased()
        if lowercased.contains("4k") {
            return 2160
        }

        let pattern = "(\\d{3,4})p"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
        guard
            let match = regex.firstMatch(in: lowercased, options: [], range: range),
            match.numberOfRanges >= 2,
            let valueRange = Range(match.range(at: 1), in: lowercased)
        else {
            return nil
        }

        return Int(lowercased[valueRange])
    }

    @MainActor
    private func presentPlayerOpenError(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc func openUpdates() {
        let path = NavigationCoordinator(rootViewController: self)
        let viewController = UIHostingController(rootView: MangaUpdatesView().environmentObject(path))
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.navigationItem.title = NSLocalizedString("MANGA_UPDATES")
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc func openDownloadQueue() {
        let viewController = UIHostingController(rootView: DownloadQueueView(type: .video))
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.navigationItem.title = NSLocalizedString("DOWNLOAD_QUEUE")
        if #available(iOS 26.0, *) {
            viewController.preferredTransition = .zoom { _ in
                self.downloadBarButton
            }
        }
        viewController.modalPresentationStyle = .pageSheet
        present(viewController, animated: true)
    }
}

extension PlayerLibraryViewController {
    private func filtersSubtitle() -> String? {
        guard !viewModel.filters.isEmpty else { return nil }
        var options: [String] = []
        for filter in viewModel.filters {
            let filterMethod = filter.type
            if filterMethod == .source {
                if let value = filter.value {
                    options.append(SourceManager.shared.source(for: value)?.name ?? value)
                }
            } else {
                options.append(filterMethod.title)
            }
        }
        return options.joined(separator: NSLocalizedString("FILTER_SEPARATOR"))
    }

    func removeFilterAction() -> UIAction {
        UIAction(
            title: NSLocalizedString("REMOVE_FILTER"),
            image: UIImage(systemName: "minus.circle")
        ) { [weak self] _ in
            Task {
                guard let self else { return }
                self.viewModel.filters.removeAll()
                await self.viewModel.loadLibrary()
                if #available(iOS 16.0, *) {
                    self.updateFilterMenuState()
                } else {
                    self.updateMoreMenu()
                }
            }
        }
    }

    @available(iOS 16.0, *)
    func updateFilterMenuState() {
        func updateFilterSubmenu(_ menu: UIMenu) -> UIMenu {
            menu.subtitle = self.filtersSubtitle()
            return menu.replacingChildren(menu.children.map { element in
                guard let action = element as? UIAction else { return element }
                if let method = PlayerLibraryViewModel.FilterMethod.allCases.first(where: { $0.title == action.title }) {
                    action.state = viewModel.filterState(for: method)
                }
                return action
            })
        }

        LibraryFilterMenuUI.updateVisibleMenu(barButtonItem: moreBarButton) { menu in
            if menu.title == NSLocalizedString("BUTTON_FILTER") {
                updateFilterSubmenu(menu)
            } else if menu.title == PlayerLibraryViewModel.FilterMethod.source.title {
                 menu.replacingChildren(self.viewModel.sourceKeys.map { key in
                    UIAction(
                        title: SourceManager.shared.source(for: key)?.name ?? key,
                        attributes: .keepsMenuPresented,
                        state: self.viewModel.filterState(for: .source, value: key)
                    ) { [weak self] _ in
                        Task {
                             await self?.viewModel.toggleFilter(method: .source, value: key)
                             self?.updateFilterMenuState()
                        }
                    }
                 })
            } else {
                menu.replacingChildren(menu.children.map { element in
                    guard let menu = element as? UIMenu else { return element }
                    if menu.children.first?.title == NSLocalizedString("SORT_BY") {
                        let shouldShowRemoveFilter = !self.viewModel.filters.isEmpty
                        let isShowingRemoveFilter = menu.children.last?.title == NSLocalizedString("REMOVE_FILTER")

                        let updatedChildren = menu.children.map { element in
                            if element.title == NSLocalizedString("BUTTON_FILTER"), let menu = element as? UIMenu {
                                return updateFilterSubmenu(menu) as UIMenuElement
                            } else {
                                return element
                            }
                        }

                        if shouldShowRemoveFilter && !isShowingRemoveFilter {
                            return menu.replacingChildren(updatedChildren + [self.removeFilterAction()])
                        } else if !shouldShowRemoveFilter && isShowingRemoveFilter {
                            return menu.replacingChildren(updatedChildren.dropLast())
                        }
                        return menu.replacingChildren(updatedChildren)
                    }
                    return element
                })
            }
        }

        LibraryFilterMenuUI.applyFilterIcon(barButtonItem: moreBarButton, hasActiveFilters: !viewModel.filters.isEmpty)
    }

    func updateMoreMenu() {
        let selectAction = LibraryMoreMenuUI.makeSelectAction { [weak self] in
            self?.setEditing(true, animated: true)
        }

        let layoutActions = LibraryMoreMenuUI.makeLayoutActions(
            usesListLayout: usesListLayout,
            setUsesListLayout: { [weak self] value in
                self?.usesListLayout = value
            },
            collectionView: collectionView,
            makeCollectionViewLayout: { [weak self] in
                self?.makeCollectionViewLayout() ?? UICollectionViewFlowLayout()
            },
            updateMenu: { [weak self] in
                self?.updateMoreMenu()
            }
        )

        let sortMenu = UIMenu(
            title: NSLocalizedString("SORT_BY"),
            subtitle: viewModel.sortMethod.title,
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: [
                UIMenu(options: .displayInline, children: PlayerLibraryViewModel.SortMethod.allCases.map { method in
                    UIAction(
                        title: method.title,
                        state: viewModel.sortMethod == method ? .on : .off
                    ) { [weak self] _ in
                        Task {
                            await self?.viewModel.setSort(method: method, ascending: false)
                            self?.updateMoreMenu()
                        }
                    }
                }),
                UIMenu(options: .displayInline, children: [false, true].map { ascending in
                    UIAction(
                        title: ascending ? viewModel.sortMethod.ascendingTitle : viewModel.sortMethod.descendingTitle,
                        state: viewModel.sortAscending == ascending ? .on : .off
                    ) { [weak self] _ in
                        guard let self else { return }
                        Task {
                            await self.viewModel.setSort(method: self.viewModel.sortMethod, ascending: ascending)
                            self.updateMoreMenu()
                        }
                    }
                })
            ]
        )

        let filterMenu = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            let attributes: UIMenuElement.Attributes = if #available(iOS 16.0, *) {
                .keepsMenuPresented
            } else {
                []
            }

            let sourceMenu = UIMenu(
                title: PlayerLibraryViewModel.FilterMethod.source.title,
                image: PlayerLibraryViewModel.FilterMethod.source.image,
                children: self.viewModel.sourceKeys.map { key in
                    UIAction(
                        title: SourceManager.shared.source(for: key)?.name ?? key,
                        attributes: attributes,
                        state: self.viewModel.filterState(for: .source, value: key)
                    ) { [weak self] _ in
                        Task {
                            await self?.viewModel.toggleFilter(method: .source, value: key)
                            if #available(iOS 16.0, *) {
                                self?.updateFilterMenuState()
                            } else {
                                self?.updateMoreMenu()
                            }
                        }
                    }
                }
            )

            let filters = UIMenu(
                title: NSLocalizedString("BUTTON_FILTER"),
                subtitle: self.filtersSubtitle(),
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                children: PlayerLibraryViewModel.FilterMethod.allCases.map { method in
                    if method == .source {
                        return sourceMenu
                    }
                    return UIAction(
                        title: method.title,
                        image: method.image,
                        attributes: attributes,
                        state: self.viewModel.filterState(for: method)
                    ) { [weak self] _ in
                        Task {
                            await self?.viewModel.toggleFilter(method: method)
                            if #available(iOS 16.0, *) {
                                self?.updateFilterMenuState()
                            } else {
                                self?.updateMoreMenu()
                            }
                        }
                    }
                }
            )
            if self.viewModel.filters.isEmpty {
                completion([filters])
            } else {
                completion([filters, self.removeFilterAction()])
            }
        }

        moreBarButton.menu = UIMenu(
            children: [
                UIMenu(options: .displayInline, children: [selectAction]),
                UIMenu(options: .displayInline, children: layoutActions),
                UIMenu(options: .displayInline, children: [sortMenu, filterMenu])
            ]
        )

        LibraryFilterMenuUI.applyFilterIcon(barButtonItem: moreBarButton, hasActiveFilters: !viewModel.filters.isEmpty)
    }
}

extension PlayerLibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        Task {
            await viewModel.search(query: searchText)
        }
        applySnapshot(animated: true)
    }
}

// MARK: - Collection View
extension PlayerLibraryViewController {
    private enum Section: Int, CaseIterable {
        case pinned
        case main
    }

    private struct PlayerLibraryEntry: Hashable {
        let kind: Int // 0: bookmark, 1: search result
        let title: String
        let imageUrl: String
        let href: String
        let moduleId: UUID
        let bookmark: PlayerLibraryItem?
        let itemInfo: PlayerLibraryViewModel.PlayerLibraryItemInfo?

        func hash(into hasher: inout Hasher) {
            if let itemInfo {
                hasher.combine(itemInfo)
            } else {
                hasher.combine(moduleId)
                hasher.combine(href)
                hasher.combine(title)
            }
        }

        static func == (lhs: PlayerLibraryEntry, rhs: PlayerLibraryEntry) -> Bool {
            lhs.hashValue == rhs.hashValue
        }
    }

    private func isSearching() -> Bool {
        !searchText.isEmpty
    }

    private func buildEntries(from items: [PlayerLibraryViewModel.PlayerLibraryItemInfo]) -> [PlayerLibraryEntry] {
        items.map { info in
            PlayerLibraryEntry(
                kind: 0,
                title: info.item.title,
                imageUrl: info.item.imageUrl,
                href: info.item.sourceUrl,
                moduleId: info.item.moduleId,
                bookmark: info.item,
                itemInfo: info
            )
        }
    }

    private func applySnapshot(animated: Bool) {
        let pinnedEntries = buildEntries(from: viewModel.pinnedItems)
        let mainEntries = buildEntries(from: viewModel.items)
        currentItems = pinnedEntries + mainEntries

        var snapshot = NSDiffableDataSourceSnapshot<Section, PlayerLibraryEntry>()
        if !pinnedEntries.isEmpty {
            snapshot.appendSections([.pinned, .main])
            snapshot.appendItems(pinnedEntries, toSection: .pinned)
        } else {
            snapshot.appendSections([.main])
        }
        snapshot.appendItems(mainEntries, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyState()
    }

    private func reloadItems() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self else { return nil }

            if self.usesListLayout {
                return Self.makeListLayoutSection(environment: environment)
            } else {
                return Self.makeGridLayoutSection(environment: environment)
            }
        }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = Self.itemSpacing + Self.sectionSpacing
        layout.configuration = config

        return layout
    }

    // MARK: - Layout Helpers
    static func makeListLayoutSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemHeight: CGFloat = 100
        let spacing: CGFloat = 10

        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        ))

        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight)
            ),
            subitems: [item]
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        section.interGroupSpacing = spacing

        return section
    }

    static func makeGridLayoutSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemsPerRow = UserDefaults.standard.integer(
            forKey: environment.container.contentSize.width > environment.container.contentSize.height
                ? "General.landscapeRows"
                : "General.portraitRows"
        )

        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(itemsPerRow)),
            heightDimension: .fractionalWidth(3 / (2 * CGFloat(itemsPerRow)))
        ))

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(environment.container.contentSize.width * 3 / (2 * CGFloat(itemsPerRow)))
            ),
            subitem: item,
            count: itemsPerRow
        )
        group.interItemSpacing = .fixed(itemSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        section.interGroupSpacing = itemSpacing

        return section
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, PlayerLibraryEntry> {
        UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }

            if self.usesListLayout {
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: "MangaListCell",
                    for: indexPath
                ) as? MangaListCell else {
                    return UICollectionViewCell()
                }

                // Construct MangaInfo for configuration
                let info = MangaInfo(
                    mangaId: item.href.normalizedModuleHref(),
                    sourceId: item.moduleId.uuidString,
                    coverUrl: URL(string: item.imageUrl),
                    title: item.title,
                    author: nil,
                    url: URL(string: item.href),
                    unread: item.itemInfo?.unread ?? 0,
                    downloads: item.itemInfo?.downloads ?? 0
                )

                cell.configure(with: info)

                if let info = item.itemInfo {
                    cell.badgeNumber = self.viewModel.badgeType.contains(.unwatched) ? info.unread : 0
                    cell.badgeNumber2 = self.viewModel.badgeType.contains(.downloaded) ? info.downloads : 0
                } else {
                    cell.badgeNumber = 0
                    cell.badgeNumber2 = 0
                }

                cell.setEditing(self.isEditing, animated: false)

                cell.unhighlight(animated: false)

                return cell
            } else {
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: "MangaGridCell",
                    for: indexPath
                ) as? MangaGridCell else {
                    return UICollectionViewCell()
                }

                cell.sourceId = item.moduleId.uuidString
                cell.mangaId = item.href.normalizedModuleHref()
                cell.title = item.title

                if let info = item.itemInfo {
                    cell.badgeNumber = self.viewModel.badgeType.contains(.unwatched) ? info.unread : 0
                    cell.badgeNumber2 = self.viewModel.badgeType.contains(.downloaded) ? info.downloads : 0
                } else {
                    cell.badgeNumber = 0
                    cell.badgeNumber2 = 0
                }

                Task {
                    await cell.loadImage(url: URL(string: item.imageUrl))
                }

                cell.unhighlight()

                return cell
            }
        }
    }
}

extension PlayerLibraryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        LibraryCellUI.highlightCellIfPossible(collectionView: collectionView, at: indexPath, isEditing: isEditing)
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        LibraryCellUI.unhighlightCellIfPossible(collectionView: collectionView, at: indexPath, isEditing: isEditing)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        if isEditing {
            let cell = collectionView.cellForItem(at: indexPath)
            LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: true)
            LibrarySelectionFeedback.selectionChanged(at: cell?.center)
            updateNavbarItems()
            updateToolbar()
            return
        }

        guard let module = ModuleManager.shared.modules.first(where: { $0.id == item.moduleId }) else { return }
        if UserDefaults.standard.bool(forKey: "PlayerLibrary.opensPlayerView"), let bookmark = item.bookmark {
            Task { [weak self] in
                await self?.openPlayerView(for: bookmark, module: module)
            }
            return
        }

        let searchItem = SearchItem(title: item.title, imageUrl: item.imageUrl, href: item.href)
        let vc: PlayerInfoViewController
        if let bookmark = item.bookmark {
            vc = PlayerInfoViewController(bookmark: bookmark, searchItem: searchItem, module: module, path: path)
        } else {
            vc = PlayerInfoViewController(searchItem: searchItem, module: module, path: path)
        }
        if #available(iOS 18.0, *) {
            vc.preferredTransition = .zoom { context in
                guard
                    context.zoomedViewController is PlayerInfoViewController,
                    let indexPath = self.dataSource.indexPath(for: item),
                    let cell = self.collectionView.cellForItem(at: indexPath)
                else {
                    return nil
                }
                return cell.contentView
            }
        }
        path.push(vc)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isEditing else { return }
        let cell = collectionView.cellForItem(at: indexPath)
        LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: false)
        updateNavbarItems()
        updateToolbar()
    }

    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        setEditing(true, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            !isEditing,
            let indexPath = indexPaths.first,
            let entry = dataSource.itemIdentifier(for: indexPath),
            let bookmark = entry.bookmark
        else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            let markAllMenu = UIMenu(
                title: NSLocalizedString("MARK_ALL"),
                image: nil,
                children: [
                    UIAction(title: NSLocalizedString("WATCHED"), image: UIImage(systemName: "eye")) { _ in
                        Task { await self.markAllWatched(for: bookmark) }
                    },
                    UIAction(title: NSLocalizedString("UNWATCHED"), image: UIImage(systemName: "eye.slash")) { _ in
                        Task { await self.markAllUnwatched(for: bookmark) }
                    }
                ]
            )

            let downloadMenu = UIMenu(
                title: NSLocalizedString("DOWNLOAD"),
                image: UIImage(systemName: "arrow.down.circle"),
                children: [
                    UIAction(title: NSLocalizedString("ALL")) { _ in
                        Task { await self.downloadAll(for: bookmark) }
                    },
                    UIAction(title: NSLocalizedString("UNWATCHED")) { _ in
                        Task { await self.downloadUnwatched(for: bookmark) }
                    }
                ]
            )

            let removeAction = UIAction(
                title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                PlayerLibraryManager.shared.removeFromLibrary(bookmark)
            }

            return UIMenu(title: "", children: [
                markAllMenu,
                downloadMenu,
                UIMenu(options: .displayInline, children: [removeAction])
            ])
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        self.collectionView(collectionView, contextMenuConfigurationForItemsAt: [indexPath], point: point)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        LibraryContextMenuPreviewUI.targetedPreview(collectionView: collectionView, at: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        self.collectionView(
            collectionView,
            contextMenuConfiguration: configuration,
            highlightPreviewForItemAt: indexPath
        )
    }
}
