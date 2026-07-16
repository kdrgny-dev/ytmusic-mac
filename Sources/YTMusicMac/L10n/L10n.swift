import Foundation

/// String catalog lookup.
///
/// Strings live in plain Swift dictionaries rather than `.strings` resources
/// because this app is a hand-rolled SPM executable: `build.sh` assembles the
/// `.app` itself and only copies the icon into `Resources/`. A resource bundle
/// would work in `swift run` and silently come up empty in a release build.
enum L10n {
    /// Cached per language so `t()` isn't rebuilding a merged dictionary on
    /// every call. Keyed by the resolved language so a stale cache can never
    /// outlive a language change, even if `reload()` is somehow missed.
    private static var cache: (language: ResolvedLanguage, table: [String: String])?

    /// Test-only pin. Assertions on translated output would otherwise depend
    /// on the test machine's system locale, and driving the real preference
    /// isn't an option — its `didSet` rebuilds menus and refetches content.
    static var _testLanguageOverride: ResolvedLanguage? {
        didSet { reload() }
    }

    static var language: ResolvedLanguage {
        _testLanguageOverride ?? Preferences.shared.language.resolved
    }

    /// Locale for date/number formatting. Region is deliberately not folded
    /// in — `gl` picks YT's content region, not how the user reads a date.
    static var locale: Locale { Locale(identifier: language.rawValue) }

    static func reload() { cache = nil }

    private static var table: [String: String] {
        let lang = language
        if let cache, cache.language == lang { return cache.table }
        let table = Strings.catalog(for: lang)
        cache = (lang, table)
        return table
    }

    /// Missing keys fall back to English before falling back to the key
    /// itself, so a gap in a translation degrades to a readable word rather
    /// than `shell.player.play`.
    static func t(_ key: String) -> String {
        table[key] ?? Strings.en[key] ?? key
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// Looks up `<key>.one` / `<key>.other`. Turkish maps both to the same
    /// string (no plural agreement after a numeral); English doesn't.
    static func plural(_ key: String, _ count: Int) -> String {
        String(format: t(count == 1 ? "\(key).one" : "\(key).other"), count)
    }
}

enum Strings {
    static func catalog(for language: ResolvedLanguage) -> [String: String] {
        switch language {
        case .english: return en
        case .turkish: return tr
        }
    }

    /// The per-domain tables, unmerged. Exposed so tests can assert the
    /// domains stay disjoint — `merged` silently keeps the first winner, and
    /// its assertion only fires in debug.
    static let enTables: [[String: String]] = [menuEN, settingsEN, statsEN, shellEN, modelEN]
    static let trTables: [[String: String]] = [menuTR, settingsTR, statsTR, shellTR, modelTR]

    static let en: [String: String] = merged(enTables)
    static let tr: [String: String] = merged(trTables)

    /// Traps duplicate keys in debug rather than letting one domain silently
    /// shadow another's string.
    private static func merged(_ tables: [[String: String]]) -> [String: String] {
        tables.reduce(into: [:]) { acc, table in
            acc.merge(table) { existing, _ in
                assertionFailure("Duplicate L10n key collided; keeping first")
                return existing
            }
        }
    }
}
