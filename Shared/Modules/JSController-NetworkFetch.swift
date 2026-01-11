//
//  JSController-NetworkFetch.swift
//  Hiyoku
//
//  Created by 686udjie on 01/10/26.
//

import WebKit
import JavaScriptCore

struct NetworkFetchOptions {
    let timeoutSeconds: Int
    let headers: [String: String]
    let cutoff: String?
    let returnHTML: Bool
    let returnCookies: Bool
    let clickSelectors: [String]
    let waitForSelectors: [String]
    let maxWaitTime: Int
    let htmlContent: String?

    init(
        timeoutSeconds: Int = 10,
        headers: [String: String] = [:],
        cutoff: String? = nil,
        returnHTML: Bool = false,
        returnCookies: Bool = true,
        clickSelectors: [String] = [],
        waitForSelectors: [String] = [],
        maxWaitTime: Int = 5,
        htmlContent: String? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.headers = headers
        self.cutoff = cutoff
        self.returnHTML = returnHTML
        self.returnCookies = returnCookies
        self.clickSelectors = clickSelectors
        self.waitForSelectors = waitForSelectors
        self.maxWaitTime = maxWaitTime
        self.htmlContent = htmlContent
    }
}

extension JSContext {
    func setupNetworkFetch() {
        let networkFetchNativeFunction: @convention(block) (
            String, JSValue?, JSValue, JSValue
        ) -> Void = { urlString, optionsValue, resolve, reject in
            DispatchQueue.main.async {
                var options = NetworkFetchOptions()

                if let optionsDict = optionsValue?.toDictionary() {
                    let timeoutSeconds = optionsDict["timeoutSeconds"] as? Int ?? 10
                    let headers = optionsDict["headers"] as? [String: String] ?? [:]
                    let cutoff = optionsDict["cutoff"] as? String
                    let returnHTML = optionsDict["returnHTML"] as? Bool ?? false
                    let returnCookies = optionsDict["returnCookies"] as? Bool ?? true
                    let clickSelectors = optionsDict["clickSelectors"] as? [String] ?? []
                    let waitForSelectors = optionsDict["waitForSelectors"] as? [String] ?? []
                    let maxWaitTime = optionsDict["maxWaitTime"] as? Int ?? 5
                    let htmlContent = optionsDict["htmlContent"] as? String

                    options = NetworkFetchOptions(
                        timeoutSeconds: timeoutSeconds,
                        headers: headers,
                        cutoff: cutoff,
                        returnHTML: returnHTML,
                        returnCookies: returnCookies,
                        clickSelectors: clickSelectors,
                        waitForSelectors: waitForSelectors,
                        maxWaitTime: maxWaitTime,
                        htmlContent: htmlContent
                    )
                }

                NetworkFetchManager.shared.performNetworkFetch(
                    urlString: urlString,
                    options: options,
                    resolve: resolve,
                    reject: reject
                )
            }
        }

        self.setObject(networkFetchNativeFunction, forKeyedSubscript: "networkFetchNative" as NSString)

        let networkFetchDefinition = """
            function networkFetch(url, options = {}) {
                if (typeof options === 'number') {
                    const timeoutSeconds = options;
                    const headers = arguments[2] || {};
                    const cutoff = arguments[3] || null;
                    options = { timeoutSeconds, headers, cutoff };
                }

                const finalOptions = {
                    timeoutSeconds: options.timeoutSeconds || 10,
                    headers: options.headers || {},
                    cutoff: options.cutoff || null,
                    returnHTML: options.returnHTML || false,
                    returnCookies: options.returnCookies !== undefined ? options.returnCookies : true,
                    clickSelectors: options.clickSelectors || [],
                    waitForSelectors: options.waitForSelectors || [],
                    maxWaitTime: options.maxWaitTime || 5,
                    htmlContent: options.htmlContent || null
                };

                return new Promise(function(resolve, reject) {
                    networkFetchNative(url, finalOptions, function(result) {
                        resolve({
                            url: result.originalUrl,
                            requests: result.requests,
                            html: result.html || null,
                            cookies: result.cookies || null,
                            success: result.success,
                            error: result.error || null,
                            totalRequests: result.requests.length,
                            cutoffTriggered: result.cutoffTriggered || false,
                            cutoffUrl: result.cutoffUrl || null,
                            htmlCaptured: result.htmlCaptured || false,
                            cookiesCaptured: result.cookiesCaptured || false,
                            elementsClicked: result.elementsClicked || [],
                            waitResults: result.waitResults || {}
                        });
                    }, reject);
                });
            }

            function networkFetchWithHTML(url, timeoutSeconds = 10) {
                return networkFetch(url, {
                    timeoutSeconds: timeoutSeconds,
                    returnHTML: true,
                    returnCookies: true
                });
            }

            function networkFetchWithCutoff(url, cutoff, timeoutSeconds = 10) {
                return networkFetch(url, {
                    timeoutSeconds: timeoutSeconds,
                    cutoff: cutoff,
                    returnCookies: true
                });
            }

            function networkFetchWithClicks(url, clickSelectors, options = {}) {
                return networkFetch(url, {
                    timeoutSeconds: options.timeoutSeconds || 10,
                    headers: options.headers || {},
                    cutoff: options.cutoff || null,
                    returnHTML: options.returnHTML || false,
                    returnCookies: options.returnCookies !== undefined ? options.returnCookies : true,
                    clickSelectors: Array.isArray(clickSelectors) ? clickSelectors : [clickSelectors],
                    waitForSelectors: options.waitForSelectors || [],
                    maxWaitTime: options.maxWaitTime || 5
                });
            }

            function networkFetchWithWaitAndClick(url, waitForSelectors, clickSelectors, options = {}) {
                return networkFetch(url, {
                    timeoutSeconds: options.timeoutSeconds || 10,
                    headers: options.headers || {},
                    cutoff: options.cutoff || null,
                    returnHTML: options.returnHTML || false,
                    returnCookies: options.returnCookies !== undefined ? options.returnCookies : true,
                    clickSelectors: Array.isArray(clickSelectors) ? clickSelectors : [clickSelectors],
                    waitForSelectors: Array.isArray(waitForSelectors) ? waitForSelectors : [waitForSelectors],
                    maxWaitTime: options.maxWaitTime || 5
                });
            }

            function networkFetchFromHTML(htmlContent, options = {}) {
                return networkFetch('', {
                    timeoutSeconds: options.timeoutSeconds || 10,
                    headers: options.headers || {},
                    cutoff: options.cutoff || null,
                    returnHTML: options.returnHTML || false,
                    returnCookies: options.returnCookies !== undefined ? options.returnCookies : true,
                    clickSelectors: options.clickSelectors || [],
                    waitForSelectors: options.waitForSelectors || [],
                    maxWaitTime: options.maxWaitTime || 5,
                    htmlContent: htmlContent
                });
            }
            """

        self.evaluateScript(networkFetchDefinition)
    }

