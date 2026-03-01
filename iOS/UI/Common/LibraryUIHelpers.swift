//
//  LibraryUIHelpers.swift
//  Hiyoku
//
//  Created by 686udjie on 2/19/26.
//

import UIKit
import AidokuRunner

// MARK: - Editing/Multi-Select UI

enum LibraryEditingUI {
    struct EditingNavbarConfig {
        let stopEditingTarget: AnyObject
        let stopEditingSelector: Selector
        let selectAllTarget: AnyObject
        let selectAllSelector: Selector
        let deselectAllTarget: AnyObject
        let deselectAllSelector: Selector
    }

    static func applyEditingNavbar(
        navigationItem: UINavigationItem,
        collectionView: UICollectionView,
        totalItemCount: Int,
        config: EditingNavbarConfig
    ) {
        let allItemsSelected = (collectionView.indexPathsForSelectedItems?.count ?? 0) == totalItemCount
        let selectToggle = UIBarButtonItem(
            title: NSLocalizedString(allItemsSelected ? "DESELECT_ALL" : "SELECT_ALL"),
            style: .plain,
            target: allItemsSelected ? config.deselectAllTarget : config.selectAllTarget,
            action: allItemsSelected ? config.deselectAllSelector : config.selectAllSelector
        )
        if #available(iOS 26.0, *) {
            selectToggle.sharesBackground = false
        }
        navigationItem.leftBarButtonItem = selectToggle
        navigationItem.rightBarButtonItems = [UIBarButtonItem(
            barButtonSystemItem: .done,
            target: config.stopEditingTarget,
            action: config.stopEditingSelector
        )]
    }

    static func applyNonEditingNavbar(
        navigationItem: UINavigationItem,
        leftBarButtonItem: UIBarButtonItem?,
        rightBarButtonItems: [UIBarButtonItem]?,
        animated: Bool
    ) {
        navigationItem.leftBarButtonItem = leftBarButtonItem
        navigationItem.setRightBarButtonItems(rightBarButtonItems, animated: animated)
    }

    static func updateToolbarVisibility(
        isEditing: Bool,
        navigationController: UINavigationController?,
        tabBarController: UITabBarController?
    ) {
        if isEditing {
            if navigationController?.isToolbarHidden ?? false {
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController?.isToolbarHidden = false
                    navigationController?.toolbar.alpha = 1
                    if #available(iOS 26.0, *) {
                        tabBarController?.isTabBarHidden = true
                    }
                }
            }
        } else if !(navigationController?.isToolbarHidden ?? true) {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController?.toolbar.alpha = 0
                if #available(iOS 26.0, *) {
                    tabBarController?.isTabBarHidden = false
                }
            } completion: { _ in
                navigationController?.isToolbarHidden = true
            }
        }
    }

    static func deselectAllItems<S: Hashable, I: Hashable>(
        collectionView: UICollectionView,
        dataSource: UICollectionViewDiffableDataSource<S, I>
    ) {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.deselectItem(at: indexPath, animated: false)
                let cell = collectionView.cellForItem(at: indexPath)
                LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: false)
            }
        }
    }

    static func deselectAllItems<T: Hashable>(
        collectionView: UICollectionView,
        dataSourceSnapshot: NSDiffableDataSourceSnapshot<String, T>,
        indexPathProvider: (T) -> IndexPath?
    ) {
        for item in dataSourceSnapshot.itemIdentifiers {
            if let indexPath = indexPathProvider(item) {
                collectionView.deselectItem(at: indexPath, animated: false)
                let cell = collectionView.cellForItem(at: indexPath)
                LibraryCellUI.setSelectedIfPossible(cell: cell, isSelected: false)
            }
        }
    }
}

// MARK: - Refresh UI

enum LibraryRefreshUI {
    static func handleRefreshAnimation(refreshControl: UIRefreshControl?) {
        Task {
            // delay hiding refresh control to avoid buggy animation
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                refreshControl?.endRefreshing()
            }
        }
    }
}

// MARK: - Cells

