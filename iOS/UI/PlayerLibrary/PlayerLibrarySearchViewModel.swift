//
//  PlayerLibrarySearchViewModel.swift
//  Hiyoku
//
//  Created by 686udjie on 01/03/2026.
//

import Foundation
import SwiftUI
import Combine
import AidokuRunner

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
