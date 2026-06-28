import AppKit
import WebKit

/// Drives the interactive SAML login in a native WKWebView window and harvests
/// the VPN cookies from the response headers (and, as a fallback,
/// from XML comments in the page body) — the same data `gp-saml-gui` collects.
@MainActor
final class SAMLLoginController: NSObject, WKNavigationDelegate, NSWindowDelegate {

    private let ignoreCert: Bool
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<SAMLResult, Error>?
    private var defaultServer = ""
    private var finished = false

    private var found: [String: String] = [:]
    private var foundServer: String?

    init(ignoreCert: Bool) {
        self.ignoreCert = ignoreCert
    }

    func present(auth: PreloginAuth, defaultServer: String) async throws -> SAMLResult {
        self.defaultServer = defaultServer
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.setupWindow()
            switch auth {
            case .post(let html, let base):
                self.webView?.loadHTMLString(html, baseURL: base)
            case .redirect(let url):
                self.webView?.load(URLRequest(url: url))
            }
        }
    }

    // MARK: - Window

    private func setupWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 620), configuration: config)
        webView.navigationDelegate = self
        // The gateway expects this exact User-Agent for the SAML protocol.
        webView.customUserAgent = "PAN GlobalProtect"
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VPN Login"
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(with result: Result<SAMLResult, Error>) {
        guard !finished else { return }
        finished = true

        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            captureHeaders(http)
        }
        decisionHandler(.allow)
        checkDone()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let self else { return }
            if let html = result as? String {
                self.captureComments(html)
                self.checkDone()
            }
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if ignoreCert, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        finish(with: .failure(CancellationError()))
    }

    // MARK: - Capture

    private func captureHeaders(_ http: HTTPURLResponse) {
        if let host = http.url?.host {
            foundServer = host
        }
        for (rawKey, rawValue) in http.allHeaderFields {
            guard let key = (rawKey as? String)?.lowercased(),
                  let value = rawValue as? String else { continue }
            if isInterestingTag(key) {
                found[key] = value
            }
        }
    }

    private func captureComments(_ html: String) {
        let commentPattern = try! NSRegularExpression(pattern: "<!--(.*?)-->", options: [.dotMatchesLineSeparators])
        let tagPattern = try! NSRegularExpression(pattern: "<([a-zA-Z0-9-]+)>([^<]*)</\\1>")
        let ns = html as NSString

        for match in commentPattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let comment = ns.substring(with: match.range(at: 1))
            let cns = comment as NSString
            for tagMatch in tagPattern.matches(in: comment, range: NSRange(location: 0, length: cns.length)) {
                let tag = cns.substring(with: tagMatch.range(at: 1)).lowercased()
                let value = cns.substring(with: tagMatch.range(at: 2))
                if isInterestingTag(tag) {
                    found[tag] = value
                }
            }
        }
    }

    private func isInterestingTag(_ tag: String) -> Bool {
        tag.hasPrefix("saml-") || tag == "prelogin-cookie" || tag == "portal-userauthcookie"
    }

    private func checkDone() {
        guard !finished, let username = found["saml-username"] else { return }

        let cookie: String
        let usergroup: String
        if let value = found["prelogin-cookie"] {
            cookie = value
            usergroup = "gateway:prelogin-cookie"
        } else if let value = found["portal-userauthcookie"] {
            cookie = value
            usergroup = "portal:portal-userauthcookie"
        } else {
            return
        }

        let result = SAMLResult(
            username: username,
            cookie: cookie,
            usergroup: usergroup,
            server: foundServer ?? defaultServer
        )
        finish(with: .success(result))
    }
}
