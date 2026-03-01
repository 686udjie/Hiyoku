//
//  PlayerLibraryViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/03/2026.
//

import UIKit
import SwiftUI
import NukeUI
import Nuke
import AidokuRunner
import Combine
import CoreData
import LocalAuthentication

class PlayerLibraryViewController: BaseObservingViewController {
    private let path = NavigationCoordinator(rootViewController: nil)
    private var searchController: UISearchController!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionViewLayout())
    private lazy var dataSource = makeDataSource()
    private var currentItems: [PlayerLibraryEntry] = []
    private lazy var refreshControl = UIRefreshControl()
    private lazy var emptyStackView = EmptyPageStackView()
    private lazy var lockedStackView = LockedPageStackView()
    private let viewModel = PlayerLibraryViewModel()
    private let searchViewModel = PlayerLibrarySearchViewModel()
    private var downloadObservers = Set<AnyCancellable>()

    private var searchText = ""
    private lazy var locked = viewModel.isCategoryLocked()
    private var ignoreOptionChange = false

    private lazy var deleteToolbarButton: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(removeSelectedFromLibrary))
        item.tintColor = .systemRed
        return item
    }()

    private static let itemSpacing: CGFloat = 12
    private static let sectionSpacing: CGFloat = 6

    private var usesListLayout: Bool {
        get { UserDefaults.standard.bool(forKey: "PlayerLibrary.listView") }
        set { UserDefaults.standard.setValue(newValue, forKey: "PlayerLibrary.listView") }
    }

    // MARK: - Bar Buttons
    private lazy var downloadBarButton = makeBarButton(
        systemName: "square.and.arrow.down", action: #selector(openDownloadQueue), titleKey: "DOWNLOAD_QUEUE"
    )
    private lazy var updatesBarButton = makeBarButton(
        systemName: "bell", action: #selector(openUpdates), titleKey: "MANGA_UPDATES"
    )
    private lazy var moreBarButton = makeBarButton(
        systemName: "ellipsis", action: nil, titleKey: "MORE_BARBUTTON"
    )
    private lazy var lockBarButton = makeBarButton(
        systemName: locked ? "lock" : "lock.open", action: #selector(performToggleLock), titleKey: "TOGGLE_LOCK"
    )

    private func makeBarButton(systemName: String, action: Selector?, titleKey: String) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: systemName), style: .plain, target: self, action: action)
        item.title = NSLocalizedString(titleKey)
        if #available(iOS 26.0, *) { item.sharesBackground = false }
        return item
    }

    override func configure() {
        super.configure()
        title = NSLocalizedString("PLAYER")
        navigationController?.navigationBar.prefersLargeTitles = true
        path.rootViewController = self.navigationController

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search in Player"
        navigationItem.searchController = searchController

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.register(MangaGridCell.self, forCellWithReuseIdentifier: "MangaGridCell")
        collectionView.register(MangaListCell.self, forCellWithReuseIdentifier: "MangaListCell")
        collectionView.dataSource = dataSource
        collectionView.alwaysBounceVertical = true
        collectionView.allowsSelectionDuringEditing = true
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        view.addSubview(collectionView)

        let registration = UICollectionView.SupplementaryRegistration<MangaListSelectionHeader>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, _ in
            guard let self else { return }
            header.delegate = self
            header.options = [NSLocalizedString("ALL")] + self.viewModel.categories

            let currentCategory = self.viewModel.currentCategory
            let categories = self.viewModel.categories
            header.selectedOption = currentCategory != nil ? (
                categories.firstIndex(of: currentCategory!) ?? -1
            ) + 1 : 0
            header.updateMenu()

            if self.viewModel.core.isLibraryLockEnabled() {
                let lockedCategories = self.viewModel.core.loadLockedCategories()
                header.lockedOptions = [0] + lockedCategories.compactMap { cat in
                    categories.firstIndex(of: cat).map { $0 + 1 }
                }
            } else {
                header.lockedOptions = []
            }
        }

        dataSource.supplementaryViewProvider = { cv, kind, ip in
            kind == UICollectionView.elementKindSectionHeader ? cv.dequeueConfiguredReusableSupplementary(using: registration, for: ip) : nil
        }

        Task {
            await SourceManager.shared.loadSources()
            await DownloadManager.shared.loadQueueState()
            await viewModel.refreshCategories()
            collectionView.collectionViewLayout = makeCollectionViewLayout()
            await viewModel.loadLibrary()
            updateNavbarItems()
        }

        [emptyStackView, lockedStackView].forEach { view.addSubview($0) }
        emptyStackView.imageSystemName = "play.tv.fill"
        emptyStackView.title = NSLocalizedString("PLAYER_EMPTY")
        emptyStackView.text = NSLocalizedString("PLAYER_ADD_CONTENT")
        lockedStackView.text = NSLocalizedString("LIBRARY_LOCKED")
        lockedStackView.buttonText = NSLocalizedString("VIEW_LIBRARY")
        lockedStackView.button.addTarget(self, action: #selector(performUnlock), for: .touchUpInside)

        viewModel.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.applySnapshot(animated: true)
        }.store(in: &downloadObservers)

        searchViewModel.$results.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.applySnapshot(animated: true)
        }.store(in: &downloadObservers)

        toolbarItems = [deleteToolbarButton, UIBarButtonItem(systemItem: .flexibleSpace)]
        updateMoreMenu()
        updateLockState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        locked = viewModel.isCategoryLocked()
        updateLockState()
        updateNavbarItems()
        updateMoreMenu()
    }

    override func constrain() {
        super.constrain()
        [collectionView, emptyStackView, lockedStackView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lockedStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockedStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func updateEmptyState() {
        let isEmpty = viewModel.items.isEmpty && viewModel.pinnedItems.isEmpty && searchText.isEmpty
        emptyStackView.title = viewModel.currentCategory == nil ? NSLocalizedString("PLAYER_EMPTY") : NSLocalizedString("CATEGORY_EMPTY")
        emptyStackView.isHidden = locked || !isEmpty
        collectionView.isScrollEnabled = emptyStackView.isHidden && lockedStackView.isHidden
        collectionView.refreshControl = collectionView.isScrollEnabled ? refreshControl : nil
    }

    override func observe() {
        super.observe()
        addObserver(forName: "General.portraitRows") { [weak self] _ in
            Task { @MainActor in self?.collectionView.collectionViewLayout.invalidateLayout() }
        }
        addObserver(forName: "General.landscapeRows") { [weak self] _ in
            Task { @MainActor in self?.collectionView.collectionViewLayout.invalidateLayout() }
        }

        let notifications: [Notification.Name] = [
            .downloadFinished, .downloadRemoved, .downloadsRemoved
        ]
        addObservers(forNames: notifications) { [weak self] _ in
            Task { await self?.viewModel.refreshLibrary() }
        }

        addObserver(forName: .updatePlayerLibraryLock) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
                self.updateHeaderLockIcons()
            }
        }
        addObserver(forName: UIApplication.willResignActiveNotification) { [weak self] _ in
            self?.locked = self?.viewModel.isCategoryLocked() ?? false
            self?.updateLockState()
        }
        addObserver(forName: .updatePlayerCategories) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.refreshCategories()
                self.collectionView.collectionViewLayout = self.makeCollectionViewLayout()
                self.updateHeaderCategories()
                await self.viewModel.loadLibrary()
                self.applySnapshot(animated: false)
            }
        }

        addObserver(forName: Notification.Name("PlayerLibrary.unreadChapterBadges")) { [weak self] _ in
            guard let self else { return }
            self.viewModel.badgeType.setPresence(.unwatched, if: self.viewModel.core.unreadBadgeEnabled())
            self.reloadItems()
        }
        addObserver(forName: Notification.Name("PlayerLibrary.downloadedChapterBadges")) { [weak self] _ in
            guard let self else { return }
            self.viewModel.badgeType.setPresence(.downloaded, if: self.viewModel.core.downloadedBadgeEnabled())
            self.reloadItems()
        }
        addObserver(forName: Notification.Name("PlayerLibrary.pinTitles")) { [weak self] _ in
            self?.viewModel.pinType = self?.viewModel.getPinType() ?? .none
            Task { await self?.viewModel.refreshLibrary() }
        }

        let navNotifications: [Notification.Name] = [
            .downloadsQueued, .downloadCancelled, .downloadsCancelled, .downloadFinished
        ]
        addObservers(forNames: navNotifications) { [weak self] _ in
            self?.updateNavbarItems()
        }
    }
}

