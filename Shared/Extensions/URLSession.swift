//
//  URLSession.swift
//  Aidoku
//
//  Created by Skitty on 12/24/21.
//

import Foundation

extension URLRequest {
    static func from(_ url: URL, headers: [String: String] = [:], method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        req.httpBody = body
        req.httpMethod = method
        return req
    }
}

extension URLSession {
    enum URLSessionError: Error {
        case noData
    }

    static let userAgents = [
        // Chrome
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",

        // FireFox
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.7; rv:136.0) Gecko/20100101 Firefox/136.0",
        "Mozilla/5.0 (X11; Linux x86_64; rv:136.0) Gecko/20100101 Firefox/136.0",
        "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:136.0) Gecko/20100101 Firefox/136.0",

        // Edge
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.3124.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.3124.0",

        // Safari
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15",

        // Mobile Chrome
        "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36",
        "Mozilla/5.0 (Linux; Android 15; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.0 Mobile Safari/537.36",
        "Mozilla/5.0 (Linux; Android 14; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36",

        // Mobile Safari
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (iPad; CPU OS 17_7_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1",

        // Mobile Firefox
        "Mozilla/5.0 (Mobile; rv:136.0) Gecko/136.0 Firefox/136.0",
        "Mozilla/5.0 (Android 15; Mobile; rv:136.0) Gecko/136.0 Firefox/136.0",

        // Mobile Edge
        "Mozilla/5.0 (Linux; Android 14; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Mobile Safari/537.36 EdgA/134.0.3124.0",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/18.0 EdgiOS/134.3124.77 Mobile/15E148 Safari/605.1.15"
    ]

    static var randomUserAgent: String = {
        userAgents.randomElement() ?? userAgents[0]
    }()

    func download(for request: URLRequest) async throws -> URL {
        if #available(iOS 15.0, *), #available(macOS 12.0, *) {
            let (data, _) = try await self.download(for: request, delegate: nil)
            return data
        } else {
            let data: URL = try await withCheckedThrowingContinuation({ continuation in
                self.downloadTask(with: request) { url, _, error in
                    if let url = url, let tmpDirectory = FileManager.default.temporaryDirectory {
                        try? FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
                        let destination = tmpDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.moveItem(at: url, to: destination)
                        continuation.resume(returning: destination)
                    } else {
                        continuation.resume(throwing: error ?? URLSessionError.noData)
                    }
                }.resume()
            })
            return data
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, *), #available(macOS 12.0, *) {
            return try await self.data(for: request, delegate: nil)
        } else {
            return try await withCheckedThrowingContinuation({ continuation in
                self.dataTask(with: request) { data, response, error in
                    if let data = data, let response = response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: error ?? URLSessionError.noData)
                    }
                }.resume()
            })
        }
    }

    func object<T: Decodable>(from url: URL) async throws -> T {
        try await self.object(from: URLRequest.from(url))
    }

    func object<T: Decodable>(from req: URLRequest) async throws -> T {
        let (data, _) = try await self.data(for: req)
        let response = try JSONDecoder().decode(T.self, from: data)
        return response
    }
}