enum LibraryCellUI {
    static func highlightCellIfPossible(collectionView: UICollectionView, at indexPath: IndexPath, isEditing: Bool) {
        guard !isEditing else { return }
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.highlight()
        } else if let cell = cell as? MangaListCell {
            cell.highlight()
        }
    }

    static func unhighlightCellIfPossible(collectionView: UICollectionView, at indexPath: IndexPath, isEditing: Bool) {
        guard !isEditing else { return }
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? MangaGridCell {
            cell.unhighlight()
        } else if let cell = cell as? MangaListCell {
            cell.unhighlight()
        }
    }

    static func setSelectedIfPossible(cell: UICollectionViewCell?, isSelected: Bool) {
        guard let cell else { return }
        if let cell = cell as? MangaGridCell {
            cell.setSelected(isSelected)
        } else if let cell = cell as? MangaListCell {
            cell.setSelected(isSelected)
        }
    }

    static func configureCell(cell: UICollectionViewCell, info: MangaInfo, isEditing: Bool, badgeProvider: (MangaInfo) -> (Int, Int)) {
        if let cell = cell as? MangaGridCell {
            cell.sourceId = info.sourceId
            cell.mangaId = info.mangaId
            cell.title = info.title
            let (b1, b2) = badgeProvider(info)
            cell.badgeNumber = b1
            cell.badgeNumber2 = b2
            cell.setEditing(isEditing, animated: false)
        } else if let cell = cell as? MangaListCell {
            let (b1, b2) = badgeProvider(info)
            cell.configure(with: info)
            cell.badgeNumber = b1
            cell.badgeNumber2 = b2
            cell.setEditing(isEditing, animated: false)
        }
    }
}

// MARK: - Feedback

enum LibrarySelectionFeedback {
    static func selectionChanged(at point: CGPoint? = nil) {
        if #available(iOS 17.5, *), let point {
            UISelectionFeedbackGenerator().selectionChanged(at: point)
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - Navigation UI

enum LibraryNavigationUI {
    static func createZoomTransition(for vc: UIViewController, sourceViewProvider: @escaping () -> Any?) {
        if #available(iOS 18.0, *) {
            vc.preferredTransition = .zoom { _ in
                sourceViewProvider() as? UIView
            }
        }
    }
}

// MARK: - Menu Factory

enum LibraryMenuFactory {
    struct SortConfig<T: RawRepresentable & CaseIterable & Equatable> where T.RawValue == Int {
        let current: T
        let ascending: Bool
        let titleProvider: (T) -> String
        let ascendingTitleProvider: (T) -> String
        let descendingTitleProvider: (T) -> String
        let handler: (T, Bool) -> Void
    }

    static func makeSortMenu<T: RawRepresentable & CaseIterable & Equatable>(config: SortConfig<T>) -> UIMenu where T.RawValue == Int {
        UIMenu(
            title: NSLocalizedString("SORT_BY"),
            subtitle: config.titleProvider(config.current),
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: [
                UIMenu(options: .displayInline, children: T.allCases.map { method in
                    UIAction(title: config.titleProvider(method), state: config.current == method ? .on : .off) { _ in
                        config.handler(method, false)
                    }
                }),
                UIMenu(options: .displayInline, children: [false, true].map { ascending in
                    UIAction(title: ascending ? config.ascendingTitleProvider(config.current) : config.descendingTitleProvider(config.current),
                             state: config.ascending == ascending ? .on : .off) { _ in
                        config.handler(config.current, ascending)
                    }
                })
            ]
        )
    }

    struct FilterConfig<T: RawRepresentable & Codable & Equatable & CaseIterable> where T.RawValue == Int {
        let title: String
        let subtitle: String?
        let image: UIImage?
        let children: [UIMenuElement]
        let removeHandler: (() -> Void)?
    }

    static func makeFilterMenu<T: RawRepresentable & Codable & Equatable & CaseIterable>(config: FilterConfig<T>) -> UIMenu where T.RawValue == Int {
        let filters = UIMenu(
            title: config.title,
            subtitle: config.subtitle,
            image: config.image,
            children: config.children
        )
        if let removeHandler = config.removeHandler {
            let removeAction = LibraryFilterMenuUI.makeRemoveFilterAction(handler: removeHandler)
            return UIMenu(children: [filters, removeAction])
        }
        return filters
    }
}

// MARK: - Action Dispatcher

enum LibraryActionDispatcher {
    static func presentConfirmRemove(
        from vc: UIViewController,
        title: String,
        sourceItem: Any,
        handler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: .destructive) { _ in handler() })
        if let popover = alert.popoverPresentationController {
            if let item = sourceItem as? UIBarButtonItem {
                popover.barButtonItem = item
            } else if let view = sourceItem as? UIView {
                popover.sourceView = view
                popover.sourceRect = view.bounds
            }
        }
        vc.present(alert, animated: true)
    }
}

