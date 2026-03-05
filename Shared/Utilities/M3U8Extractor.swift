//
//  M3U8Extractor.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import AVKit
import Foundation

// MARK: - M3U8 Parser and Extractor

final class M3U8Extractor {

    static let shared = M3U8Extractor()

    private let networkClient: M3U8NetworkClient

    init(networkClient: M3U8NetworkClient = M3U8NetworkClient()) {
        self.networkClient = networkClient
    }

    // MARK: - M3U8 Models

    struct M3U8Playlist: Sendable {
        let version: Int?
        let targetDuration: Double?
        let mediaSequence: Int?
        let segments: [M3U8Segment]
        let isLive: Bool
        let endList: Bool

        var isMainPlaylist: Bool {
            segments.isEmpty
        }
    }

    struct M3U8Segment: Sendable {
        let duration: Double
        let url: String
        let title: String?
        let byteRange: String?
        let discontinuity: Bool
    }

    // MARK: - Parsing Methods

    /// Parses M3U8 content from string
    func parseM3U8(content: String, baseUrl: String) -> M3U8Playlist? {
        guard let baseURL = URL(string: baseUrl) else {
            return nil
        }

        var version: Int?
        var targetDuration: Double?
        var mediaSequence: Int?
        var segments: [M3U8Segment] = []
        var isLive = true
        var endList = false

        var currentDuration: Double = 0
        var currentTitle: String?
        var currentByteRange: String?
        var currentDiscontinuity = false

        content.enumerateLines { line, _ in
            let trimmed = line.trimmedLeadingWhitespace
            guard !trimmed.isEmpty else { return }

            switch trimmed.first {
            case "#":
                if trimmed.hasPrefix("#EXT-X-VERSION:") {
                    version = Int(trimmed.dropFirst(15))
                } else if trimmed.hasPrefix("#EXT-X-TARGETDURATION:") {
                    targetDuration = Double(trimmed.dropFirst(22))
                } else if trimmed.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                    mediaSequence = Int(trimmed.dropFirst(22))
                } else if trimmed == "#EXT-X-ENDLIST" {
                    endList = true
                    isLive = false
                } else if trimmed == "#EXT-X-DISCONTINUITY" {
                    currentDiscontinuity = true
                } else if trimmed.hasPrefix("#EXTINF:") {
                    let info = trimmed.dropFirst(8)
                    if let comma = info.firstIndex(of: ",") {
                        currentDuration = Double(info[..<comma]) ?? 0
                        let titleStart = info.index(after: comma)
                        currentTitle = titleStart < info.endIndex ? String(info[titleStart...]) : nil
                    } else {
                        currentDuration = Double(info) ?? 0
                        currentTitle = nil
                    }
                } else if trimmed.hasPrefix("#EXT-X-BYTERANGE:") {
                    currentByteRange = String(trimmed.dropFirst(17))
                }
            default:
                guard let segmentURL = self.resolveUrl(trimmed, baseURL: baseURL) else {
                    return
                }

                segments.append(
                    M3U8Segment(
                        duration: currentDuration,
                        url: segmentURL.absoluteString,
                        title: currentTitle,
                        byteRange: currentByteRange,
                        discontinuity: currentDiscontinuity
                    )
                )

                currentDuration = 0
                currentTitle = nil
                currentByteRange = nil
                currentDiscontinuity = false
            }
        }

