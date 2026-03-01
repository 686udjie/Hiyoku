//
//  LibraryCore.swift
//  Hiyoku
//
//  Created by 686udjie on 01/03/2026.
//

import UIKit

// MARK: - Shared Types

/// Generic filter used by both Library and PlayerLibrary view models.
/// Each view model provides its own `FilterMethod` enum as `T`.
struct LibraryFilter<T: RawRepresentable & Codable & Equatable>: Codable, Equatable where T.RawValue == Int {
    var type: T
    var value: String?
    var exclude: Bool
}

/// Badge type shared by both libraries.
struct LibraryBadgeType: OptionSet {
    let rawValue: Int

    static let unread = LibraryBadgeType(rawValue: 1 << 0)
    static let downloaded = LibraryBadgeType(rawValue: 1 << 1)
}

// MARK: - Core Logic

struct LibraryCore {
    let prefix: String // "Library" or "PlayerLibrary"

    // MARK: - Filters

    func loadFilters<T: RawRepresentable & Codable & Equatable>() -> [LibraryFilter<T>] where T.RawValue == Int {
        guard let data = UserDefaults.standard.data(forKey: "\(prefix).filters"),
              let filters = try? JSONDecoder().decode([LibraryFilter<T>].self, from: data) else {
            return []
        }
        return filters
    }

    func saveFilters<T: RawRepresentable & Codable & Equatable>(_ filters: [LibraryFilter<T>]) where T.RawValue == Int {
        if let data = try? JSONEncoder().encode(filters) {
            UserDefaults.standard.set(data, forKey: "\(prefix).filters")
        }
    }

    /// Three-state toggle: off → include → exclude → off
    func toggleFilter<T: RawRepresentable & Codable & Equatable>(
        filters: inout [LibraryFilter<T>],
        method: T,
        value: String? = nil
    ) where T.RawValue == Int {
        if let index = filters.firstIndex(where: { $0.type == method && $0.value == value }) {
            if filters[index].exclude {
                filters.remove(at: index)
            } else {
                filters[index].exclude = true
            }
        } else {
            filters.append(LibraryFilter(type: method, value: value, exclude: false))
        }
    }

    func filterState<T: RawRepresentable & Codable & Equatable>(
        filters: [LibraryFilter<T>],
        method: T,
        value: String? = nil
    ) -> UIMenuElement.State where T.RawValue == Int {
        if let filter = filters.first(where: { $0.type == method && $0.value == value }) {
            return filter.exclude ? .mixed : .on
        }
        return .off
    }

    // MARK: - Category Lock

    func isCategoryLocked(currentCategory: String?) -> Bool {
        guard UserDefaults.standard.bool(forKey: "\(prefix).lockLibrary") else { return false }
        if let currentCategory {
            return UserDefaults.standard.stringArray(forKey: "\(prefix).lockedCategories")?.contains(currentCategory) ?? false
        }
        return true
    }

    // MARK: - Pin Type

    func pinTitleRaw() -> String? {
        UserDefaults.standard.string(forKey: "\(prefix).pinTitles")
    }

    func loadPinType<P: RawRepresentable>(defaultValue: P) -> P where P.RawValue == String {
        pinTitleRaw().flatMap(P.init) ?? defaultValue
    }

    // MARK: - Sort

    func loadSortOption() -> Int {
        UserDefaults.standard.integer(forKey: "\(prefix).sortOption")
    }

    func loadSortAscending() -> Bool {
        UserDefaults.standard.bool(forKey: "\(prefix).sortAscending")
    }

    func saveSortOption(_ rawValue: Int) {
        UserDefaults.standard.set(rawValue, forKey: "\(prefix).sortOption")
    }

    func saveSortAscending(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "\(prefix).sortAscending")
    }

    // MARK: - Badges

    func unreadBadgeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "\(prefix).unreadChapterBadges")
    }

    func downloadedBadgeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "\(prefix).downloadedChapterBadges")
    }

    func loadBadgeType() -> LibraryBadgeType {
        var type: LibraryBadgeType = []
        if unreadBadgeEnabled() { type.insert(.unread) }
        if downloadedBadgeEnabled() { type.insert(.downloaded) }
        return type
    }

    // MARK: - Current Category

    func loadCurrentCategory() -> String? {
        UserDefaults.standard.string(forKey: "\(prefix).currentCategory")
    }

    func saveCurrentCategory(_ value: String?) {
        UserDefaults.standard.set(value, forKey: "\(prefix).currentCategory")
    }

    // MARK: - Categories

    func loadCategoriesList() -> [String] {
        UserDefaults.standard.stringArray(forKey: "\(prefix).categoriesList") ?? []
    }

    /// If currentCategory no longer exists in the list, reset it to nil. Returns true if it was reset.
    func validateCurrentCategory(categories: [String], currentCategory: inout String?) -> Bool {
        if currentCategory != nil && !categories.contains(currentCategory!) {
            currentCategory = nil
            return true
        }
        return false
    }

    func loadLockedCategories() -> [String] {
        UserDefaults.standard.stringArray(forKey: "\(prefix).lockedCategories") ?? []
    }

    func isLibraryLockEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "\(prefix).lockLibrary")
    }

    // MARK: - Item Categories (PlayerLibrary)

    func loadItemCategories() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: "\(prefix).itemCategories") as? [String: [String]] ?? [:]
    }

    func saveItemCategories(_ categories: [String: [String]]) {
        UserDefaults.standard.set(categories, forKey: "\(prefix).itemCategories")
    }

    // MARK: - Sort (convenience)

    func saveSort(methodRawValue: Int, ascending: Bool) {
        saveSortOption(methodRawValue)
        saveSortAscending(ascending)
    }
}
