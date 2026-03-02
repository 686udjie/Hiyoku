//
//  PlayerLibraryViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/03/2026.
//

import UIKit
import SwiftUI
import AidokuRunner
import Combine
import LocalAuthentication

// swiftlint:disable:next type_body_length
class PlayerLibraryViewController: OldMangaCollectionViewController {
    private let path = NavigationCoordinator(rootViewController: nil)
    let viewModel = PlayerLibraryViewModel()

    // MARK: Bar Buttons
    private lazy var downloadBarButton = makeBarButton(
        systemName: "square.and.arrow.down",
        action: #selector(openDownloadQueue),
        titleKey: "DOWNLOAD_QUEUE",
        role: .download
    )
    private lazy var lockBarButton = makeBarButton(
        systemName: locked ? "lock" : "lock.open",
        action: #selector(performToggleLock),
        titleKey: "TOGGLE_LOCK",
        role: .lock
    )
    private lazy var moreBarButton = makeBarButton(
        systemName: "ellipsis",
        action: nil,
        titleKey: "MORE_BARBUTTON",
        role: .more
    )
    private lazy var updatesBarButton = makeBarButton(
        systemName: "bell",
        action: #selector(openUpdates),
        titleKey: "MANGA_UPDATES",
        role: .updates
    )

    private func makeBarButton(
        systemName: String? = nil,
        action: Selector?,
        titleKey: String,
        role: LibraryRootNavbarUI.ButtonRole
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: systemName.flatMap { UIImage(systemName: $0) },
            style: .plain,
            target: self,
            action: action
        )
        item.title = NSLocalizedString(titleKey)
        LibraryRootNavbarUI.configureButton(item, role: role)
        return item
    }

    // MARK: State
    private lazy var refreshControl = UIRefreshControl()
    private lazy var emptyStackView = EmptyPageStackView()
    private lazy var lockedStackView = LockedPageStackView()

    private lazy var locked = viewModel.isCategoryLocked()
    private var ignoreOptionChange = false
    private var lastSearch: String?

    // Lookup maps for Player <-> MangaInfo
    private var mangaInfoByPlayerId: [UUID: MangaInfo] = [:]
    private var playerInfoByMangaKey: [String: PlayerLibraryViewModel.PlayerLibraryItemInfo] = [:]

    // MARK: Settings-backed layout preference
    private func setUsesListLayout(_ value: Bool) {
        UserDefaults.standard.setValue(value, forKey: "PlayerLibrary.listView")
        usesListLayout = value
    }

    private func makeUpdatedCollectionViewLayout() -> UICollectionViewLayout {
        makeCollectionViewLayout()
    }

    // MARK: Lifecycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshControl.didMoveToSuperview()
        if !navigationItem.hidesSearchBarWhenScrolling {
            navigationItem.hidesSearchBarWhenScrolling = true
        }
    }

    override func configure() {
        super.configure()

        title = NSLocalizedString("PLAYER")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false
        path.rootViewController = navigationController

        usesListLayout = UserDefaults.standard.bool(forKey: "PlayerLibrary.listView")

        // search controller
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search in Player"
        navigationItem.searchController = searchController

        // toolbar (editing)
        let deleteButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(removeSelectedFromLibrary)
        )
        deleteButton.image = UIImage(systemName: "trash")
        if #unavailable(iOS 26.0) {
            deleteButton.tintColor = .systemRed
        }
        toolbarItems = [deleteButton, UIBarButtonItem(systemItem: .flexibleSpace)]

        // pull to refresh
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh(refreshControl:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        collectionView.allowsMultipleSelection = true
        collectionView.allowsSelectionDuringEditing = true
        collectionView.keyboardDismissMode = .onDrag

        // header view
        let registration = UICollectionView.SupplementaryRegistration<MangaListSelectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, _ in
            guard let self = self else { return }
            header.delegate = self
            header.options = [NSLocalizedString("ALL")] + self.viewModel.categories
            header.selectedOption = self.viewModel.currentCategory != nil
                ? (self.viewModel.categories.firstIndex(of: self.viewModel.currentCategory!) ?? -1) + 1
                : 0
            header.updateMenu()

            if self.viewModel.core.isLibraryLockEnabled() {
                let lockedCategories = self.viewModel.core.loadLockedCategories()
                header.lockedOptions = [0] + lockedCategories.compactMap { category in
                    self.viewModel.categories.firstIndex(of: category).map { $0 + 1 }
                }
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            if kind == UICollectionView.elementKindSectionHeader {
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: registration,
                    for: indexPath
                )
            }
            return nil
        }

        // empty / locked views
        emptyStackView.isHidden = true
        lockedStackView.isHidden = true
        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED")
            : NSLocalizedString("CATEGORY_LOCKED")
        lockedStackView.buttonText = NSLocalizedString("VIEW_LIBRARY")
        lockedStackView.button.addTarget(self, action: #selector(performUnlock), for: .touchUpInside)
        view.addSubview(emptyStackView)
        view.addSubview(lockedStackView)

        // navbar + menus
        updateMoreMenu()
        updateNavbarItems()

        // initial data load
        _ = Task<Void, Never> { @MainActor [weak self] in
            guard let self = self else { return }
            await SourceManager.shared.loadSources()
            await DownloadManager.shared.loadQueueState()
            await viewModel.refreshCategories()
            collectionView.collectionViewLayout = self.makeCollectionViewLayout()
            updateNavbarItems()
            await viewModel.loadLibrary()
            updateEmptyState()
            updateLockState()
        }
    }

    override func constrain() {
        super.constrain()
        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        lockedStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lockedStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockedStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    deinit {
        navbarDownloadTask?.cancel()
    }

    // MARK: Observers
    override func observe() {
        super.observe()

        addObserver(forName: .downloadsQueued) { [weak self] _ in
            self?.queueDownloadNavbarRefresh()
        }
        addObserver(forName: .downloadCancelled) { [weak self] _ in
            self?.queueDownloadNavbarRefresh()
        }
        addObserver(forName: .downloadsCancelled) { [weak self] _ in
            self?.queueDownloadNavbarRefresh()
        }
        addObserver(forName: .downloadFinished) { [weak self] notification in
            self?.queueDownloadNavbarRefresh()
            self?.handleDownloadCountUpdate(notification: notification)
        }
        addObserver(forName: .downloadRemoved, using: handleDownloadCountUpdate)
        addObserver(forName: .downloadsRemoved, using: handleDownloadCountUpdate)

        addObserver(forName: .updatePlayerLibrary) { [weak self] _ in
            guard let self = self else { return }
            _ = Task<Void, Never> { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateEmptyState()
                self.updateDataSource()
            }
        }
        addObserver(forName: .updatePlayerLibraryLock) { [weak self] _ in
            guard let self = self else { return }
            _ = Task<Void, Never> { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
            }
        }
        addObserver(forName: .updatePlayerCategories) { [weak self] _ in
            guard let self = self else { return }
            _ = Task<Void, Never> { @MainActor in
                await self.viewModel.refreshCategories()
                self.collectionView.collectionViewLayout = self.makeCollectionViewLayout()
                self.updateDataSource()
                if !self.isEditing {
                    self.updateToolbar()
                }
                self.updateHeaderCategories()
                if self.viewModel.core.isLibraryLockEnabled() {
                    NotificationCenter.default.post(name: .updatePlayerLibraryLock, object: nil)
                }
            }
        }

        addObserver(forName: Notification.Name("PlayerLibrary.unreadChapterBadges")) { [weak self] _ in
            _ = Task<Void, Never> { @MainActor [weak self] in
                guard let self = self else { return }
                if self.viewModel.core.unreadBadgeEnabled() {
                    self.viewModel.badgeType.insert(.unwatched)
                } else {
                    self.viewModel.badgeType.remove(.unwatched)
                }
                self.reloadItems()
            }
        }
        addObserver(forName: Notification.Name("PlayerLibrary.downloadedChapterBadges")) { [weak self] _ in
            _ = Task<Void, Never> { @MainActor [weak self] in
                guard let self = self else { return }
                if self.viewModel.core.downloadedBadgeEnabled() {
                    self.viewModel.badgeType.insert(.downloaded)
                } else {
                    self.viewModel.badgeType.remove(.downloaded)
                }
                self.reloadItems()
            }
        }
        addObserver(forName: Notification.Name("PlayerLibrary.pinTitles")) { [weak self] _ in
            guard let self = self else { return }
            self.viewModel.pinType = self.viewModel.getPinType()
            _ = Task<Void, Never> { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        addObserver(forName: UIApplication.willResignActiveNotification) { [weak self] _ in
            guard let self = self else { return }
            _ = Task<Void, Never> { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
            }
        }
    }

    private func handleDownloadCountUpdate(notification: Notification) {
        guard (notification.object as? Download)?.mangaIdentifier != nil || (notification.object as? MangaIdentifier) != nil else { return }
        _ = Task<Void, Never> { @MainActor in
            await self.viewModel.refreshLibrary() // refresh counts for simplicity
            self.updateDataSource()
        }
    }

    // MARK: Navbar
    private var navbarDownloadTask: Task<Void, Never>?

    private func queueDownloadNavbarRefresh() {
        _ = Task<Void, Never> { @MainActor [weak self] in
            self?.refreshDownloadButtonVisibility()
        }
    }

    @MainActor
    private func refreshDownloadButtonVisibility() {
        navbarDownloadTask?.cancel()
        navbarDownloadTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Ignore stale notification updates when the view is not visible.
            guard self.isViewLoaded, self.view.window != nil, !self.isEditing else { return }
            let shouldShowButton = await DownloadManager.shared.hasQueuedDownloads(type: .video)
            guard !Task.isCancelled else { return }
            guard self.isViewLoaded, self.view.window != nil, !self.isEditing else { return }
            LibraryRootNavbarUI.setDownloadVisibility(
                navigationItem: self.navigationItem,
                downloadButton: self.downloadBarButton,
                trailingButton: self.updatesBarButton,
                visible: shouldShowButton
            )
        }
    }

    func updateNavbarItems() {
        guard Thread.isMainThread else {
            _ = Task<Void, Never> { @MainActor [weak self] in self?.updateNavbarItems() }
            return
        }

        navbarDownloadTask?.cancel()

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

        var items: [UIBarButtonItem] = [moreBarButton]
        if viewModel.isCategoryLocked() {
            items.append(lockBarButton)
        }
        items.append(updatesBarButton)
        LibraryRootNavbarUI.applyNonEditingNavbar(
            navigationItem: navigationItem,
            items: items
        )
        refreshDownloadButtonVisibility()
    }

    // MARK: Toolbar
    func updateToolbar() {
        if isEditing {
            LibraryEditingUI.updateToolbarVisibility(
                isEditing: true,
                navigationController: navigationController,
                tabBarController: tabBarController
            )
            toolbarItems?.first?.isEnabled = !(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
        } else if !(navigationController?.isToolbarHidden ?? true) {
            LibraryEditingUI.updateToolbarVisibility(
                isEditing: false,
                navigationController: navigationController,
                tabBarController: tabBarController
            )
        }
    }

    // MARK: Empty / Lock
    func updateEmptyState() {
        emptyStackView.imageSystemName = "play.tv.fill"
        emptyStackView.title = viewModel.currentCategory == nil
            ? NSLocalizedString("PLAYER_EMPTY")
            : NSLocalizedString("CATEGORY_EMPTY")
        emptyStackView.text = viewModel.items.isEmpty && viewModel.pinnedItems.isEmpty
            ? NSLocalizedString("PLAYER_ADD_CONTENT")
            : NSLocalizedString("LIBRARY_ADJUST_FILTERS")
    }

    func updateLockState() {
        if locked {
            guard emptyStackView.alpha != 0 else { return }
            collectionView.isScrollEnabled = false
            emptyStackView.alpha = 0
            lockedStackView.alpha = 0
            lockedStackView.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.lockedStackView.alpha = 1
            }
        } else {
            collectionView.isScrollEnabled = emptyStackView.isHidden
            lockedStackView.isHidden = true
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.emptyStackView.alpha = 1
            }
        }
        lockBarButton.image = UIImage(systemName: locked ? "lock" : "lock.open")
        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED")
            : NSLocalizedString("CATEGORY_LOCKED")

        updateNavbarItems()
        updateHeaderLockIcons()
        updateDataSource()
    }

    func updateHeaderLockIcons() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader) else { return }
        if viewModel.core.isLibraryLockEnabled() {
            let lockedCategories = viewModel.core.loadLockedCategories()
            header.lockedOptions = [0] + lockedCategories.compactMap { category in
                viewModel.categories.firstIndex(of: category).map { $0 + 1 }
            }
        } else {
            header.lockedOptions = []
        }
    }

    func updateHeaderCategories() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader) else { return }
        ignoreOptionChange = true
        header.options = [NSLocalizedString("ALL")] + viewModel.categories
        header.setSelectedOption(
            viewModel.currentCategory != nil
                ? (viewModel.categories.firstIndex(of: viewModel.currentCategory!) ?? -1) + 1
                : 0
        )
    }

    // MARK: Editing
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

    @objc func stopEditing() {
        setEditing(false, animated: true)
        deselectAllItems()
    }

    @objc func selectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    @objc func deselectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    // MARK: Refresh
    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl? = nil) {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            refreshControl?.endRefreshing()
        }

        Task {
            await PlayerLibraryManager.shared.checkForUpdates(category: viewModel.currentCategory) { _ in }
        }
    }

    // MARK: Navigation
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

    @objc func openUpdates() {
        let path = NavigationCoordinator(rootViewController: self)
        let viewController = UIHostingController(rootView: MangaUpdatesView().environmentObject(path))
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.navigationItem.title = NSLocalizedString("MANGA_UPDATES")
        navigationController?.pushViewController(viewController, animated: true)
    }

    // MARK: Menu / Filters
    func updateMoreMenu() {
        let layoutActions = LibraryMoreMenuUI.makeLayoutActions(
            usesListLayout: usesListLayout,
            setUsesListLayout: { [weak self] in self?.setUsesListLayout($0) },
            collectionView: collectionView,
            makeCollectionViewLayout: { [weak self] in self?.makeUpdatedCollectionViewLayout() ?? UICollectionViewFlowLayout() },
            updateMenu: { [weak self] in self?.updateMoreMenu() }
        )

        let sortMenu = LibraryMenuFactory.makeSortMenu(
            config: .init(
                current: viewModel.sortMethod,
                ascending: viewModel.sortAscending,
                titleProvider: { $0.title },
                ascendingTitleProvider: { $0.ascendingTitle },
                descendingTitleProvider: { $0.descendingTitle },
                handler: { [weak self] (method: PlayerLibraryViewModel.SortMethod, ascending: Bool) in
                    Task {
                        await self?.viewModel.setSort(method: method, ascending: ascending)
                        self?.updateDataSource()
                        self?.updateMoreMenu()
                    }
                }
            )
        )

        let filterMenu = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self = self else { return completion([]) }
            let attributes: UIMenuElement.Attributes = if #available(iOS 16.0, *) { .keepsMenuPresented } else { [] }
            let srcMenu = UIMenu(
                title: PlayerLibraryViewModel.FilterMethod.source.title,
                image: PlayerLibraryViewModel.FilterMethod.source.image,
                children: self.viewModel.sourceKeys.map { key in
                    UIAction(
                        title: SourceManager.shared.source(for: key)?.name ?? key,
                        state: self.viewModel.filterState(for: .source, value: key)
                    ) { _ in
                        Task {
                            await self.viewModel.toggleFilter(method: .source, value: key)
                            self.updateDataSource()
                            self.updateMoreMenu()
                        }
                    }
                }
            )
            let children = PlayerLibraryViewModel.FilterMethod.allCases.map { method in
                method == .source ? srcMenu : UIAction(
                    title: method.title,
                    image: method.image,
                    attributes: attributes,
                    state: self.viewModel.filterState(for: method)
                ) { _ in
                    Task {
                        await self.viewModel.toggleFilter(method: method)
                        self.updateDataSource()
                        self.updateMoreMenu()
                    }
                }
            }
            let config = LibraryMenuFactory.FilterConfig<PlayerLibraryViewModel.FilterMethod>(
                title: NSLocalizedString("BUTTON_FILTER"),
                subtitle: LibraryFilterMenuUI.buildFiltersSubtitle(
                    filters: self.viewModel.filters,
                    allMethods: PlayerLibraryViewModel.FilterMethod.allCases,
                    titleProvider: { $0.title },
                    valueProvider: { type, value in
                        type == .source ? SourceManager.shared.source(for: value)?.name ?? value : nil
                    }
                ),
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                children: children,
                removeHandler: self.viewModel.filters.isEmpty ? nil : { [weak self] in
                    Task {
                        self?.viewModel.filters.removeAll()
                        await self?.viewModel.loadLibrary()
                        self?.updateDataSource()
                        self?.updateMoreMenu()
                    }
                }
            )
            completion([LibraryMenuFactory.makeFilterMenu(config: config)])
        }

        let mainMenu = UIMenu(children: [
            UIMenu(options: .displayInline, children: [
                LibraryMoreMenuUI.makeSelectAction { [weak self] in self?.setEditing(true, animated: true) }
            ]),
            UIMenu(options: .displayInline, children: layoutActions),
            UIMenu(options: .displayInline, children: [sortMenu, filterMenu])
        ])
        moreBarButton.menu = mainMenu
        LibraryFilterMenuUI.applyFilterIcon(barButtonItem: moreBarButton, hasActiveFilters: !viewModel.filters.isEmpty)
    }

    // MARK: Data Source
    func clearDataSource() {
        let snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()
        dataSource.apply(snapshot)
    }

    func updateDataSource() {
        // build mapping
        mangaInfoByPlayerId = [:]
        playerInfoByMangaKey = [:]

        func mapItem(_ info: PlayerLibraryViewModel.PlayerLibraryItemInfo) -> MangaInfo {
            let mangaId = info.item.sourceUrl.normalizedModuleHref()
            let sourceId = info.item.moduleId.uuidString
            let mapped = MangaInfo(
                mangaId: mangaId,
                sourceId: sourceId,
                coverUrl: URL(string: info.item.imageUrl),
                title: info.item.title,
                author: nil,
                url: URL(string: info.item.sourceUrl),
                unread: info.unread,
                downloads: info.downloads
            )
            mangaInfoByPlayerId[info.id] = mapped
            playerInfoByMangaKey["\(sourceId)|\(mangaId)"] = info
            return mapped
        }

        let pinned = viewModel.pinnedItems.map(mapItem)
        let regular = viewModel.items.map(mapItem)

        var snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()
        if !locked {
            if !pinned.isEmpty {
                snapshot.appendSections(Section.allCases)
                snapshot.appendItems(pinned, toSection: .pinned)
            } else {
                snapshot.appendSections([.regular])
            }
            snapshot.appendItems(regular, toSection: .regular)
        }

        dataSource.apply(snapshot)

        updateEmptyState()

        // empty/scroll state
        if navigationItem.searchController?.searchBar.text?.isEmpty ?? true {
            emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
        } else {
            emptyStackView.isHidden = true
        }
        collectionView.isScrollEnabled = emptyStackView.isHidden && lockedStackView.isHidden
        collectionView.refreshControl = collectionView.isScrollEnabled ? refreshControl : nil
    }

    func reloadItems() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot)
    }

    // MARK: Locking
    func lock() { locked = true; updateLockState() }
    func unlock() { locked = false; updateLockState() }

    func attemptUnlock() async {
        do {
            let success = try await LAContext().evaluatePolicy(
                .defaultPolicy,
                localizedReason: NSLocalizedString("AUTH_FOR_LIBRARY")
            )
            guard success else { return }
        } catch {
            return
        }
        unlock()
    }

    @objc func performUnlock() { Task { await attemptUnlock() } }
    @objc func performToggleLock() { Task { locked ? await attemptUnlock() : lock() } }

    // MARK: Selection / Context Menu
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let info = dataSource.itemIdentifier(for: indexPath) else { return }

        if isEditing {
            let cell = collectionView.cellForItem(at: indexPath)
            LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: true)
            LibrarySelectionFeedback.selectionChanged(at: cell?.center)
            updateNavbarItems()
            updateToolbar()
            return
        }

        handleOpen(info: info)
        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isEditing {
            let cell = collectionView.cellForItem(at: indexPath)
            LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: false)
            updateNavbarItems()
            updateToolbar()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard !isEditing else { return }
        super.collectionView(collectionView, didHighlightItemAt: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let manga = dataSource.itemIdentifier(for: indexPath),
              let playerInfo = playerInfoByMangaKey["\(manga.sourceId)|\(manga.mangaId)"]
        else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let self = self else { return nil }
            let actions = self.buildContextMenuActions(for: playerInfo.item)
            return UIMenu(title: "", children: actions)
        }
    }

    private func handleOpen(info: MangaInfo) {
        guard let playerInfo = playerInfoByMangaKey["\(info.sourceId)|\(info.mangaId)"],
              let module = ModuleManager.shared.modules.first(where: { $0.id.uuidString == info.sourceId }) else { return }

        if UserDefaults.standard.bool(forKey: "PlayerLibrary.opensPlayerView") {
            Task {
                await PlayerLibraryNavHelper.openPlayerView(for: playerInfo.item, module: module, from: self) {
                    await self.viewModel.refreshLibrary()
                }
            }
        } else {
            let searchItem = SearchItem(title: playerInfo.item.title, imageUrl: playerInfo.item.imageUrl, href: playerInfo.item.sourceUrl)
            let vc = PlayerInfoViewController(bookmark: playerInfo.item, searchItem: searchItem, module: module, path: path)
            LibraryNavigationUI.createZoomTransition(
                for: vc,
                sourceViewProvider: { [weak self] in
                    guard
                        let self,
                        let indexPath = self.dataSource.indexPath(for: info),
                        let cell = self.collectionView.cellForItem(at: indexPath)
                    else { return nil }
                    if let cell = cell as? MangaListCell { return cell.coverImageView }
                    return cell.contentView
                }
            )
            path.push(vc)
        }
    }

    private func buildContextMenuActions(for item: PlayerLibraryItem) -> [UIMenuElement] {
        let markMenu = UIMenu(title: NSLocalizedString("MARK_ALL"), children: [
            UIAction(title: NSLocalizedString("WATCHED"), image: UIImage(systemName: "eye")) { _ in
                Task { await self.viewModel.markEpisodes(items: [item], watched: true) }
            },
            UIAction(title: NSLocalizedString("UNWATCHED"), image: UIImage(systemName: "eye.slash")) { _ in
                Task { await self.viewModel.markEpisodes(items: [item], watched: false) }
            }
        ])

        let downloadMenu = UIMenu(
            title: NSLocalizedString("DOWNLOAD"),
            image: UIImage(systemName: "arrow.down.circle"),
            children: [
                UIAction(title: NSLocalizedString("ALL")) { _ in
                    Task { await self.viewModel.downloadBatch(items: [item], unwatchedOnly: false) }
                },
                UIAction(title: NSLocalizedString("UNWATCHED")) { _ in
                    Task { await self.viewModel.downloadBatch(items: [item], unwatchedOnly: true) }
                }
            ]
        )

        let categoriesMenu: UIMenu? = viewModel.categories.isEmpty ? nil : UIMenu(
            title: NSLocalizedString("CATEGORIES"), image: UIImage(systemName: "folder"),
            children: viewModel.categories.map { category in
                let selected = viewModel.categories(for: item).contains(category)
                return UIAction(title: category, state: selected ? .on : .off) { _ in
                    Task {
                        await self.viewModel.toggleCategory(for: item, category: category)
                        self.updateDataSource()
                    }
                }
            }
        )

        let remove = UIAction(
            title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { _ in
            PlayerLibraryManager.shared.removeFromLibrary(item)
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        return [markMenu, downloadMenu] + (categoriesMenu != nil ? [categoriesMenu!] : []) + [remove]
    }

    // MARK: Remove
    @objc func removeSelectedFromLibrary() {
        let selectedItems = collectionView.indexPathsForSelectedItems ?? []
        let playerItems: [PlayerLibraryItem] = selectedItems.compactMap {
            dataSource.itemIdentifier(for: $0)
        }.compactMap { info in
            playerInfoByMangaKey["\(info.sourceId)|\(info.mangaId)"]?.item
        }
        guard !playerItems.isEmpty else { return }

        LibraryActionDispatcher.presentConfirmRemove(
            from: self,
            title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
            sourceItem: toolbarItems?.first as Any
        ) { [weak self] in
            guard let self = self else { return }
            playerItems.forEach { PlayerLibraryManager.shared.removeFromLibrary($0) }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
                self.stopEditing()
            }
        }
    }
    // MARK: - Layout
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = super.makeCollectionViewLayout()
        guard let layout = layout as? UICollectionViewCompositionalLayout else { return layout }

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = layout.configuration.interSectionSpacing
        if !viewModel.categories.isEmpty {
            let globalHeader = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(40)
                ),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            config.boundarySupplementaryItems = [globalHeader]
        }
        layout.configuration = config
        return layout
    }

    override func configure(cell: MangaGridCell, info: MangaInfo) {
        super.configure(cell: cell, info: info)
        let playerInfo = playerInfoByMangaKey["\(info.sourceId)|\(info.mangaId)"]
        cell.badgeNumber = viewModel.badgeType.contains(.unwatched) ? (playerInfo?.unread ?? 0) : 0
        cell.badgeNumber2 = viewModel.badgeType.contains(.downloaded) ? (playerInfo?.downloads ?? 0) : 0
        cell.setEditing(isEditing, animated: false)
    }

    override func configure(cell: MangaListCell, info: MangaInfo) {
        super.configure(cell: cell, info: info)
        let playerInfo = playerInfoByMangaKey["\(info.sourceId)|\(info.mangaId)"]
        cell.badgeNumber = viewModel.badgeType.contains(.unwatched) ? (playerInfo?.unread ?? 0) : 0
        cell.badgeNumber2 = viewModel.badgeType.contains(.downloaded) ? (playerInfo?.downloads ?? 0) : 0
        cell.setEditing(isEditing, animated: false)
    }
}

// MARK: - Search
extension PlayerLibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard searchController.searchBar.text != lastSearch else { return }
        lastSearch = searchController.searchBar.text
        Task {
            await viewModel.search(query: searchController.searchBar.text ?? "")
            updateDataSource()
        }
    }
}

// MARK: - Header Delegate
extension PlayerLibraryViewController: MangaListSelectionHeaderDelegate {
    nonisolated func optionSelected(_ index: Int) {
        Task { @MainActor in
            guard !ignoreOptionChange else {
                ignoreOptionChange = false
                return
            }
            if index == 0 {
                viewModel.currentCategory = nil
            } else {
                viewModel.currentCategory = viewModel.categories[index - 1]
            }
            locked = viewModel.isCategoryLocked()
            updateLockState()
            deselectAllItems()
            updateToolbar()
            updateNavbarItems()

            await viewModel.loadLibrary()
            updateEmptyState()
            updateDataSource()
        }
    }
}
