//
//  JSController.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation
import JavaScriptCore

// MARK: - JavaScript Engine Controller

/// Manages JavaScript execution context for player modules
/// Handles module loading, search operations, and stream extraction
public struct StreamInfo: Codable, Sendable {
    public let title: String
    public let url: String
    public let headers: [String: String]
}

public class JSController: ObservableObject {
    public static let shared = JSController()

    private actor JSContextMutex {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func lock() async {
            if !isLocked {
                isLocked = true
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func unlock() {
            if waiters.isEmpty {
                isLocked = false
                return
            }
            let next = waiters.removeFirst()
            next.resume()
        }

        func withLock<T>(_ operation: () async throws -> T) async rethrows -> T {
            await lock()
            defer { unlock() }
            return try await operation()
        }
    }

    var context: JSContext
    private var modules: [String: JSValue] = [:] // Used for direct JSValue access if needed, though mostly using context
    private var loadedScripts: [String: ScrapingModule] = [:]
    private var currentModuleId: String?
    private let queue = DispatchQueue(label: "com.aidoku.jscontroller", qos: .userInitiated)
    private let contextMutex = JSContextMutex()

    init() {
        self.context = JSContext()
        setupContext()
    }

    func setupContext() {
        context.setupJavaScriptEnvironment()
        let asyncChaptersHelper = """
        function extractChaptersWithCallback(href, callback) {
            try {
                var result = extractChapters(href);
                if (result && typeof result.then === 'function') {
                    result.then(function(arr) {
                        callback(arr);
                    }).catch(function(e) {
                        callback([]);
                    });
                } else {
                    callback(result);
                }
            } catch (_) {
                callback([]);
            }
        }
        """
        let asyncEpisodesHelper = """
        function extractEpisodesWithCallback(href, callback) {
            try {
                var result = extractEpisodes(href);
                if (result && typeof result.then === 'function') {
                    result.then(function(arr) {
                        callback(arr);
                    }).catch(function(e) {
                        callback([]);
                    });
                } else {
                    callback(result);
                }
            } catch (_) {
                callback([]);
            }
        }
        """
        context.evaluateScript(asyncChaptersHelper)
        context.evaluateScript(asyncEpisodesHelper)
        context.exceptionHandler = { (_: JSContext?, _: JSValue?) in
            // Exception handling - errors are handled in promise handlers
        }
    }

    func loadScript(_ script: String) {
        // Reset context and setup environment for a fresh module load
        context = JSContext()
        setupContext()
        context.evaluateScript(script)
    }
    private func loadScriptForModule(_ script: String, moduleId: String) {
        // Load script for a specific module - reset context to ensure clean state
        context = JSContext()
        setupContext()
        context.evaluateScript(script)
        _ = context.objectForKeyedSubscript("extractEpisodes") != nil
        _ = context.objectForKeyedSubscript("extractStreamUrl") != nil
    }

    // MARK: - Module Management

    /// Loads and executes a JavaScript module script
    /// - Parameter module: The scraping module to load
    func loadModuleScript(_ module: ScrapingModule) async {
        await contextMutex.withLock {
            do {
                let scriptContent = try await ModuleManager.shared.getModuleContent(module)
                loadedScripts[module.id.uuidString] = module
                loadScriptForModule(scriptContent, moduleId: module.id.uuidString)
                currentModuleId = module.id.uuidString
            } catch {
            }
        }
    }

    func ensureModuleLoaded(_ module: ScrapingModule) async throws {
        if currentModuleId == module.id.uuidString {
            return
        }
        let scriptContent = try await ModuleManager.shared.getModuleContent(module)
        loadedScripts[module.id.uuidString] = module
        loadScriptForModule(scriptContent, moduleId: module.id.uuidString)
        currentModuleId = module.id.uuidString
    }

    private func validateContext() -> Bool {
        context.exception == nil
    }

    private func getJavaScriptFunction(_ functionName: String,
                                       module: ScrapingModule) throws -> JSValue {
        guard let function = context.objectForKeyedSubscript(functionName) else {
            throw NSError(domain: "JSController", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(functionName) function not found in module \(module.metadata.sourceName)"])
        }
        return function
    }

    private func callJavaScriptFunction(_ function: JSValue,
                                        withArguments arguments: [Any]) throws -> JSValue {
        let result = function.call(withArguments: arguments)
        guard let result = result else {
            throw NSError(domain: "JSController", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Function returned invalid response"])
        }
        return result
    }

    private func setupPromiseHandlers(for promise: JSValue,
                                      successHandler: @escaping (JSValue) -> Void,
                                      errorHandler: @escaping (JSValue?) -> Void) {
        let thenBlock: @convention(block) (JSValue) -> Void = successHandler
        let catchBlock: @convention(block) (JSValue) -> Void = errorHandler

        let thenFunction = JSValue(object: thenBlock, in: context)
        let catchFunction = JSValue(object: catchBlock, in: context)

        promise.invokeMethod("then", withArguments: [thenFunction as Any])
        promise.invokeMethod("catch", withArguments: [catchFunction as Any])
    }

    func unloadModuleScript(_ module: ScrapingModule) async {
        loadedScripts.removeValue(forKey: module.id.uuidString)
        // If we're unloading the currently loaded module, reset the current module ID
        if currentModuleId == module.id.uuidString {
            currentModuleId = nil
        }
        // Reset context to clear the module
        context = JSContext()
        setupContext()

        // Reload all other active modules
        for (_, module) in loadedScripts {
            await loadModuleScript(module)
        }
    }

    func getLoadedModules() -> [ScrapingModule] {
        Array(loadedScripts.values)
    }

    // MARK: - Helper Methods
    private func awaitPromiseResolution(_ promise: JSValue) async -> JSValue? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let resumeOnce: (JSValue?) -> Void = { value in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            let thenBlock: @convention(block) (JSValue) -> Void = { result in
                resumeOnce(result)
            }
            let catchBlock: @convention(block) (JSValue) -> Void = { _ in
                resumeOnce(nil)
            }

            let thenFunction = JSValue(object: thenBlock, in: context)
            let catchFunction = JSValue(object: catchBlock, in: context)

            promise.invokeMethod("then", withArguments: [thenFunction as Any])
            promise.invokeMethod("catch", withArguments: [catchFunction as Any])
        }
    }
}

// MARK: - Search Operations
extension JSController {
    /// Performs a search using the specified module's JavaScript search function
    /// - Parameters:
    ///   - keyword: The search query
    ///   - module: The module to use for searching
    ///   - completion: Callback with search results or empty array on failure
    func fetchJsSearchResults(keyword: String, module: ScrapingModule, completion: @escaping ([SearchItem]) -> Void) {
        Task {
            let items = await self.fetchJsSearchResults(keyword: keyword, module: module)
            DispatchQueue.main.async {
                completion(items)
            }
        }
    }

    func fetchJsSearchResults(keyword: String, module: ScrapingModule) async -> [SearchItem] {
        await contextMutex.withLock {
            do {
                try await ensureModuleLoaded(module)

                guard validateContext() else {
                    return []
                }

                let searchFunction = try getJavaScriptFunction("searchResults", module: module)
                let promise = try callJavaScriptFunction(
                    searchFunction,
                    withArguments: [keyword]
                )

                guard let result = await awaitPromiseResolution(promise) else {
                    return []
                }
                return parseSearchResults(result)
            } catch {
                return []
            }
        }
    }

    /// Fetches the show page URL for a given content using the module's search results
    /// - Parameters:
    ///   - contentUrl: The content URL to get show page for (used as search keyword)
    ///   - module: The module to use for fetching
    /// - Returns: The show page URL or nil if not found
    func fetchShowPageUrl(contentUrl: String, module: ScrapingModule) async -> String? {
        await contextMutex.withLock {
            do {
                try await ensureModuleLoaded(module)
                guard validateContext() else {
                    return nil
                }
                // Setup network fetch functions for this module
                context.setupNetworkFetch()
                context.setupNetworkFetchSimple()

                // Extract title from content URL for search
                let searchKeyword: String
                if contentUrl.contains("://") {
                    // Extract last component from full URL
                    let components = contentUrl.components(separatedBy: "/")
                    searchKeyword = components.last?.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                        .components(separatedBy: ".")
                        .first ?? contentUrl
                } else {
                    // Use contentUrl as-is for relative paths
                    searchKeyword = contentUrl.replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "_", with: " ")
                        .components(separatedBy: ".")
                        .first ?? contentUrl
                }

                // Use search results to get the href URL
                let searchResults = await fetchJsSearchResults(keyword: searchKeyword, module: module)

                if let firstResult = searchResults.first {

                    return firstResult.href
                } else {

                    return nil
                }
            } catch {

                return nil
            }
        }
    }

    private func parseSearchResults(_ result: JSValue) -> [SearchItem] {
        guard let jsonString = result.toString(),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        do {
            guard let array = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                return []
            }

            return array.compactMap { item -> SearchItem? in
                guard let title = item["title"] as? String,
                      let imageUrl = item["image"] as? String,
                      let href = item["href"] as? String else {
                    return nil
                }
                return SearchItem(title: title, imageUrl: imageUrl, href: href)
            }
        } catch {
            return []
        }
    }
}

// MARK: - Episode Operations
extension JSController {
    /// Extracts episode list for content using the module's JavaScript functions
    /// Copied exactly from Sora's fetchDetailsJS implementation
    /// - Parameters:
    ///   - contentUrl: The URL of the content to get episodes for
    ///   - module: The module to use for episode extraction
    ///   - completion: Callback with episode list or empty array on failure
    func fetchPlayerEpisodes(contentUrl: String, module: ScrapingModule, completion: @escaping ([PlayerEpisode]) -> Void) {
        Task {
            let episodes = await self.fetchPlayerEpisodes(contentUrl: contentUrl, module: module)
            DispatchQueue.main.async {
                completion(episodes)
            }
        }
    }

