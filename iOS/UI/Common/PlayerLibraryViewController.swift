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

    private let searchViewModel = PlayerLibrarySearchViewModel()

    private var searchText = ""

    private var itemCounts: [UUID: (unread: Int, downloads: Int)] = [:]

    private lazy var downloadBarButton = UIBarButtonItem(
        image: UIImage(systemName: "square.and.arrow.down"),
        style: .plain,
        target: self,
        action: #selector(openDownloadQueue)
    )

    private lazy var updatesBarButton = UIBarButtonItem(
        image: UIImage(systemName: "bell"),
        style: .plain,
        target: self,
        action: #selector(openUpdates)
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

        // Observe library changes to update empty state + snapshot
        libraryObserver = PlayerLibraryManager.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySnapshot(animated: true)
            }

        searchResultsObserver = searchViewModel.$results
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySnapshot(animated: true)
            }

        applySnapshot(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.searchController = searchController
        navigationController?.navigationBar.layoutIfNeeded()
        updateNavbarItems()
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
        let isEmpty = PlayerLibraryManager.shared.items.isEmpty && !isSearching
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

        let refreshCounts: (Notification) -> Void = { [weak self] _ in
            self?.refreshCounts()
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
            addObserver(forName: name, using: refreshCounts)
        }

        let checkNavbarDownloadButton: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let shouldShowButton = await DownloadManager.shared.hasQueuedDownloads(type: .video)
                let index = self.navigationItem.rightBarButtonItems?.firstIndex(of: self.downloadBarButton)
                if shouldShowButton && index == nil {
                    // rightmost button (usually)
                    let insertIndex = max(0, (self.navigationItem.rightBarButtonItems?.count ?? 1) - 1)
                    self.navigationItem.rightBarButtonItems?.insert(
                        self.downloadBarButton,
                        at: insertIndex
                    )
                } else if !shouldShowButton, let index = index {
                    self.navigationItem.rightBarButtonItems?.remove(at: index)
                }
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
            var items: [UIBarButtonItem] = [updatesBarButton]
            if hasDownloads {
                items.append(downloadBarButton)
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
}

extension PlayerLibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        searchViewModel.search(query: searchText)
        applySnapshot(animated: true)
    }
}

// MARK: - Collection View
extension PlayerLibraryViewController {
    private enum Section: Int, CaseIterable {
        case main
    }

    private struct PlayerLibraryEntry: Hashable {
        enum Kind: Hashable {
            case bookmark(id: UUID)
            case search(id: UUID)
        }

        let kind: Kind
        let title: String
        let imageUrl: String
        let href: String
        let moduleId: UUID
        let bookmark: PlayerLibraryItem?

        var badgeKey: UUID? {
            switch kind {
            case .bookmark(let id): id
            case .search: nil
            }
        }
    }

    private func isSearching() -> Bool {
        !searchText.isEmpty
    }

    private func buildEntries() -> [PlayerLibraryEntry] {
        if isSearching() {
            return searchViewModel.results.map { result in
                PlayerLibraryEntry(
                    kind: .search(id: result.id),
                    title: result.title,
                    imageUrl: result.imageUrl,
                    href: result.href,
                    moduleId: result.module.id,
                    bookmark: nil
                )
            }
        } else {
            return PlayerLibraryManager.shared.items.map { item in
                PlayerLibraryEntry(
                    kind: .bookmark(id: item.id),
                    title: item.title,
                    imageUrl: item.imageUrl,
                    href: item.sourceUrl,
                    moduleId: item.moduleId,
                    bookmark: item
                )
            }
        }
    }