    func setupNetworkFetchSimple() {
        let networkFetchSimpleNativeFunction: @convention(block) (
            String, JSValue?, JSValue, JSValue
        ) -> Void = { urlString, optionsValue, resolve, reject in
            DispatchQueue.main.async {
                var timeoutSeconds = 5
                var htmlContent: String?
                var headers: [String: String] = [:]
                if let optionsDict = optionsValue?.toDictionary() {
                    timeoutSeconds = optionsDict["timeoutSeconds"] as? Int ?? 5
                    htmlContent = optionsDict["htmlContent"] as? String
                    headers = optionsDict["headers"] as? [String: String] ?? [:]
                }
                NetworkFetchSimpleManager.shared.performNetworkFetch(
                    urlString: urlString,
                    timeoutSeconds: timeoutSeconds,
                    htmlContent: htmlContent,
                    headers: headers,
                    resolve: resolve,
                    reject: reject
                )
            }
        }
        self.setObject(networkFetchSimpleNativeFunction, forKeyedSubscript: "networkFetchSimpleNative" as NSString)
        let networkFetchSimpleDefinition = """
            function networkFetchSimple(url, options = {}) {
                if (typeof options === 'number') {
                    const timeoutSeconds = options;
                    options = { timeoutSeconds };
                }
                const finalOptions = {
                    timeoutSeconds: options.timeoutSeconds || 5,
                    htmlContent: options.htmlContent || null,
                    headers: options.headers || {}
                };
                return new Promise(function(resolve, reject) {
                    networkFetchSimpleNative(url, finalOptions, function(result) {
                        resolve({
                            url: result.originalUrl,
                            requests: result.requests,
                            success: result.success,
                            error: result.error || null,
                            totalRequests: result.requests.length
                        });
                    }, reject);
                });
            }
            function networkFetchSimpleFromHTML(htmlContent, options = {}) {
                return networkFetchSimple('', {
                    timeoutSeconds: options.timeoutSeconds || 5,
                    htmlContent: htmlContent,
                    headers: options.headers || {}
                });
            }
            """
        self.evaluateScript(networkFetchSimpleDefinition)
    }
}

