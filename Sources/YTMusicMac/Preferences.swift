import Foundation
import Combine

/// Centralized app preferences backed by UserDefaults. Singleton with
/// @Published properties so SwiftUI views can bind directly.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var notifyOnTrackChange: Bool {
        didSet { defaults.set(notifyOnTrackChange, forKey: Keys.notify) }
    }

    @Published var miniPlayerAlwaysOnTop: Bool {
        didSet { defaults.set(miniPlayerAlwaysOnTop, forKey: Keys.miniOnTop) }
    }

    @Published var sidebarCollapsed: Bool {
        didSet { defaults.set(sidebarCollapsed, forKey: Keys.sidebarCollapsed) }
    }

    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            ThemeBridge.shared.apply(theme)
        }
    }

    @Published var alwaysShuffle: Bool {
        didSet {
            defaults.set(alwaysShuffle, forKey: Keys.alwaysShuffle)
            PrefBridge.shared.setAlwaysShuffle(alwaysShuffle)
        }
    }

    @Published var autoReloadOnIdle: Bool {
        didSet { defaults.set(autoReloadOnIdle, forKey: Keys.autoReloadOnIdle) }
    }

    /// Crossfade: fade the outgoing track's tail out and the incoming
    /// track's head in over `crossfadeDuration` seconds. True overlapping
    /// crossfade isn't possible over YT's single audio element, so this is
    /// a fade-out→fade-in at the boundary (see PlayerBridge `__ytmSetFade`).
    @Published var crossfadeEnabled: Bool {
        didSet {
            defaults.set(crossfadeEnabled, forKey: Keys.crossfadeEnabled)
            PrefBridge.shared.setCrossfade(enabled: crossfadeEnabled, duration: crossfadeDuration)
        }
    }

    /// Seconds of fade at each track boundary (0–12).
    @Published var crossfadeDuration: Double {
        didSet {
            defaults.set(crossfadeDuration, forKey: Keys.crossfadeDuration)
            PrefBridge.shared.setCrossfade(enabled: crossfadeEnabled, duration: crossfadeDuration)
        }
    }

    /// When true, the WebView's UI is hidden via CSS and a SwiftUI shell
    /// covers the window. WebView still runs in the background as the audio
    /// engine. Default OFF until the shell is feature-complete.
    @Published var nativeUIMode: Bool {
        didSet {
            defaults.set(nativeUIMode, forKey: Keys.nativeUIMode)
            FeatureBridge.shared.set("hideYTApp", enabled: nativeUIMode)
        }
    }

    private init() {
        self.notifyOnTrackChange = defaults.bool(forKey: Keys.notify)
        self.miniPlayerAlwaysOnTop = defaults.object(forKey: Keys.miniOnTop) as? Bool ?? true
        self.sidebarCollapsed = defaults.bool(forKey: Keys.sidebarCollapsed)
        self.alwaysShuffle = defaults.object(forKey: Keys.alwaysShuffle) as? Bool ?? true
        self.autoReloadOnIdle = defaults.object(forKey: Keys.autoReloadOnIdle) as? Bool ?? true
        self.crossfadeEnabled = defaults.object(forKey: Keys.crossfadeEnabled) as? Bool ?? true
        self.crossfadeDuration = defaults.object(forKey: Keys.crossfadeDuration) as? Double ?? 5
        self.nativeUIMode = defaults.bool(forKey: Keys.nativeUIMode)
        let raw = defaults.string(forKey: Keys.theme) ?? Theme.default.rawValue
        self.theme = Theme(rawValue: raw) ?? .default
    }

    private enum Keys {
        static let notify = "pref.notifyOnTrackChange"
        static let miniOnTop = "pref.miniPlayerAlwaysOnTop"
        static let sidebarCollapsed = "pref.sidebarCollapsed"
        static let theme = "pref.theme"
        static let alwaysShuffle = "pref.alwaysShuffle"
        static let autoReloadOnIdle = "pref.autoReloadOnIdle"
        static let crossfadeEnabled = "pref.crossfadeEnabled"
        static let crossfadeDuration = "pref.crossfadeDuration"
        static let nativeUIMode = "pref.nativeUIMode"
    }
}

/// Thin wrapper around the JS `window.__ytmSetFeature` bridge so toggling
/// CSS features doesn't require reloading the webview.
final class FeatureBridge {
    static let shared = FeatureBridge()

    func set(_ feature: String, enabled: Bool) {
        let js = "window.__ytmSetFeature && window.__ytmSetFeature('\(feature)', \(enabled))"
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

/// Bridge for runtime JS prefs (not CSS toggles) — currently just the
/// shuffle-keeper. Lives here so all JS-side preferences are wired the
/// same way.
final class PrefBridge {
    static let shared = PrefBridge()

    func setAlwaysShuffle(_ on: Bool) {
        let js = "window.__ytmSetAlwaysShuffle && window.__ytmSetAlwaysShuffle(\(on))"
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func setCrossfade(enabled: Bool, duration: Double) {
        let js = "window.__ytmSetFade && window.__ytmSetFade(\(enabled), \(duration))"
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func enterClip() { run("window.__ytmEnterClip && window.__ytmEnterClip()") }
    func exitClip()  { run("window.__ytmExitClip && window.__ytmExitClip()") }

    private func run(_ js: String) {
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
