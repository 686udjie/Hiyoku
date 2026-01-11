//
//  DebouncedSearch.swift
//  Hiyoku
//
//  Created by 686udjie on 01/11/26.
//

import Foundation

/// Protocol for objects that perform debounced search operations
protocol DebouncedSearchable: AnyObject {
    var searchDebounceTimer: Timer? { get set }
    var currentSearchTask: Task<Void, Never>? { get set }

    /// Perform a search operation after debouncing
    func performSearch(query: String, delay: TimeInterval, searchAction: @escaping () async -> Void)

    /// Cancel any ongoing search operations
    func cancelSearch()
}

/// Default implementation for debounced search
extension DebouncedSearchable {
    func performSearch(query: String, delay: TimeInterval = 0.35, searchAction: @escaping () async -> Void) {
        // Cancel previous timer and task
        cancelSearch()

        guard !query.isEmpty else { return }

        // Start delay timer
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            self.currentSearchTask = Task {
                await searchAction()
            }
        }
    }

    func cancelSearch() {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = nil
        currentSearchTask?.cancel()
        currentSearchTask = nil
    }
}