class NetworkFetchSimpleManager: NSObject, ObservableObject {
    static let shared = NetworkFetchSimpleManager()

    private var activeMonitors: [String: NetworkFetchSimpleMonitor] = [:]

    private override init() {
        super.init()
    }

    func performNetworkFetch(
        urlString: String,
        timeoutSeconds: Int,
        htmlContent: String? = nil,
        headers: [String: String] = [:],
        resolve: JSValue,
        reject: JSValue
    ) {
        let monitorId = UUID().uuidString
        let monitor = NetworkFetchSimpleMonitor()
        activeMonitors[monitorId] = monitor
        monitor.startMonitoring(
            urlString: urlString,
            timeoutSeconds: timeoutSeconds,
            htmlContent: htmlContent,
            headers: headers
        ) { [weak self] result in
            self?.activeMonitors.removeValue(forKey: monitorId)
            DispatchQueue.main.async {
                if !resolve.isUndefined {
                    resolve.call(withArguments: [result])
                }
            }
        }
    }
}

class NetworkFetchSimpleMonitor: NSObject, ObservableObject {
    private var webView: WKWebView?
    private var completionHandler: (([String: Any]) -> Void)?
    private var timer: Timer?

    @Published private(set) var networkRequests: [String] = []

    private var originalUrlString: String = ""

