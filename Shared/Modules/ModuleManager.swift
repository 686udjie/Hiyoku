//
//  ModuleManager.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation

@MainActor
class ModuleManager: ObservableObject {
    static let shared = ModuleManager()

    @Published var modules: [ScrapingModule] = []
    @Published var selectedModuleChanged = false

    private let fileManager = FileManager.default
    private let modulesFileName = "registry.json"
    private let legacyModulesFileName = "modules.json"
    private let logger = Logger()

    init() {
        loadModules()
    }

    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getSourcesDirectory() -> URL {
        getDocumentsDirectory().appendingPathComponent("Sources", isDirectory: true)
    }

    private func getModulesFilePath() -> URL {
        getDocumentsDirectory().appendingPathComponent(modulesFileName)
    }

    private func getLocalUrl(for module: ScrapingModule) -> URL {
        getSourcesDirectory().appendingPathComponent(module.localPath)
    }

    func loadModules() {
        getSourcesDirectory().createDirectory()
        migrateFromLegacy()
        let discoveredModules = discoverModules()
        var uniqueModules: [UUID: ScrapingModule] = [:]
        for module in discoveredModules {
            uniqueModules[module.id] = module
        }
        modules = Array(uniqueModules.values).sorted { $0.metadata.sourceName < $1.metadata.sourceName }
        for i in 0..<modules.count {
            modules[i].updateMetadata = nil
        }
        Task {
            await checkForUpdates()
        }
    }

