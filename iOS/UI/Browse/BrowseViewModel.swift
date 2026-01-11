//
//  BrowseViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/30/22.
//

import Foundation
import AidokuRunner

@MainActor
class BrowseViewModel {
    var updatesSources: [SourceInfo2] = []
    var pinnedSources: [SourceInfo2] = []
    var installedSources: [SourceInfo2] = []
    var playerSources: [SourceInfo2] = []

    var unfilteredExternalSources: [ExternalSourceInfo] = []

    // stored sources when searching
    private var query: String?
    private var storedUpdatesSources: [SourceInfo2]?
    private var storedPinnedSources: [SourceInfo2]?
    private var storedInstalledSources: [SourceInfo2]?
    private var storedPlayerSources: [SourceInfo2]?
    private var storedExternalSources: [ExternalSourceInfo]?

    private func getInstalledSources() -> [SourceInfo2] {
        SourceManager.shared.sources.map { $0.toInfo() }
    }

    private func getPlayerSources() -> [SourceInfo2] {
        // Reload modules dynamically to ensure we have the latest list
        ModuleManager.shared.loadModules()
        // Show only active player modules (not novel modules) - display as many as possible
        return ModuleManager.shared.modules.filter { $0.isPlayerModule && $0.isActive }.map { module in
            SourceInfo2(
                sourceId: module.id.uuidString,
                iconUrl: URL(string: module.metadata.iconUrl),
                name: module.metadata.sourceName,
                languages: [module.metadata.language],
                version: Int(module.metadata.version.components(separatedBy: ".").first ?? "1") ?? 1,
                contentRating: .safe
            )
        }
    }

    // load installed sources
    func loadInstalledSources() {
        let installedSources = getInstalledSources()
        let playerSources = getPlayerSources()
        // Combine installed sources with active player sources from player sources
        let combinedInstalledSources = installedSources + playerSources

        if storedInstalledSources != nil {
            storedInstalledSources = combinedInstalledSources
            storedPlayerSources = playerSources
            search(query: query)
        } else {
            self.installedSources = combinedInstalledSources
            self.playerSources = playerSources
        }
    }

    // load player sources
    func loadPlayerSources() {
        let playerSources = getPlayerSources()
        // Update installed sources to include player sources
        let installedSources = getInstalledSources()
        let combinedInstalledSources = installedSources + playerSources

        if storedPlayerSources != nil {
            storedPlayerSources = playerSources
            storedInstalledSources = combinedInstalledSources
            search(query: query)
        } else {
            self.playerSources = playerSources
            self.installedSources = combinedInstalledSources
        }
    }

    func loadPinnedSources() {
        // Get all installed sources including player sources
        let installedSourcesFromManager = getInstalledSources()
        let playerSources = getPlayerSources()
        let allInstalledSources = installedSourcesFromManager + playerSources
        let defaultPinnedSources = UserDefaults.standard.stringArray(forKey: "Browse.pinnedList") ?? []

        var pinnedSources: [SourceInfo2] = []
        for sourceId in defaultPinnedSources {
            // Check both regular sources and player sources for pinned items
            guard let source = allInstalledSources.first(where: { $0.sourceId == sourceId }) else {
                // remove sourceId from userdefault stored pinned list in cases such as uninstall.
                UserDefaults.standard.set(defaultPinnedSources.filter({ $0 != sourceId }), forKey: "Browse.pinnedList")
                continue
            }

            pinnedSources.append(source)
            // remove sources from the installed array.
            if let index = self.installedSources.firstIndex(of: source) {
                self.installedSources.remove(at: index)
            }
            // remove sources from the stored installed array.
            if let index = self.storedInstalledSources?.firstIndex(of: source) {
                self.storedInstalledSources?.remove(at: index)
            }
        }
        if storedPinnedSources != nil {
            storedPinnedSources = pinnedSources
            search(query: query)
        } else {
            self.pinnedSources = pinnedSources
        }
    }

    // load external source lists
    func loadExternalSources(reload: Bool = false) async {
        await SourceManager.shared.loadSourceLists(reload: reload)

        // ensure external sources have unique ids
        var sourceById: [String: ExternalSourceInfo] = [:]

        for sourceList in SourceManager.shared.sourceLists {
            for source in sourceList.sources {
                if let existing = sourceById[source.id] {
                    // if a newer version exists, replace it
                    if source.version > existing.version {
                        sourceById[source.id] = source
                    }
                } else {
                    sourceById[source.id] = source
                }
            }
        }

        unfilteredExternalSources = Array(sourceById.values)
    }

    func loadUpdates() {
        guard let appVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let appVersion = SemanticVersion(appVersionString)

        updatesSources = unfilteredExternalSources.compactMap { info -> SourceInfo2? in
            // check version availability
            if let minAppVersion = info.minAppVersion {
                let minAppVersion = SemanticVersion(minAppVersion)
                if minAppVersion > appVersion {
                    return nil
                }
            }
            if let maxAppVersion = info.maxAppVersion {
                let maxAppVersion = SemanticVersion(maxAppVersion)
                if maxAppVersion < appVersion {
                    return nil
                }
            }

            if let installedSource = installedSources.first(where: { $0.sourceId == info.id }) {
                if info.version > installedSource.version {
                    return info.toInfo()
                }
                return nil
            }
            if let pinnedSource = pinnedSources.first(where: { $0.sourceId == info.id }) {
                if info.version > pinnedSource.version {
                    return info.toInfo()
                }
                return nil
            }
            return nil
        }

    }

    // filter sources by search query
    func search(query: String?) {
        self.query = query
        if let query = query?.lowercased(), !query.isEmpty {
            // store full source arrays
            if storedUpdatesSources == nil {
                storedUpdatesSources = updatesSources
                storedPinnedSources = pinnedSources
                storedInstalledSources = installedSources
                storedPlayerSources = playerSources
            }
            guard
                let storedUpdatesSources = storedUpdatesSources,
                let storedPinnedSources = storedPinnedSources,
                let storedInstalledSources = storedInstalledSources,
                let storedPlayerSources = storedPlayerSources
            else { return }
            updatesSources = storedUpdatesSources.filter { $0.name.lowercased().contains(query) }
            pinnedSources = storedPinnedSources.filter { $0.name.lowercased().contains(query) }
            installedSources = storedInstalledSources.filter { $0.name.lowercased().contains(query) }
            playerSources = storedPlayerSources.filter { $0.name.lowercased().contains(query) }
        } else {
            // reset search, restore source arrays
            if let storedUpdatesSources = storedUpdatesSources {
                updatesSources = storedUpdatesSources
                self.storedUpdatesSources = nil
            }
            if let storedPinnedSources = storedPinnedSources {
                pinnedSources = storedPinnedSources
                self.storedPinnedSources = nil
            }
            if let storedInstalledSources = storedInstalledSources {
                installedSources = storedInstalledSources
                self.storedInstalledSources = nil
            }
            if let storedPlayerSources = storedPlayerSources {
                playerSources = storedPlayerSources
                self.storedPlayerSources = nil
            }
        }
    }
}