    func startMonitoring(
        urlString: String,
        timeoutSeconds: Int,
        htmlContent: String? = nil,
        headers: [String: String] = [:],
        completion: @escaping ([String: Any]) -> Void
    ) {
        originalUrlString = urlString
        completionHandler = completion
        networkRequests.removeAll()
        if let htmlContent = htmlContent, !htmlContent.isEmpty {
            setupWebView()
            loadHTMLContent(htmlContent)
        } else {
            guard let url = URL(string: urlString) else {
                completion([
                    "originalUrl": urlString,
                    "requests": [],
                    "success": false,
                    "error": "Invalid URL format"
                ])
                return
            }
            setupWebView()
            loadURL(url: url, headers: headers)
        }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutSeconds), repeats: false) { [weak self] _ in
            self?.stopMonitoring()
        }
    }

    private func loadHTMLContent(_ htmlContent: String) {
        guard let webView = webView else { return }

        addRequest("data:text/html;charset=utf-8,<html_content>")

        webView.loadHTMLString(htmlContent, baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.simulateUserInteraction()
        }
    }

    private func setupWebView() {
        let config = createWebViewConfiguration()
        setupWebView(with: config)
    }

    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userScript = WKUserScript(
            source: createNetworkMonitoringJS(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "networkLogger")

        return config
    }

    private func setupWebView(with config: WKWebViewConfiguration) {
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            configuration: config
        )
        webView?.navigationDelegate = self
        webView?.customUserAgent = URLSession.randomUserAgent
    }

    private func createNetworkMonitoringJS() -> String {
        """
        (function() {
            \(createNavigatorSpoofingJS())
            \(createNetworkHooksJS())
            \(createPropertyHooksJS())
            \(createPlayerHooksJS())
            \(createNuclearScanJS())
        })();
        """
    }

    private func createNavigatorSpoofingJS() -> String {
        """
            Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
            Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
            delete window.navigator.__proto__.webdriver;

            window.chrome = { runtime: {} };
            Object.defineProperty(navigator, 'permissions', { get: () => undefined });
        """
    }

    private func createNetworkHooksJS() -> String {
        """
            const originalFetch = window.fetch;
            const originalXHROpen = XMLHttpRequest.prototype.open;
            const originalXHRSend = XMLHttpRequest.prototype.send;

            window.fetch = function() {
                const url = arguments[0];
                const options = arguments[1] || {};

                try {
                    const fullUrl = new URL(url, window.location.href).href;
                    window.webkit.messageHandlers.networkLogger.postMessage({
                        type: 'fetch',
                        url: fullUrl
                    });
                } catch(e) {
                    window.webkit.messageHandlers.networkLogger.postMessage({
                        type: 'fetch',
                        url: url.toString()
                    });
                }
                return originalFetch.apply(this, arguments);
            };

            XMLHttpRequest.prototype.open = function() {
                const method = arguments[0];
                const url = arguments[1];

                try {
                    this._url = new URL(url, window.location.href).href;
                } catch(e) {
                    this._url = url;
                }

                window.webkit.messageHandlers.networkLogger.postMessage({
                    type: 'xhr-open',
                    url: this._url
                });

                const self = this;
                const originalOnReadyStateChange = this.onreadystatechange;

                this.onreadystatechange = function() {
                    if (this.readyState === 4) {
                        if (this.responseURL) {
                            window.webkit.messageHandlers.networkLogger.postMessage({
                                type: 'xhr-response',
                                url: this.responseURL
                            });
                        }

                        try {
                            const responseText = this.responseText;
                            if (responseText) {
                                const urlRegex = /(https?:\\/\\/[^\\s"'<>]+\\.(m3u8|ts|mp4|webm|mkv))/gi;
                                const matches = responseText.match(urlRegex);
                                if (matches) {
                                    matches.forEach(function(match) {
                                        window.webkit.messageHandlers.networkLogger.postMessage({
                                            type: 'response-content',
                                            url: match
                                        });
                                    });
                                }
                            }
                        } catch(e) {
                        }
                    }

                    if (originalOnReadyStateChange) {
                        originalOnReadyStateChange.apply(this, arguments);
                    }
                };

                return originalXHROpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function() {
                if (this._url) {
                    window.webkit.messageHandlers.networkLogger.postMessage({
                        type: 'xhr-send',
                        url: this._url
                    });
                }
                return originalXHRSend.apply(this, arguments);
            };

            const originalWebSocket = window.WebSocket;
            window.WebSocket = function(url, protocols) {
                window.webkit.messageHandlers.networkLogger.postMessage({
                    type: 'websocket',
                    url: url
                });
                return new originalWebSocket(url, protocols);
            };
        """
    }

    private func createPropertyHooksJS() -> String {
        """
            const hookUrlProperties = function(obj, properties) {
                properties.forEach(function(prop) {
                    if (obj && obj.prototype) {
                        const descriptor = Object.getOwnPropertyDescriptor(obj.prototype, prop) || {};
                        const originalSetter = descriptor.set;

                        if (originalSetter) {
                            Object.defineProperty(obj.prototype, prop, {
                                set: function(value) {
                                    if (typeof value === 'string' && (value.includes('http') || value.includes('.m3u8') || value.includes('.ts'))) {
                                        window.webkit.messageHandlers.networkLogger.postMessage({
                                            type: 'property-set',
                                            url: value
                                        });
                                    }
                                    return originalSetter.call(this, value);
                                },
                                get: descriptor.get,
                                configurable: true
                            });
                        }
                    }
                });
            };

            hookUrlProperties(HTMLVideoElement, ['src']);
            hookUrlProperties(HTMLSourceElement, ['src']);
            hookUrlProperties(HTMLScriptElement, ['src']);
            hookUrlProperties(HTMLImageElement, ['src']);
        """
    }

    private func createPlayerHooksJS() -> String {
        """
            let jwHookAttempts = 0;
            const aggressiveJWHook = function() {
                jwHookAttempts++;

                if (window.jwplayer) {
                    const originalJWPlayer = window.jwplayer;
                    window.jwplayer = function(id) {
                        const player = originalJWPlayer.apply(this, arguments);

                        if (player && player.setup) {
                            const originalSetup = player.setup;
                            player.setup = function(config) {
                                const extractUrls = function(obj, path = '') {
                                    if (!obj) return;

                                    if (typeof obj === 'string' && (obj.includes('http') || obj.includes('.m3u8') || obj.includes('.ts'))) {
                                        window.webkit.messageHandlers.networkLogger.postMessage({
                                            type: 'jwplayer-config',
                                            url: obj
                                        });
                                    } else if (typeof obj === 'object' && obj !== null) {
                                        Object.keys(obj).forEach(function(key) {
                                            extractUrls(obj[key], path + '.' + key);
                                        });
                                    }
                                };

                                extractUrls(config);
                                return originalSetup.call(this, config);
                            };
                        }

                        return player;
                    };

                    Object.keys(originalJWPlayer).forEach(function(key) {
                        window.jwplayer[key] = originalJWPlayer[key];
                    });
                }

                if (jwHookAttempts < 20) {
                    setTimeout(aggressiveJWHook, 200);
                }
            };

            aggressiveJWHook();
        """
    }

    private func createNuclearScanJS() -> String {
        """
            const nuclearScan = function() {
                Object.keys(window).forEach(function(key) {
                    try {
                        const value = window[key];
                        if (typeof value === 'string' &&
                    (value.includes('.m3u8') || value.includes('.ts') ||
                    (value.includes('http') && value.includes('.')))) {
                            window.webkit.messageHandlers.networkLogger.postMessage({
                                type: 'global-variable',
                                url: value
                            });
                        }
                    } catch(e) {
                    }
                });

                document.querySelectorAll('script').forEach(function(script) {
                    if (script.textContent) {
                        const urlRegex = /(https?:\\/\\/[^\\s"'<>]+\\.(m3u8|ts|mp4))/gi;
                        const matches = script.textContent.match(urlRegex);
                        if (matches) {
                            matches.forEach(function(match) {
                                window.webkit.messageHandlers.networkLogger.postMessage({
                                    type: 'script-content',
                                    url: match
                                });
                            });
                        }
                    }
                });

                const clickableSelectors = [
                    'button', '.play', '.play-button', '[data-play]', '.video-play',
                    '.jwplayer', '.player', '[id*="player"]', '[class*="play"]',
                    'div[onclick]', 'span[onclick]', 'a[onclick]'
                ];

                clickableSelectors.forEach(function(selector) {
                    document.querySelectorAll(selector).forEach(function(el) {
                        try {
                            el.click();
                        } catch(e) {
                        }
                    });
                });
            };

            setTimeout(nuclearScan, 500);
            setTimeout(nuclearScan, 1500);
            setTimeout(nuclearScan, 3000);
        """
    }

    private func loadURL(url: URL, headers: [String: String] = [:]) {
        guard let webView = webView else { return }
        addRequest(url.absoluteString)
        var request = URLRequest(url: url)
        request.setValue(URLSession.randomUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("upgrade-insecure-requests", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if request.value(forHTTPHeaderField: "Referer") == nil {
            let randomReferers = [
                "https://www.google.com/",
                "https://www.youtube.com/",
                "https://twitter.com/",
                "https://www.reddit.com/",
                "https://www.facebook.com/"
            ]
            let defaultReferer = randomReferers.randomElement() ?? "https://www.google.com/"
            request.setValue(defaultReferer, forHTTPHeaderField: "Referer")
        }
        webView.load(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.simulateUserInteraction()
        }
    }

    private func simulateUserInteraction() {
        guard let webView = webView else { return }

        let jsInteraction = """
        setTimeout(function() {
            const playButtons = document.querySelectorAll('button, div, span, a').filter(function(el) {
                const text = el.textContent || el.innerText || '';
                const classes = el.className || '';
                return text.toLowerCase().includes('play') ||
                       classes.toLowerCase().includes('play') ||
                       el.getAttribute('aria-label')?.toLowerCase().includes('play');
            });
            playButtons.forEach(function(btn, index) {
                setTimeout(function() {
                    btn.click();
                }, index * 200);
            });
            window.scrollTo(0, document.body.scrollHeight / 2);
            setTimeout(function() {
                window.scrollTo(0, 0);
            }, 500);
            document.querySelectorAll('video').forEach(function(video) {
                if (video.play && typeof video.play === 'function') {
                    video.play().catch(function(e) {
                    });
                }
            });
            if (window.jwplayer) {
                try {
                    const players = window.jwplayer().getInstances?.() || [];
                    players.forEach(function(player) {
                        if (player.play) {
                            player.play();
                        }
                    });
                } catch(e) {}
            }
            if (window.videojs) {
                try {
                    window.videojs.getAllPlayers?.().forEach(function(player) {
                        if (player.play) {
                            player.play();
                        }
                    });
                } catch(e) {}
            }
        }, 1000);
        """
        webView.evaluateJavaScript(jsInteraction, completionHandler: nil)
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "networkLogger")

        let originalUrl = networkRequests.first == "data:text/html;charset=utf-8,<html_content>" ?
            "data:text/html;charset=utf-8,<html_content>" :
            (webView?.url?.absoluteString ?? originalUrlString)

        let result: [String: Any] = [
            "originalUrl": originalUrl,
            "requests": networkRequests,
            "success": true
        ]

        webView = nil

        completionHandler?(result)
        completionHandler = nil
    }

    private func addRequest(_ urlString: String) {
        DispatchQueue.main.async {
            if !self.networkRequests.contains(urlString) {
                self.networkRequests.append(urlString)
            }
        }
    }
}

