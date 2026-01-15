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

        title = module.metadata.sourceName
        view.backgroundColor = .systemBackground

        resultsViewController = PlayerSearchResultsViewController(module: module, parentVC: self)
        searchController = UISearchController(searchResultsController: resultsViewController)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search..."
        searchController.searchBar.delegate = self

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

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
                self.navigationItem.rightBarButtonItem?.customView ?? self.navigationItem.searchController?.searchBar
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
                            Image(systemName: "tv.fill")
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

    let module: ScrapingModule
    private var results: [SearchItem] = []
    private var isLoading = false
    private var hostingController: UIHostingController<PlayerSearchResultsGrid>?
    private weak var parentPlayerSourceVC: PlayerSourceViewController?

    var searchDebounceTimer: Timer?
    var currentSearchTask: Task<Void, Never>?

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
        view.backgroundColor = .systemBackground
        showResultsGrid()
    }

    private func showResultsGrid() {
        updateResultsGrid()

        guard hostingController == nil else { return }

        hostingController = UIHostingController(rootView: makeGridView())
        guard let hostingController = hostingController else { return }

        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func makeGridView() -> PlayerSearchResultsGrid {
        PlayerSearchResultsGrid(
            results: results,
            isLoading: isLoading,
            module: module
        ) { [weak self] selectedItem in
            guard let self = self, let parentVC = self.parentPlayerSourceVC else { return }
            parentVC.navigateToPlayerDetails(
                title: selectedItem.title,
                imageUrl: selectedItem.imageUrl,
                href: selectedItem.href
            )
        }
    }

    func performSearch(query: String) {
        results = []

        guard !query.isEmpty else {
            isLoading = false
            updateResultsGrid()
            return
        }

        isLoading = true
        updateResultsGrid()

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
            self.results = searchResults
            self.isLoading = false
            self.updateResultsGrid()
        }
    }

    private func performJavaScriptSearch(query: String) async -> [SearchItem] {
        await JSController.shared.fetchJsSearchResults(keyword: query, module: module)
    }

    private func updateResultsGrid() {
        hostingController?.rootView = makeGridView()
    }
}

struct PlayerSearchResultsGrid: View {
    @AppStorage("mediaColumnsPortrait") private var mediaColumnsPortrait: Int = 2
    @AppStorage("mediaColumnsLandscape") private var mediaColumnsLandscape: Int = 4
    @Environment(\.verticalSizeClass) var verticalSizeClass

    let results: [SearchItem]
    let isLoading: Bool
    let module: ScrapingModule
    let onItemSelected: (SearchItem) -> Void

    private var columnsCount: Int {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let isLandscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
            return isLandscape ? mediaColumnsLandscape : mediaColumnsPortrait
        } else {
            return verticalSizeClass == .compact ? mediaColumnsLandscape : mediaColumnsPortrait
        }
    }

    private var cellWidth: CGFloat {
        let totalSpacing = CGFloat(columnsCount - 1) * 12 // 12pt spacing between columns
        let availableWidth = UIScreen.main.bounds.width - 24 // 12pt padding on each side
        return (availableWidth - totalSpacing) / CGFloat(columnsCount)
    }

    var body: some View {
        if results.isEmpty {
            if isLoading {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnsCount), spacing: 12) {
                        ForEach(0..<20, id: \.self) { _ in
                            PlayerSearchResultPlaceholder(cellWidth: cellWidth)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            } else {
                UnavailableView.search(text: "")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnsCount), spacing: 12) {
                    ForEach(results, id: \.href) { item in
                        Button {
                            onItemSelected(item)
                        } label: {
                            LazyImage(url: URL(string: item.imageUrl)) { state in
                                if let uiImage = state.imageContainer?.image {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: cellWidth, height: cellWidth * 1.5)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            LinearGradient(
                                                gradient: UIConstants.imageOverlayGradient,
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .overlay(
                                            Text(item.title)
                                                .foregroundStyle(.white)
                                                .font(.system(size: 15, weight: .medium))
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(2)
                                                .padding(8),
                                            alignment: .bottomLeading
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: cellWidth, height: cellWidth * 1.5)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundStyle(.gray)
                                        )
                                        .overlay(
                                            LinearGradient(
                                                gradient: UIConstants.imageOverlayGradient,
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .overlay(
                                            Text(item.title)
                                                .foregroundStyle(.white)
                                                .font(.system(size: 15, weight: .medium))
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(2)
                                                .padding(8),
                                            alignment: .bottomLeading
                                        )
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }
}

struct PlayerSearchResultPlaceholder: View {
    let cellWidth: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemFill))
            .frame(width: cellWidth, height: cellWidth * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
            .overlay(
                LinearGradient(
                    gradient: UIConstants.imageOverlayGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading Title")
                        .foregroundStyle(.white)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(2)
                        .padding(8)
                    Spacer()
                },
                alignment: .bottomLeading
            )
            .redacted(reason: .placeholder)
            .shimmering()
    }
}
