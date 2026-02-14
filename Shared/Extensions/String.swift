//
//  String.swift
//  Aidoku
//
//  Created by Skitty on 5/25/22.
//

import Foundation

extension String {
    func take(first: Int) -> String {
        first < count ? String(self[self.startIndex..<self.index(self.startIndex, offsetBy: first)]) : self
    }

//    func take(last: Int) -> String {
//        last < count ? String(self[self.index(self.endIndex, offsetBy: -last)..<self.endIndex]) : self
//    }
//
//    func drop(first: Int) -> String {
//        first < count ? String(self[self.index(self.startIndex, offsetBy: first)..<self.endIndex]) : ""
//    }
//
//    func drop(last: Int) -> String {
//        last < count ? String(self[self.startIndex..<self.index(self.endIndex, offsetBy: -last)]) : ""
//    }

    func date(format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.date(from: self)
    }

    func fuzzyMatch(_ pattern: String) -> Bool? {
        if pattern.isEmpty { return false }
        var rem = pattern[...]
        for char in self where char == rem[rem.startIndex] {
            rem.removeFirst()
            if rem.isEmpty { return true }
        }
        return false
    }
}

extension String {
    func lastPathComponent() -> String {
        let s = self.last == "/" ? String(self.dropLast()) : self
        return if let idx = s.lastIndex(of: "/") {
            String(s[index(idx, offsetBy: 1)...])
        } else {
            self
        }
    }

    func removingExtension() -> String {
        if let idx = lastIndex(of: ".") {
            String(self[..<idx])
        } else {
            self
        }
    }

    func pathExtension() -> String {
        if let idx = lastIndex(of: ".") {
            String(self[index(idx, offsetBy: 1)...])
        } else {
            ""
        }
    }
}

extension String {
    var normalized: String {
        precomposedStringWithCanonicalMapping
    }

    func percentEncoded() -> String {
        normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }

    func normalizedModuleHref() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let httpRange = trimmed.range(of: "http") {
            if httpRange.lowerBound != trimmed.startIndex {
                let prevIndex = trimmed.index(before: httpRange.lowerBound)
                if trimmed[prevIndex] == ":" {
                    return trimmed
                }
            }
            return String(trimmed[httpRange.lowerBound...])
        } else if let colonRange = trimmed.range(of: ":", options: .caseInsensitive) {
            let beforeColon = String(trimmed[..<colonRange.lowerBound])
            if !beforeColon.contains(" ") && !beforeColon.contains("/") {
                return String(trimmed[colonRange.lowerBound...])
            }
        }
        return trimmed
    }

    func absoluteUrl(withBaseUrl baseUrl: String) -> String {
        let normalizedHref = normalizedModuleHref()
        guard !normalizedHref.isEmpty else { return normalizedHref }
        if normalizedHref.starts(with: "http") {
            return normalizedHref
        }
        let base = baseUrl.trimmingCharacters(in: .init(charactersIn: "/"))
        let relative = normalizedHref.trimmingCharacters(in: .init(charactersIn: "/"))
        return "\(base)/\(relative)"
    }
}