extension NetworkFetchSimpleMonitor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            addRequest(url.absoluteString)
        }
        decisionHandler(.allow)
    }
}

extension NetworkFetchSimpleMonitor: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "networkLogger" {
            if let messageBody = message.body as? [String: Any],
               let url = messageBody["url"] as? String {
                addRequest(url)
            }
        }
    }
}

class NetworkFetchManager: NSObject, ObservableObject {
    static let shared = NetworkFetchManager()

    private var activeMonitors: [String: NetworkFetchMonitor] = [:]

    private override init() {
        super.init()
    }

    func performNetworkFetch(urlString: String, options: NetworkFetchOptions, resolve: JSValue, reject: JSValue) {
        let monitorId = UUID().uuidString
        let monitor = NetworkFetchMonitor()
        activeMonitors[monitorId] = monitor

        monitor.startMonitoring(
            urlString: urlString,
            options: options
        ) { [weak self] result in
            self?.activeMonitors.removeValue(forKey: monitorId)

            DispatchQueue.main.async {
                if !resolve.isUndefined {
                    resolve.call(withArguments: [result])
                }
            }
        }
    }
}

class NetworkFetchMonitor: NSObject, ObservableObject {
    private var webView: WKWebView?
    private var completionHandler: (([String: Any]) -> Void)?
    private var timer: Timer?
    private var options: NetworkFetchOptions?
    private var elementsClicked: [String] = []
    private var waitResults: [String: Bool] = [:]
    private var cookies: [String: String] = [:]