    private func applySnapshot(animated: Bool) {
        currentItems = buildEntries()
        var snapshot = NSDiffableDataSourceSnapshot<Section, PlayerLibraryEntry>()
        snapshot.appendSections([.main])
        snapshot.appendItems(currentItems, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyState()
        refreshCounts()
    }

    private func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let spacing: CGFloat = 16
            let isLandscape = environment.container.effectiveContentSize.width > environment.container.effectiveContentSize.height
            let itemsPerRow = max(1, UserDefaults.standard.integer(forKey: isLandscape ? "General.landscapeRows" : "General.portraitRows"))

            let availableWidth = max(1, environment.container.effectiveContentSize.width - 32)

            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalHeight(1)
            ))

            let groupHeight = availableWidth * 3 / (2 * CGFloat(itemsPerRow))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(groupHeight)
                ),
                subitem: item,
                count: itemsPerRow
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            section.interGroupSpacing = spacing

            return section
        }
        return layout
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, PlayerLibraryEntry> {
        collectionView.register(MangaGridCell.self, forCellWithReuseIdentifier: "MangaGridCell")

        return UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "MangaGridCell",
                for: indexPath
            ) as? MangaGridCell else {
                return UICollectionViewCell()
            }

            cell.sourceId = item.moduleId.uuidString
            cell.mangaId = item.href.normalizedModuleHref()
            cell.title = item.title
            if let badgeKey = item.badgeKey {
                cell.badgeNumber = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges")
                    ? (self.itemCounts[badgeKey]?.unread ?? 0)
                    : 0
                cell.badgeNumber2 = UserDefaults.standard.bool(forKey: "Library.downloadedChapterBadges")
                    ? (self.itemCounts[badgeKey]?.downloads ?? 0)
                    : 0
            } else {
                cell.badgeNumber = 0
                cell.badgeNumber2 = 0
            }
            Task {
                await cell.loadImage(url: URL(string: item.imageUrl))
            }
            return cell
        }
    }
}

extension PlayerLibraryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? MangaGridCell)?.highlight()
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        (collectionView.cellForItem(at: indexPath) as? MangaGridCell)?.unhighlight()
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
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bounds,
            cornerRadius: cell.contentView.layer.cornerRadius
        )
        return UITargetedPreview(view: cell.contentView, parameters: parameters)
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

private extension PlayerLibraryViewController {
    func refreshCounts() {
        Task {
            await fetchCounts()
        }
    }

    func fetchCounts() async {
        let items = PlayerLibraryManager.shared.items
        let counts = await withTaskGroup(of: (UUID, Int, Int)?.self) { group in
            for item in items {
                group.addTask {
                    guard let module = await MainActor.run(body: {
                        ModuleManager.shared.modules.first(where: { $0.id == item.moduleId })
                    }) else { return nil }
                    let sourceId = module.id.uuidString
                    let animeId = item.sourceUrl.normalizedModuleHref()
                    let episodes = await CoreDataManager.shared.container.performBackgroundTask { context in
                        CoreDataManager.shared.getChapters(sourceId: sourceId, mangaId: animeId, context: context)
                            .compactMap { $0.id }
                    }
                    let history = await CoreDataManager.shared.getPlayerReadingHistory(sourceId: sourceId, mangaId: animeId)
                    var unread = 0
                    if !episodes.isEmpty {
                        let readIds = Set(history.filter { $0.value.progress > 0 && $0.value.progress == $0.value.total }.keys)
                        unread = episodes.filter { !readIds.contains($0) }.count
                    }
                    let sourceName = module.metadata.sourceName
                    let candidates = [
                        (sourceId, animeId),
                        (sourceId, item.title),
                        (sourceName, animeId),
                        (sourceName, item.title)
                    ]
                    var downloads = 0
                    for (src, key) in candidates {
                        downloads = await DownloadManager.shared.downloadsCount(for: MangaIdentifier(sourceKey: src, mangaKey: key))
                        if downloads > 0 { break }
                    }
                    return (item.id, unread, downloads)
                }
            }
            var results: [UUID: (Int, Int)] = [:]
            for await result in group {
                if let (id, unread, downloads) = result {
                    results[id] = (unread, downloads)
                }
            }
            return results
        }
        await MainActor.run {
            self.itemCounts = counts

            var snapshot = self.dataSource.snapshot()
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
            self.dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
}
