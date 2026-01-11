//
//  JSContext+Extensions.swift
//  Hiyoku
//
//  Created by 686udjie on 01/07/26.
//

import JavaScriptCore

extension JSContext {
    func setupConsoleLogging() {
        let consoleObject = JSValue(newObjectIn: self)

        let consoleLogFunction: @convention(block) (String) -> Void = { _ in
        }
        consoleObject?.setObject(consoleLogFunction, forKeyedSubscript: "log" as NSString)

        let consoleErrorFunction: @convention(block) (String) -> Void = { _ in
        }
        consoleObject?.setObject(consoleErrorFunction, forKeyedSubscript: "error" as NSString)

        self.setObject(consoleObject, forKeyedSubscript: "console" as NSString)

        let logFunction: @convention(block) (String) -> Void = { _ in
        }
        self.setObject(logFunction, forKeyedSubscript: "log" as NSString)
    }

    func setupNativeFetch() {
        let fetchNativeFunction: @convention(block) (String, [String: String]?, JSValue, JSValue) -> Void = { urlString, headers, resolve, reject in
            guard let url = URL(string: urlString) else {
                reject.call(withArguments: ["Invalid URL"])
                return
            }
            var request = URLRequest(url: url)
            if let headers = headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    reject.call(withArguments: [error.localizedDescription])
                    return
                }
                guard let data = data else {
                    reject.call(withArguments: ["No data"])
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    resolve.call(withArguments: [text])
                } else {
                    reject.call(withArguments: ["Unable to decode data"])
                }
            }
            task.resume()
        }
        self.setObject(fetchNativeFunction, forKeyedSubscript: "fetchNative" as NSString)

        let fetchDefinition = """
                        function fetch(url, headers) {
                            return new Promise(function(resolve, reject) {
                                fetchNative(url, headers, resolve, reject);
                            });
                        }
                        """
        self.evaluateScript(fetchDefinition)
    }

    private func processHeaders(_ headersAny: Any?) -> [String: String]? {
        var headers: [String: String]?

        if let headersAny = headersAny {
            if headersAny is NSNull {
                headers = nil
            } else if let headersDict = headersAny as? [String: Any] {
                var safeHeaders: [String: String] = [:]
                for (key, value) in headersDict {
                    let stringValue: String
                    if let str = value as? String {
                        stringValue = str
                    } else if let num = value as? NSNumber {
                        stringValue = num.stringValue
                    } else if value is NSNull {
                        continue
                    } else {
                        stringValue = String(describing: value)
                    }
                    safeHeaders[key] = stringValue
                }
                headers = safeHeaders.isEmpty ? nil : safeHeaders
            } else if let headersDict = headersAny as? [AnyHashable: Any] {
                var safeHeaders: [String: String] = [:]
                for (key, value) in headersDict {
                    let stringKey = String(describing: key)

                    let stringValue: String
                    if let str = value as? String {
                        stringValue = str
                    } else if let num = value as? NSNumber {
                        stringValue = num.stringValue
                    } else if value is NSNull {
                        continue
                    } else {
                        stringValue = String(describing: value)
                    }
                    safeHeaders[stringKey] = stringValue
                }
                headers = safeHeaders.isEmpty ? nil : safeHeaders
            } else {
                headers = nil
            }
        }
        return headers
    }

    private func getTextEncoding(from encodingString: String?) -> String.Encoding {
        guard let encodingString = encodingString?.lowercased() else {
            return .utf8
        }

        switch encodingString {
        case "utf-8", "utf8":
            return .utf8
        case "windows-1251", "cp1251":
            return .windowsCP1251
        case "windows-1252", "cp1252":
            return .windowsCP1252
        case "iso-8859-1", "latin1":
            return .isoLatin1
        case "ascii":
            return .ascii
        case "utf-16", "utf16":
            return .utf16
        default:
            return .utf8
        }
    }

    func setupFetchV2() {
        let fetchV2NativeFunction:
            @convention(block) (String, Any?, String?, String?, ObjCBool, String?, JSValue, JSValue) -> Void
            = { urlString, headersAny, method, body, _, encoding, resolve, _ in
            guard let url = URL(string: urlString) else {
                DispatchQueue.main.async {
                    resolve.call(withArguments: ["Invalid URL"])
                }
                return
            }

            let headers = self.processHeaders(headersAny)

            let httpMethod = method ?? "GET"
            var request = URLRequest(url: url)
            request.httpMethod = httpMethod

            let textEncoding = self.getTextEncoding(from: encoding)

            let bodyIsEmpty = body == nil || (body)?.isEmpty == true || body == "null" || body == "undefined"

            if httpMethod == "GET" && !bodyIsEmpty {
                DispatchQueue.main.async {
                    resolve.call(withArguments: ["GET request must not have a body"])
                }
                return
            }

            if httpMethod != "GET" && !bodyIsEmpty {
                if let bodyString = body {
                    request.httpBody = bodyString.data(using: .utf8)
                } else {
                    let bodyString = String(describing: body!)
                    request.httpBody = bodyString.data(using: .utf8)
                }
            }

            if let headers = headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            let session = URLSession.shared

            let task = session.downloadTask(with: request) { tempFileURL, response, error in
                defer { session.finishTasksAndInvalidate() }

                let callResolve: ([String: Any]) -> Void = { dict in
                    DispatchQueue.main.async {
                        if !resolve.isUndefined {
                            resolve.call(withArguments: [dict])
                        }
                    }
                }

                if let error = error {
                    callResolve(["error": error.localizedDescription])
                    return
                }

                guard let tempFileURL = tempFileURL else {
                    callResolve(["error": "No data"])
                    return
                }

                var safeHeaders: [String: String] = [:]
                if let httpResponse = response as? HTTPURLResponse {
                    for (key, value) in httpResponse.allHeaderFields {
                        if let keyString = key as? String {
                            let valueString: String
                            if let str = value as? String {
                                valueString = str
                            } else {
                                valueString = String(describing: value)
                            }
                            safeHeaders[keyString] = valueString
                        }
                    }
                }

                var responseDict: [String: Any] = [
                    "status": (response as? HTTPURLResponse)?.statusCode ?? 0,
                    "headers": safeHeaders,
                    "body": ""
                ]

                do {
                    let data = try Data(contentsOf: tempFileURL)

                    if data.count > 10_000_000 {
                        callResolve(["error": "Response exceeds maximum size"])
                        return
                    }

                    if let text = String(data: data, encoding: textEncoding) {
                        responseDict["body"] = text
                        callResolve(responseDict)
                    } else {
                        if let fallbackText = String(data: data, encoding: .utf8) {
                            responseDict["body"] = fallbackText
                            callResolve(responseDict)
                        } else {
                            callResolve(responseDict)
                        }
                    }

                } catch {
                    callResolve(["error": "Error reading downloaded file"])
                }
            }
            task.resume()
            }

        self.setObject(fetchV2NativeFunction, forKeyedSubscript: "fetchV2Native" as NSString)

        let fetchv2Definition = """
            function fetchv2(url, headers = {}, method = "GET", body = null, redirect = true, encoding) {

                var processedBody = null;
                if(method != "GET") {
                    processedBody = (body && (typeof body === 'object')) ? JSON.stringify(body) : (body || null)
                }

                var finalEncoding = encoding || "utf-8";

                // Ensure headers is an object and not null/undefined
                var processedHeaders = {};
                if (headers && typeof headers === 'object' && !Array.isArray(headers)) {
                    processedHeaders = headers;
                }

                return new Promise(function(resolve, reject) {
                    fetchV2Native(url, processedHeaders, method, processedBody, redirect, finalEncoding, function(rawText) {
                        const responseObj = {
                            headers: rawText.headers,
                            status: rawText.status,
                            _data: rawText.body,
                            text: function() {
                                return Promise.resolve(this._data);
                            },
                            json: function() {
                                try {
                                    return Promise.resolve(JSON.parse(this._data));
                                } catch (e) {
                                    return Promise.reject("JSON parse error: " + e.message);
                                }
                            }
                        };
                        resolve(responseObj);
                    }, reject);
                });
            }
            """
        self.evaluateScript(fetchv2Definition)
    }

    func setupBase64Functions() {
        let btoaFunction: @convention(block) (String) -> String? = { data in
            guard let data = data.data(using: .utf8) else {
                return nil
            }
            return data.base64EncodedString()
        }

        let atobFunction: @convention(block) (String) -> String? = { base64String in
            guard let data = Data(base64Encoded: base64String) else {
                return nil
            }

            return String(data: data, encoding: .utf8)
        }

        self.setObject(btoaFunction, forKeyedSubscript: "btoa" as NSString)
        self.setObject(atobFunction, forKeyedSubscript: "atob" as NSString)
    }

    func setupScrapingUtilities() {
        let scrapingUtils = """
        function getElementsByTag(html, tag) {
            const regex = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'gi');
            let result = [];
            let match;
            while ((match = regex.exec(html)) !== null) {
                result.push(match[1]);
            }
            return result;
        }
        function getAttribute(html, tag, attr) {
            const regex = new RegExp(`<${tag}[^>]*${attr}=[\"']?([^\"' >]+)[\"']?[^>]*>`, 'i');
            const match = regex.exec(html);
            return match ? match[1] : null;
        }
        function getInnerText(html) {
            return html.replace(/<[^>]+>/g, '').replace(/\\s+/g, ' ').trim();
        }
        function extractBetween(str, start, end) {
            const s = str.indexOf(start);
            if (s === -1) return '';
            const e = str.indexOf(end, s + start.length);
            if (e === -1) return '';
            return str.substring(s + start.length, e);
        }
        function stripHtml(html) {
            return html.replace(/<[^>]+>/g, '');
        }
        function normalizeWhitespace(str) {
            return str.replace(/\\s+/g, ' ').trim();
        }
        function urlEncode(str) {
            return encodeURIComponent(str);
        }
        function urlDecode(str) {
            try { return decodeURIComponent(str); } catch (e) { return str; }
        }
        function htmlEntityDecode(str) {
            return str.replace(/&([a-zA-Z]+);/g, function(_, entity) {
                const entities = { quot: '"', apos: "'", amp: '&', lt: '<', gt: '>' };
                return entities[entity] || _;
            });
        }
        function transformResponse(response, fn) {
            try { return fn(response); } catch (e) { return response; }
        }
        """
        self.evaluateScript(scrapingUtils)
    }

    func setupWeirdCode() {
        // Setup any weird code that might be needed
    }

    func setupNetworkFetch() {
        // Setup network fetch functionality
    }

    func setupNetworkFetchSimple() {
        // Setup simple network fetch
    }

    func setupJavaScriptEnvironment() {
        setupWeirdCode()
        setupConsoleLogging()
        setupNativeFetch()
        setupNetworkFetch()
        setupNetworkFetchSimple()
        setupFetchV2()
        setupBase64Functions()
        setupScrapingUtilities()
    }
}
