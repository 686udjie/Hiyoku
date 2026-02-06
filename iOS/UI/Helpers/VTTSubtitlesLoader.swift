//
//  VTTSubtitlesLoader.swift
//  Hiyoku
//
//  Created by 686udjie on 18/01/26.
//

import Foundation

struct SubtitleCue: Identifiable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let text: String
    let lines: [String]
    init(startTime: Double, endTime: Double, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        let rawLines = text.components(separatedBy: .newlines)
        self.lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

class VTTSubtitlesLoader: ObservableObject {
    @Published var cues: [SubtitleCue] = []
    enum SubtitleFormat {
        case vtt
        case srt
        case unknown
    }
    func load(from urlString: String) {
        let url: URL
        if urlString.hasPrefix("/") {
            url = URL(fileURLWithPath: urlString)
        } else if let u = URL(string: urlString) {
            url = u
        } else {
            return
        }
        if url.isFileURL {
            do {
                let data = try Data(contentsOf: url)
                processSubtitleData(data)
            } catch {
                DispatchQueue.main.async {
                    self.cues = []
                }
            }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            self?.processSubtitleData(data)
        }.resume()
    }

    private func processSubtitleData(_ data: Data?) {
        guard let responseData = data,
              let subtitleContent = String(data: responseData, encoding: .utf8),
              !subtitleContent.isEmpty else {
            DispatchQueue.main.async {
                self.cues = []
            }
            return
        }
        let trimmed = subtitleContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedFormat: SubtitleFormat = trimmed.contains("WEBVTT") ? .vtt : .srt
        DispatchQueue.main.async {
            switch detectedFormat {
            case .vtt:
                self.cues = self.parseVTT(content: subtitleContent)
            case .srt:
                self.cues = self.parseSRT(content: subtitleContent)
            case .unknown:
                self.cues = self.parseVTT(content: subtitleContent)
            }
        }
    }
    // MARK: - VTT Parsing
    private func parseVTT(content: String) -> [SubtitleCue] {
        let contentLines = content.components(separatedBy: .newlines)
        var subtitleCues: [SubtitleCue] = []
        var activeStartTime: Double?
        var activeEndTime: Double?
        var activeSubtitleText: String = ""
        var processingCueContent = false
        for (lineIndex, currentLine) in contentLines.enumerated() {
            let cleanedLine = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedLine.isEmpty || cleanedLine == "WEBVTT" || cleanedLine.starts(with: "NOTE") {
                if processingCueContent && !activeSubtitleText.isEmpty {
                    if let beginTime = activeStartTime, let finishTime = activeEndTime {
                        subtitleCues.append(SubtitleCue(startTime: beginTime, endTime: finishTime, text: activeSubtitleText))
                    }
                    processingCueContent = false
                    activeStartTime = nil
                    activeEndTime = nil
                    activeSubtitleText = ""
                }
                continue
            }
            if cleanedLine.contains("-->") {
                if processingCueContent && !activeSubtitleText.isEmpty {
                    if let beginTime = activeStartTime, let finishTime = activeEndTime {
                        subtitleCues.append(SubtitleCue(startTime: beginTime, endTime: finishTime, text: activeSubtitleText))
                    }
                }
                let timeComponents = cleanedLine.components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
                if timeComponents.count >= 2 {
                    activeStartTime = parseVTTTime(timeComponents[0])
                    activeEndTime = parseVTTTime(timeComponents[1])
                    activeSubtitleText = ""
                    processingCueContent = true
                }
            } else if processingCueContent {
                if !activeSubtitleText.isEmpty {
                    activeSubtitleText += "\n"
                }
                activeSubtitleText += cleanedLine
                let isFinalLine = lineIndex == contentLines.count - 1
                let followingLine = isFinalLine ? "" : contentLines[lineIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if isFinalLine || followingLine.isEmpty || followingLine.contains("-->") {
                    if let beginTime = activeStartTime, let finishTime = activeEndTime {
                        subtitleCues.append(SubtitleCue(startTime: beginTime, endTime: finishTime, text: activeSubtitleText))
                        activeStartTime = nil
                        activeEndTime = nil
                        activeSubtitleText = ""
                        processingCueContent = false
                    }
                }
            }
        }
        return subtitleCues
    }
    private func parseVTTTime(_ timeString: String) -> Double {
        // VTT format: optional-hours:minutes:seconds.milliseconds
        // or minutes:seconds.milliseconds
        let cleanTime = timeString.components(separatedBy: CharacterSet.whitespaces)[0]
        let timeSegments = cleanTime.components(separatedBy: ":")
        var hourValue: Double = 0
        var minuteValue: Double = 0
        var secondValue: Double = 0
        if timeSegments.count == 3 {
            hourValue = Double(timeSegments[0]) ?? 0
            minuteValue = Double(timeSegments[1]) ?? 0
            let secondsString = timeSegments[2]
            let secondComponents = secondsString.components(separatedBy: ".")
            secondValue = Double(secondComponents[0]) ?? 0
            if secondComponents.count > 1 {
                secondValue += Double("0." + secondComponents[1]) ?? 0
            }
        } else if timeSegments.count == 2 {
            minuteValue = Double(timeSegments[0]) ?? 0
            let secondsString = timeSegments[1]
            let secondComponents = secondsString.components(separatedBy: ".")
            secondValue = Double(secondComponents[0]) ?? 0
            if secondComponents.count > 1 {
                secondValue += Double("0." + secondComponents[1]) ?? 0
            }
        }
        return hourValue * 3600 + minuteValue * 60 + secondValue
    }
    // MARK: - SRT Parsing
    private func parseSRT(content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalizedContent.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
            // Index line is lines[0], Time line is lines[1] usually, but sometimes index is missing or merged.
            // Standard SRT:
            // 1
            // 00:00:20,000 --> 00:00:24,400
            // Text line 1
            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[timeLineIndex]
            let times = timeLine.components(separatedBy: "-->")
            guard times.count >= 2 else { continue }
            let startTime = parseSRTTimecode(times[0].trimmingCharacters(in: .whitespaces))
            let endTime = parseSRTTimecode(times[1].trimmingCharacters(in: .whitespaces))
            var textLines = [String]()
            if lines.count > timeLineIndex + 1 {
                textLines = Array(lines[(timeLineIndex + 1)...])
            }
            let text = textLines.joined(separator: "\n")
            cues.append(SubtitleCue(startTime: startTime, endTime: endTime, text: text))
        }
        return cues
    }
    private func parseSRTTimecode(_ timeString: String) -> Double {
        // SRT format: 00:00:20,000
        let parts = timeString.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }
        let secondsParts = parts[2].components(separatedBy: ",")
        guard secondsParts.count == 2,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(secondsParts[0]),
              let milliseconds = Double(secondsParts[1]) else {
            return 0
        }
        return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000
    }
}

extension String {
    var strippedHTML: String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}
