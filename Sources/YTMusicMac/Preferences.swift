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

    @Published var applyPlayerLayout: Bool {
        didSet {
            defaults.set(applyPlayerLayout, forKey: Keys.playerLayout)
            FeatureBridge.shared.set("playerLayout", enabled: applyPlayerLayout)
        }
    }

    @Published var hidePromos: Bool {
        didSet {
            defaults.set(hidePromos, forKey: Keys.hidePromos)
            FeatureBridge.shared.set("hidePromos", enabled: hidePromos)
        }
    }

    @Published var zebraStriping: Bool {
        didSet {
            defaults.set(zebraStriping, forKey: Keys.zebraStriping)
            FeatureBridge.shared.set("zebraStriping", enabled: zebraStriping)
        }
    }

    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            ThemeBridge.shared.apply(theme)
        }
    }

    @Published var compactMode: Bool {
        didSet {
            defaults.set(compactMode, forKey: Keys.compactMode)
            FeatureBridge.shared.set("compactMode", enabled: compactMode)
        }
    }

    @Published var stackedHeader: Bool {
        didSet {
            defaults.set(stackedHeader, forKey: Keys.stackedHeader)
            FeatureBridge.shared.set("stackedHeader", enabled: stackedHeader)
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
        self.applyPlayerLayout = defaults.object(forKey: Keys.playerLayout) as? Bool ?? true
        self.hidePromos = defaults.object(forKey: Keys.hidePromos) as? Bool ?? true
        self.zebraStriping = defaults.object(forKey: Keys.zebraStriping) as? Bool ?? true
        self.compactMode = defaults.bool(forKey: Keys.compactMode)
        self.stackedHeader = defaults.bool(forKey: Keys.stackedHeader)
        self.alwaysShuffle = defaults.object(forKey: Keys.alwaysShuffle) as? Bool ?? true
        self.autoReloadOnIdle = defaults.object(forKey: Keys.autoReloadOnIdle) as? Bool ?? true
        self.nativeUIMode = defaults.bool(forKey: Keys.nativeUIMode)
        let raw = defaults.string(forKey: Keys.theme) ?? Theme.default.rawValue
        self.theme = Theme(rawValue: raw) ?? .default
    }

    private enum Keys {
        static let notify = "pref.notifyOnTrackChange"
        static let miniOnTop = "pref.miniPlayerAlwaysOnTop"
        static let playerLayout = "pref.applyPlayerLayout"
        static let hidePromos = "pref.hidePromos"
        static let zebraStriping = "pref.zebraStriping"
        static let compactMode = "pref.compactMode"
        static let stackedHeader = "pref.stackedHeader"
        static let theme = "pref.theme"
        static let alwaysShuffle = "pref.alwaysShuffle"
        static let autoReloadOnIdle = "pref.autoReloadOnIdle"
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
}
