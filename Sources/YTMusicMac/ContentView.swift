import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        WebViewRepresentable()
            .ignoresSafeArea()
    }
}

/// SwiftUI just hands back the singleton WKWebView so the same one is reused
/// across window close/reopen cycles. We detach it from any previous superview
/// first; the singleton itself stays alive in WebViewHolder.
struct WebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let wv = WebViewHolder.shared.obtain()
        wv.removeFromSuperview()
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Owns the single WKWebView instance for the whole app lifetime. Acts as the
/// script message handler, navigation delegate, and UI delegate so we don't
/// need a SwiftUI Coordinator (which would die with the view).
final class WebViewHolder: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let shared = WebViewHolder()

    private var _webView: WKWebView?
    var webView: WKWebView? { _webView }

    func obtain() -> WKWebView {
        if let existing = _webView { return existing }
        let wv = build()
        _webView = wv
        return wv
    }

    private func build() -> WKWebView {
        // Cap URLCache so YT's image responses (album art, thumbnails) don't
        // grow without bound over a long session. 32 MB memory / 128 MB disk
        // is plenty for browsing a playlist or two while staying tight.
        // macOS' default leaves these unset — silent unbounded growth.
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 128 * 1024 * 1024)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Disable Intelligent Tracking Prevention so cross-site cookies in the
        // accounts.google.com → youtube.com → music.youtube.com login chain survive.
        // Private SPI — fine for a personal app, may need updating on new macOS.
        WebViewTweaks.disableITP(on: config.websiteDataStore)
        WebViewTweaks.allowAllStorage(on: config.preferences)

        let userContent = WKUserContentController()
        userContent.add(self, name: "ytmBridge")
        userContent.add(self, name: "ytmLog")
        userContent.add(self, name: "ytmQueue")
        userContent.add(self, name: "ytmEvent")
        userContent.addUserScript(WKUserScript(
            source: PlayerBridge.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContent.addUserScript(WKUserScript(
            source: PlayerBridge.consoleCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        userContent.addUserScript(WKUserScript(
            source: PlayerBridge.cssBootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        // Keep swipe gestures ON so we still RECEIVE back/forward intents in
        // Native Mode — but decidePolicyFor reroutes them to the native nav
        // stack and cancels the WebView's own history nav (see below), so they
        // never change the playing /watch track.
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        // Layer-backed + dark base so resize feels snappy and pre-paint
        // doesn't flash white. underPageBackgroundColor handles the area
        // exposed during elastic scroll / window resize before YT's CSS paints.
        webView.wantsLayer = true
        let dark = NSColor(red: 0.012, green: 0.012, blue: 0.012, alpha: 1)
        webView.layer?.backgroundColor = dark.cgColor
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = dark
        }
        // Private SPI: stop WKWebView from painting its own white background
        // before the page loads. Same kind of private call we already use in
        // WebViewTweaks; safe and reverts to no-op if missing.
        WebViewTweaks.setDrawsBackground(on: webView, value: false)
        webView.load(URLRequest(url: URL(string: "https://music.youtube.com")!))
        return webView
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "ytmBridge":
            if let body = message.body as? [String: Any] {
                MediaController.shared.updateNowPlaying(info: body)
            }
        case "ytmLog":
            if let body = message.body as? [String: Any],
               let level = body["level"] as? String,
               let text = body["text"] as? String {
                FileHandle.standardError.write(Data("[js:\(level)] \(text)\n".utf8))
            }
        case "ytmQueue":
            if let body = message.body as? [String: Any] {
                NativeShellViewModel.shared.updateQueue(from: body)
            }
        case "ytmEvent":
            if let body = message.body as? [String: Any],
               let name = body["name"] as? String {
                switch name {
                case "ended":    Task { @MainActor in NativeShellViewModel.shared.handleTrackEnded() }
                case "exitClip": Task { @MainActor in NativeShellViewModel.shared.exitClip() }
                case "clipReady": Task { @MainActor in NativeShellViewModel.shared.clipReady() }
                case "clipTrackChanged":
                    let hasVideo = (body["hasVideo"] as? Bool) ?? false
                    Task { @MainActor in NativeShellViewModel.shared.clipTrackChanged(hasVideo: hasVideo) }
                case "clipUnavailable": Task { @MainActor in NativeShellViewModel.shared.clipUnavailable() }
                default: break
                }
            }
        default: break
        }
    }

    // MARK: - WKNavigationDelegate / WKUIDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-apply user preferences after every page load so the JS bridge
        // reflects current toggle state regardless of what the bootstrap
        // script's defaults were.
        let prefs = Preferences.shared
        // Keep YT's web UI hidden under the SwiftUI shell after reloads when
        // Native Mode is on (otherwise it would flash back in on navigation).
        FeatureBridge.shared.set("hideYTApp", enabled: prefs.nativeUIMode)
        PrefBridge.shared.setAlwaysShuffle(prefs.alwaysShuffle)
        PrefBridge.shared.setCrossfade(enabled: prefs.crossfadeEnabled, duration: prefs.crossfadeDuration)
        ThemeBridge.shared.apply(prefs.theme)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // In Native Mode the WebView is a hidden audio engine. A back/forward
        // history navigation (swipe gesture) would load the previous/next
        // /watch page and change the playing track. Instead, reroute it to the
        // native nav stack (direction inferred from the back/forward list) and
        // cancel the WebView's own history nav. (Our own loads are .other /
        // .linkActivated, never .backForward, so this only catches history nav.)
        if Preferences.shared.nativeUIMode,
           navigationAction.navigationType == .backForward {
            let targetURL = navigationAction.request.url
            let forwardURL = webView.backForwardList.forwardItem?.url
            Task { @MainActor in
                if let t = targetURL, t == forwardURL {
                    NativeShellViewModel.shared.goForward()
                } else {
                    NativeShellViewModel.shared.goBack()
                }
            }
            decisionHandler(.cancel)
            return
        }
        if let url = navigationAction.request.url,
           let host = url.host,
           navigationAction.navigationType == .linkActivated,
           !host.contains("youtube.com") && !host.contains("google.com") && !host.contains("googleusercontent.com") && !host.contains("googleapis.com") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    /// Explicit file picker handler so HTML5 `<input type="file">` (used when
    /// uploading a custom playlist cover) actually shows an NSOpenPanel.
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // MARK: - public actions

    func focusSearch() {
        _webView?.evaluateJavaScript("window.__ytmFocusSearch && window.__ytmFocusSearch()", completionHandler: nil)
    }

    func reload() {
        _webView?.reload()
    }

    /// Reload but suppress YT's autoplay-on-load for a short window. Used by
    /// the idle reloader so a 30-min-paused session doesn't spontaneously
    /// start playing the current /watch track in the background after the
    /// page reloads. The flag is read by the injected bridge (it persists in
    /// localStorage across the reload) which pauses any autoplay until it
    /// expires. Manual reloads don't set the flag, so they behave normally.
    func reloadSuppressingAutoplay(seconds: Double = 12) {
        let untilMs = Int(seconds * 1000)
        let js = "try{localStorage.setItem('__ytmSuppressAutoplay', String(Date.now()+\(untilMs)))}catch(e){}"
        _webView?.evaluateJavaScript(js) { [weak self] _, _ in
            self?._webView?.reload()
        }
    }

    func clearAllData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                if let url = URL(string: "https://music.youtube.com") {
                    self?._webView?.load(URLRequest(url: url))
                }
            }
        }
    }
}
