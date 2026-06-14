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

    private init() {
        self.notifyOnTrackChange = defaults.bool(forKey: Keys.notify)
        self.miniPlayerAlwaysOnTop = defaults.object(forKey: Keys.miniOnTop) as? Bool ?? true
        self.applyPlayerLayout = defaults.object(forKey: Keys.playerLayout) as? Bool ?? true
        self.hidePromos = defaults.object(forKey: Keys.hidePromos) as? Bool ?? true
    }

    private enum Keys {
        static let notify = "pref.notifyOnTrackChange"
        static let miniOnTop = "pref.miniPlayerAlwaysOnTop"
        static let playerLayout = "pref.applyPlayerLayout"
        static let hidePromos = "pref.hidePromos"
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
