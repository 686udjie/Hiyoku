//
//  SourceSearchViewController.swift
//  Aidoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import Combine
import SwiftUI

class SourceSearchViewController: MangaCollectionViewController {
    let viewModel: SourceSearchViewModel
    let source: AidokuRunner.Source

    var searchText: String = ""
    var enabledFilters: [FilterValue] = [] {
        didSet {
            if viewModel.hasAppeared && enabledFilters != oldValue {
                viewModel.loadManga(
                    searchText: searchText,
                    filters: enabledFilters,
                    force: true
                )
            }
        }
    }

    override var entries: [AidokuRunner.Manga] {
        get { viewModel.entries }
        set { viewModel.entries = newValue }
    }
    override var bookmarkedItems: Set<String> {
        get { viewModel.bookmarkedItems }
        set { viewModel.bookmarkedItems = newValue }
    }

    init(source: AidokuRunner.Source) {
        self.source = source
        self.viewModel = .init(source: source)
        super.init()
    }

    override func configure() {
        super.configure()

        errorView.onRetry = { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.viewModel.loadManga(
                searchText: self.searchText,
                filters: self.enabledFilters,
                force: true
            )
        }
    }

    override func observe() {
        super.observe()

        viewModel.$loadingInitial
            .sink { [weak self] loading in
                guard let self, !loading else { return }
                self.hideLoadingView()
            }
            .store(in: &cancellables)

        viewModel.$entries
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    if self.viewModel.error == nil {
                        self.updateDataSource()
                    }
                }
            }
            .store(in: &cancellables)

        viewModel.$error
            .sink { [weak self] error in
                guard let self else { return }
                if let error {
                    self.errorView.setError(error)
                    self.errorView.show()
                    self.clearEntries()
                } else {
                    self.errorView.hide()
                }
            }
            .store(in: &cancellables)

        viewModel.$shouldScrollToTop
            .sink { [weak self] shouldScroll in
                guard let self, shouldScroll else { return }
                self.scrollToTop()
                self.viewModel.shouldScrollToTop = false
            }
            .store(in: &cancellables)

        addObserver(forName: .init("refresh-content")) { [weak self] _ in
            guard let self else { return }
            self.viewModel.loadManga(
                searchText: self.searchText,
                filters: self.enabledFilters,
                force: true
            )
        }
    }
}

extension SourceSearchViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let manga = dataSource.itemIdentifier(for: indexPath) else { return }
        if isPlayerSource {
            // Handle player selection
            showPlayerDetails(for: manga, at: indexPath)
        } else {
            // Default manga handling
            super.collectionView(collectionView, didSelectItemAt: indexPath)
        }
    }

    private var isPlayerSource: Bool {
        // Player sources are represented by an Aidoku Source whose key is the module UUID string.
        playerModule(for: source.key) != nil
    }

    private func playerModule(for sourceKey: String) -> ScrapingModule? {
        if let uuid = UUID(uuidString: sourceKey) {
            if let module = ModuleManager.shared.modules.first(where: { $0.id == uuid && $0.isActive && $0.isPlayerModule }) {
                return module
            }
        }
        func normalize(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let sourceName = normalize(source.name)
        return ModuleManager.shared.modules.first(where: {
            $0.isActive && $0.isPlayerModule && normalize($0.metadata.sourceName) == sourceName
        })
    }

    private func showPlayerDetails(for manga: AidokuRunner.Manga, at indexPath: IndexPath) {
        let searchItem = SearchItem(
            title: manga.title,
            imageUrl: manga.cover ?? "",
            href: manga.key
        )

        // Find the module for this source
        var module = playerModule(for: source.key)

        if module == nil {
            module = ScrapingModule(
                id: UUID(),
                metadata: ModuleMetadata(
                    sourceName: source.name,
                    author: ModuleMetadata.Author(name: "Unknown", icon: ""),
                    iconUrl: "",
                    version: "1.0.0",
                    language: "en",
                    baseUrl: "",
                    streamType: "player",
                    quality: "HD",
                    searchBaseUrl: "",
                    scriptUrl: "",
                    asyncJS: nil,
                    streamAsyncJS: nil,
                    softsub: nil,
                    multiStream: nil,
                    multiSubs: nil,
                    type: nil,
                    novel: false
                ),
                localPath: "",
                metadataUrl: ""
            )
        }

        // Create and push PlayerInfoViewController
        let playerInfoVC = PlayerInfoViewController(
            searchItem: searchItem,
            module: module,
            path: NavigationCoordinator(rootViewController: parent?.navigationController)
        )

        // Add zoom transition animation (iOS 18+)
        if #available(iOS 18.0, *) {
            playerInfoVC.preferredTransition = .zoom { context in
                guard
                    context.zoomedViewController is PlayerInfoViewController,
                    let manga = self.dataSource.itemIdentifier(for: indexPath),
                    let indexPath = self.dataSource.indexPath(for: manga),
                    let cell = self.collectionView.cellForItem(at: indexPath)
                else {
                    return nil
                }
                if let cell = cell as? MangaListCell {
                    return cell.coverImageView
                } else {
                    return cell.contentView
                }
            }
        }

        if let navigationController = parent?.navigationController {
            navigationController.pushViewController(playerInfoVC, animated: true)
        } else {
            // Fallback: try to find navigation controller by walking up the responder chain
            var responder: UIResponder? = self
            while responder != nil {
                if let vc = responder as? UIViewController, let nav = vc.navigationController {
                    nav.pushViewController(playerInfoVC, animated: true)
                    break
                }
                responder = responder?.next
            }
        }
    }

    func onAppear() {
        viewModel.onAppear(searchText: searchText, filters: enabledFilters)
    }

    func scrollToTop(animated: Bool = true) {
        collectionView.setContentOffset(.init(x: 0, y: -view.safeAreaInsets.top), animated: animated)
    }

    @objc override func refresh(_ control: UIRefreshControl) {
        Task {
            viewModel.loadManga(searchText: searchText, filters: enabledFilters, force: true)
            await viewModel.waitForSearch()
            control.endRefreshing()
            scrollToTop() // it scrolls down slightly after refresh ends
        }
    }
}

// MARK: UICollectionViewDelegate
extension SourceSearchViewController {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        let mangaCount = viewModel.entries.count
        let hasMore = viewModel.hasMore
        if indexPath.row == mangaCount - 1 && hasMore {
            Task {
                await viewModel.loadMore(searchText: searchText, filters: enabledFilters)
            }
        }
    }
}

// MARK: UISearchBarDelegate
extension SourceSearchViewController {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        viewModel.loadManga(
            searchText: searchText,
            filters: enabledFilters,
            delay: true
        )
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        viewModel.loadManga(
            searchText: searchText,
            filters: enabledFilters,
            force: true
        )
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchText = ""
        viewModel.loadManga(
            searchText: searchText,
            filters: enabledFilters
        )
    }
}