    func fetchPlayerEpisodes(contentUrl: String, module: ScrapingModule) async -> [PlayerEpisode] {
        let raw = contentUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        var candidateArguments: [String] = [raw]
        if let parsedUrl = URL(string: raw) {
            candidateArguments.append(parsedUrl.absoluteString)
            if !parsedUrl.path.isEmpty {
                candidateArguments.append(parsedUrl.path)
            }
        }
        if !raw.starts(with: "http"), !raw.starts(with: "/") {
            candidateArguments.append("/" + raw)
        }
        var seen = Set<String>()
        candidateArguments = candidateArguments.filter { seen.insert($0).inserted }

        do {
            if let episodes = try await fetchPlayerEpisodesFromJS(candidateArguments: candidateArguments, module: module), !episodes.isEmpty {
                return episodes
            }

            guard let urlToFetch = URL(string: raw), raw.starts(with: "http") else {
                return []
            }

            let (data, _) = try await URLSession.shared.data(from: urlToFetch)
            guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
                return []
            }

            let htmlEpisodes = try await fetchPlayerEpisodesFromJS(candidateArguments: [html], module: module) ?? []
            return htmlEpisodes
        } catch {
            return []
        }
    }

    private func fetchPlayerEpisodesFromJS(candidateArguments: [String], module: ScrapingModule) async throws -> [PlayerEpisode]? {
        try await contextMutex.withLock {
            try await ensureModuleLoaded(module)

            if context.exception != nil {
                return []
            }
            guard let extractEpisodesFunction = context.objectForKeyedSubscript("extractEpisodes") else {
                return []
            }

            for argument in candidateArguments {
                guard let value = extractEpisodesFunction.call(withArguments: [argument]) else {
                    continue
                }

                if value.hasProperty("then") {
                    guard let resolved = await awaitPromiseResolution(value) else {
                        continue
                    }
                    let episodes = parseEpisodesFromResult(resolved)
                    if !episodes.isEmpty {
                        return episodes
                    }
                } else {
                    let episodes = parseEpisodesFromResult(value)
                    if !episodes.isEmpty {
                        return episodes
                    }
                }
            }

            return []
        }
    }

