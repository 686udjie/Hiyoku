//
//  PlayerSourceViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import UIKit
import SwiftUI
import NukeUI

class PlayerSourceViewController: UIViewController {

    let module: ScrapingModule
    private var searchController: UISearchController!
    private var resultsViewController: PlayerSearchResultsViewController!
    private var initialSearchQuery: String?
    private var initialView: UIHostingController<PlayerSourceInitialView>?

    init(module: ScrapingModule, initialSearchQuery: String? = nil) {
        self.module = module
        self.initialSearchQuery = initialSearchQuery
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
    }

    func configure() {
        title = module.metadata.sourceName
        view.backgroundColor = .systemBackground

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        resultsViewController = PlayerSearchResultsViewController(module: module, parentVC: self)
        searchController = UISearchController(searchResultsController: resultsViewController)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = true
        searchController.searchBar.delegate = self

        if #available(iOS 16, *) {
            navigationItem.preferredSearchBarPlacement = .stacked
        }

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        // fix iPadOS 26 bug
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            typealias SetClearAsCancelButtonVisibility = @convention(c) (NSObject, Selector, NSInteger) -> Void
            let selector = NSSelectorFromString("_setClearAsCancelButtonVisibilityWhenEmpty:")
            let methodIMP = searchController.method(for: selector)
            let method = unsafeBitCast(methodIMP, to: SetClearAsCancelButtonVisibility.self)
            method(searchController, selector, 1)
        }

        if let initialQuery = initialSearchQuery, !initialQuery.isEmpty {
            searchController.searchBar.text = initialQuery
            searchController.isActive = true
            resultsViewController.performSearch(query: initialQuery)
            searchController.searchResultsController?.view.isHidden = false
        } else {
            showInitialView()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let initialQuery = initialSearchQuery, !initialQuery.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.hideInitialView()
                self?.searchController.searchBar.becomeFirstResponder()
            }
        }
    }

    private func showInitialView() {
        initialView = UIHostingController(rootView: PlayerSourceInitialView(module: module))
        guard let initialView = initialView else { return }
        addChild(initialView)
        initialView.view.frame = view.bounds
        initialView.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(initialView.view)
        initialView.didMove(toParent: self)
    }

    private func hideInitialView() {
        initialView?.willMove(toParent: nil)
        initialView?.view.removeFromSuperview()
        initialView?.removeFromParent()
        initialView = nil
    }

    func navigateToPlayerDetails(title: String, imageUrl: String, href: String) {
        let playerItem = SearchItem(title: title, imageUrl: imageUrl, href: href)
        let infoVC = PlayerInfoViewController(
            searchItem: playerItem,
            module: module,
            path: NavigationCoordinator(rootViewController: self)
        )

        if #available(iOS 18.0, *) {
            infoVC.preferredTransition = .zoom { _ in
                guard let resultsVC = self.searchController.searchResultsController as? PlayerSearchResultsViewController else {
                     return nil
                }

                guard let cell = resultsVC.cell(for: playerItem) as? MangaGridCell else {
                    return nil
                }

                return cell.contentView
            }
        }

        if let navController = navigationController {
            navController.pushViewController(infoVC, animated: true)
        } else if let presentingVC = parent?.presentingViewController ?? presentingViewController {
            presentingVC.present(infoVC, animated: true)
        }
    }

    private func showQualitySelection(streamUrls: [String], title: String) {
        let alert = UIAlertController(
            title: "Select Quality",
            message: "Choose video quality to stream",
            preferredStyle: .actionSheet
        )

        for (index, streamUrl) in streamUrls.enumerated() {
            let qualityLabel = "Quality \(index + 1)"
            let action = UIAlertAction(title: qualityLabel, style: .default) { [weak self] _ in
                guard let self = self else { return }
                let videoPlayer = PlayerViewController(
                    module: self.module,
                    videoUrl: streamUrl,
                    videoTitle: title
                )
                self.navigationController?.pushViewController(videoPlayer, animated: true)
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }

        present(alert, animated: true)
    }
}

extension PlayerSourceViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let query = searchController.searchBar.text, !query.isEmpty else {
            return
        }

        if let resultsVC = searchController.searchResultsController as? PlayerSearchResultsViewController {
            resultsVC.performSearch(query: query)
        }
    }
}

extension PlayerSourceViewController: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let query = searchBar.text, !query.isEmpty else {
            return
        }
        searchController.searchResultsController?.view.isHidden = false
    }
}

struct PlayerSourceInitialView: View {
    let module: ScrapingModule

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            LazyImage(url: URL(string: module.metadata.iconUrl)) { state in
                if let uiImage = state.imageContainer?.image {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.gray)
                        )
                }
            }

            Text("Search")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter a title in the search bar above to find content from \(module.metadata.sourceName)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