        return M3U8Playlist(
            version: version,
            targetDuration: targetDuration,
            mediaSequence: mediaSequence,
            segments: segments,
            isLive: isLive,
            endList: endList
        )
    }

    /// Downloads and parses M3U8 playlist from URL
    func fetchAndParseM3U8(url: String, headers: [String: String] = [:]) async throws -> M3U8Playlist {
        guard let playlistURL = URL(string: url) else {
            throw M3U8Error.invalidURL
        }

        let finalHeaders = mergedHeaders(headers, referer: url)
        let content = try await networkClient.fetchText(from: playlistURL, headers: finalHeaders)

        return parseM3U8(content: content, baseUrl: playlistURL.deletingLastPathComponent().absoluteString)
            ?? M3U8Playlist(
                version: nil,
                targetDuration: nil,
                mediaSequence: nil,
                segments: [],
                isLive: false,
                endList: true
            )
    }

    /// Extracts direct video URLs from M3U8 segments
    func extractVideoSegments(from playlist: M3U8Playlist) -> [String] {
        playlist.segments.map(\.url)
    }

    /// Creates a playable AVPlayerItem from M3U8 URL with automatic quality selection
    func createPlayerItemWithBestQuality(from m3u8Url: String, headers: [String: String] = [:]) async throws -> AVPlayerItem {
        do {
            let qualities = try await getStreamQualities(from: m3u8Url, headers: headers, markHighest: false)
            if let bestQuality = getHighestQuality(from: qualities) {
                return try await createPlayerItem(from: bestQuality.url, headers: headers)
            }
        } catch {
            // If quality detection fails, fall back to original URL.
        }

        return try await createPlayerItem(from: m3u8Url, headers: headers)
    }

    /// Creates a playable PlayerItem from M3U8 URL
    func createPlayerItem(from m3u8Url: String, headers: [String: String] = [:]) async throws -> AVPlayerItem {
        guard let url = URL(string: m3u8Url) else {
            throw M3U8Error.invalidURL
        }

        let finalHeaders = mergedHeaders(headers, referer: m3u8Url)
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": finalHeaders]
        let asset = AVURLAsset(url: url, options: options)

        return AVPlayerItem(asset: asset)
    }

    /// Resolves the best stream URL from an M3U8 playlist.
    /// If the URL points to a master playlist, it returns the URL of the highest quality stream.
    /// If it's already a media playlist, it returns the original URL.
    func resolveBestStreamUrl(url: String, headers: [String: String] = [:]) async throws -> String {
        do {
            let qualities = try await getStreamQualities(from: url, headers: headers, markHighest: false)
            if let best = getHighestQuality(from: qualities) {
                return best.url
            }
        } catch {
        }
        return url
    }

    /// Gets stream quality information from main playlist
    func getStreamQualities(from mainPlaylistUrl: String, headers: [String: String] = [:], markHighest: Bool = true) async throws -> [StreamQuality] {
        guard let playlistURL = URL(string: mainPlaylistUrl) else {
            throw M3U8Error.invalidURL
        }

        let finalHeaders = mergedHeaders(headers, referer: mainPlaylistUrl)
        let content = try await networkClient.fetchText(from: playlistURL, headers: finalHeaders)

        var qualities: [StreamQuality] = []
        var currentBandwidth: Int?
        var currentResolution: String?
        var currentCodecs: String?

        content.enumerateLines { line, _ in
            let trimmed = line.trimmedLeadingWhitespace
            guard !trimmed.isEmpty else { return }

            switch trimmed.first {
            case "#":
                guard trimmed.hasPrefix("#EXT-X-STREAM-INF:") else {
                    return
                }
                let attrs = self.parseAttributes(String(trimmed.dropFirst(18)))
                currentBandwidth = Int(attrs["BANDWIDTH"] ?? "")
                currentResolution = attrs["RESOLUTION"]
                currentCodecs = attrs["CODECS"]
            default:
                guard currentBandwidth != nil || currentResolution != nil else {
                    return
                }
                guard let streamURL = self.resolveUrl(trimmed, baseURL: playlistURL.deletingLastPathComponent()) else {
                    currentBandwidth = nil
                    currentResolution = nil
                    currentCodecs = nil
                    return
                }

                let urlString = streamURL.absoluteString
                let bandwidth = currentBandwidth ?? self.extractBandwidth(from: urlString)
                let resolution = currentResolution ?? self.extractResolution(from: urlString)
                let title = self.generateQualityTitle(resolution: resolution, bandwidth: bandwidth)

                qualities.append(
                    StreamQuality(
                        url: urlString,
                        bandwidth: bandwidth,
                        resolution: resolution,
                        codecs: currentCodecs,
                        title: title
                    )
                )

                currentBandwidth = nil
                currentResolution = nil
                currentCodecs = nil
            }
        }

        if qualities.isEmpty {
            return [StreamQuality(url: mainPlaylistUrl, bandwidth: 0, resolution: nil, codecs: nil, title: "Default")]
        }

        qualities.sort { $0.bandwidth > $1.bandwidth }

        guard markHighest, let best = getHighestQuality(from: qualities), best.bandwidth > 0 else {
            return qualities
        }

        return qualities.map { quality in
            let title = quality.bandwidth == best.bandwidth ? "\(quality.title) ⭐" : quality.title
            return StreamQuality(
                url: quality.url,
                bandwidth: quality.bandwidth,
                resolution: quality.resolution,
                codecs: quality.codecs,
                title: title
            )
        }
    }

    /// Gets the highest quality stream from available qualities
    func getHighestQuality(from qualities: [StreamQuality]) -> StreamQuality? {
        var best: StreamQuality?
        for quality in qualities {
            guard quality.bandwidth > 0 else { continue }
            if let currentBest = best {
                if quality.bandwidth > currentBest.bandwidth {
                    best = quality
                }
            } else {
                best = quality
            }
        }
        return best ?? qualities.first
    }

    func clearMemoryCache() async {
        await networkClient.clear()
    }

    // MARK: - Helpers

    private func mergedHeaders(_ headers: [String: String], referer: String) -> [String: String] {
        guard headers.isEmpty else { return headers }

        return [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": referer
        ]
    }

    private func resolveUrl(_ path: Substring, baseURL: URL) -> URL? {
        URL(string: String(path), relativeTo: baseURL)?.absoluteURL
    }

    private func parseAttributes(_ infoString: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var current = ""
        var inQuotes = false

        func flush(_ chunk: String) {
            guard let split = chunk.firstIndex(of: "=") else { return }
            let key = chunk[..<split].trimmingCharacters(in: .whitespaces)
            let valueStart = chunk.index(after: split)
            let value = chunk[valueStart...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !key.isEmpty {
                attributes[String(key)] = value
            }
        }

        for char in infoString {
            switch char {
            case "\"":
                inQuotes.toggle()
                current.append(char)
            case "," where !inQuotes:
                flush(current)
                current.removeAll(keepingCapacity: true)
            default:
                current.append(char)
            }
        }

        if !current.isEmpty {
            flush(current)
        }

        return attributes
    }

    private enum Regex {
        static let resolutionVertical = try? NSRegularExpression(pattern: "(\\d{3,4})p", options: .caseInsensitive)
        static let resolutionDimensions = try? NSRegularExpression(pattern: "(\\d{3,4})x(\\d{3,4})", options: .caseInsensitive)
        static let bandwidth = try? NSRegularExpression(pattern: "(?:BANDWIDTH|bitrate)=(\\d+)", options: .caseInsensitive)
        static let kbps = try? NSRegularExpression(pattern: "(\\d+)k", options: .caseInsensitive)
        static let mbps = try? NSRegularExpression(pattern: "(\\d+)m", options: .caseInsensitive)
        static let bps = try? NSRegularExpression(pattern: "(\\d+)bps", options: .caseInsensitive)
    }

    private static let qualityMap: [(Int, String)] = [
        (4320, "8K"),
        (2160, "4K"),
        (1440, "2K"),
        (1080, "FHD"),
        (720, "HD"),
        (480, "SD")
    ]

    private func extractResolution(from url: String) -> String? {
        if let height = firstMatchInt(Regex.resolutionDimensions, in: url, captureGroup: 2) {
            return "\(height)p"
        }

        if let vertical = firstMatchInt(Regex.resolutionVertical, in: url, captureGroup: 1) {
            return "\(vertical)p"
        }

        let lowered = url.lowercased()
        if lowered.contains("8k") { return "4320p" }
        if lowered.contains("4k") || lowered.contains("uhd") { return "2160p" }
        if lowered.contains("2k") { return "1440p" }
        if lowered.contains("fhd") { return "1080p" }
        if lowered.contains("hd") { return "720p" }
        if lowered.contains("sd") { return "480p" }
        return nil
    }

    private func extractBandwidth(from url: String) -> Int {
        if let value = firstMatchInt(Regex.bandwidth, in: url, captureGroup: 1) {
            return value
        }
        if let value = firstMatchInt(Regex.bps, in: url, captureGroup: 1) {
            return value
        }
        if let value = firstMatchInt(Regex.kbps, in: url, captureGroup: 1) {
            return value * 1_000
        }
        if let value = firstMatchInt(Regex.mbps, in: url, captureGroup: 1) {
            return value * 1_000_000
        }
        return 0
    }

    private func firstMatchInt(_ regex: NSRegularExpression?, in text: String, captureGroup: Int) -> Int? {
        guard let regex else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > captureGroup,
              let matchRange = Range(match.range(at: captureGroup), in: text)
        else {
            return nil
        }

        return Int(text[matchRange])
    }

    private func generateQualityTitle(resolution: String?, bandwidth: Int) -> String {
        if let resolution {
            let normalized: String
            let height: Int

            if resolution.contains("x") {
                let components = resolution.split(separator: "x")
                let h = components.last.map(String.init) ?? resolution
                normalized = h.hasSuffix("p") ? h : "\(h)p"
                height = Int(h.replacingOccurrences(of: "p", with: "")) ?? 0
            } else {
                normalized = resolution.hasSuffix("p") ? resolution : "\(resolution)p"
                height = Int(resolution.replacingOccurrences(of: "p", with: "")) ?? 0
            }

            return "\(normalized) (\(qualityLabel(for: height)))"
        }

        if bandwidth > 0 {
            let height = estimateHeightFromBandwidth(bandwidth)
            let speed = bandwidth >= 1_000_000 ? "\(bandwidth / 1_000_000)Mbps" : "\(bandwidth / 1000)Kbps"
            return "\(speed) (\(qualityLabel(for: height)))"
        }

        return "Auto"
    }

    private func qualityLabel(for height: Int) -> String {
        for (threshold, label) in Self.qualityMap where height >= threshold {
            return label
        }
        return "Low"
    }

    private func estimateHeightFromBandwidth(_ bandwidth: Int) -> Int {
        switch Double(bandwidth) / 1_000_000 {
        case 25...:
            return 4320
        case 15..<25:
            return 2160
        case 8..<15:
            return 1440
        case 5..<8:
            return 1080
        case 2.5..<5:
            return 720
        case 1..<2.5:
            return 480
        default:
            return 360
        }
    }
}

