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
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

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

        for line in lines {
            if line.hasPrefix("#EXT-X-VERSION:") {
                let versionStr = String(line.dropFirst("#EXT-X-VERSION:".count))
                version = Int(versionStr)
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                let durationStr = String(line.dropFirst("#EXT-X-TARGETDURATION:".count))
                targetDuration = Double(durationStr)
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let sequenceStr = String(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
                mediaSequence = Int(sequenceStr)
            } else if line == "#EXT-X-ENDLIST" {
                endList = true
                isLive = false
            } else if line == "#EXT-X-DISCONTINUITY" {
                currentDiscontinuity = true
            } else if line.hasPrefix("#EXTINF:") {
                // Parse duration and title from #EXTINF:duration,title
                let infString = String(line.dropFirst("#EXTINF:".count))
                let components = infString.components(separatedBy: ",")
                if let durationStr = components.first {
                    currentDuration = Double(durationStr) ?? 0
                }
                if components.count > 1 {
                    currentTitle = components[1]
                }
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                currentByteRange = String(line.dropFirst("#EXT-X-BYTERANGE:".count))
            } else if !line.hasPrefix("#") {
                // This is a segment URL
                let segmentUrl = resolveUrl(line, baseUrl: baseUrl)
                let segment = M3U8Segment(
                    duration: currentDuration,
                    url: segmentUrl,
                    title: currentTitle,
                    byteRange: currentByteRange,
                    discontinuity: currentDiscontinuity
                )
                segments.append(segment)

                // Reset current segment info
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
        guard let urlObj = URL(string: url) else {
            throw M3U8Error.invalidURL
        }

        // Create request with provided headers or default headers to avoid blocking
        var request = URLRequest(url: urlObj)
        if headers.isEmpty {
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue(urlObj.absoluteString, forHTTPHeaderField: "Referer")
        } else {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let content = String(data: data, encoding: .utf8) else {
            throw M3U8Error.invalidContent
        }

        let baseUrl = urlObj.deletingLastPathComponent().absoluteString
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
            print("Quality detection failed, using original URL: \(error)")
        }

        // Fallback to original URL
        return try await createPlayerItem(from: m3u8Url, headers: headers)
    }

    /// Creates a playable AVPlayerItem from M3U8 URL
    func createPlayerItem(from m3u8Url: String, headers: [String: String] = [:]) async throws -> AVPlayerItem {
        // Use provided headers or default headers for fetching the playlist
        let fetchHeaders = headers.isEmpty ? [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": m3u8Url
        ] : headers

        _ = try await fetchAndParseM3U8(url: m3u8Url, headers: fetchHeaders)

        guard let url = URL(string: m3u8Url) else {
            throw M3U8Error.invalidURL
        }

        // Use provided headers or default headers for AVPlayer
        let finalHeaders = headers.isEmpty ? [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": m3u8Url
        ] : headers

        // Use the correct key for HTTP headers in AVURLAsset
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": finalHeaders]
        let asset = AVURLAsset(url: url, options: options)

        return AVPlayerItem(asset: asset)
    }

    /// Gets stream quality information from main playlist
    func getStreamQualities(from mainPlaylistUrl: String, headers: [String: String] = [:]) async throws -> [StreamQuality] {
        guard let url = URL(string: mainPlaylistUrl) else {
            throw M3U8Error.invalidURL
        }

        // Create request with provided headers or default headers to avoid blocking
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

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let content = String(data: data, encoding: .utf8) else {
            throw M3U8Error.invalidContent
        }

        let baseUrl = url.deletingLastPathComponent().absoluteString
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var qualities: [StreamQuality] = []
        var currentBandwidth: Int = 0
        var currentResolution: String?
        var currentCodecs: String?
        var currentUrl: String?

        for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
            // Parse stream info line
            // Format: #EXT-X-STREAM-INF:BANDWIDTH=...,RESOLUTION=...,CODECS="..."
            let infoString = String(line.dropFirst("#EXT-X-STREAM-INF:".count))

            // Extract bandwidth
            if let bandwidthRange = infoString.range(of: "BANDWIDTH=") {
                let afterBandwidth = String(infoString[bandwidthRange.upperBound...])
                let bandwidthEnd = afterBandwidth.range(of: ",") ??
                    afterBandwidth.range(of: "\n") ??
                    (afterBandwidth.endIndex..<afterBandwidth.endIndex)
                let bandwidthStr = String(afterBandwidth[..<bandwidthEnd.lowerBound])
                currentBandwidth = Int(bandwidthStr) ?? 0
            }

            // Extract resolution
            if let resolutionRange = infoString.range(of: "RESOLUTION=") {
                let afterResolution = String(infoString[resolutionRange.upperBound...])
                let resolutionEnd = afterResolution.range(of: ",") ??
                    afterResolution.range(of: "\n") ??
                    (afterResolution.endIndex..<afterResolution.endIndex)
                let resolutionStr = String(afterResolution[..<resolutionEnd.lowerBound])
                currentResolution = resolutionStr
            }

            // Extract codecs
            if let codecsRange = infoString.range(of: "CODECS=") {
                let afterCodecs = String(infoString[codecsRange.upperBound...])
                let codecsEnd = afterCodecs.range(of: ",") ?? afterCodecs.range(of: "\n") ?? (afterCodecs.endIndex..<afterCodecs.endIndex)
                var codecsStr = String(afterCodecs[..<codecsEnd.lowerBound])
                // Remove quotes if present
                codecsStr = codecsStr.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                currentCodecs = codecsStr
            }

            // Get the URL from the next line
            if index + 1 < lines.count {
                let nextLine = lines[index + 1]
                if !nextLine.hasPrefix("#") {
                    currentUrl = resolveUrl(nextLine, baseUrl: baseUrl)
                }
            }

            // Create quality entry if we have a URL
            if let url = currentUrl {
                let title = generateQualityTitle(resolution: currentResolution, bandwidth: currentBandwidth)
                qualities.append(StreamQuality(
                    url: url,
                    bandwidth: currentBandwidth,
                    resolution: currentResolution,
                    codecs: currentCodecs,
                    title: title
                ))
            }

            // Reset for next stream
            currentBandwidth = 0
            currentResolution = nil
            currentCodecs = nil
            currentUrl = nil
        }

        // If no qualities found (not a main playlist), return single quality
        if qualities.isEmpty {
            return [StreamQuality(
                url: mainPlaylistUrl,
                bandwidth: 0,
                resolution: nil,
                codecs: nil,
                title: "Default"
            )]

            }

        // Sort by bandwidth (highest first)
        qualities.sort { $0.bandwidth > $1.bandwidth }

        return qualities
    }

    /// Gets the highest quality stream from available qualities
    func getHighestQuality(from qualities: [StreamQuality]) -> StreamQuality? {
        qualities.max { $0.bandwidth < $1.bandwidth }
    }

    /// Gets stream qualities with highest quality marked
    func getQualitiesWithHighestMarked(from mainPlaylistUrl: String, headers: [String: String] = [:]) async throws -> [StreamQuality] {
        let qualities = try await getStreamQualities(from: mainPlaylistUrl, headers: headers)

        // Mark the highest quality
        if let highest = qualities.max(by: { $0.bandwidth < $1.bandwidth }) {
            return qualities.map { quality in
                StreamQuality(
                    url: quality.url,
                    bandwidth: quality.bandwidth,
                    resolution: quality.resolution,
                    codecs: quality.codecs,
                    title: quality.bandwidth == highest.bandwidth ? "\(quality.title) ⭐" : quality.title
                )
            }
        }

        return qualities
    }

    // MARK: - Helper Methods

    private func resolveUrl(_ url: String, baseUrl: String) -> String {
        if url.hasPrefix("http") {
            return url
        }

        guard let base = URL(string: baseUrl) else {
            return url
        }

        if url.hasPrefix("/") {
            return base.scheme! + "://" + base.host! + url
        } else {
            return base.appendingPathComponent(url).absoluteString
        }
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
        if let resolution = resolution {
            // Parse resolution like "1920x1080" or "1080p"
            if resolution.contains("x") {
                let parts = resolution.components(separatedBy: "x")
                if parts.count == 2, let height = Int(parts[1]) {
                    // Add quality label for common resolutions
                    let qualityLabel = getQualityLabel(for: height)
                    return "\(height)p (\(qualityLabel))"
                }
                return resolution
            } else if resolution.hasSuffix("p") {
                let heightStr = String(resolution.dropLast())
                if let height = Int(heightStr) {
                    let qualityLabel = getQualityLabel(for: height)
                    return "\(height)p (\(qualityLabel))"
                }
                return resolution
            } else {
                return resolution
            }
        } else if bandwidth > 0 {
            // Estimate quality from bandwidth if resolution not available
            let estimatedHeight = estimateHeightFromBandwidth(bandwidth)
            let qualityLabel = getQualityLabel(for: estimatedHeight)
            if bandwidth >= 1_000_000 {
                return "\(bandwidth / 1_000_000)Mbps (\(qualityLabel))"
            } else {
                return "\(bandwidth / 1000)Kbps (\(qualityLabel))"
            }
        } else {
            return "Auto"
        }
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