    private func parseEpisodesFromResult(_ result: JSValue) -> [PlayerEpisode] {
        // Try to parse as array directly
        if let episodesArray = result.toArray() as? [[String: String]] {
            return episodesArray.compactMap { episodeData -> PlayerEpisode? in
                guard let num = episodeData["number"],
                      let link = episodeData["href"],
                      let number = Int(num) else {
                    return nil
                }
                let title = episodeData["title"] ?? "Episode \(number)"
                return PlayerEpisode(
                    number: number,
                    title: title,
                    url: link,
                    dateUploaded: nil,
                    scanlator: episodeData["scanlator"],
                    language: episodeData["language"] ?? "",
                    subtitleUrl: episodeData["subtitle"] ?? episodeData["subtitles"]
                )
            }
        }
        // Try to parse as JSON string
        if let jsonString = result.toString(),
           let data = jsonString.data(using: .utf8) {
            do {
                if let array = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                    return array.compactMap { item -> PlayerEpisode? in
                        guard let num = item["number"],
                              let link = item["href"] as? String,
                              let number = (num as? Int) ?? (num as? String).flatMap(Int.init) else {
                            return nil
                        }
                        let title = (item["title"] as? String) ?? "Episode \(number)"
                        return PlayerEpisode(
                            number: number,
                            title: title,
                            url: link,
                            dateUploaded: nil,
                            scanlator: item["scanlator"] as? String,
                            language: (item["language"] as? String) ?? "",
                            subtitleUrl: (item["subtitle"] as? String) ?? (item["subtitles"] as? String)
                        )
                    }
                }
                } catch {
                }
        }
        return []
    }
}

