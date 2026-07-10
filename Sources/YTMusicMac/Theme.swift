import Foundation
import SwiftUI

/// Color themes that recolor YT Music. Two consumers share one source of
/// truth (the `palette` hex values):
///   1. The classic WebView UI — via CSS custom properties injected into a
///      single `<style id="__ytm_theme__">` element (see `css` / ThemeBridge).
///   2. The Native Mode SwiftUI shell — via the `*Color` accessors below,
///      which the shell uses for its surface tokens.
enum Theme: String, CaseIterable, Identifiable {
    case `default`
    case oledBlack
    case midnight
    case forest
    case dracula
    case sepia
    case rosePine
    // Imported themes — each has a light (:root) and dark (.dark) variant.
    case caffeineLight
    case spotifyLight
    case modernMinimalLight
    case marvelLight
    case caffeineDark
    case spotifyDark
    case modernMinimalDark
    case marvelDark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:           return "Default (YT Music)"
        case .oledBlack:         return "OLED Black"
        case .midnight:          return "Midnight Blue"
        case .forest:            return "Forest"
        case .dracula:           return "Dracula"
        case .sepia:             return "Sepia"
        case .rosePine:          return "Rosé Pine"
        case .caffeineLight:     return "Caffeine"
        case .spotifyLight:      return "Spotify"
        case .modernMinimalLight:return "Modern Minimal"
        case .marvelLight:       return "Marvel"
        case .caffeineDark:      return "Caffeine"
        case .spotifyDark:       return "Spotify"
        case .modernMinimalDark: return "Modern Minimal"
        case .marvelDark:        return "Marvel"
        }
    }

    /// The three surface tints + optional text color, as hex. Single source
    /// of truth for both the CSS and the native palette. `.default` mirrors
    /// the near-black the native shell historically hardcoded.
    struct Palette {
        let base: String     // app background (main content)
        let raised: String   // player bar / panels (= --card)
        let menu: String     // hover / chips / popups (= --secondary/muted)
        let text: String?    // nil = keep YT/white default
        let accent: String   // active-control / highlight tint (= --primary)
        let isDark: Bool     // drives colorScheme + .primary contrast
        let sidebar: String  // sidebar surface (= --sidebar) — distinct region
        let border: String   // dividers / outlines (= --border)
    }

    var palette: Palette {
        switch self {
        case .default:   return Palette(base: "#0b0b0d", raised: "#181819", menu: "#232326", text: nil,       accent: "#21cc75", isDark: true,  sidebar: "#141416", border: "#2a2a2e")
        case .oledBlack: return Palette(base: "#000000", raised: "#0c0c0c", menu: "#101010", text: nil,       accent: "#21cc75", isDark: true,  sidebar: "#070707", border: "#1c1c1c")
        case .midnight:  return Palette(base: "#0b1220", raised: "#141d30", menu: "#1a2440", text: "#e8ecf5", accent: "#4f8cff", isDark: true,  sidebar: "#0e1728", border: "#243150")
        case .forest:    return Palette(base: "#0d1a0d", raised: "#152b15", menu: "#1b3a1b", text: "#e3f0e3", accent: "#21cc75", isDark: true,  sidebar: "#102610", border: "#244a24")
        case .dracula:   return Palette(base: "#282a36", raised: "#343746", menu: "#44475a", text: "#f8f8f2", accent: "#bd93f9", isDark: true,  sidebar: "#21222e", border: "#44475a")
        case .sepia:     return Palette(base: "#2a2419", raised: "#3a3327", menu: "#4a4031", text: "#e8dcc4", accent: "#d9a441", isDark: true,  sidebar: "#332c1f", border: "#514633")
        case .rosePine:  return Palette(base: "#191724", raised: "#1f1d2e", menu: "#26233a", text: "#e0def4", accent: "#ebbcba", isDark: true,  sidebar: "#1f1d2e", border: "#403d54")
        // Imported themes — light (:root) variants.
        case .caffeineLight:     return Palette(base: "#f8f8f8", raised: "#fcfcfc", menu: "#ffdfb1", text: "#1f1f1f", accent: "#63493f", isDark: false, sidebar: "#ffffff", border: "#d7d7d7")
        case .spotifyLight:      return Palette(base: "#fcfcfc", raised: "#ffffff", menu: "#d3e0ea", text: "#313e38", accent: "#00b262", isDark: false, sidebar: "#f3faff", border: "#dbe6ee")
        case .modernMinimalLight:return Palette(base: "#ffffff", raised: "#ffffff", menu: "#dcf2ff", text: "#333333", accent: "#3981f6", isDark: false, sidebar: "#f6f8fb", border: "#e4e8ef")
        case .marvelLight:       return Palette(base: "#fff6f5", raised: "#fceae8", menu: "#eac8c0", text: "#3a0608", accent: "#d40c1a", isDark: false, sidebar: "#fbf0ef", border: "#e6cfcc")
        // Imported themes — dark (.dark) variants.
        case .caffeineDark:      return Palette(base: "#121212", raised: "#1c1c1c", menu: "#3a3128", text: "#eeeeee", accent: "#fcdfc2", isDark: true,  sidebar: "#0d0d0d", border: "#2a2620")
        case .spotifyDark:       return Palette(base: "#0a0e1a", raised: "#161b27", menu: "#282d3d", text: "#e9f0f5", accent: "#00b262", isDark: true,  sidebar: "#10131c", border: "#292e38")
        case .modernMinimalDark: return Palette(base: "#161616", raised: "#262626", menu: "#1e3a8b", text: "#e4e4e4", accent: "#3981f6", isDark: true,  sidebar: "#101012", border: "#3a3a3a")
        case .marvelDark:        return Palette(base: "#140f0e", raised: "#221c1b", menu: "#a4730b", text: "#f5eceb", accent: "#d40c1a", isDark: true,  sidebar: "#0d0807", border: "#383130")
        }
    }

    // Native-shell colors derived from the palette.
    /// " (Light)"/" (Dark)" only for the imported themes that ship both
    /// variants — empty for the originals so their names stay clean.
    var variantSuffix: String {
        switch self {
        case .caffeineLight, .spotifyLight, .modernMinimalLight, .marvelLight: return " (Light)"
        case .caffeineDark, .spotifyDark, .modernMinimalDark, .marvelDark:     return " (Dark)"
        default: return ""
        }
    }

    var baseColor: Color    { Color(hex: palette.base) }
    var surfaceColor: Color { Color(hex: palette.raised) }
    var raisedColor: Color  { Color(hex: palette.menu) }
    var accentColor: Color  { Color(hex: palette.accent) }
    var sidebarColor: Color { Color(hex: palette.sidebar) }
    var borderColor: Color  { Color(hex: palette.border) }
    var isDark: Bool        { palette.isDark }

    /// Text/icon color that stays legible ON TOP of `accentColor`. Hardcoding
    /// white washes out on pale accents. 0.179 is where white and black ink
    /// give equal WCAG contrast — anything brighter takes black. A saturated
    /// mid-tone like Spotify's green (0.44) reads far better with black ink,
    /// which a naive "is it dark?" threshold gets backwards.
    var onAccentColor: Color {
        Self.relativeLuminance(ofHex: palette.accent) > 0.179 ? .black : .white
    }

    static func relativeLuminance(ofHex hex: String) -> Double {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let channels = [Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff)]
            .map { c -> Double in
                let n = c / 255
                return n <= 0.03928 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4)
            }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// CSS injected into the `<style id="__ytm_theme__">` slot. We override
    /// both the modern `--yt-spec-*` variables and the older `--ytmusic-*`
    /// ones, plus a fallback `background` rule on the app shell to catch
    /// any spot that didn't pick up the variable. `.default` leaves YT's
    /// own theme untouched.
    var css: String {
        guard self != .default else { return "" }
        let p = palette
        return Self.make(base: p.base, raised: p.raised, menu: p.menu, text: p.text)
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

extension Color {
    /// Build a Color from a "#rrggbb" hex string. Falls back to black on a
    /// malformed string so a bad theme value can't crash the UI.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self = Color(red: r, green: g, blue: b)
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