// MARK: - Actions & UI Updates
extension PlayerLibraryViewController {
    func updateNavbarItems() {
        if isEditing {
            let config = LibraryEditingUI.EditingNavbarConfig(
                stopEditingTarget: self, stopEditingSelector: #selector(stopEditing),
                selectAllTarget: self, selectAllSelector: #selector(selectAllItems),
                deselectAllTarget: self, deselectAllSelector: #selector(deselectAllItems)
            )
            LibraryEditingUI.applyEditingNavbar(
                navigationItem: navigationItem, collectionView: collectionView,
                totalItemCount: dataSource.snapshot().itemIdentifiers.count, config: config
            )
            return
        }
        navigationItem.leftBarButtonItem = nil
        Task { @MainActor in
            let hasDownloads = await DownloadManager.shared.hasQueuedDownloads(type: .video)
            let items = [moreBarButton, updatesBarButton] + (hasDownloads ? [downloadBarButton] : [])
            navigationItem.setRightBarButtonItems(items, animated: true)
            updateNavbarLock()
        }
    }

    func updateToolbar() {
        if isEditing {
            LibraryEditingUI.updateToolbarVisibility(isEditing: true, navigationController: navigationController, tabBarController: tabBarController)
            toolbarItems?.first?.isEnabled = !(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
        } else {
            LibraryEditingUI.updateToolbarVisibility(isEditing: false, navigationController: navigationController, tabBarController: tabBarController)
        }
    }

    @objc func stopEditing() { setEditing(false, animated: true); deselectAllItems() }
    @objc func selectAllItems() {
        dataSource.snapshot().itemIdentifiers.forEach { item in
            guard let indexPath = dataSource.indexPath(for: item) else { return }
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            LibraryCellUI.setSelectedIfPossible(
                cell: collectionView.cellForItem(at: indexPath), isSelected: true
            )
        }
        updateNavbarItems()
        updateToolbar()
    }

    @objc func deselectAllItems() {
        LibraryEditingUI.deselectAllItems(collectionView: collectionView, dataSource: dataSource)
        updateNavbarItems()
        updateToolbar()
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl? = nil) {
        LibraryRefreshUI.handleRefreshAnimation(refreshControl: refreshControl)
        Task {
            await PlayerLibraryManager.shared.backgroundRefreshLibrary(category: viewModel.currentCategory)
        }
    }

    func updateNavbarLock() {
        LibraryLockUI.updateNavbarLock(
            locked: locked,
            isEditing: isEditing,
            navigationItem: navigationItem,
            lockBarButton: lockBarButton
        )
    }
    func updateHeaderLockIcons() {
        LibraryHeaderUI.updateLockIcons(
            collectionView: collectionView,
            core: viewModel.core,
            categories: viewModel.categories
        )
    }
    func updateHeaderCategories() {
        LibraryHeaderUI.updateCategories(
            collectionView: collectionView,
            categories: viewModel.categories,
            currentCategory: viewModel.currentCategory
        )
    }

    func unlock() async { if await LibraryLockUI.attemptUnlock() { locked = false; updateLockState() } }
    @objc func performUnlock() { Task { await unlock() } }
    @objc func performToggleLock() { Task { if locked { await unlock() } else { locked = true; updateLockState() } } }

    func updateLockState() {
        let lockedText = viewModel.currentCategory == nil ? NSLocalizedString("LIBRARY_LOCKED") : NSLocalizedString("CATEGORY_LOCKED")
        LibraryLockUI.updateLockAnimation(config: .init(
            locked: locked, collectionView: collectionView, emptyStackView: emptyStackView,
            lockedStackView: lockedStackView, lockBarButton: lockBarButton, lockedText: lockedText
        ))
        lockBarButton.image = UIImage(systemName: locked ? "lock" : "lock.open")
        updateEmptyState()
        updateNavbarLock()
        updateHeaderLockIcons()
        applySnapshot(animated: false)
    }

    @objc private func removeSelectedFromLibrary() {
        let bookmarks = (collectionView.indexPathsForSelectedItems ?? []).compactMap { dataSource.itemIdentifier(for: $0)?.bookmark }
        guard !bookmarks.isEmpty else { return }

        LibraryActionDispatcher.presentConfirmRemove(
            from: self,
            title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
            sourceItem: deleteToolbarButton
        ) { [weak self] in
            bookmarks.forEach { PlayerLibraryManager.shared.removeFromLibrary($0) }
            self?.stopEditing()
        }
    }
}

// MARK: - Navigation Hub
extension PlayerLibraryViewController {
    @objc func openUpdates() {
        navigationController?.pushViewController(
            UIHostingController(
                rootView: MangaUpdatesView().environmentObject(path)
            ),
            animated: true
        )
    }
    @objc func openDownloadQueue() {
        let vc = UIHostingController(rootView: DownloadQueueView(type: .video))
        LibraryNavigationUI.createZoomTransition(
            for: vc,
            sourceViewProvider: { [weak self] in self?.downloadBarButton.customView }
        )
        present(vc, animated: true)
    }
    private func handleItemSelection(_ item: PlayerLibraryEntry) {
        guard !locked, let module = ModuleManager.shared.modules.first(where: { $0.id == item.moduleId }) else { return }
        if UserDefaults.standard.bool(forKey: "PlayerLibrary.opensPlayerView"), let bookmark = item.bookmark {
            Task {
                await PlayerLibraryNavHelper.openPlayerView(for: bookmark, module: module, from: self) {
                    await self.viewModel.refreshLibrary()
                }
            }
        } else {
            let searchItem = SearchItem(title: item.title, imageUrl: item.imageUrl, href: item.href)
            let vc = PlayerInfoViewController(bookmark: item.bookmark, searchItem: searchItem, module: module, path: path)
            LibraryNavigationUI.createZoomTransition(
                for: vc,
                sourceViewProvider: { [weak self] in
                    self?.dataSource.indexPath(for: item).flatMap { self?.collectionView.cellForItem(at: $0)?.contentView }
                }
            )
            path.push(vc)
        }
    }
}
// MARK: - Menu Generation
extension PlayerLibraryViewController {
    private func filtersSubtitle() -> String? {
        LibraryFilterMenuUI.buildFiltersSubtitle(
            filters: viewModel.filters,
            allMethods: PlayerLibraryViewModel.FilterMethod.allCases,
            titleProvider: { $0.title },
            valueProvider: { type, value in
                type == .source ? SourceManager.shared.source(for: value)?.name ?? value : nil
            }
        )
    }

