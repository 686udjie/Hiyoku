//
//  PlayerLibraryViewController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/05/26.
//

import UIKit
import SwiftUI
import NukeUI
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

class PlayerLibraryViewController: BaseViewController {

    private let path = NavigationCoordinator(rootViewController: nil)
    private var searchController: UISearchController!
    private var playerView: PlayerView!
    private lazy var emptyStackView = EmptyPageStackView()
    private var libraryObserver: AnyCancellable?

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

        // Add SwiftUI PlayerView (simplified bookmark banners)
        playerView = PlayerView()
        let hostingController = UIHostingController(rootView: playerView.environmentObject(path))
        addChild(hostingController)

        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        // Set up empty state view (add after SwiftUI view so it's on top)
        emptyStackView.isHidden = true
        emptyStackView.imageSystemName = "play.tv.fill"
        emptyStackView.title = NSLocalizedString("PLAYER_EMPTY", comment: "")
        emptyStackView.text = NSLocalizedString("PLAYER_ADD_CONTENT", comment: "")
        view.addSubview(emptyStackView)

        // Observe library changes to update empty state
        libraryObserver = PlayerLibraryManager.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateEmptyState()
            }

        updateEmptyState()
    }

    override func constrain() {
        super.constrain()

        emptyStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func updateEmptyState() {
        let isSearching = !playerView.searchText.isEmpty
        let isEmpty = PlayerLibraryManager.shared.items.isEmpty && !isSearching
        emptyStackView.isHidden = !isEmpty
    }
}

extension PlayerLibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text ?? ""
        playerView.searchText = searchText

        // Trigger search through all player sources
        playerView.searchViewModel.search(query: searchText)

        // Update empty state visibility
        updateEmptyState()
    }
}

// MARK: - Player View
struct PlayerView: View {
    @StateObject private var libraryManager = PlayerLibraryManager.shared
    @StateObject var searchViewModel = PlayerLibrarySearchViewModel()
    @State var searchText = "" // Made public for UIKit search controller
    @EnvironmentObject private var path: NavigationCoordinator

    private let gridColumns = [
        GridItem(.adaptive(minimum: 140), spacing: 16)
    ]

    var filteredBookmarks: [PlayerLibraryItem] {
        if searchText.isEmpty {
            return libraryManager.items
        } else {
            return libraryManager.items.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var searchResults: [PlayerLibrarySearchResult] {
        searchViewModel.results
    }

    var body: some View {
        ZStack {
            if searchText.isEmpty {
                // Show bookmarks when not searching
                if !libraryManager.items.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filteredBookmarks) { bookmark in
                                Button {
                                    let zoomSourceIdentifier = "player-banner-\(bookmark.id.uuidString)"
                                    // Navigate to player info page
                                    let searchItem = SearchItem(
                                        title: bookmark.title,
                                        imageUrl: bookmark.imageUrl,
                                        href: bookmark.sourceUrl
                                    )

                                    // Find the module for this bookmark
                                    if let module = ModuleManager.shared.modules.first(where: { $0.id == bookmark.moduleId }) {
                                        let playerInfoVC = PlayerInfoViewController(
                                            bookmark: bookmark,
                                            searchItem: searchItem,
                                            module: module,
                                            path: path
                                        )
                                        // Add zoom transition animation (iOS 18+)
                                        if #available(iOS 18.0, *) {
                                            playerInfoVC.preferredTransition = .zoom { _ in
                                                guard let root = path.navigationController?.view else { return nil }
                                                return root.findSubview(withAccessibilityIdentifier: zoomSourceIdentifier)
                                            }
                                        }
                                        path.push(playerInfoVC)
                                    }
                                } label: {
                                    bookmarkBanner(for: bookmark)
                                        .accessibilityIdentifier("player-banner-\(bookmark.id.uuidString)")
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            } else {
                // Show search results when searching
                if searchViewModel.isLoading {
                    PlaceholderGridView()
                } else if searchResults.isEmpty {
                    UnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(searchResults) { result in
                                Button {
                                    let zoomSourceIdentifier = "player-search-banner-\(result.id.uuidString)"
                                    // Navigate to player info page for search result
                                    let searchItem = SearchItem(
                                        title: result.title,
                                        imageUrl: result.imageUrl,
                                        href: result.href
                                    )

                                    let playerInfoVC = PlayerInfoViewController(
                                        searchItem: searchItem,
                                        module: result.module,
                                        path: path
                                    )
                                    // Add zoom transition animation (iOS 18+)
                                    if #available(iOS 18.0, *) {
                                        playerInfoVC.preferredTransition = .zoom { _ in
                                            guard let root = path.navigationController?.view else { return nil }
                                            return root.findSubview(withAccessibilityIdentifier: zoomSourceIdentifier)
                                        }
                                    }
                                    path.push(playerInfoVC)
                                } label: {
                                    searchResultBanner(for: result)
                                        .accessibilityIdentifier("player-search-banner-\(result.id.uuidString)")
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }


    private func bookmarkBanner(for bookmark: PlayerLibraryItem) -> some View {
        MangaGridItem(
            source: nil,
            title: bookmark.title,
            coverImage: bookmark.imageUrl,
            bookmarked: false
        )
    }

    private func searchResultBanner(for result: PlayerLibrarySearchResult) -> some View {
        MangaGridItem(
            source: nil,
            title: result.title,
            coverImage: result.imageUrl,
            bookmarked: false
        )
    }
}


private extension UIView {
    func findSubview(withAccessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.findSubview(withAccessibilityIdentifier: identifier) {
                return match
            }
        }
        return nil
    }
}
