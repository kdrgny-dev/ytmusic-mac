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

        /// The "PL..." form used in /watch?list= URLs.
        var playlistURLId: String {
            id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        }
    }

    struct TrackSummary: Identifiable, Hashable {
        let id: String           // videoId
        let title: String
        let artist: String
        let duration: String?
        let thumbnailURL: String?
    }

    @Published private(set) var playlists: [PlaylistSummary] = []
    @Published private(set) var loadingPlaylists = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticated: Bool

    @Published private(set) var selectedPlaylist: PlaylistSummary?
    @Published private(set) var tracks: [TrackSummary] = []
    @Published private(set) var loadingTracks = false
    @Published private(set) var tracksError: String?

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

    /// Show a playlist in the main content area: fetch its tracks via
    /// InnerTube and update state. Does NOT navigate the WebView yet —
    /// that happens when the user actually plays a track, so the audio
    /// engine doesn't reshuffle just because someone clicked a playlist
    /// to look at its contents.
    func openPlaylist(_ p: PlaylistSummary) {
        selectedPlaylist = p
        tracks = []
        tracksError = nil
        Task { await loadTracks(for: p) }
    }

    private func loadTracks(for p: PlaylistSummary) async {
        loadingTracks = true
        defer { loadingTracks = false }
        do {
            let data = try await client.browse(browseId: p.id)
            let parsed = TrackParser.parse(data: data)
            // Guard against a race where the user clicked a different
            // playlist while this one was loading.
            guard selectedPlaylist?.id == p.id else { return }
            tracks = parsed
            tracksError = parsed.isEmpty ? "Empty playlist." : nil
        } catch {
            guard selectedPlaylist?.id == p.id else { return }
            tracksError = "\(error)"
        }
    }

    /// Play a specific track inside the current playlist. We navigate the
    /// hidden WebView to /watch?v=<videoId>&list=<playlistId> so YT's
    /// audio engine treats it as "the user clicked this row" — playback
    /// starts immediately and prev/next stay within the playlist.
    func playTrack(_ t: TrackSummary) {
        guard let p = selectedPlaylist else { return }
        let urlStr = "https://music.youtube.com/watch?v=\(t.id)&list=\(p.playlistURLId)"
        guard let url = URL(string: urlStr) else { return }
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

/// Pulls track rows out of a playlist-detail browse response. Each track
/// lives in a `musicResponsiveListItemRenderer` with flexColumns for the
/// strings and a `playlistItemData.videoId` for the playback ID.
enum TrackParser {
    static func parse(data: Data) -> [NativeShellViewModel.TrackSummary] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [NativeShellViewModel.TrackSummary] = []
        var seen = Set<String>()
        walk(json) { dict in
            guard let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any],
                  let track = extract(renderer) else { return }
            // Same dedup pattern as PlaylistParser — YT often returns the
            // same track in multiple shelves.
            if seen.insert(track.id).inserted { out.append(track) }
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

    private static func extract(_ renderer: [String: Any]) -> NativeShellViewModel.TrackSummary? {
        let flex = (renderer["flexColumns"] as? [[String: Any]]) ?? []
        let fixed = (renderer["fixedColumns"] as? [[String: Any]]) ?? []
        let title = textInFlexColumn(flex, index: 0)
        // Artist + album sometimes share a column with bullet separators;
        // we grab the first run which is the artist name.
        let artist = textInFlexColumn(flex, index: 1)
        let duration = textInFixedColumn(fixed, index: 0)
        let videoId: String? = {
            // Preferred path: playlistItemData.videoId on the row itself.
            if let vid = (renderer["playlistItemData"] as? [String: Any])?["videoId"] as? String {
                return vid
            }
            // Fallback: dig out of the overlay's play-button navigation
            // endpoint. Some YT response variants only carry it there.
            guard let overlay = renderer["overlay"] as? [String: Any],
                  let thumbOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                  let content = thumbOverlay["content"] as? [String: Any],
                  let play = content["musicPlayButtonRenderer"] as? [String: Any],
                  let nav = play["playNavigationEndpoint"] as? [String: Any],
                  let watch = nav["watchEndpoint"] as? [String: Any]
            else { return nil }
            return watch["videoId"] as? String
        }()
        let thumbs = ((renderer["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])
            .flatMap { ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] }
        let thumbURL = thumbs?.last?["url"] as? String

        guard let id = videoId, !title.isEmpty else { return nil }
        return .init(id: id, title: title, artist: artist, duration: duration, thumbnailURL: thumbURL)
    }

    private static func textInFlexColumn(_ columns: [[String: Any]], index: Int) -> String {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func textInFixedColumn(_ columns: [[String: Any]], index: Int) -> String? {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return nil }
        let s = runs.compactMap { $0["text"] as? String }.joined()
        return s.isEmpty ? nil : s
    }
}
