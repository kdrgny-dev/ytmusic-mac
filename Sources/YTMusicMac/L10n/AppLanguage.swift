import Foundation

/// A language the app actually ships strings for. `AppLanguage.system`
/// always resolves down to one of these.
enum ResolvedLanguage: String, Equatable {
    case english = "en"
    case turkish = "tr"
}

/// User-facing language choice. Default is `.system`, which follows macOS
/// and falls back to English for anything we don't ship.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case turkish

    var id: String { rawValue }

    var resolved: ResolvedLanguage {
        switch self {
        case .english: return .english
        case .turkish: return .turkish
        case .system:  return Self.systemResolved
        }
    }

    /// `hl` for InnerTube, and the locale we format dates/numbers with.
    var code: String { resolved.rawValue }

    /// Language names stay in their own language — a user who has landed in
    /// the wrong language must still be able to find their way out. Only
    /// "System" is translated.
    var label: String {
        switch self {
        case .system:  return L10n.t("settings.language.system")
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    private static var systemResolved: ResolvedLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let base = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        return ResolvedLanguage(rawValue: base) ?? .english
    }
}

/// Thread-safe view of the locale prefs for readers that aren't on the main
/// thread — `InnerTubeClient` is an actor and must not touch `Preferences`'
/// `@Published` properties. UserDefaults is safe to read from anywhere, and
/// it's the same storage those properties write through.
enum LocaleSnapshot {
    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: PrefKeys.language) ?? "") ?? .system
    }

    static var region: AppRegion {
        AppRegion(rawValue: UserDefaults.standard.string(forKey: PrefKeys.region) ?? "") ?? .system
    }
}

/// `gl` for InnerTube — drives which charts and new releases YT serves.
/// Deliberately separate from `AppLanguage`: wanting an English interface
/// says nothing about wanting US charts.
enum AppRegion: String, CaseIterable, Identifiable {
    case system
    case US, GB, CA, AU, IE, NZ, ZA
    case TR, DE, FR, ES, IT, NL, SE, NO, DK, FI, PL, PT, GR, RU, UA
    case JP, KR, IN, ID, BR, MX, AR, CL, CO, EG, SA, AE

    var id: String { rawValue }

    /// The concrete `gl` value. `.system` reads the Mac's region, and falls
    /// back to US because YT rejects a missing/empty `gl`.
    var code: String {
        guard self == .system else { return rawValue }
        return Locale.current.region?.identifier.uppercased() ?? "US"
    }

    /// Country names come from the app's language, not `Locale.current` —
    /// otherwise an English interface on a Turkish Mac would list "Almanya".
    func label(in language: ResolvedLanguage) -> String {
        if self == .system {
            let resolvedName = Locale(identifier: language.rawValue)
                .localizedString(forRegionCode: code) ?? code
            return L10n.t("settings.region.system", resolvedName)
        }
        return Locale(identifier: language.rawValue)
            .localizedString(forRegionCode: rawValue) ?? rawValue
    }
}
