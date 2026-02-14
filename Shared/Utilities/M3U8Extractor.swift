//
//  M3U8Extractor.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import Foundation
import AVKit

// MARK: - M3U8 Parser and Extractor

class M3U8Extractor {

    static let shared = M3U8Extractor()

    private init() {}

    // MARK: - M3U8 Models

    struct M3U8Playlist {
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

    struct M3U8Segment {
        let duration: Double
        let url: String
        let title: String?
        let byteRange: String?
        let discontinuity: Bool
    }

    // MARK: - Parsing Methods

    /// Parses M3U8 content from string
    func parseM3U8(content: String, baseUrl: String) -> M3U8Playlist? {
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

        // Memory efficient parsing using enumerateLines
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            if trimmed.hasPrefix("#") {
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
                    // Parse duration and title
                    let infString = trimmed.dropFirst(8)
                    let commaIndex = infString.firstIndex(of: ",") ?? infString.endIndex
                    let durationStr = infString[..<commaIndex]
                    currentDuration = Double(durationStr) ?? 0

                    if commaIndex < infString.endIndex {
                        currentTitle = String(infString[infString.index(after: commaIndex)...])
                    }
                } else if trimmed.hasPrefix("#EXT-X-BYTERANGE:") {
                    currentByteRange = String(trimmed.dropFirst(17))
                }
            } else {
                // Segment URL
                let segmentUrl = self.resolveUrl(trimmed, baseUrl: baseUrl)
                let segment = M3U8Segment(
                    duration: currentDuration,
                    url: segmentUrl,
                    title: currentTitle,
                    byteRange: currentByteRange,
                    discontinuity: currentDiscontinuity
                )
                segments.append(segment)

                // Reset per-segment info
                currentDuration = 0
                currentTitle = nil
                currentByteRange = nil
                currentDiscontinuity = false
            }
        }