class PlayerSearchResultsViewController: UIViewController, DebouncedSearchable {
    private enum Section {
        case main
    }
    let module: ScrapingModule
    private var results: [SearchItem] = []
    private weak var parentPlayerSourceVC: PlayerSourceViewController?
    var searchDebounceTimer: Timer?
    var currentSearchTask: Task<Void, Never>?
    private var isLoading = false
    // UI Elements
    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            guard let self = self else { return nil }
            return self.createLayout(environment: environment)
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        return collectionView
    }()
    private lazy var dataSource = makeDataSource()
    private lazy var placeholderView: UIHostingController<PlaceholderGridView> = {
        let hostingController = UIHostingController(rootView: PlaceholderGridView())
        hostingController.view.backgroundColor = .systemBackground
        return hostingController
    }()
    private lazy var emptyView: UIHostingController<UnavailableView> = {
        let hostingController = UIHostingController(
            rootView: UnavailableView(
                "No results found",
                systemImage: "magnifyingglass",
                description: Text("Try adjusting your search terms")
            )
        )
        hostingController.view.backgroundColor = .systemBackground
        return hostingController
    }()
    init(module: ScrapingModule, parentVC: PlayerSourceViewController) {
        self.module = module
        self.parentPlayerSourceVC = parentVC
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupDataSource()
    }
    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // Add placeholder view as a child view controller
        addChild(placeholderView)
        view.addSubview(placeholderView.view)
        placeholderView.view.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.didMove(toParent: self)
        placeholderView.view.isHidden = true
        // Add empty view as a child view controller
        addChild(emptyView)
        view.addSubview(emptyView.view)
        emptyView.view.translatesAutoresizingMaskIntoConstraints = false
        emptyView.didMove(toParent: self)
        emptyView.view.isHidden = true
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholderView.view.topAnchor.constraint(equalTo: view.topAnchor),
            placeholderView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholderView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyView.view.topAnchor.constraint(equalTo: view.topAnchor),
            emptyView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    private func setupDataSource() {
        collectionView.register(MangaGridCell.self, forCellWithReuseIdentifier: "MangaGridCell")
    }
    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, SearchItem> {
        UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            // swiftlint:disable force_cast
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaGridCell", for: indexPath) as! MangaGridCell
            // swiftlint:enable force_cast
            cell.title = item.title
            cell.sourceId = self.module.id.uuidString
            Task {
                await cell.loadImage(url: URL(string: item.imageUrl))
            }
            return cell
        }
    }
    private func createLayout(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemsPerRow = UserDefaults.standard.integer(
            forKey: environment.container.contentSize.width > environment.container.contentSize.height
            ? "General.landscapeRows"
            : "General.portraitRows"
        )

        let count = itemsPerRow > 0 ? itemsPerRow : (environment.container.contentSize.width > environment.container.contentSize.height ? 4 : 2)

        let itemSpacing: CGFloat = 12

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1 / CGFloat(count)),
            heightDimension: .fractionalWidth(3 / (2 * CGFloat(count)))
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(environment.container.contentSize.width * 3 / (2 * CGFloat(count)))
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: count)
        group.interItemSpacing = .fixed(itemSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        section.interGroupSpacing = itemSpacing

        return section
    }
    func performSearch(query: String) {
        guard !query.isEmpty else {
            updateSnapshot(with: [])
            placeholderView.view.isHidden = true
            emptyView.view.isHidden = true
            collectionView.isHidden = false
            return
        }

        isLoading = true
        placeholderView.view.isHidden = false
        emptyView.view.isHidden = true
        collectionView.isHidden = true

        performSearch(query: query, delay: 0.7) { [weak self] in
            await self?.executeSearch(query: query)
        }
    }

    private func executeSearch(query: String) async {
        guard !Task.isCancelled else { return }
        await JSController.shared.loadModuleScript(module)
        guard !Task.isCancelled else { return }
        let searchResults = await performJavaScriptSearch(query: query)
        guard !Task.isCancelled else { return }

        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.placeholderView.view.isHidden = true
            self.results = searchResults
            self.updateSnapshot(with: searchResults)
            if searchResults.isEmpty {
                self.collectionView.isHidden = true
                self.emptyView.view.isHidden = false
            } else {
                self.collectionView.isHidden = false
                self.emptyView.view.isHidden = true
            }
        }
    }

    private func performJavaScriptSearch(query: String) async -> [SearchItem] {
        await JSController.shared.fetchJsSearchResults(keyword: query, module: module)
    }

    private func updateSnapshot(with items: [SearchItem]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, SearchItem>()
        snapshot.appendSections([Section.main])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    func cell(for item: SearchItem) -> UICollectionViewCell? {
        guard let indexPath = dataSource.indexPath(for: item) else { return nil }
        return collectionView.cellForItem(at: indexPath)
    }
}

extension SearchItem: Hashable {
    public static func == (lhs: SearchItem, rhs: SearchItem) -> Bool {
        lhs.href == rhs.href
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(href)
    }
}

extension PlayerSearchResultsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        parentPlayerSourceVC?.navigateToPlayerDetails(
            title: item.title,
            imageUrl: item.imageUrl,
            href: item.href
        )
    }
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? MangaGridCell else { return nil }

        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bounds,
            cornerRadius: cell.contentView.layer.cornerRadius
        )

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
             // TODO: Add context menu actions here
             nil
        }
    }
}
