import Foundation
import CryptoKit

/// Reads YouTube auth cookies (already populated by the WebView login)
/// and produces the SAPISIDHASH headers InnerTube needs.
///
/// Why this exists in the WebView app:
/// The WebView is great at "play this song" but bad at "give me the user's
/// playlist list as a Swift data type". For library/search/playlist data
/// we want native calls so the SwiftUI shell can render without scraping
/// YT's DOM. Cookies are already in HTTPCookieStorage.shared (WebView
/// shares them), we just sign requests on top of that.
final class AuthSession: @unchecked Sendable {
    let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init(cookieStorage: HTTPCookieStorage = .shared) {
        self.cookieStorage = cookieStorage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    /// We're "authenticated" the moment a SAPISID cookie shows up — that
    /// matches what YT's web app uses to flip its UI from logged-out to
    /// logged-in.
    var isAuthenticated: Bool { sapisid != nil }

    private var sapisid: String? {
        cookieStorage.cookies?.first(where: {
            $0.name == "SAPISID" &&
            ($0.domain == ".youtube.com" || $0.domain == ".google.com")
        })?.value
    }

    /// Triple-hash Authorization header — what the real YT Music web app
    /// sends. Without all three, /player and some browse endpoints return
    /// UNPLAYABLE or LOGIN_REQUIRED despite the cookies being valid.
    ///
    /// Format per hash: `<scheme> <ts>_<sha1hex>`
    /// where `sha1hex = SHA1("<ts> <cookie> <origin>")`.
    func sapisidHashHeader(origin: String) -> String? {
        let ts = Int(Date().timeIntervalSince1970)
        let parts: [(scheme: String, cookieName: String)] = [
            ("SAPISIDHASH",   "SAPISID"),
            ("SAPISID1PHASH", "__Secure-1PAPISID"),
            ("SAPISID3PHASH", "__Secure-3PAPISID")
        ]
        let cookies = cookieStorage.cookies ?? []
        var pieces: [String] = []
        for part in parts {
            guard let c = cookies.first(where: { $0.name == part.cookieName &&
                ($0.domain == ".youtube.com" || $0.domain == ".google.com") })
            else { continue }
            let input = "\(ts) \(c.value) \(origin)"
            let digest = Insecure.SHA1.hash(data: Data(input.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            pieces.append("\(part.scheme) \(ts)_\(hex)")
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }
}
