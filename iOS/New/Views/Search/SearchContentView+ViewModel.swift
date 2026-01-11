//
//  SearchContentView+ViewModel.swift
//  Aidoku
//
//  Created by Skitty on 11/14/25.
//

import AidokuRunner
import SwiftUI

extension SearchContentView {
    @MainActor
    class ViewModel: ObservableObject {
        struct SearchResult: Identifiable, Equatable {
            let source: AidokuRunner.Source?
            let module: ScrapingModule?
            let result: AidokuRunner.MangaPageResult

            var id: String {
                if let source = source {
                    return "source-\(source.id)"
                } else if let module = module {
                    return "module-\(module.id.uuidString)"
                } else {
                    return "unknown"
                }
            }

            static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
                lhs.id == rhs.id
            }
        }

        var sources: [AidokuRunner.Source] = []
        var modules: [ScrapingModule] = []
        var filters: [FilterValue] = []

        @Published var results: [SearchResult] = []
        @Published var history: [String] = []
        @Published var isLoading: Bool = false

        static let maxHistoryEntries = 20

        private var searchQuery: String = ""
        private var searchTask: Task<Void, Never>?
        private var searchDebounceTimer: Timer?

        var resultsIsEmpty: Bool {
            !results.contains(where: { !$0.result.entries.isEmpty })
        }

        init() {
            history = UserDefaults.standard.stringArray(forKey: "Search.history") ?? []
        }
    }
}

extension SearchContentView.ViewModel {
    func search(query: String, delay: Bool) {
        if !delay {
            updateHistory(query: query)
        }
        guard searchQuery != query else { return }
        searchDebounceTimer?.invalidate()
        searchTask?.cancel()
        if query.isEmpty {
            results = []
            isLoading = false
            return
        }

        if delay {
            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.searchTask = Task {
                        await self?.performSearch(query: query)
                    }
                }
            }
        } else {
            searchTask = Task {
                await self.performSearch(query: query)
            }
        }
    }

    private func performSearch(query: String) async {
        // Clear previous results immediately to prevent showing old data
        results = []
        searchQuery = query
        isLoading = true

        // Check if task was cancelled before starting fetch
        guard !Task.isCancelled else {
            isLoading = false
            return
        }

        await fetchData(query: query)

        // Don't set isLoading = false if task was cancelled during fetch
        guard !Task.isCancelled else { return }
        isLoading = false
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: "Search.history")
        withAnimation {
            history = []
        }
    }

    func removeHistory(item: String) {
        if let index = history.firstIndex(of: item) {
            withAnimation {
                _ = history.remove(at: index)
            }
            UserDefaults.standard.set(history, forKey: "Search.history")
        }
    }

    func updateFilters(_ filters: [FilterValue]) {
        self.filters = filters
        if !searchQuery.isEmpty {
            searchTask?.cancel()
            searchDebounceTimer?.invalidate()
            searchTask = Task {
                guard !Task.isCancelled else { return }
                isLoading = true

                let filteredSources: [AidokuRunner.Source] = filteredSources()
                let filteredModules: [ScrapingModule] = filteredModules()

                // remove filtered out sources (player modules are not filtered)
                results.removeAll { result in
                    if let source = result.source {
                        return !filteredSources.contains(where: { $0.key == source.key })
                    } else if let module = result.module {
                        return !filteredModules.contains(where: { $0.id == module.id })
                    }
                    return true
                }

                guard !Task.isCancelled else { return }
                // add sources that weren't included before
                let newSources = filteredSources.filter { source in
                    !results.contains(where: { $0.source?.key == source.key })
                }
                await appendFetchedData(query: searchQuery, sources: newSources, modules: [])
                guard !Task.isCancelled else { return }
                isLoading = false
            }
        }
    }
}

extension SearchContentView.ViewModel {
    private func updateHistory(query: String) {
        guard !query.isEmpty else { return }

        var newHistory = history

        if let index = newHistory.firstIndex(of: query) {
            newHistory.remove(at: index)
        }
        newHistory.append(query)

        if newHistory.count > Self.maxHistoryEntries {
            newHistory.remove(at: 0)
        }

        UserDefaults.standard.set(newHistory, forKey: "Search.history")
        withAnimation {
            history = newHistory
        }
    }

    private func filteredSources() -> [AidokuRunner.Source] {
        sources.filter { source in
            for filter in filters {
                switch filter {
                    case .multiselect(let id, let included, let excluded):
                        switch id {
                            case "contentRating":
                                let includedRatings = included.compactMap { SourceContentRating(stringValue: $0) }
                                let excludedRatings = excluded.compactMap { SourceContentRating(stringValue: $0) }
                                let sourceRating = source.contentRating
                                if !includedRatings.isEmpty && !includedRatings.contains(sourceRating) {
                                    return false
                                } else if !excludedRatings.isEmpty && excludedRatings.contains(sourceRating) {
                                    return false
                                }
                            case "languages":
                                let sourceLanguages = source.getSelectedLanguages()
                                if !included.isEmpty && !sourceLanguages.contains(where: { included.contains($0) }) {
                                    return false
                                } else if !excluded.isEmpty && sourceLanguages.contains(where: { excluded.contains($0) }) {
                                    return false
                                }
                            case "sources":
                                let sourceKey = source.key
                                if !included.isEmpty && !included.contains(sourceKey) {
                                    return false
                                } else if !excluded.isEmpty && excluded.contains(sourceKey) {
                                    return false
                                }
                            default:
                                continue
                        }
                    default:
                        continue
                }
            }
            return true
        }
    }

    private func filteredModules() -> [ScrapingModule] {
        // Player modules are exempt from filters - return all active modules
        modules
    }

    private func fetchData(query: String) async {
        guard !query.isEmpty else { return }

        let sources = filteredSources()
        let modules = filteredModules() // Player modules (exempt from filters)

        await appendFetchedData(query: query, sources: sources, modules: modules)
    }

    private func appendFetchedData(query: String, sources: [AidokuRunner.Source], modules: [ScrapingModule]) async {
        // Don't proceed if task was cancelled
        guard !Task.isCancelled else { return }

        // Sequential execution in single task to prevent multiple results
        var allResults: [SearchResult] = []
        // Fetch from all sources sequentially
        for source in sources {
            guard !Task.isCancelled else { break }

            do {
                let result = try await source.getSearchMangaList(query: query, page: 1, filters: [])
                allResults.append(.init(source: source, module: nil, result: result))
            } catch {
                // Continue with other sources even if one fails
                continue
            }
        }

        // Fetch from all modules sequentially
        for module in modules {
            guard !Task.isCancelled else { break }

            let result = await searchPlayerInModule(module, query: query)
            if let result = result {
                allResults.append(.init(source: nil, module: module, result: result))
            }
        }

        // Update results once at the end
        guard !Task.isCancelled else { return }
        results = allResults
    }

    private func searchPlayerInModule(_ module: ScrapingModule, query: String) async -> AidokuRunner.MangaPageResult? {
        let searchItems = await JSController.shared.fetchJsSearchResults(keyword: query, module: module)
        if searchItems.isEmpty {
            return AidokuRunner.MangaPageResult(entries: [], hasNextPage: false)
        }

        // Convert SearchItem array to MangaPageResult
        let mangaEntries = searchItems.map { item -> AidokuRunner.Manga in
            AidokuRunner.Manga(
                sourceKey: module.id.uuidString,
                key: item.href,
                title: item.title,
                cover: item.imageUrl
            )
        }

        return AidokuRunner.MangaPageResult(
            entries: mangaEntries,
            hasNextPage: false // Assume single page for now
        )
    }
}