// MARK: - Context Menu Preview

enum LibraryContextMenuPreviewUI {
    static func targetedPreview(collectionView: UICollectionView, at indexPath: IndexPath) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
        let parameters = UIPreviewParameters()

        if let listCell = cell as? MangaListCell {
            let padding: CGFloat = 8
            let rect = listCell.bounds.insetBy(dx: -padding, dy: -padding)
            parameters.visiblePath = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            return UITargetedPreview(view: listCell.contentView, parameters: parameters)
        } else if let gridCell = cell as? MangaGridCell {
            parameters.visiblePath = UIBezierPath(
                roundedRect: gridCell.bounds,
                cornerRadius: gridCell.contentView.layer.cornerRadius
            )
            return UITargetedPreview(view: gridCell.contentView, parameters: parameters)
        }

        return nil
    }
}

// MARK: - Layout Configuration

enum LibraryLayoutUI {
    static func createCompositionalLayout(
        usesListLayout: Bool,
        hasCategories: Bool,
        interSectionSpacing: CGFloat,
        listSectionProvider: @escaping (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection,
        gridSectionProvider: @escaping (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection
    ) -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { _, env in
            usesListLayout ? listSectionProvider(env) : gridSectionProvider(env)
        }
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = interSectionSpacing
        if hasCategories {
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(40)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            config.boundarySupplementaryItems = [header]
        }
        layout.configuration = config
        return layout
    }
}

// MARK: - Layout

enum LibraryMoreMenuUI {
    static func makeSelectAction(startEditing: @escaping () -> Void) -> UIAction {
        UIAction(
            title: NSLocalizedString("SELECT"),
            image: UIImage(systemName: "checkmark.circle")
        ) { _ in
            startEditing()
        }
    }

    static func makeLayoutActions(
        usesListLayout: Bool,
        setUsesListLayout: @escaping (Bool) -> Void,
        collectionView: UICollectionView,
        makeCollectionViewLayout: @escaping () -> UICollectionViewLayout,
        updateMenu: @escaping () -> Void
    ) -> [UIAction] {
        [
            UIAction(
                title: NSLocalizedString("LAYOUT_GRID"),
                image: UIImage(systemName: "square.grid.2x2"),
                state: usesListLayout ? .off : .on
            ) { _ in
                guard usesListLayout else { return }
                setUsesListLayout(false)
                collectionView.setCollectionViewLayout(makeCollectionViewLayout(), animated: true)
                collectionView.reloadData()
                updateMenu()
            },
            UIAction(
                title: NSLocalizedString("LAYOUT_LIST"),
                image: UIImage(systemName: "list.bullet"),
                state: usesListLayout ? .on : .off
            ) { _ in
                guard !usesListLayout else { return }
                setUsesListLayout(true)
                collectionView.setCollectionViewLayout(makeCollectionViewLayout(), animated: true)
                collectionView.reloadData()
                updateMenu()
            }
        ]
    }
}

// MARK: - Filtering Menu

enum LibraryFilterMenuUI {
    @available(iOS 16.0, *)
    static func updateVisibleMenu(
        barButtonItem: UIBarButtonItem,
        update: @escaping (UIMenu) -> UIMenu
    ) {
        let contextMenuInteraction = barButtonItem.value(forKey: "_contextMenuInteraction") as? UIContextMenuInteraction
        guard let contextMenuInteraction else { return }
        contextMenuInteraction.updateVisibleMenu { menu in
            update(menu)
        }
    }

    static func applyFilterIcon(
        barButtonItem: UIBarButtonItem,
        hasActiveFilters: Bool
    ) {
        if hasActiveFilters {
            barButtonItem.isSelected = true
            barButtonItem.image = UIImage(systemName: "line.3.horizontal.decrease")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        } else {
            barButtonItem.isSelected = false
            barButtonItem.image = UIImage(systemName: "ellipsis")
        }
    }

