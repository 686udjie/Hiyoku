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

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(unread)
            hasher.combine(downloads)
            hasher.combine(item)
        }

        static func == (lhs: PlayerLibraryItemInfo, rhs: PlayerLibraryItemInfo) -> Bool {
            lhs.id == rhs.id &&
            lhs.unread == rhs.unread &&
            lhs.downloads == rhs.downloads &&
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

    var originalItems: [PlayerLibraryItem] = []
    @Published var sourceKeys: [String] = [] // Source names or IDs

    var sortMethod: SortMethod = .dateAdded
    var sortAscending: Bool = false

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

        self.items = filtered
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
                    let (unread, downloads) = await self.fetchCount(for: item)
                    return PlayerLibraryItemInfo(id: item.id, item: item, unread: unread, downloads: downloads)
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

    private func fetchCount(for item: PlayerLibraryItem) async -> (Int, Int) {
        guard let module = await MainActor.run(body: {
            ModuleManager.shared.modules.first(where: { $0.id == item.moduleId })
        }) else { return (0, 0) }

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

        return (unread, downloads)
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
        let isEmpty = viewModel.items.isEmpty && !isSearching
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
            Notification.Name("Library.unreadChapterBadges"),
            Notification.Name("Library.downloadedChapterBadges"),
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

    func updateNavbarItems() {
        Task { @MainActor in
            let hasDownloads = await DownloadManager.shared.hasQueuedDownloads(type: .video)
            var items: [UIBarButtonItem] = [moreBarButton, updatesBarButton]
            if hasDownloads {
                items.insert(downloadBarButton, at: 1)
            }
            navigationItem.setRightBarButtonItems(items, animated: true)
        }
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

    // MARK: - Menu

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
        // _contextMenuInteraction only exists on ios 16+
        let contextMenuInteraction = moreBarButton.value(forKey: "_contextMenuInteraction") as? UIContextMenuInteraction
        guard let contextMenuInteraction else { return }

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

        contextMenuInteraction.updateVisibleMenu { menu in
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

        // Update button appearance
        if !viewModel.filters.isEmpty {
            moreBarButton.isSelected = true
            moreBarButton.image = UIImage(systemName: "line.3.horizontal.decrease")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        } else {
            moreBarButton.isSelected = false
            moreBarButton.image = UIImage(systemName: "ellipsis")
        }
    }

    func updateMoreMenu() {
        let layoutActions = [
            UIAction(
                title: NSLocalizedString("LAYOUT_GRID"),
                image: UIImage(systemName: "square.grid.2x2"),
                state: usesListLayout ? .off : .on
            ) { [weak self] _ in
                guard let self, self.usesListLayout else { return }
                self.usesListLayout = false
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: true)
                self.collectionView.reloadData()
                self.updateMoreMenu()
            },
            UIAction(
                title: NSLocalizedString("LAYOUT_LIST"),
                image: UIImage(systemName: "list.bullet"),
                state: usesListLayout ? .on : .off
            ) { [weak self] _ in
                guard let self, !self.usesListLayout else { return }
                self.usesListLayout = true
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: true)
                self.collectionView.reloadData()
                self.updateMoreMenu()
            }
        ]

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
                UIMenu(options: .displayInline, children: layoutActions),
                UIMenu(options: .displayInline, children: [sortMenu, filterMenu])
            ]
        )

        // Update icon based on active filters
        if !viewModel.filters.isEmpty {
            moreBarButton.isSelected = true
            moreBarButton.image = UIImage(systemName: "line.3.horizontal.decrease")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        } else {
            moreBarButton.isSelected = false
            moreBarButton.image = UIImage(systemName: "ellipsis")
        }
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

    private func buildEntries() -> [PlayerLibraryEntry] {

        viewModel.items.map { info in
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
        currentItems = buildEntries()
        var snapshot = NSDiffableDataSourceSnapshot<Section, PlayerLibraryEntry>()
        snapshot.appendSections([.main])
        snapshot.appendItems(currentItems, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyState()
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
                    cell.badgeNumber = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges")
                        ? info.unread
                        : 0
                    cell.badgeNumber2 = UserDefaults.standard.bool(forKey: "Library.downloadedChapterBadges")
                        ? info.downloads
                        : 0
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
                    cell.badgeNumber = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges")
                        ? info.unread
                        : 0
                    cell.badgeNumber2 = UserDefaults.standard.bool(forKey: "Library.downloadedChapterBadges")
                        ? info.downloads
                        : 0
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
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.highlight()
        } else if let cell = cell as? MangaListCell {
            cell.highlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.unhighlight()
        } else if let cell = cell as? MangaListCell {
            cell.unhighlight()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        guard let module = ModuleManager.shared.modules.first(where: { $0.id == item.moduleId }) else { return }
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

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        let parameters = UIPreviewParameters()

        if let listCell = cell as? MangaListCell {
            let padding: CGFloat = 8
            let rect = listCell.bounds.insetBy(dx: -padding, dy: -padding)
            parameters.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            return UITargetedPreview(view: listCell.contentView, parameters: parameters)
        } else if cell is MangaGridCell {
            parameters.visiblePath = UIBezierPath(
                roundedRect: cell.bounds,
                cornerRadius: cell.contentView.layer.cornerRadius
            )
            return UITargetedPreview(view: cell.contentView, parameters: parameters)
        }

        return nil
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
