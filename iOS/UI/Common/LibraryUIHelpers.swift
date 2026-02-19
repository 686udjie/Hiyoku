//
//  LibraryUIHelpers.swift
//  Hiyoku
//
//  Created by 686udjie on 2/19/26.
//

import UIKit

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
        } else if cell is MangaGridCell {
            parameters.visiblePath = UIBezierPath(
                roundedRect: cell.bounds,
                cornerRadius: cell.contentView.layer.cornerRadius
            )
            return UITargetedPreview(view: cell.contentView, parameters: parameters)
        }

        return nil
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
}
