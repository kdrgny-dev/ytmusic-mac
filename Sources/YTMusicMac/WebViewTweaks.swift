import Foundation
import WebKit

/// Wrappers around WKWebView private SPI we need for Google sign-in to work
/// inside an embedded WKWebView. These call into private setters via the
/// Objective-C runtime; they're stable across recent macOS versions but may
/// need updating in the future. Acceptable trade-off for a personal app.
enum WebViewTweaks {

    /// Turn off Intelligent Tracking Prevention on the data store, so the
    /// accounts.google.com → youtube.com → music.youtube.com cookie handoff
    /// during login isn't broken by cross-site cookie heuristics.
    static func disableITP(on dataStore: WKWebsiteDataStore) {
        callBoolSetter(dataStore, selectorName: "_setResourceLoadStatisticsEnabled:", value: false)
    }

    /// Tell WKPreferences to allow all third-party storage (cookies, local
    /// storage). 0 == WKStorageBlockingAllowAll in the private enum.
    static func allowAllStorage(on prefs: WKPreferences) {
        callIntSetter(prefs, selectorName: "_setStorageBlockingPolicy:", value: 0)
    }

    // MARK: - private runtime helpers

    private static func callBoolSetter(_ target: AnyObject, selectorName: String, value: Bool) {
        let sel = NSSelectorFromString(selectorName)
        guard target.responds(to: sel) else { return }
        let imp = target.method(for: sel)
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        fn(target, sel, value)
    }

    private static func callIntSetter(_ target: AnyObject, selectorName: String, value: Int) {
        let sel = NSSelectorFromString(selectorName)
        guard target.responds(to: sel) else { return }
        let imp = target.method(for: sel)
        typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        fn(target, sel, value)
    }
}