    @Published private(set) var networkRequests: [String] = []
    @Published private(set) var cutoffTriggered = false
    @Published private(set) var cutoffUrl: String?
    @Published private(set) var htmlContent: String?
    @Published private(set) var htmlCaptured = false
    @Published private(set) var cookiesCaptured = false

    func startMonitoring(urlString: String, options: NetworkFetchOptions, completion: @escaping ([String: Any]) -> Void) {
        self.options = options
        completionHandler = completion
        networkRequests.removeAll()
        cutoffTriggered = false
        cutoffUrl = nil
        htmlContent = nil
        htmlCaptured = false
        cookiesCaptured = false
        elementsClicked.removeAll()
        waitResults.removeAll()
        cookies.removeAll()

        if let htmlContent = options.htmlContent, !htmlContent.isEmpty {
            setupWebView()
            loadHTMLContent(htmlContent)
        } else {
            guard let url = URL(string: urlString) else {
                completion([
                    "originalUrl": urlString,
                    "requests": [],
                    "html": NSNull(),
                    "cookies": NSNull(),
                    "success": false,
                    "error": "Invalid URL format",
                    "htmlCaptured": false,
                    "cookiesCaptured": false,
                    "elementsClicked": [],
                    "waitResults": [:]
                ])
                return
            }

            setupWebView()
            loadURL(url: url, headers: options.headers)
        }

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(options.timeoutSeconds), repeats: false) { [weak self] _ in
            if options.returnHTML || options.returnCookies {
                self?.captureDataThenComplete()
            } else {
                self?.stopMonitoring(reason: "timeout")
            }
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let jsCode = """
        (function() {
            Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
            Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
            delete window.navigator.__proto__.webdriver;

            window.chrome = { runtime: {} };
            Object.defineProperty(navigator, 'permissions', { get: () => undefined });

            const originalFetch = window.fetch;
            const originalXHROpen = XMLHttpRequest.prototype.open;
            const originalXHRSend = XMLHttpRequest.prototype.send;

            window.fetch = function() {
                const url = arguments[0];
                const options = arguments[1] || {};

                try {
                    const fullUrl = new URL(url, window.location.href).href;
                    window.webkit.messageHandlers.networkLogger.postMessage({
                        type: 'fetch',
                        url: fullUrl
                    });
                } catch(e) {
                    window.webkit.messageHandlers.networkLogger.postMessage({
                        type: 'fetch',
                        url: url.toString()
                    });
                }
                return originalFetch.apply(this, arguments);
            };

            XMLHttpRequest.prototype.open = function() {
                const method = arguments[0];
                const url = arguments[1];

                try {
                    this._url = new URL(url, window.location.href).href;
                } catch(e) {
                    this._url = url;
                }

                window.webkit.messageHandlers.networkLogger.postMessage({
                    type: 'xhr-open',
                    url: this._url
                });

                const self = this;
                const originalOnReadyStateChange = this.onreadystatechange;

                this.onreadystatechange = function() {
                    if (this.readyState === 4) {
                        if (this.responseURL) {
                            window.webkit.messageHandlers.networkLogger.postMessage({
                                type: 'xhr-response',
                                url: this.responseURL
                            });
                        }
                    }

                    if (originalOnReadyStateChange) {
                        originalOnReadyStateChange.apply(this, arguments);
                    }
                };

                return originalXHROpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function() {
                if (this._url) {
                    window.webkit.messageHandlers.networkLogger.postMessage({
                        type: 'xhr-send',
                        url: this._url
                    });
                }
                return originalXHRSend.apply(this, arguments);
            };
        })();
        """

        let userScript = WKUserScript(source: jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "networkLogger")

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), configuration: config)
        webView?.navigationDelegate = self

        webView?.customUserAgent = URLSession.randomUserAgent
    }

    private func loadURL(url: URL, headers: [String: String] = [:]) {
        guard let webView = webView else { return }
        addRequest(url.absoluteString)
        var request = URLRequest(url: url)
        request.setValue(URLSession.randomUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("upgrade-insecure-requests", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if request.value(forHTTPHeaderField: "Referer") == nil {
            let randomReferers = [
                "https://www.google.com/",
                "https://www.youtube.com/",
                "https://twitter.com/",
                "https://www.reddit.com/",
                "https://www.facebook.com/"
            ]
            let defaultReferer = randomReferers.randomElement() ?? "https://www.google.com/"
            request.setValue(defaultReferer, forHTTPHeaderField: "Referer")
        }
        webView.load(request)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.simulateUserInteraction()
        }
    }

    private func loadHTMLContent(_ htmlContent: String) {
        guard let webView = webView else { return }

        addRequest("data:text/html;charset=utf-8,<html_content>")

        webView.loadHTMLString(htmlContent, baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.simulateUserInteraction()
        }
    }

    private func simulateUserInteraction() {
        guard let webView = webView else { return }

        let jsInteraction = """
        setTimeout(function() {
            window.scrollTo(0, document.body.scrollHeight / 2);
            setTimeout(function() {
                window.scrollTo(0, 0);
            }, 500);
        }, 1000);
        """
        webView.evaluateJavaScript(jsInteraction, completionHandler: nil)
    }

    private func captureDataThenComplete() {
        guard let webView = webView else { return }

        var capturedHTML: String?
        var capturedCookies: [String: String] = [:]

        // Capture HTML
        if options?.returnHTML == true {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
                if let html = result as? String {
                    capturedHTML = html
                }
                self.completeWithCapturedData(html: capturedHTML, cookies: capturedCookies)
            }
        }

        // Capture cookies
        if options?.returnCookies == true {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    capturedCookies[cookie.name] = cookie.value
                }
                if self.options?.returnHTML != true {
                    self.completeWithCapturedData(html: nil, cookies: capturedCookies)
                }
            }
        }
    }

    private func completeWithCapturedData(html: String?, cookies: [String: String]?) {
        let originalUrl = webView?.url?.absoluteString ?? ""

        let result: [String: Any] = [
            "originalUrl": originalUrl,
            "requests": networkRequests,
            "html": html ?? NSNull(),
            "cookies": cookies ?? NSNull(),
            "success": true,
            "htmlCaptured": html != nil,
            "cookiesCaptured": cookies != nil,
            "elementsClicked": elementsClicked,
            "waitResults": waitResults,
            "cutoffTriggered": cutoffTriggered,
            "cutoffUrl": cutoffUrl ?? NSNull()
        ]

        stopMonitoring(reason: "data_captured", result: result)
    }

    private func stopMonitoring(reason: String = "timeout", result: [String: Any]? = nil) {
        timer?.invalidate()
        timer = nil

        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "networkLogger")

        let finalResult = result ?? [
            "originalUrl": webView?.url?.absoluteString ?? "",
            "requests": networkRequests,
            "html": NSNull(),
            "cookies": NSNull(),
            "success": false,
            "error": reason,
            "htmlCaptured": false,
            "cookiesCaptured": false,
            "elementsClicked": [],
            "waitResults": [:],
            "cutoffTriggered": cutoffTriggered,
            "cutoffUrl": cutoffUrl ?? NSNull()
        ]

        webView = nil

        completionHandler?(finalResult)
        completionHandler = nil
    }

    private func addRequest(_ urlString: String) {
        DispatchQueue.main.async {
            if !self.networkRequests.contains(urlString) {
                self.networkRequests.append(urlString)
            }
        }
    }
}

extension NetworkFetchMonitor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            addRequest(url.absoluteString)

            // Check for cutoff
            if let cutoff = options?.cutoff, !cutoff.isEmpty {
                if url.absoluteString.contains(cutoff) {
                    cutoffTriggered = true
                    cutoffUrl = url.absoluteString
                    decisionHandler(.cancel)
                    stopMonitoring(reason: "cutoff_triggered")
                    return
                }
            }
        }
        decisionHandler(.allow)
    }
}

extension NetworkFetchMonitor: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "networkLogger" {
            if let messageBody = message.body as? [String: Any],
               let url = messageBody["url"] as? String {
                addRequest(url)
            }
        }
    }
}
