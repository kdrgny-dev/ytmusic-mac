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

    /// How the category (mood/genre) page lays its playlists out.
    @Published var categoryLayout: CategoryLayout {
        didSet { defaults.set(categoryLayout.rawValue, forKey: Keys.categoryLayout) }
    }

    /// Interface language. Also becomes InnerTube's `hl`, so YT's own shelf
    /// and genre titles come back in the same language as the chrome.
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Keys.language)
            Task { @MainActor in LanguageBridge.apply() }
        }
    }

    /// InnerTube's `gl` — which country's charts and new releases YT serves.
    /// Separate from `language` on purpose: an English interface doesn't
    /// imply US charts.
    @Published var region: AppRegion {
        didSet {
            guard region != oldValue else { return }
            defaults.set(region.rawValue, forKey: Keys.region)
            Task { @MainActor in NativeShellViewModel.shared.reloadLocalizedContent() }
        }
    }

    /// Record what plays into a local SQLite file so the app can show the
    /// listening stats YouTube Music itself never surfaces. Nothing leaves
    /// the machine. Turning it off must also drop the listen in progress,
    /// otherwise it would be written the next time a track changes.
    @Published var historyEnabled: Bool {
        didSet {
            defaults.set(historyEnabled, forKey: Keys.historyEnabled)
            if !historyEnabled { MediaController.shared.resetHistoryTracking() }
        }
    }

    private init() {
        self.language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        self.region = AppRegion(rawValue: defaults.string(forKey: Keys.region) ?? "") ?? .system
        self.categoryLayout = CategoryLayout(rawValue: defaults.string(forKey: Keys.categoryLayout) ?? "")
            ?? .largeGrid
        self.notifyOnTrackChange = defaults.bool(forKey: Keys.notify)
        self.miniPlayerAlwaysOnTop = defaults.object(forKey: Keys.miniOnTop) as? Bool ?? true
        self.sidebarCollapsed = defaults.bool(forKey: Keys.sidebarCollapsed)
        self.alwaysShuffle = defaults.object(forKey: Keys.alwaysShuffle) as? Bool ?? true
        self.autoReloadOnIdle = defaults.object(forKey: Keys.autoReloadOnIdle) as? Bool ?? true
        self.crossfadeEnabled = defaults.object(forKey: Keys.crossfadeEnabled) as? Bool ?? true
        self.crossfadeDuration = defaults.object(forKey: Keys.crossfadeDuration) as? Double ?? 5
        self.nativeUIMode = defaults.bool(forKey: Keys.nativeUIMode)
        self.historyEnabled = defaults.object(forKey: Keys.historyEnabled) as? Bool ?? true
        let raw = defaults.string(forKey: Keys.theme) ?? Theme.default.rawValue
        self.theme = Theme(rawValue: raw) ?? .default
    }

    fileprivate typealias Keys = PrefKeys
}

enum PrefKeys {
        static let notify = "pref.notifyOnTrackChange"
        static let miniOnTop = "pref.miniPlayerAlwaysOnTop"
        static let sidebarCollapsed = "pref.sidebarCollapsed"
        static let theme = "pref.theme"
        static let alwaysShuffle = "pref.alwaysShuffle"
        static let autoReloadOnIdle = "pref.autoReloadOnIdle"
        static let crossfadeEnabled = "pref.crossfadeEnabled"
        static let crossfadeDuration = "pref.crossfadeDuration"
        static let nativeUIMode = "pref.nativeUIMode"
        static let categoryLayout = "pref.categoryLayout"
        static let historyEnabled = "pref.historyEnabled"
        static let language = "pref.language"
        static let region = "pref.region"
}

enum CategoryLayout: String, CaseIterable, Identifiable {
    case largeGrid
    case smallGrid
    case list

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .largeGrid: return "square.grid.2x2"
        case .smallGrid: return "square.grid.3x3"
        case .list:      return "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .largeGrid: return L10n.t("category.layout.largeGrid")
        case .smallGrid: return L10n.t("category.layout.smallGrid")
        case .list:      return L10n.t("category.layout.list")
        }
    }

    /// Cover edge length in the two grid modes.
    var coverSize: CGFloat {
        switch self {
        case .largeGrid: return 160
        case .smallGrid: return 104
        case .list:      return 44
        }
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