// MARK: - Network Client

actor M3U8NetworkClient {

    private struct RequestKey: Hashable {
        let url: String
        let headers: String

        init(url: URL, headers: [String: String]) {
            self.url = url.absoluteString
            self.headers = headers.map { "\($0.key.lowercased())=\($0.value)" }.sorted().joined(separator: "&")
        }
    }

    private let session: URLSession
    private var cache: [RequestKey: String] = [:]
    private var inFlight: [RequestKey: Task<String, Error>] = [:]
    private let maxCacheEntries = 12

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchText(from url: URL, headers: [String: String]) async throws -> String {
        let key = RequestKey(url: url, headers: headers)

        if let cached = cache[key] {
            return cached
        }

        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<String, Error> {
            var request = URLRequest(url: url)
            headers.forEach { header, value in
                request.setValue(value, forHTTPHeaderField: header)
            }

            let (data, _) = try await session.data(for: request)
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                throw M3U8Error.invalidContent
            }
            return text
        }

        inFlight[key] = task

        do {
            let text = try await task.value
            cache[key] = text
            if cache.count > maxCacheEntries {
                cache.removeAll(keepingCapacity: true)
            }
            inFlight[key] = nil
            return text
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func clear() {
        cache.removeAll(keepingCapacity: false)
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll(keepingCapacity: false)
    }
}

// MARK: - Supporting Models

struct StreamQuality: Sendable {
    let url: String
    let bandwidth: Int
    let resolution: String?
    let codecs: String?
    let title: String
}

// MARK: - Error Types

enum M3U8Error: LocalizedError {
    case invalidURL
    case invalidContent
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid M3U8 URL"
        case .invalidContent:
            return "Invalid M3U8 content"
        case .parsingFailed:
            return "Failed to parse M3U8 playlist"
        }
    }
}

private extension String {
    var trimmedLeadingWhitespace: Substring {
        self[...].drop(while: { $0 == " " || $0 == "\t" })
    }
}