    func removeFilterAction() -> UIAction {
        LibraryFilterMenuUI.makeRemoveFilterAction { [weak self] in
            Task {
                self?.viewModel.filters.removeAll()
                await self?.viewModel.loadLibrary()
                self?.updateMoreMenu()
            }
        }
    }

    func updateMoreMenu() {
        let layoutActions = LibraryMoreMenuUI.makeLayoutActions(
            usesListLayout: usesListLayout,
            setUsesListLayout: { [weak self] in self?.usesListLayout = $0 },
            collectionView: collectionView,
            makeCollectionViewLayout: { [weak self] in
                self?.makeCollectionViewLayout() ?? UICollectionViewFlowLayout()
            },
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
                        self?.updateMoreMenu()
                    }
                }
            )
        )

        let filterMenu = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
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
                        self.updateMoreMenu()
                    }
                }
            }
            let config = LibraryMenuFactory.FilterConfig<PlayerLibraryViewModel.FilterMethod>(
                title: NSLocalizedString("BUTTON_FILTER"),
                subtitle: self.filtersSubtitle(),
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                children: children,
                removeHandler: self.viewModel.filters.isEmpty ? nil : { [weak self] in
                    Task { self?.viewModel.filters.removeAll(); await self?.viewModel.loadLibrary(); self?.updateMoreMenu() }
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
}

// MARK: - Collection View & Data Source
extension PlayerLibraryViewController: UICollectionViewDelegate, UISearchResultsUpdating {
    private enum Section: Int, CaseIterable { case pinned, main }
    private struct PlayerLibraryEntry: Hashable {
        let kind: Int
        let title, imageUrl, href: String
        let moduleId: UUID
        let bookmark: PlayerLibraryItem?
        let itemInfo: PlayerLibraryViewModel.PlayerLibraryItemInfo?
        func hash(into h: inout Hasher) {
            if let i = itemInfo {
                h.combine(i)
            } else {
                h.combine(moduleId)
                h.combine(href)
                h.combine(title)
            }
        }
        static func == (l: PlayerLibraryEntry, r: PlayerLibraryEntry) -> Bool { l.hashValue == r.hashValue }
    }

    func updateSearchResults(for sc: UISearchController) {
        searchText = sc.searchBar.text ?? ""
        Task {
            await viewModel.search(query: searchText)
            applySnapshot(animated: true)
        }
    }

    private func applySnapshot(animated: Bool) {
        let pinned = viewModel.pinnedItems.map {
            PlayerLibraryEntry(
                kind: 0, title: $0.item.title, imageUrl: $0.item.imageUrl,
                href: $0.item.sourceUrl, moduleId: $0.item.moduleId, bookmark: $0.item, itemInfo: $0
            )
        }
        let main = viewModel.items.map {
            PlayerLibraryEntry(
                kind: 0, title: $0.item.title, imageUrl: $0.item.imageUrl,
                href: $0.item.sourceUrl, moduleId: $0.item.moduleId, bookmark: $0.item, itemInfo: $0
            )
        }
        var snap = NSDiffableDataSourceSnapshot<Section, PlayerLibraryEntry>()
        if !locked {
            if !pinned.isEmpty {
                snap.appendSections([.pinned, .main])
                snap.appendItems(pinned, toSection: .pinned)
            } else {
                snap.appendSections([.main])
            }
            snap.appendItems(main, toSection: .main)
        }
        dataSource.apply(snap, animatingDifferences: animated)
        updateEmptyState()
    }

    private func reloadItems() {
        var snap = dataSource.snapshot()
        snap.reconfigureItems(snap.itemIdentifiers)
        dataSource.apply(snap, animatingDifferences: false)
    }

    private func makeCollectionViewLayout() -> UICollectionViewLayout {
        LibraryLayoutUI.createCompositionalLayout(
            usesListLayout: usesListLayout,
            hasCategories: !viewModel.categories.isEmpty,
            interSectionSpacing: Self.itemSpacing + Self.sectionSpacing,
            listSectionProvider: Self.makeListLayoutSection,
            gridSectionProvider: Self.makeGridLayoutSection
        )
    }

    static func makeListLayoutSection(env: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(100)))
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(100)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)
        section.interGroupSpacing = 10
        return section
    }

    static func makeGridLayoutSection(env: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let isLandscape = env.container.contentSize.width > env.container.contentSize.height
        let key = isLandscape ? "General.landscapeRows" : "General.portraitRows"
        let cols = UserDefaults.standard.integer(forKey: key)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(cols)),
            heightDimension: .fractionalWidth(3 / (2 * CGFloat(cols)))
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupHeight = env.container.contentSize.width * 3 / (2 * CGFloat(cols))
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(groupHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: cols)
        group.interItemSpacing = .fixed(itemSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)
        section.interGroupSpacing = itemSpacing
        return section
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, PlayerLibraryEntry> {
        UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] cv, ip, item in
            guard let self else { return UICollectionViewCell() }
            let mangaInfo = MangaInfo(
                mangaId: item.href.normalizedModuleHref(), sourceId: item.moduleId.uuidString,
                coverUrl: URL(string: item.imageUrl), title: item.title, author: nil,
                url: URL(string: item.href), unread: item.itemInfo?.unread ?? 0,
                downloads: item.itemInfo?.downloads ?? 0
            )

            if self.usesListLayout {
                guard let cell = cv.dequeueReusableCell(withReuseIdentifier: "MangaListCell", for: ip) as? MangaListCell else {
                    return UICollectionViewCell()
                }
                LibraryCellUI.configureCell(cell: cell, info: mangaInfo, isEditing: self.isEditing) { _ in
                    (self.viewModel.badgeType.contains(.unwatched) ? (item.itemInfo?.unread ?? 0) : 0,
                     self.viewModel.badgeType.contains(.downloaded) ? (item.itemInfo?.downloads ?? 0) : 0)
                }
                return cell
            } else {
                guard let cell = cv.dequeueReusableCell(withReuseIdentifier: "MangaGridCell", for: ip) as? MangaGridCell else {
                    return UICollectionViewCell()
                }
                LibraryCellUI.configureCell(cell: cell, info: mangaInfo, isEditing: self.isEditing) { _ in
                    (self.viewModel.badgeType.contains(.unwatched) ? (item.itemInfo?.unread ?? 0) : 0,
                     self.viewModel.badgeType.contains(.downloaded) ? (item.itemInfo?.downloads ?? 0) : 0)
                }
                Task { await cell.loadImage(url: URL(string: item.imageUrl)) }
                return cell
            }
        }
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        if let item = dataSource.itemIdentifier(for: ip) { handleItemSelection(item) }
    }
    func collectionView(
        _ cv: UICollectionView, contextMenuConfigurationForItemsAt ips: [IndexPath], point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isEditing, !locked, let ip = ips.first, let entry = dataSource.itemIdentifier(for: ip),
              let bookmark = entry.bookmark else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let actions: [UIMenuElement] = self.buildContextMenuActions(for: bookmark)
            return UIMenu(children: actions)
        }
    }

    private func buildContextMenuActions(for bookmark: PlayerLibraryItem) -> [UIMenuElement] {
        let markMenu = UIMenu(title: NSLocalizedString("MARK_ALL"), children: [
            UIAction(title: NSLocalizedString("WATCHED"), image: UIImage(systemName: "eye")) { _ in
                Task { await self.viewModel.markEpisodes(items: [bookmark], watched: true) }
            },
            UIAction(title: NSLocalizedString("UNWATCHED"), image: UIImage(systemName: "eye.slash")) { _ in
                Task { await self.viewModel.markEpisodes(items: [bookmark], watched: false) }
            }
        ])

        let downloadMenu = UIMenu(
            title: NSLocalizedString("DOWNLOAD"),
            image: UIImage(systemName: "arrow.down.circle"),
            children: [
                UIAction(title: NSLocalizedString("ALL")) { _ in
                    Task { await self.viewModel.downloadBatch(items: [bookmark], unwatchedOnly: false) }
                },
                UIAction(title: NSLocalizedString("UNWATCHED")) { _ in
                    Task { await self.viewModel.downloadBatch(items: [bookmark], unwatchedOnly: true) }
                }
            ]
        )

        let categoriesMenu: UIMenu? = viewModel.categories.isEmpty ? nil : UIMenu(
            title: NSLocalizedString("CATEGORIES"), image: UIImage(systemName: "folder"),
            children: viewModel.categories.map { category in
                let selected = viewModel.categories(for: bookmark).contains(category)
                return UIAction(title: category, state: selected ? .on : .off) { _ in
                    Task { await self.viewModel.toggleCategory(for: bookmark, category: category); self.applySnapshot(animated: true) }
                }
            }
        )

        let remove = UIAction(title: NSLocalizedString("REMOVE_FROM_LIBRARY"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            PlayerLibraryManager.shared.removeFromLibrary(bookmark)
        }

        return [markMenu, downloadMenu] + (categoriesMenu != nil ? [categoriesMenu!] : []) + [remove]
    }
}

// MARK: - Header Delegate

extension PlayerLibraryViewController: MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int) {
        Task { @MainActor in
            guard !ignoreOptionChange else { ignoreOptionChange = false; return }
            viewModel.currentCategory = index == 0 ? nil : viewModel.categories[index - 1]
            locked = viewModel.isCategoryLocked(); updateLockState()
            await viewModel.loadLibrary(); applySnapshot(animated: false)
        }
    }
}

extension PlayerLibraryViewModel.BadgeType {
    mutating func setPresence(_ element: Self, if condition: Bool) { if condition { insert(element) } else { remove(element) } }
}
