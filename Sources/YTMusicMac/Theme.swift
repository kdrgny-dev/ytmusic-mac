import Foundation

/// Color themes that recolor YT Music by overriding the CSS custom
/// properties it uses for backgrounds and surfaces. Applied live via a
/// single `<style id="__ytm_theme__">` element managed from JS — switching
/// themes is just rewriting that one style.
enum Theme: String, CaseIterable, Identifiable {
    case `default`
    case oledBlack
    case midnight
    case forest
    case dracula
    case sepia
    case rosePine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:   return "Default (YT Music)"
        case .oledBlack: return "OLED Black"
        case .midnight:  return "Midnight Blue"
        case .forest:    return "Forest"
        case .dracula:   return "Dracula"
        case .sepia:     return "Sepia"
        case .rosePine:  return "Rosé Pine"
        }
    }

    /// CSS injected into the `<style id="__ytm_theme__">` slot. We override
    /// both the modern `--yt-spec-*` variables and the older `--ytmusic-*`
    /// ones, plus a fallback `background` rule on the app shell to catch
    /// any spot that didn't pick up the variable.
    var css: String {
        switch self {
        case .default:
            return "" // no override
        case .oledBlack:
            return Self.make(base: "#000000", raised: "#0c0c0c", menu: "#101010", text: nil)
        case .midnight:
            return Self.make(base: "#0b1220", raised: "#141d30", menu: "#1a2440", text: "#e8ecf5")
        case .forest:
            return Self.make(base: "#0d1a0d", raised: "#152b15", menu: "#1b3a1b", text: "#e3f0e3")
        case .dracula:
            return Self.make(base: "#282a36", raised: "#343746", menu: "#44475a", text: "#f8f8f2")
        case .sepia:
            return Self.make(base: "#2a2419", raised: "#3a3327", menu: "#4a4031", text: "#e8dcc4")
        case .rosePine:
            return Self.make(base: "#191724", raised: "#1f1d2e", menu: "#26233a", text: "#e0def4")
        }
    }

    /// Templated CSS so each theme is a single line of params.
    private static func make(base: String, raised: String, menu: String, text: String?) -> String {
        let textVars = text.map { """
        --yt-spec-text-primary: \($0);
        --ytmusic-text-primary: \($0);
        """ } ?? ""
        return """
        :root, html, body, ytmusic-app, ytmusic-app-layout {
          --yt-spec-base-background: \(base);
          --yt-spec-raised-background: \(raised);
          --yt-spec-additional-background: \(raised);
          --yt-spec-menu-background: \(menu);
          --yt-spec-static-overlay-background-medium: \(raised);
          --yt-spec-static-overlay-background-heavy: \(base);
          --ytmusic-general-background-a: \(base);
          --ytmusic-general-background-b: \(raised);
          --ytmusic-general-background-c: \(menu);
          --ytmusic-general-background: \(base);
          --ytmusic-app-background: \(base);
          --ytmusic-nav-bar-background: \(raised);
          --ytmusic-player-bar-background-color: \(raised);
          --ytmusic-color-black1: \(base);
          --ytmusic-color-black2: \(raised);
          --ytmusic-color-black3: \(menu);
          --ytmusic-color-black4: \(menu);
          --ytmusic-color-grey1: \(menu);
          \(textVars)
        }

        /* Base page surfaces */
        html, body,
        ytmusic-app, ytmusic-app-layout,
        ytmusic-browse-response, ytmusic-section-list-renderer,
        #content.ytmusic-app-layout, #main-panel.ytmusic-app-layout {
          background-color: \(base) !important;
          background-image: none !important;
        }

        /* Top nav, sidebar, player bar — and their immediate children that
           sometimes carry their own bg color. */
        ytmusic-nav-bar,
        ytmusic-nav-bar > *,
        ytmusic-guide-renderer, ytmusic-mini-guide-renderer,
        tp-yt-app-drawer, tp-yt-app-drawer#guide,
        ytmusic-player-bar,
        ytmusic-player-bar > *,
        #player-bar-background,
        ytmusic-app-layout[player-fullscreened] ytmusic-player-bar {
          background-color: \(raised) !important;
        }

        /* The playlist / album detail header has a gradient overlay; flatten it
           to the theme's base color so it doesn't show YT's default grey. */
        ytmusic-detail-header-renderer .background-gradient,
        ytmusic-responsive-header-renderer .background-gradient,
        ytmusic-detail-header-renderer,
        ytmusic-responsive-header-renderer {
          background: linear-gradient(180deg, \(raised) 0%, \(base) 100%) !important;
        }

        /* Menus / popups */
        tp-yt-paper-listbox,
        tp-yt-paper-dialog,
        ytmusic-menu-popup-renderer,
        ytmusic-popup-container {
          background-color: \(menu) !important;
        }
        """
    }
}

/// JS bridge for live theme swapping.
final class ThemeBridge {
    static let shared = ThemeBridge()

    func apply(_ theme: Theme) {
        let escaped = theme.css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`",  with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        let js = "window.__ytmSetTheme && window.__ytmSetTheme(`\(escaped)`)"
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