    static func buildFiltersSubtitle<T: RawRepresentable & Codable & Equatable & CaseIterable>(
        filters: [LibraryFilter<T>],
        allMethods: T.AllCases,
        titleProvider: (T) -> String,
        valueProvider: (T, String) -> String?
    ) -> String? where T.RawValue == Int {
        guard !filters.isEmpty else { return nil }
        var options: [String] = []
        var methods: Set<T.RawValue> = []

        for filterMethod in allMethods {
            guard methods.insert(filterMethod.rawValue).inserted else {
                continue
            }

            if let filter = filters.first(where: { $0.type == filterMethod }) {
                guard options.count < 3 else {
                    options.removeLast()
                    options.append(NSLocalizedString("AND_MORE"))
                    break
                }

                if let value = filter.value {
                    if let resolvedValue = valueProvider(filter.type, value) {
                        options.append(resolvedValue)
                        continue
                    }
                }

                if filter.exclude {
                    options.append(String(format: NSLocalizedString("NOT_%@"), titleProvider(filter.type)))
                } else {
                    options.append(titleProvider(filter.type))
                }
            }
        }
        return options.joined(separator: NSLocalizedString("FILTER_SEPARATOR"))
    }

    static func makeRemoveFilterAction(
        handler: @escaping () -> Void
    ) -> UIAction {
        UIAction(
            title: NSLocalizedString("REMOVE_FILTER"),
            image: UIImage(systemName: "minus.circle")
        ) { _ in
            handler()
        }
    }
}

// MARK: - Lock UI

import LocalAuthentication

enum LibraryLockUI {
    static func attemptUnlock() async -> Bool {
        do {
            return try await LAContext().evaluatePolicy(
                .defaultPolicy,
                localizedReason: NSLocalizedString("AUTH_FOR_LIBRARY")
            )
        } catch {
            return false
        }
    }

    struct LockAnimationConfig {
        let locked: Bool
        let collectionView: UICollectionView
        let emptyStackView: UIView
        let lockedStackView: LockedPageStackView
        let lockBarButton: UIBarButtonItem
        let lockedText: String
    }

    static func updateLockAnimation(config: LockAnimationConfig) {
        if config.locked {
            guard config.emptyStackView.alpha != 0 else { return }
            config.collectionView.isScrollEnabled = false
            config.emptyStackView.alpha = 0
            config.lockedStackView.alpha = 0
            config.lockedStackView.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                config.lockedStackView.alpha = 1
            }
        } else {
            config.collectionView.isScrollEnabled = config.emptyStackView.isHidden
            config.lockedStackView.isHidden = true
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                config.emptyStackView.alpha = 1
            }
        }
        config.lockBarButton.image = UIImage(systemName: config.locked ? "lock" : "lock.open")
        config.lockedStackView.text = config.lockedText
    }

    static func updateNavbarLock(
        locked: Bool,
        isEditing: Bool,
        navigationItem: UINavigationItem,
        lockBarButton: UIBarButtonItem
    ) {
        guard !isEditing else { return }
        let index = navigationItem.rightBarButtonItems?.firstIndex(of: lockBarButton)
        if locked && index == nil {
            if navigationItem.rightBarButtonItems?.count ?? 0 == 0 {
                navigationItem.rightBarButtonItems = [lockBarButton]
            } else {
                navigationItem.rightBarButtonItems?.insert(lockBarButton, at: 1)
            }
        } else if !locked, let index = index {
            navigationItem.rightBarButtonItems?.remove(at: index)
        }
    }
}

// MARK: - Header UI

enum LibraryHeaderUI {
    static func updateLockIcons(
        collectionView: UICollectionView,
        core: LibraryCore,
        categories: [String]
    ) {
        guard let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader else { return }
        if core.isLibraryLockEnabled() {
            let lockedCategories = core.loadLockedCategories()
            header.lockedOptions = [0] + lockedCategories.compactMap { category -> Int? in
                if let index = categories.firstIndex(of: category) {
                    return index + 1
                }
                return nil
            }
        } else {
            header.lockedOptions = []
        }
    }

    static func updateCategories(
        collectionView: UICollectionView,
        categories: [String],
        currentCategory: String?
    ) {
        guard let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(index: 0)
        ) as? MangaListSelectionHeader else { return }
        header.options = [NSLocalizedString("ALL")] + categories
        header.setSelectedOption(
            currentCategory != nil
                ? (categories.firstIndex(of: currentCategory!) ?? -1) + 1
                : 0
        )
    }
}