// MARK: - Streaming Operations
extension JSController {
    /// Extracts streaming URLs for a player using the module's JavaScript functions
    /// - Parameters:
    ///   - episodeId: The episode ID (from extractEpisodes result) to get streams for
    ///   - module: The module to use for stream extraction
    ///   - completion: Callback with stream info (URL and headers) or empty array on failure
    func fetchPlayerStreams(
        episodeId: String,
        module: ScrapingModule,
        completion: @escaping ([StreamInfo], String?) -> Void
    ) {
        Task {
            let (streams, subtitle) = await self.fetchPlayerStreams(episodeId: episodeId, module: module)
            DispatchQueue.main.async {
                completion(streams, subtitle)
            }
        }
    }

    func fetchPlayerStreams(episodeId: String, module: ScrapingModule) async -> ([StreamInfo], String?) {
        await contextMutex.withLock {
            do {
                try await ensureModuleLoaded(module)
                guard validateContext() else {
                    return ([], nil)
                }
                guard let extractStreamUrl = context.objectForKeyedSubscript("extractStreamUrl") else {
                    return ([], nil)
                }

                let result = extractStreamUrl.call(withArguments: [episodeId])
                let streams = await parseStreamResultFromJSValue(result)
                return streams
            } catch {
                return ([], nil)
            }
        }
    }

    private func parseStreamResultFromJSValue(_ result: JSValue?) async -> ([StreamInfo], String?) {
        guard let result = result else {
            return ([], nil)
        }

        // Handle Promise if returned
        if result.hasProperty("then") {
            guard let resolvedValue = await awaitPromiseResolution(result) else {
                return ([], nil)
            }
            guard let resultString = resolvedValue.toString(), !resultString.isEmpty else {
                return ([], nil)
            }
            return parseStreamResult(resultString)
        }

        // Try to get string representation
        guard let resultString = result.toString(), !resultString.isEmpty else {
            return ([], nil)
        }

        return parseStreamResult(resultString)
    }

    private func parseStreamResult(_ resultString: String) -> ([StreamInfo], String?) {
        // Try to parse as JSON first
        if let data = resultString.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    var streamInfos: [StreamInfo] = []
                    var subtitleUrl: String?

                    // Extract subtitle
                    if let subs = json["subtitles"] as? [String], let first = subs.first {
                        subtitleUrl = first
                    } else if let sub = json["subtitles"] as? String {
                        subtitleUrl = sub
                    }
                    // Module returns: { streams: [{ title: "SUB", streamUrl: "m3u8_url", headers: {...} }], subtitles: "..." }
                    if let streamSources = json["streams"] as? [[String: Any]] {
                        // Extract streamUrl and headers from stream objects (module format)
                        streamInfos = streamSources.compactMap { source -> StreamInfo? in
                            guard let streamUrl = source["streamUrl"] as? String ?? source["url"] as? String ?? source["stream"] as? String else {
                                return nil
                            }

                            let title = source["title"] as? String ?? "Stream"

                            // Extract headers if provided
                            var headers: [String: String] = [:]
                            if let headersDict = source["headers"] as? [String: String] {
                                headers = headersDict
                            } else {
                                // Default headers if not provided
                                headers = [
                                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                                        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                                    "Referer": streamUrl
                                ]
                            }
                            return StreamInfo(title: title, url: streamUrl, headers: headers)
                        }
                    } else if let streamsArray = json["streams"] as? [String] {
                        // Simple array of URLs - use default headers
                        streamInfos = streamsArray.map { url in
                            StreamInfo(title: "Stream", url: url, headers: [
                                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                                "Referer": url
                            ])
                        }
                    } else if let streamUrl = json["stream"] as? String {
                        streamInfos = [StreamInfo(title: "Stream", url: streamUrl, headers: [
                            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                            "Referer": streamUrl
                        ])]
                    }

                    return (streamInfos, subtitleUrl)
                }

                // Try to parse as simple array of strings
                if let streamsArray = try JSONSerialization.jsonObject(with: data, options: []) as? [String] {
                    return (streamsArray.map { url in
                        StreamInfo(title: "Stream", url: url, headers: [
                            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                            "Referer": url
                        ])
                    }, nil)
                }
            } catch {
            }
        }

        // If not JSON, treat as direct URL with default headers
        return ([StreamInfo(title: "Stream", url: resultString, headers: [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": resultString
        ])], nil)
    }
}
