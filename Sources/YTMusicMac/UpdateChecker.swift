import Foundation
import Combine

/// Polls the download site for a newer build. There's no Sparkle here on
/// purpose: the app is ad-hoc signed, so an in-place self-update would trip
/// Gatekeeper anyway. We just tell the user a new DMG exists and open it.
///
/// The manifest is served from the site at `/version.json`, but the DMG it
/// points to lives in GitHub Releases (the single download source):
/// `{ "version": "0.2", "notes": "…",
///    "dmg": "https://github.com/…/releases/latest/download/YTMusic.dmg" }`
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Update: Equatable {
        let version: String
        let notes: String?
        let downloadURL: URL
    }

    /// Non-nil when a newer version exists and the user hasn't skipped it.
    @Published private(set) var available: Update?
    /// Set by "Güncellemeleri denetle" so the menu can report "you're current".
    @Published private(set) var lastCheckFoundNothing = false

    private let manifestURL = URL(string: "https://ytmusic-mac.vercel.app/version.json")!
    private let skippedKey = "pref.skippedUpdateVersion"

    /// The running build's `CFBundleShortVersionString`.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private init() {}

    /// Check now, then once every six hours for as long as the app runs.
    func startPeriodicChecks() {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
            }
        }
    }

    @discardableResult
    func check() async -> Update? {
        var req = URLRequest(url: manifestURL)
        // The manifest is tiny and changes rarely, but a cached copy would
        // hide the release we just published.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let dmg = (json["dmg"] as? String).flatMap(URL.init(string:))
        else { return nil }

        let notes = json["notes"] as? String
        let skipped = UserDefaults.standard.string(forKey: skippedKey)
        let isNewer = AppVersion.isNewer(version, than: currentVersion)
        let update = Update(version: version, notes: notes, downloadURL: dmg)

        await MainActor.run {
            self.lastCheckFoundNothing = !isNewer
            self.available = (isNewer && version != skipped) ? update : nil
        }
        return isNewer ? update : nil
    }

    /// Hide this version's banner until a newer one ships.
    func skip(_ update: Update) {
        UserDefaults.standard.set(update.version, forKey: skippedKey)
        available = nil
    }
}

/// Dotted numeric version comparison ("0.10" > "0.9"), tolerant of missing
/// components ("1" == "1.0") and of trailing junk ("1.2-beta" → 1.2).
enum AppVersion {
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = components(lhs), b = components(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ s: String) -> [Int] {
        s.split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }
}