    private func migrateFromLegacy() {
        let sourcesDir = getSourcesDirectory()
        let registryUrl = getModulesFilePath()
        let modulesUrl = getDocumentsDirectory().appendingPathComponent(legacyModulesFileName)
        var legacyModules: [ScrapingModule] = []
        for url in [registryUrl, modulesUrl] where fileManager.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([ScrapingModule].self, from: data) {
                legacyModules.append(contentsOf: decoded)
            }
            url.removeItem()
        }
        for module in legacyModules {
            let moduleDirName = module.metadata.sourceName.directoryName
            let moduleDir = sourcesDir.appendingPathComponent(moduleDirName)
            moduleDir.createDirectory()
            var localPath = module.localPath
            if !localPath.contains("/") {
                let oldScriptUrl = getDocumentsDirectory().appendingPathComponent(localPath)
                let newScriptFileName = "\(moduleDirName).js"
                let newScriptPath = "\(moduleDirName)/\(newScriptFileName)"
                let newScriptUrl = sourcesDir.appendingPathComponent(newScriptPath)
                if oldScriptUrl.exists {
                    try? fileManager.moveItem(at: oldScriptUrl, to: newScriptUrl)
                    localPath = newScriptPath
                }
            }
            let scrapingModule = ScrapingModule(
                id: module.id,
                metadata: module.metadata,
                localPath: localPath,
                metadataUrl: module.metadataUrl,
                isActive: module.isActive
            )
            saveModuleToDisk(scrapingModule)
        }
    }

    private func discoverModules() -> [ScrapingModule] {
        let sourcesDir = getSourcesDirectory()
        var discovered: [ScrapingModule] = []
        for folderUrl in sourcesDir.contents {
            guard folderUrl.isDirectory else { continue }
            let moduleJsonUrl = folderUrl.appendingPathComponent("module.json")
            if moduleJsonUrl.exists,
               let data = try? Data(contentsOf: moduleJsonUrl),
               let module = try? JSONDecoder().decode(ScrapingModule.self, from: data) {
                discovered.append(module)
            }
        }
        return discovered
    }

    private func saveModuleToDisk(_ module: ScrapingModule) {
        let moduleDir = getLocalUrl(for: module).deletingLastPathComponent()
        let moduleJsonUrl = moduleDir.appendingPathComponent("module.json")
        moduleDir.createDirectory()
        if let data = try? JSONEncoder().encode(module) {
            try? data.write(to: moduleJsonUrl)
        }
    }

    func saveModules() {
        for module in modules {
            saveModuleToDisk(module)
        }
    }

    private func downloadScript(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "InvalidURL", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid script URL: \(urlString)"])
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DecodeError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode script from \(urlString)"])
        }
        return content
    }

    private func installScript(metadata: ModuleMetadata, content: String) throws -> String {
        let moduleDirName = metadata.sourceName.directoryName
        let moduleDir = getSourcesDirectory().appendingPathComponent(moduleDirName)
        moduleDir.createDirectory()

        let scriptFileName = "\(moduleDirName).js"
        let scriptRelativePath = "\(moduleDirName)/\(scriptFileName)"
        let scriptLocalUrl = getSourcesDirectory().appendingPathComponent(scriptRelativePath)

        try content.write(to: scriptLocalUrl, atomically: true, encoding: .utf8)
        return scriptRelativePath
    }

    func addModule(metadataUrl: String) async throws -> ScrapingModule {
        // Check if module with this URL already exists
        guard !modules.contains(where: { $0.metadataUrl == metadataUrl }) else {
            throw NSError(domain: "ModuleAlreadyAdded", code: -4, userInfo: [NSLocalizedDescriptionKey: "Module already added"])
        }
        guard let url = URL(string: metadataUrl) else {
            throw NSError(domain: "InvalidURL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid metadata URL: \(metadataUrl)"])
        }
        // Download metadata
        let (metadataData, _) = try await URLSession.shared.data(from: url)
        let metadata = try JSONDecoder().decode(ModuleMetadata.self, from: metadataData)
        // Download the JavaScript script
        let scriptContent = try await downloadScript(from: metadata.scriptUrl)

        let scriptRelativePath = try installScript(metadata: metadata, content: scriptContent)

        let module = ScrapingModule(
            metadata: metadata,
            localPath: scriptRelativePath,
            metadataUrl: metadataUrl,
            isActive: true
        )
        saveModuleToDisk(module)
        modules.append(module)
        NotificationCenter.default.post(name: .moduleAdded, object: module.id.uuidString)
        return module
    }

    func getModuleContent(_ module: ScrapingModule) async throws -> String {
        let localUrl = getLocalUrl(for: module)
        // If file doesn't exist, download it from scriptUrl
        return try String(contentsOf: localUrl, encoding: .utf8)
    }

    func deleteModule(_ module: ScrapingModule) {
        modules.removeAll { $0.id == module.id }
        saveModules()
        // Delete the local folder
        let localUrl = getLocalUrl(for: module)
        let moduleDir = localUrl.deletingLastPathComponent()
        try? fileManager.removeItem(at: moduleDir)
        NotificationCenter.default.post(name: .moduleRemoved, object: module.id.uuidString)
    }

    func checkForUpdates() async {
        for i in 0..<modules.count {
            let module = modules[i]
            guard let url = URL(string: module.metadataUrl) else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let latestMetadata = try JSONDecoder().decode(ModuleMetadata.self, from: data)

                if self.shouldUpdate(module: module, latestMetadata: latestMetadata) {
                    modules[i].updateMetadata = latestMetadata
                } else {
                    modules[i].updateMetadata = nil
                }
            } catch {
                logger.error("Failed to check for updates for \(module.metadata.sourceName): \(error)")
            }
        }
        NotificationCenter.default.post(name: .moduleStateChanged, object: nil)
    }

    private func shouldUpdate(module: ScrapingModule, latestMetadata: ModuleMetadata) -> Bool {
        let currentVersion = SemanticVersion(module.metadata.version)
        let latestVersion = SemanticVersion(latestMetadata.version)

        let localUrl = getLocalUrl(for: module)
        let fileExists = localUrl.exists

        let scriptUrlChanged = module.metadata.scriptUrl != latestMetadata.scriptUrl

        return latestVersion > currentVersion || !fileExists || scriptUrlChanged
    }

    func updateModule(_ module: ScrapingModule) async throws {
        guard let updateMetadata = module.updateMetadata else { return }

        // Download the new script
        let scriptContent = try await downloadScript(from: updateMetadata.scriptUrl)

        let scriptRelativePath = try installScript(metadata: updateMetadata, content: scriptContent)

        if let index = modules.firstIndex(where: { $0.id == module.id }) {
            modules[index] = ScrapingModule(
                id: module.id,
                metadata: updateMetadata,
                updateMetadata: nil,
                localPath: scriptRelativePath,
                metadataUrl: module.metadataUrl,
                isActive: module.isActive
            )
            saveModuleToDisk(modules[index])
        }

        NotificationCenter.default.post(name: .moduleStateChanged, object: module.id.uuidString)
    }
}
