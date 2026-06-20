import Foundation
import Combine

/// State for the SwiftUI shell — owns the auth + InnerTube clients and
/// surfaces decoded data (playlist list, etc.) as @Published values for
/// SwiftUI to bind to. One instance, created when the shell is first
/// shown, lives for the app's lifetime.
@MainActor
final class NativeShellViewModel: ObservableObject {
    static let shared = NativeShellViewModel()

    struct PlaylistSummary: Identifiable, Hashable {
        let id: String           // "VLPL..." browseId from InnerTube
        let title: String
        let thumbnailURL: String?
    }

    @Published private(set) var playlists: [PlaylistSummary] = []
    @Published private(set) var loadingPlaylists = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticated: Bool

    private let auth = AuthSession()
    private let client: InnerTubeClient

    private init() {
        self.client = InnerTubeClient(auth: auth)
        self.isAuthenticated = auth.isAuthenticated
    }

    /// Hit InnerTube for the user's playlists. Safe to call from .onAppear —
    /// re-entrancy is gated so a fast double-call doesn't fire two requests.
    func loadPlaylistsIfNeeded() {
        guard !loadingPlaylists else { return }
        Task { await loadPlaylists() }
    }

    func reload() {
        Task { await loadPlaylists() }
    }

    private func loadPlaylists() async {
        isAuthenticated = auth.isAuthenticated
        guard isAuthenticated else {
            errorMessage = "Sign in via YT Music to see your library."
            return
        }
        loadingPlaylists = true
        defer { loadingPlaylists = false }
        do {
            // FEmusic_liked_playlists is the YT Music "playlists you own /
            // liked" landing page — same data backing the web sidebar.
            let data = try await client.browse(browseId: "FEmusic_liked_playlists")
            playlists = PlaylistParser.parse(data: data)
            errorMessage = playlists.isEmpty ? "No playlists yet." : nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Navigate the (hidden) WebView to a playlist URL so the audio
    /// engine picks up the new context. The user only sees our SwiftUI
    /// shell; WebView listens for the URL change and updates its queue.
    func openPlaylist(_ p: PlaylistSummary) {
        // browseId is "VLPL..."; the URL form needs "PL..." (drop "VL").
        let playlistId = p.id.hasPrefix("VL") ? String(p.id.dropFirst(2)) : p.id
        guard let url = URL(string: "https://music.youtube.com/playlist?list=\(playlistId)")
        else { return }
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
    }
}

/// Tiny JSON walker that finds the renderers we care about anywhere in the
/// InnerTube response tree. YT's responses nest deeply and the exact path
/// varies by endpoint version; a recursive scan for `musicTwoRowItemRenderer`
/// works across the shapes we've seen.
enum PlaylistParser {
    static func parse(data: Data) -> [NativeShellViewModel.PlaylistSummary] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [NativeShellViewModel.PlaylistSummary] = []
        var seen = Set<String>()
        walk(json) { node in
            guard let dict = node as? [String: Any],
                  let renderer = dict["musicTwoRowItemRenderer"] as? [String: Any],
                  let item = extract(renderer) else { return }
            // YT often returns the same playlist twice (e.g. once in a
            // pinned shelf, once in the grid). De-dup by browseId.
            if seen.insert(item.id).inserted { out.append(item) }
        }
        return out
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let arr = node as? [Any] {
            for value in arr { walk(value, visit: visit) }
        }
    }

    private static func extract(_ renderer: [String: Any]) -> NativeShellViewModel.PlaylistSummary? {
        let title = ((renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .first?["text"] as? String ?? ""
        let browseId = ((renderer["navigationEndpoint"] as? [String: Any])?["browseEndpoint"]
            as? [String: Any])?["browseId"] as? String
        let thumbs = ((renderer["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"]
            as? [String: Any]).flatMap {
                ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            }
        let thumbURL = thumbs?.last?["url"] as? String
        guard let id = browseId, id.hasPrefix("VL"), !title.isEmpty else { return nil }
        return .init(id: id, title: title, thumbnailURL: thumbURL)
    }
}