        let playlist = M3U8Playlist(
            version: version,
            targetDuration: targetDuration,
            mediaSequence: mediaSequence,
            segments: segments,
            isLive: isLive,
            endList: endList
        )
        return playlist
    }

    /// Downloads and parses M3U8 playlist from URL
    func fetchAndParseM3U8(url: String, headers: [String: String] = [:]) async throws -> M3U8Playlist {
        let (content, baseUrl) = try await fetchContent(from: url, headers: headers)
        return parseM3U8(content: content, baseUrl: baseUrl) ?? M3U8Playlist(
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
        playlist.segments.map { $0.url }
    }

    /// Creates a playable AVPlayerItem from M3U8 URL with automatic quality selection
    func createPlayerItemWithBestQuality(from m3u8Url: String, headers: [String: String] = [:]) async throws -> AVPlayerItem {
        // First, try to get qualities and select the best one
        do {
            let qualities = try await getStreamQualities(from: m3u8Url, headers: headers)
            if let bestQuality = getHighestQuality(from: qualities) {
                // Use the highest quality URL instead of the original
                return try await createPlayerItem(from: bestQuality.url, headers: headers)
            }
        } catch {
            // If quality detection fails, fall back to original URL
        }

        // Fallback to original URL
        return try await createPlayerItem(from: m3u8Url, headers: headers)
    }

    /// Creates a playable PlayerItem from M3U8 URL
    func createPlayerItem(from m3u8Url: String, headers: [String: String] = [:]) async throws -> AVPlayerItem {
        // Use provided headers or default headers for fetching the playlist
        let fetchHeaders = !headers.isEmpty ? headers : [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": m3u8Url
        ]

        _ = try await fetchAndParseM3U8(url: m3u8Url, headers: fetchHeaders)

        guard let url = URL(string: m3u8Url) else {
            throw M3U8Error.invalidURL
        }

        // Use provided headers or default headers for AVPlayer
        let finalHeaders = !headers.isEmpty ? headers : [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": m3u8Url
        ]

        // Use the correct key for HTTP headers in AVURLAsset
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": finalHeaders]
        let asset = AVURLAsset(url: url, options: options)

        return AVPlayerItem(asset: asset)
    }

    /// Resolves the best stream URL from an M3U8 playlist.
    /// If the URL points to a master playlist, it returns the URL of the highest quality stream.
    /// If it's already a media playlist, it returns the original URL.
    func resolveBestStreamUrl(url: String, headers: [String: String] = [:]) async throws -> String {
        do {
            let qualities = try await getStreamQualities(from: url, headers: headers)
            if let best = getHighestQuality(from: qualities) {
                return best.url
            }
        } catch {
        }
        return url
    }

    /// Gets stream quality information from main playlist using efficient parsing
    func getStreamQualities(from mainPlaylistUrl: String, headers: [String: String] = [:], markHighest: Bool = true) async throws -> [StreamQuality] {
        let (content, baseUrl) = try await fetchContent(from: mainPlaylistUrl, headers: headers)
        var qualities: [StreamQuality] = []
        // State parsing variables
        var currentBandwidth: Int = 0
        var currentResolution: String?
        var currentCodecs: String?

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }

            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                let infoString = String(trimmed.dropFirst(18))
                let attrs = self.parseAttributes(infoString)
                currentBandwidth = Int(attrs["BANDWIDTH"] ?? "") ?? 0
                currentResolution = attrs["RESOLUTION"]
                currentCodecs = attrs["CODECS"]
            } else if !trimmed.hasPrefix("#") {
                if currentBandwidth > 0 || currentResolution != nil {
                    let streamUrl = self.resolveUrl(trimmed, baseUrl: baseUrl)
                    qualities.append(StreamQuality(
                        url: streamUrl,
                        bandwidth: currentBandwidth,
                        resolution: currentResolution,
                        codecs: currentCodecs,
                        title: "" // Will be set after sorting/marking
                    ))

                    currentBandwidth = 0
                    currentResolution = nil
                    currentCodecs = nil
                }
            }
        }

        if qualities.isEmpty {
            return [StreamQuality(url: mainPlaylistUrl, bandwidth: 0, resolution: nil, codecs: nil, title: "Default")]
        }

        qualities.sort { $0.bandwidth > $1.bandwidth }

        // Generate titles and mark highest
        let highestBandwidth = qualities.first?.bandwidth ?? 0
        return qualities.map { q in
            var title = generateQualityTitle(resolution: q.resolution, bandwidth: q.bandwidth)
            if markHighest && q.bandwidth == highestBandwidth && highestBandwidth > 0 {
                title += " ⭐"
            }
            return StreamQuality(url: q.url, bandwidth: q.bandwidth, resolution: q.resolution, codecs: q.codecs, title: title)
        }
    }

    /// Gets the highest quality stream from available qualities
    func getHighestQuality(from qualities: [StreamQuality]) -> StreamQuality? {
        qualities.max { $0.bandwidth < $1.bandwidth }
    }

    // MARK: - Helper Methods

    private func resolveUrl(_ url: String, baseUrl: String) -> String {
        if url.hasPrefix("http") {
            return url
        }

        guard let base = URL(string: baseUrl) else {
            return url
        }

        let resolvedUrl: String
        if url.hasPrefix("/") {
            resolvedUrl = base.scheme! + "://" + base.host! + url
        } else {
            resolvedUrl = base.appendingPathComponent(url).absoluteString
        }
        return resolvedUrl
    }

    private func createRequest(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        if headers.isEmpty {
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        } else {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        return request
    }

    private func fetchContent(from url: String, headers: [String: String]) async throws -> (content: String, baseUrl: String) {
        guard let urlObj = URL(string: url) else {
            throw M3U8Error.invalidURL
        }

        let request = createRequest(url: urlObj, headers: headers)
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let content = String(data: data, encoding: .utf8) else {
            throw M3U8Error.invalidContent
        }

        return (content, urlObj.deletingLastPathComponent().absoluteString)
    }

    private func parseAttributes(_ infoString: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let parts = infoString.components(separatedBy: ",")
        for part in parts {
            let pair = part.components(separatedBy: "=")
            if pair.count == 2 {
                let key = pair[0].trimmingCharacters(in: .whitespaces)
                let value = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                attributes[key] = value
            }
        }
        return attributes
    }

    private func extractResolution(from url: String) -> String? {
        // Enhanced patterns to extract resolution from various URL formats
        let patterns = [
            "(\\d{3,4})p",           // 1080p, 720p, etc.
            "(\\d{3,4})x(\\d{3,4})", // 1920x1080, 1280x720, etc.
            "4k", "8k", "2k",         // Direct quality labels
            "uhd", "fhd", "hd", "sd"  // Common quality abbreviations
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: url.utf16.count)
                if let match = regex.firstMatch(in: url, options: [], range: range) {
                    if match.numberOfRanges > 1 {
                        // For patterns like 1920x1080, get the height (second group)
                        if match.numberOfRanges > 2 {
                            let heightRange = match.range(at: 2)
                            if let swiftRange = Range(heightRange, in: url),
                               let height = Int(String(url[swiftRange])) {
                                return "\(height)p"
                            }
                        }

                        // For patterns like 1080p, get the first group
                        let matchRange = match.range(at: 1)
                        if let swiftRange = Range(matchRange, in: url) {
                            let resolution = String(url[swiftRange])

                            // Convert direct quality labels to resolution
                            switch resolution.lowercased() {
                            case "4k", "uhd": return "2160p"
                            case "8k": return "4320p"
                            case "2k": return "1440p"
                            case "fhd": return "1080p"
                            case "hd": return "720p"
                            case "sd": return "480p"
                            default:
                                return resolution.hasSuffix("p") ? resolution : "\(resolution)p"
                            }
                        }
                    } else {
                        // Handle single word matches like "4k", "8k"
                        let matchRange = match.range
                        if let swiftRange = Range(matchRange, in: url) {
                            let quality = String(url[swiftRange]).lowercased()
                            switch quality {
                            case "4k", "uhd": return "2160p"
                            case "8k": return "4320p"
                            case "2k": return "1440p"
                            case "fhd": return "1080p"
                            case "hd": return "720p"
                            case "sd": return "480p"
                            default: break
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private func extractBandwidth(from url: String) -> Int {
        // Enhanced patterns to extract bandwidth from various formats
        let patterns = [
            "BANDWIDTH=(\\d+)",           // Standard M3U8 format
            "bitrate=(\\d+)",            // Alternative format
            "(\\d+)k",                  // 5000k, 3000k, etc.
            "(\\d+)bps",                 // 5000000bps, etc.
            "(\\d+)m"                   // 5m, 10m, etc.
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: url.utf16.count)
                if let match = regex.firstMatch(in: url, options: [], range: range) {
                    if match.numberOfRanges > 1 {
                        let matchRange = match.range(at: 1)
                        if let swiftRange = Range(matchRange, in: url),
                           let value = Int(String(url[swiftRange])) {

                            // Convert to proper bandwidth based on format
                            if pattern.contains("k") {
                                return value * 1000  // Convert k to bps
                            } else if pattern.contains("m") {
                                return value * 1_000_000  // Convert m to bps
                            } else if pattern.contains("bps") {
                                return value  // Already in bps
                            } else {
                                return value  // Standard bandwidth format
                            }
                        }
                    }
                }
            }
        }
        return 0
    }

    private func generateQualityTitle(resolution: String?, bandwidth: Int) -> String {
        let label: String
        let res: String

        if let resolution = resolution {
            if resolution.contains("x") {
                res = resolution.components(separatedBy: "x").last ?? resolution
            } else {
                res = resolution
            }
            let height = Int(res.replacingOccurrences(of: "p", with: "")) ?? 0
            label = getQualityLabel(for: height)
        } else if bandwidth > 0 {
            let height = estimateHeightFromBandwidth(bandwidth)
            label = getQualityLabel(for: height)
            res = bandwidth >= 1_000_000 ? "\(bandwidth / 1_000_000)Mbps" : "\(bandwidth / 1000)Kbps"
        } else {
            return "Auto"
        }

        return res.hasSuffix("p") ? "\(res) (\(label))" : "\(res)p (\(label))"
    }

    private func getQualityLabel(for height: Int) -> String {
        switch height {
        case 4320...:
            return "8K"
        case 2160...:
            return "4K"
        case 1440...:
            return "2K"
        case 1080...:
            return "FHD"
        case 720...:
            return "HD"
        case 480...:
            return "SD"
        default:
            return "Low"
        }
    }

    private func estimateHeightFromBandwidth(_ bandwidth: Int) -> Int {
        // Rough estimation of video height from bandwidth
        let bandwidthMbps = Double(bandwidth) / 1_000_000
        switch bandwidthMbps {
        case 25...:
            return 4320 // 8K
        case 15..<25:
            return 2160 // 4K
        case 8..<15:
            return 1440 // 2K
        case 5..<8:
            return 1080 // FHD
        case 2.5..<5:
            return 720 // HD
        case 1..<2.5:
            return 480 // SD
        default:
            return 360 // Low
        }
    }
}

// MARK: - Supporting Models

struct StreamQuality {
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
