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
    private let modulesFileName = "modules.json"
    private let logger = Logger()

    init() {
        loadModules()
    }

    private func getDocumentsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getModulesFilePath() -> URL {
        getDocumentsDirectory().appendingPathComponent(modulesFileName)
    }

    func loadModules() {
        let url = getModulesFilePath()
        do {
            let data = try Data(contentsOf: url)
            modules = try JSONDecoder().decode([ScrapingModule].self, from: data)
        } catch {
            modules = []
        }
    }

    func saveModules() {
        let url = getModulesFilePath()
        guard let data = try? JSONEncoder().encode(modules) else { return }
        try? data.write(to: url)
    }

    func addModule(metadataUrl: String) async throws -> ScrapingModule {
        // Check if module with this URL already exists
        guard !modules.contains(where: { $0.metadataUrl == metadataUrl }) else {
            throw NSError(domain: "ModuleAlreadyAdded", code: -4, userInfo: [NSLocalizedDescriptionKey: "Module already added"])
        }
        guard let url = URL(string: metadataUrl) else {
            throw NSError(domain: "Invalid metadata URL", code: -1)
        }
        // Download metadata
        let (metadataData, _) = try await URLSession.shared.data(from: url)

        let metadata = try JSONDecoder().decode(ModuleMetadata.self, from: metadataData)
        // Download the JavaScript script from scriptUrl
        guard let scriptUrl = URL(string: metadata.scriptUrl) else {
            throw NSError(domain: "Invalid script URL", code: -2)
        }
        let (scriptData, _) = try await URLSession.shared.data(from: scriptUrl)
        guard let scriptContent = String(data: scriptData, encoding: .utf8) else {
            throw NSError(domain: "Failed to decode script", code: -3)
        }
        // Save script to local file
        let fileName = "\(UUID().uuidString).js"
        let localUrl = getDocumentsDirectory().appendingPathComponent(fileName)
        try scriptContent.write(to: localUrl, atomically: true, encoding: .utf8)
        let module = ScrapingModule(
            metadata: metadata,
            localPath: fileName,
            metadataUrl: metadataUrl,
            isActive: true
        )
        modules.append(module)
        saveModules()
        NotificationCenter.default.post(name: .moduleAdded, object: module.id.uuidString)
        return module
    }

    func getModuleContent(_ module: ScrapingModule) async throws -> String {
        let localUrl = getDocumentsDirectory().appendingPathComponent(module.localPath)
        // If file doesn't exist, download it from scriptUrl
        if !fileManager.fileExists(atPath: localUrl.path) {
            guard let scriptUrl = URL(string: module.metadata.scriptUrl) else {
                throw NSError(domain: "Invalid script URL", code: -2)
            }
            let (scriptData, _) = try await URLSession.shared.data(from: scriptUrl)
            guard let scriptContent = String(data: scriptData, encoding: .utf8) else {
                throw NSError(domain: "Failed to decode script", code: -3)
            }
            try scriptContent.write(to: localUrl, atomically: true, encoding: .utf8)
            return scriptContent
        }
        return try String(contentsOf: localUrl, encoding: .utf8)
    }

    func deleteModule(_ module: ScrapingModule) {
        modules.removeAll { $0.id == module.id }
        saveModules()
        // Also delete the local file
        let localUrl = getDocumentsDirectory().appendingPathComponent(module.localPath)
        try? fileManager.removeItem(at: localUrl)
        NotificationCenter.default.post(name: .moduleRemoved, object: module.id.uuidString)
    }
}
