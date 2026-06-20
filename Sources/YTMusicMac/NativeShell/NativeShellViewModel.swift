import Foundation
import AppKit
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

    /// A single horizontal carousel on the home/explore page. Title +
    /// the cards inside it.
    struct HomeShelf: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let items: [HomeCard]
    }

    /// Cards in a home shelf. Reuses SearchKind so the click router can
    /// dispatch the same way regardless of where the card came from.
    struct HomeCard: Identifiable, Hashable {
        let id: String        // videoId for songs, browseId for the rest
        let kind: SearchKind
        let title: String
        let subtitle: String
        let thumbnailURL: String?
        /// For songs, the row may include a playlistId so playback inherits
        /// the queue context the shelf is seeded with.
        let playlistId: String?
    }

    /// Which view fills the main content area. Mutually exclusive — the
    /// shell only ever shows one. Drives MainContent's switch.
    /// Defaults to .home so the user lands on recommendations instead of
    /// an empty stage.
    enum MainSection: Equatable {
        case empty
        case home
        case playlist(PlaylistSummary)
        case category(GenreChip)
    }
    @Published private(set) var mainSection: MainSection = .home

    @Published private(set) var categoryPlaylists: [PlaylistSummary] = []
    @Published private(set) var categoryLoading: Bool = false
    @Published private(set) var categoryError: String?
    @Published private(set) var categoryTitle: String = ""

    // MARK: - Navigation history (back/forward, mouse 4/5 friendly)
    private var backStack: [MainSection] = []
    private var forwardStack: [MainSection] = []
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false

    /// Push the CURRENT mainSection onto the back stack so we can return
    /// to it. Caller should invoke this BEFORE mutating mainSection. The
    /// previous version took the value as a parameter and guarded with
    /// `from != mainSection` — but `from` was always the current
    /// mainSection because callers passed it in, so the guard
    /// short-circuited every push and the stack stayed empty.
    private func pushHistory() {
        // De-dup consecutive entries: if the top of the stack already
        // equals where we are, no need to re-push.
        if backStack.last == mainSection { return }
        backStack.append(mainSection)
        if backStack.count > 50 { backStack.removeFirst(backStack.count - 50) }
        forwardStack.removeAll()
        canGoBack = !backStack.isEmpty
        canGoForward = false
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(mainSection)
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
        apply(section: prev)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(mainSection)
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
        apply(section: next)
    }

    /// Restore main view to a history entry. Re-fires the data load for
    /// list-bearing sections so the user sees the right tracks/playlists,
    /// not the last-viewed entity's leftover state.
    private func apply(section: MainSection) {
        mainSection = section
        switch section {
        case .empty: break
        case .home: if !homeLoaded { Task { await loadHome() } }
        case .playlist(let p):
            selectedPlaylist = p
            Task { await loadTracks(for: p) }
        case .category(let g):
            categoryTitle = g.title
            Task { await loadCategory(g) }
        }
    }

    @Published private(set) var homeShelves: [HomeShelf] = []
    @Published private(set) var homeLoading: Bool = false
    @Published private(set) var homeError: String?
    private var homeLoaded: Bool = false

    /// One chip on the moods & genres landing page. Every chip shares the
    /// same browseId (`FEmusic_moods_and_genres_category`) and is only
    /// distinguished by its `params` token — so we use `params` as the
    /// stable id, not the browseId.
    struct GenreChip: Identifiable, Hashable {
        let id: String        // = params, unique per chip
        let title: String
        let params: String
        let browseId: String
        /// Decoded RGBA from the response's `solid.leftStripeColor` int.
        /// YT ships per-category brand colors; we use them as the chip's
        /// background so the grid looks like YT/Spotify's coloured tiles.
        let color: UInt32?
    }

    /// YT splits the page into multiple sections — "Moods & moments",
    /// "Genres", "Decades", etc. Each becomes one horizontal carousel
    /// in Home so the user can scroll a section without it eating
    /// vertical space.
    struct GenreSection: Identifiable {
        let id: String
        let title: String
        let chips: [GenreChip]
    }

    @Published private(set) var genreSections: [GenreSection] = []

    struct QueueItem: Identifiable, Hashable {
        let id: Int        // index — stable per render, matches JS-side index
        let videoId: String?
        let title: String
        let artist: String
        let thumbnailURL: String?
        let isPlaying: Bool
    }

    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var queuePlayingIndex: Int = -1
    @Published var isQueueVisible: Bool = false

    enum SearchKind: String, CaseIterable, Identifiable {
        case playlist, song, artist, album
        var id: String { rawValue }

        /// Title shown in the tab picker.
        var label: String {
            switch self {
            case .playlist: return "Playlists"
            case .song:     return "Songs"
            case .artist:   return "Artists"
            case .album:    return "Albums"
            }
        }

        /// YT's well-known `params` token that scopes /search to one
        /// facet. Lets us pull the full filtered list (vs. the mixed
        /// landing page which caps each shelf at a handful).
        var filterParam: String {
            switch self {
            case .song:     return "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
            case .album:    return "EgWKAQIYAWoKEAkQBRAKEAMQBA=="
            case .artist:   return "EgWKAQIgAWoKEAkQBRAKEAMQBA=="
            case .playlist: return "EgeKAQQoAEABagwQDhAKEAMQBBAJEAU="
            }
        }
    }

    struct SearchResult: Identifiable, Hashable {
        let id: String           // videoId for songs, browseId for the rest
        let kind: SearchKind
        let title: String
        let subtitle: String     // artist for songs, "Album" / "Playlist" / etc. for cards
        let thumbnailURL: String?
    }

    @Published var isSearchVisible: Bool = false
    @Published var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }
    @Published var searchTab: SearchKind = .playlist {
        didSet { scheduleSearch() }
    }
    /// Cached results per (query, tab) so flipping tabs is instant on
    /// re-visit. Cleared on overlay close.
    private var searchCache: [String: [SearchResult]] = [:]
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchLoading: Bool = false
    @Published private(set) var searchError: String?

    private var searchTask: Task<Void, Never>?

    private func cacheKey(query: String, tab: SearchKind) -> String {
        "\(tab.rawValue)|\(query.lowercased())"
    }

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
        pushHistory()
        selectedPlaylist = p
        mainSection = .playlist(p)
        tracks = []
        tracksError = nil
        Task { await loadTracks(for: p) }
    }

    /// Genre / mood chip click — opens a native category page that lists
    /// every playlist YT curates under that mood/genre. The previous
    /// implementation navigated the hidden WebView which the user couldn't
    /// see, so clicks felt broken.
    func openGenre(_ g: GenreChip) {
        pushHistory()
        mainSection = .category(g)
        categoryTitle = g.title
        Task { await loadCategory(g) }
    }

    private func loadCategory(_ g: GenreChip) async {
        guard !categoryLoading else { return }
        categoryLoading = true
        defer { categoryLoading = false }
        categoryPlaylists = []
        categoryError = nil
        do {
            let data = try await client.browse(
                browseId: g.browseId.isEmpty ? "FEmusic_moods_and_genres_category" : g.browseId,
                params: g.params
            )
            let cards = CategoryParser.parse(data: data)
            categoryPlaylists = cards
            categoryError = cards.isEmpty ? "No playlists in this category." : nil
        } catch {
            categoryError = "Couldn't load this category."
        }
    }

    /// Click handler for a home shelf card — routes by kind so each card
    /// type lands in the right place (song plays, playlist opens detail,
    /// album/artist navigate the WebView until they get native views).
    func openHomeCard(_ c: HomeCard) {
        switch c.kind {
        case .song:
            // Include the playlistId when YT gave us one — keeps the
            // shelf's queue context (e.g. "Quick picks" plays through
            // the rest of the shelf instead of starting a fresh radio).
            var urlStr = "https://music.youtube.com/watch?v=\(c.id)"
            if let plid = c.playlistId, !plid.isEmpty {
                urlStr += "&list=\(plid)"
            }
            if let url = URL(string: urlStr) {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        case .playlist:
            let p = PlaylistSummary(id: c.id, title: c.title, thumbnailURL: c.thumbnailURL)
            openPlaylist(p)
        case .album, .artist:
            let urlStr = "https://music.youtube.com/browse/\(c.id)"
            if let url = URL(string: urlStr) {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        }
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

    /// Called by WebViewHolder when the JS bridge pushes a queue update.
    /// Body shape: `{ items: [{title, artist, thumbnail, isPlaying, index}], playingIndex, total }`.
    func updateQueue(from body: [String: Any]) {
        let raw = (body["items"] as? [[String: Any]]) ?? []
        // YT's DOM sometimes marks more than one queue row "selected"
        // (live versions, alt encodings, duplicate cards). The single
        // source of truth is the JS-computed playingIndex — we override
        // each item's isPlaying based on that so only ONE row lights up.
        let playingIdx = (body["playingIndex"] as? Int) ?? -1
        let mapped: [QueueItem] = raw.compactMap { dict in
            let idx = dict["index"] as? Int ?? 0
            let videoId = (dict["videoId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let title = dict["title"] as? String ?? ""
            let artist = dict["artist"] as? String ?? ""
            let thumb = dict["thumbnail"] as? String
            guard !title.isEmpty else { return nil }
            return QueueItem(id: idx, videoId: videoId, title: title, artist: artist,
                             thumbnailURL: thumb, isPlaying: idx == playingIdx)
        }
        queue = mapped
        queuePlayingIndex = playingIdx
    }

    /// Jump playback to the n-th item in the current queue.
    func jumpToQueueIndex(_ index: Int) {
        let js = "window.__ytmJumpQueue && window.__ytmJumpQueue(\(index))"
        WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func toggleQueue() { isQueueVisible.toggle() }

    /// Navigate the (hidden) WebView to a top-level YT Music section.
    /// Used by the sidebar Home / Explore items so the queue context
    /// + autoplay seed line up with what the user is browsing.
    func goHome() {
        pushHistory()
        mainSection = .home
        selectedPlaylist = nil
        // Lazy-load: fetch once per session, refresh on explicit user action.
        if !homeLoaded { Task { await loadHome() } }
    }

    func reloadHome() { Task { await loadHome() } }

    private func loadHome() async {
        guard !homeLoading else { return }
        homeLoading = true
        defer { homeLoading = false }
        // Kick off shelves + genres concurrently so Home arrives fully
        // populated, not in two visible pops.
        async let shelvesTask: [HomeShelf] = {
            do {
                let data = try await self.client.browse(browseId: "FEmusic_home")
                return HomeParser.parse(data: data)
            } catch { return [] }
        }()
        async let genresTask: [GenreSection] = {
            do {
                let data = try await self.client.browse(browseId: "FEmusic_moods_and_genres")
                return GenreParser.parseSections(data: data)
            } catch { return [] }
        }()
        let shelves = await shelvesTask
        let sections = await genresTask
        homeShelves = shelves
        genreSections = sections
        homeError = shelves.isEmpty && sections.isEmpty
            ? "Couldn't load home."
            : nil
        homeLoaded = true
    }

    func goExplore() {
        // Explore is a richer second tab; route to home until it has its
        // own parser. Keeps the sidebar item interactive.
        goHome()
        showToast("Explore native view coming next")
    }

    private func navigateWebView(to urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
    }

    func toggleSearch() {
        isSearchVisible.toggle()
        if !isSearchVisible {
            searchQuery = ""
            searchResults = []
            searchCache.removeAll()
            searchError = nil
            searchTab = .playlist
        }
    }

    /// Debounce typing so we don't fire a /search call per keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchError = nil
            searchLoading = false
            return
        }
        // Cache hit → flip immediately, no network.
        let key = cacheKey(query: query, tab: searchTab)
        if let cached = searchCache[key] {
            searchResults = cached
            searchError = cached.isEmpty ? "No results." : nil
            return
        }
        let tab = searchTab
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(query: query, tab: tab)
        }
    }

    private func runSearch(query: String, tab: SearchKind) async {
        searchLoading = true
        defer { searchLoading = false }
        do {
            // Filtered call — YT returns ALL items in that one facet
            // instead of capping each shelf in the mixed landing response.
            let data = try await client.search(query: query, params: tab.filterParam)
            let parsed = SearchResultsParser.parse(data: data).filter { $0.kind == tab }
            guard !Task.isCancelled else { return }
            // Cache + display only if the user is still looking at this
            // (query, tab) pair — otherwise drop on the floor.
            let key = cacheKey(query: query, tab: tab)
            searchCache[key] = parsed
            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query,
               searchTab == tab {
                searchResults = parsed
                searchError = parsed.isEmpty ? "No results." : nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            searchError = "Search failed"
        }
    }

    /// Route a search result to the right action: songs play, playlists/
    /// albums load in main content, artists navigate the WebView for now.
    func openSearchResult(_ r: SearchResult) {
        switch r.kind {
        case .song:
            let urlStr = "https://music.youtube.com/watch?v=\(r.id)"
            if let url = URL(string: urlStr) {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        case .playlist:
            // Reuse the existing playlist detail flow — drop into a
            // PlaylistSummary so MainContent shows its tracks.
            let p = PlaylistSummary(id: r.id, title: r.title,
                                    thumbnailURL: r.thumbnailURL)
            openPlaylist(p)
        case .album, .artist:
            // Albums browse like playlists (we can load them via /browse),
            // artists are richer. For v0 just navigate the WebView so the
            // queue/play context updates; UI catches up next pass.
            let urlStr = "https://music.youtube.com/browse/\(r.id)"
            if let url = URL(string: urlStr) {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        }
        isSearchVisible = false
        searchQuery = ""
        searchResults = []
        searchCache.removeAll()
    }

    // MARK: - Track actions (context menu)

    /// Toast-style status surfaced after a like / add-to-queue etc. so the
    /// user gets visible feedback even when the action is purely network.
    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    func likeTrack(videoId: String, title: String) {
        Task {
            do {
                _ = try await client.like(videoId: videoId)
                showToast("Liked: \(title)")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Like failed (HTTP \(code))")
            } catch {
                showToast("Like failed")
            }
        }
    }

    func dislikeTrack(videoId: String, title: String) {
        Task {
            do {
                _ = try await client.dislike(videoId: videoId)
                showToast("Disliked: \(title)")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Dislike failed (HTTP \(code))")
            } catch {
                showToast("Dislike failed")
            }
        }
    }

    /// "Add to queue" / "Play next" — placeholder for now. Doing this
    /// properly needs an action token tied to YT's queue continuation
    /// (the actual "..." menu carries it as queueAddEndpoint.params).
    /// We can't synthesize that token from outside; the right fix is
    /// owning the queue model ourselves and chaining videoIds as
    /// /watch?v= navigations on track-end. That's the next big rock.
    func addToQueue(videoId: String, title: String, playNext: Bool = false) {
        showToast("Add to queue — coming soon (own queue model)")
    }

    func addToPlaylist(videoId: String, playlistId: String, trackTitle: String, playlistTitle: String) {
        Task {
            do {
                let bareId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId

                // "Liked Music" is YT's auto-playlist of liked songs. It's
                // not editable via /browse/edit_playlist — the way YT adds
                // a track to it is by calling the like endpoint. Route there
                // so the user sees a real success instead of a useless
                // "not editable" message.
                if bareId == "LM" {
                    _ = try await client.like(videoId: videoId)
                    showToast("Added “\(trackTitle)” to Liked Music")
                    return
                }

                guard bareId.hasPrefix("PL") else {
                    showToast("\(playlistTitle) isn't editable")
                    return
                }
                _ = try await client.addToPlaylist(playlistId: bareId, videoId: videoId)
                showToast("Added “\(trackTitle)” to \(playlistTitle)")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Save failed (HTTP \(code))")
            } catch {
                showToast("Save failed")
            }
        }
    }

    func openInBrowser(videoId: String) {
        let urlStr = "https://music.youtube.com/watch?v=\(videoId)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when the playlist is already in the user's library — i.e.
    /// present in `playlists`. Drives the Save/Remove button toggle.
    func isPlaylistSaved(_ p: PlaylistSummary) -> Bool {
        playlists.contains(where: { $0.id == p.id })
    }

    /// Save a playlist to the user's library. Routes through the like
    /// endpoint with a playlistId target — same primitive YT's own
    /// "Save to library" button uses. Reloads sidebar on success so the
    /// new entry shows up without an explicit refresh tap.
    func savePlaylistToLibrary(_ p: PlaylistSummary) {
        Task {
            do {
                let bareId = p.id.hasPrefix("VL") ? String(p.id.dropFirst(2)) : p.id
                _ = try await client.savePlaylist(playlistId: bareId)
                showToast("Saved “\(p.title)” to library")
                await loadPlaylists()
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Save failed (HTTP \(code))")
            } catch {
                showToast("Save failed")
            }
        }
    }

    /// Inverse of save — drop the playlist from the user's library.
    /// Uses the like/removelike endpoint with a playlistId target.
    func removePlaylistFromLibrary(_ p: PlaylistSummary) {
        Task {
            do {
                let bareId = p.id.hasPrefix("VL") ? String(p.id.dropFirst(2)) : p.id
                _ = try await client.removePlaylist(playlistId: bareId)
                showToast("Removed “\(p.title)” from library")
                await loadPlaylists()
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Remove failed (HTTP \(code))")
            } catch {
                showToast("Remove failed")
            }
        }
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

/// Unified search-response walker. The reason this exists (and replaces
/// the old TrackParser-for-songs + SearchCardParser-for-cards combo):
/// in YT Music search responses, BOTH songs and albums show up as
/// `musicResponsiveListItemRenderer`. Telling them apart by renderer
/// type silently mis-classifies albums as songs.
///
/// Instead we use the first run of the subtitle text — YT writes
/// "Song", "Album", "Artist", "Playlist", "Profile", "Video", "EP",
/// "Single" there. That label is the authoritative type.
enum SearchResultsParser {
    static func parse(data: Data) -> [NativeShellViewModel.SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [NativeShellViewModel.SearchResult] = []
        var seen = Set<String>()
        walk(json) { dict in
            if let r = (dict["musicResponsiveListItemRenderer"] as? [String: Any]),
               let item = extractList(r), seen.insert(item.id).inserted {
                out.append(item)
            }
            if let r = (dict["musicTwoRowItemRenderer"] as? [String: Any]),
               let item = extractCard(r), seen.insert(item.id).inserted {
                out.append(item)
            }
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

    /// Kind from subtitle first-run; fallback to navigationEndpoint shape.
    private static func kind(subtitleFirst: String?,
                             hasVideoId: Bool,
                             browseIdPrefix: String?) -> NativeShellViewModel.SearchKind? {
        let label = subtitleFirst?.lowercased() ?? ""
        switch label {
        case "song", "video", "single", "ep": return .song
        case "album": return .album
        case "playlist", "community playlist", "featured playlist": return .playlist
        case "artist", "profile": return .artist
        default: break
        }
        // Subtitle didn't tell us — infer from id shape.
        if hasVideoId { return .song }
        switch browseIdPrefix {
        case "UC": return .artist
        case "MPRE", "OLAK": return .album
        case "VLPL", "VLRD": return .playlist
        default: return nil
        }
    }

    private static func extractList(_ renderer: [String: Any]) -> NativeShellViewModel.SearchResult? {
        let flex = (renderer["flexColumns"] as? [[String: Any]]) ?? []
        let title = textInFlexColumn(flex, index: 0)
        let subtitle = textInFlexColumn(flex, index: 1)
        let subtitleFirst = firstRunInFlexColumn(flex, index: 1)
        let videoId = (renderer["playlistItemData"] as? [String: Any])?["videoId"] as? String
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
        let watchVideoId = (nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
            ?? (nav?["watchPlaylistEndpoint"] as? [String: Any])?["playlistId"] as? String
        let resolvedVideoId = videoId ?? watchVideoId
        let prefix = browseId.flatMap { String($0.prefix(4)) }
        guard let k = kind(subtitleFirst: subtitleFirst,
                           hasVideoId: resolvedVideoId != nil,
                           browseIdPrefix: prefix) else { return nil }
        let id: String
        if k == .song, let vid = resolvedVideoId {
            id = vid
        } else if let bid = browseId {
            id = bid
        } else { return nil }
        let thumbs = ((renderer["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])
            .flatMap { ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] }
        let thumbURL = thumbs?.last?["url"] as? String
        return .init(id: id, kind: k, title: title, subtitle: subtitle, thumbnailURL: thumbURL)
    }

    private static func textInFlexColumn(_ columns: [[String: Any]], index: Int) -> String {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func firstRunInFlexColumn(_ columns: [[String: Any]], index: Int) -> String? {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return nil }
        return runs.first?["text"] as? String
    }

    private static func extractCard(_ renderer: [String: Any]) -> NativeShellViewModel.SearchResult? {
        let title = ((renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .first?["text"] as? String ?? ""
        let subtitleRuns = ((renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
        let subtitle = subtitleRuns.compactMap { $0["text"] as? String }.joined()
        let subtitleFirst = subtitleRuns.first?["text"] as? String
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
        let watchVideoId = (nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
        let prefix = browseId.flatMap { String($0.prefix(4)) }
        guard let k = kind(subtitleFirst: subtitleFirst,
                           hasVideoId: watchVideoId != nil,
                           browseIdPrefix: prefix) else { return nil }
        let id: String
        if k == .song, let vid = watchVideoId {
            id = vid
        } else if let bid = browseId {
            id = bid
        } else { return nil }
        let thumbs = ((renderer["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])
            .flatMap { ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] }
        let thumbURL = thumbs?.last?["url"] as? String
        guard !title.isEmpty else { return nil }
        return .init(id: id, kind: k, title: title, subtitle: subtitle, thumbnailURL: thumbURL)
    }
}

/// Walks the FEmusic_home browse response and pulls every
/// `musicCarouselShelfRenderer` — one shelf per horizontal carousel on
/// the YT Music home page ("Quick picks", "Listen again",
/// "Mixed for you", "New releases", artist mixes, etc.). Each shelf has
/// a title pulled from its header and a list of HomeCards extracted from
/// either musicTwoRowItemRenderer (artwork-led cards) or
/// musicResponsiveListItemRenderer (song rows).
enum HomeParser {
    static func parse(data: Data) -> [NativeShellViewModel.HomeShelf] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var shelves: [NativeShellViewModel.HomeShelf] = []
        var idx = 0
        walk(json) { dict in
            guard let renderer = dict["musicCarouselShelfRenderer"] as? [String: Any]
            else { return }
            if let shelf = extractShelf(renderer, index: idx) {
                shelves.append(shelf)
                idx += 1
            }
        }
        return shelves
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let arr = node as? [Any] {
            for value in arr { walk(value, visit: visit) }
        }
    }

    private static func extractShelf(_ renderer: [String: Any],
                                     index: Int) -> NativeShellViewModel.HomeShelf? {
        let header = renderer["header"] as? [String: Any]
        let (title, subtitle) = extractHeader(header)
        let contents = (renderer["contents"] as? [[String: Any]]) ?? []
        let cards: [NativeShellViewModel.HomeCard] = contents.compactMap { item in
            if let r = item["musicTwoRowItemRenderer"] as? [String: Any] {
                return extractTwoRow(r)
            }
            if let r = item["musicResponsiveListItemRenderer"] as? [String: Any] {
                return extractList(r)
            }
            return nil
        }
        guard !title.isEmpty, !cards.isEmpty else { return nil }
        return .init(id: "shelf-\(index)-\(title)",
                     title: title,
                     subtitle: subtitle,
                     items: cards)
    }

    /// Carousel headers live behind a `musicCarouselShelfBasicHeaderRenderer`
    /// which has a `title.runs[*].text` for the section name and an
    /// optional `strapline.runs[*].text` (e.g. "Quick picks").
    private static func extractHeader(_ header: [String: Any]?) -> (title: String, subtitle: String?) {
        guard let header = header,
              let basic = header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
        else { return ("", nil) }
        let titleRuns = ((basic["title"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
        let title = titleRuns.compactMap { $0["text"] as? String }.joined()
        let strap = ((basic["strapline"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined()
        return (title, strap?.isEmpty == false ? strap : nil)
    }

    private static func extractTwoRow(_ renderer: [String: Any]) -> NativeShellViewModel.HomeCard? {
        let title = ((renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }.joined() ?? ""
        let subtitleRuns = ((renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
        let subtitle = subtitleRuns.compactMap { $0["text"] as? String }.joined()
        let subtitleFirst = subtitleRuns.first?["text"] as? String

        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browseId = (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
        let watchEndpoint = nav?["watchEndpoint"] as? [String: Any]
        let videoId = watchEndpoint?["videoId"] as? String
        let watchPlaylistId = (nav?["watchPlaylistEndpoint"] as? [String: Any])?["playlistId"] as? String

        let prefix = browseId.flatMap { String($0.prefix(4)) }
        guard let kind = kind(subtitleFirst: subtitleFirst,
                              hasVideoId: videoId != nil,
                              browseIdPrefix: prefix,
                              hasPlaylistEndpoint: watchPlaylistId != nil) else { return nil }
        let id: String
        switch kind {
        case .song: id = videoId ?? watchPlaylistId ?? ""
        default: id = browseId ?? watchPlaylistId ?? ""
        }
        guard !id.isEmpty else { return nil }
        let thumbs = ((renderer["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"]
            as? [String: Any]).flatMap {
                ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            }
        let thumbURL = thumbs?.last?["url"] as? String
        let playlistId = watchEndpoint?["playlistId"] as? String
        return .init(id: id, kind: kind, title: title, subtitle: subtitle,
                     thumbnailURL: thumbURL, playlistId: playlistId)
    }

    private static func extractList(_ renderer: [String: Any]) -> NativeShellViewModel.HomeCard? {
        let flex = (renderer["flexColumns"] as? [[String: Any]]) ?? []
        let title = textInFlexColumn(flex, index: 0)
        let subtitle = textInFlexColumn(flex, index: 1)
        let subtitleFirst = firstRunInFlexColumn(flex, index: 1)
        let videoId = (renderer["playlistItemData"] as? [String: Any])?["videoId"] as? String
        let prefix: String? = nil // list rows are almost always songs here
        guard let kind = kind(subtitleFirst: subtitleFirst,
                              hasVideoId: videoId != nil,
                              browseIdPrefix: prefix,
                              hasPlaylistEndpoint: false) else { return nil }
        guard let vid = videoId, !title.isEmpty else { return nil }
        let thumbs = ((renderer["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"]
            as? [String: Any]).flatMap {
                ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            }
        let thumbURL = thumbs?.last?["url"] as? String
        // Try to inherit the shelf's playlistId for queue context.
        let watch = (renderer["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any]
        let playlistId = watch?["playlistId"] as? String
        return .init(id: vid, kind: kind, title: title, subtitle: subtitle,
                     thumbnailURL: thumbURL, playlistId: playlistId)
    }

    private static func kind(subtitleFirst: String?,
                             hasVideoId: Bool,
                             browseIdPrefix: String?,
                             hasPlaylistEndpoint: Bool) -> NativeShellViewModel.SearchKind? {
        let label = subtitleFirst?.lowercased() ?? ""
        switch label {
        case "song", "video", "single", "ep": return .song
        case "album": return .album
        case "playlist", "community playlist", "featured playlist": return .playlist
        case "artist", "profile": return .artist
        default: break
        }
        if hasVideoId { return .song }
        if hasPlaylistEndpoint { return .playlist }
        switch browseIdPrefix {
        case "UC": return .artist
        case "MPRE", "OLAK": return .album
        case "VLPL", "VLRD": return .playlist
        default: return nil
        }
    }

    private static func textInFlexColumn(_ columns: [[String: Any]], index: Int) -> String {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func firstRunInFlexColumn(_ columns: [[String: Any]], index: Int) -> String? {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return nil }
        return runs.first?["text"] as? String
    }
}

/// Pulls every playlist tile out of a moods/genres category response.
/// The page is structured as a stack of section grids — each contains
/// musicTwoRowItemRenderer entries that point at a playlist via a VLPL
/// or VLRDA browseId.
enum CategoryParser {
    static func parse(data: Data) -> [NativeShellViewModel.PlaylistSummary] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [NativeShellViewModel.PlaylistSummary] = []
        var seen = Set<String>()
        walk(json) { dict in
            guard let renderer = dict["musicTwoRowItemRenderer"] as? [String: Any],
                  let item = extract(renderer),
                  seen.insert(item.id).inserted else { return }
            out.append(item)
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
        guard let id = browseId,
              id.hasPrefix("VL") || id.hasPrefix("MPRE") || id.hasPrefix("OLAK"),
              !title.isEmpty else { return nil }
        return .init(id: id, title: title, thumbnailURL: thumbURL)
    }
}

/// Pulls the genre/mood chips out of the FEmusic_moods_and_genres
/// browse response. YT structures the page as multiple sections —
/// "Moods & moments", "Genres", "Decades", etc. Each section is a
/// `gridRenderer` whose header carries the section title and whose
/// items are `musicNavigationButtonRenderer` chips.
enum GenreParser {
    static func parseSections(data: Data) -> [NativeShellViewModel.GenreSection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var sections: [NativeShellViewModel.GenreSection] = []
        var idx = 0
        walk(json) { dict in
            guard let grid = dict["gridRenderer"] as? [String: Any],
                  let section = extractSection(grid, index: idx) else { return }
            sections.append(section)
            idx += 1
        }
        return sections
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let arr = node as? [Any] {
            for value in arr { walk(value, visit: visit) }
        }
    }

    private static func extractSection(_ grid: [String: Any],
                                       index: Int) -> NativeShellViewModel.GenreSection? {
        let header = (grid["header"] as? [String: Any])?["gridHeaderRenderer"] as? [String: Any]
        let title = ((header?["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined() ?? ""
        let items = (grid["items"] as? [[String: Any]]) ?? []
        let chips = items.compactMap { item -> NativeShellViewModel.GenreChip? in
            guard let r = item["musicNavigationButtonRenderer"] as? [String: Any]
            else { return nil }
            return extractChip(r)
        }
        guard !chips.isEmpty else { return nil }
        return .init(id: "genre-section-\(index)-\(title)",
                     title: title.isEmpty ? "More" : title,
                     chips: chips)
    }

    private static func extractChip(_ renderer: [String: Any]) -> NativeShellViewModel.GenreChip? {
        let title = ((renderer["buttonText"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }.joined() ?? ""
        let browse = (renderer["clickCommand"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
            ?? (renderer["onTapCommand"] as? [String: Any])?["browseEndpoint"] as? [String: Any]
        let browseId = browse?["browseId"] as? String ?? ""
        let params = browse?["params"] as? String ?? ""
        // YT ships per-chip brand colors inside `solid.leftStripeColor`
        // as an int. Used as the chip's background tint so the grid looks
        // like the YT/Spotify colored tile design instead of monochrome.
        let solid = renderer["solid"] as? [String: Any]
        var colorInt: UInt32?
        if let raw = solid?["leftStripeColor"] {
            if let u = raw as? UInt32                          { colorInt = u }
            else if let i = raw as? Int64, let u = UInt32(exactly: i) { colorInt = u }
            else if let i = raw as? Int,   let u = UInt32(exactly: i) { colorInt = u }
            else if let n = raw as? NSNumber                   { colorInt = n.uint32Value }
        }
        guard !title.isEmpty, !params.isEmpty else { return nil }
        return .init(id: params,
                     title: title,
                     params: params,
                     browseId: browseId,
                     color: colorInt)
    }
}

/// Legacy parser kept for the music-card sidebar / playlist landing pages
/// (which only show playlists). New search code uses SearchResultsParser.
enum SearchCardParser {
    static func parse(data: Data) -> [NativeShellViewModel.SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [NativeShellViewModel.SearchResult] = []
        var seen = Set<String>()
        walk(json) { dict in
            guard let renderer = dict["musicTwoRowItemRenderer"] as? [String: Any],
                  let item = extract(renderer) else { return }
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

    private static func extract(_ renderer: [String: Any]) -> NativeShellViewModel.SearchResult? {
        let title = ((renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .first?["text"] as? String ?? ""
        // Subtitle runs can be ["Album", " • ", "Artist"]; we keep the
        // human-readable joined form for display.
        let subtitleRuns = ((renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
        let subtitle = subtitleRuns.compactMap { $0["text"] as? String }.joined()
        let browseId = ((renderer["navigationEndpoint"] as? [String: Any])?["browseEndpoint"]
            as? [String: Any])?["browseId"] as? String
        let thumbs = ((renderer["thumbnailRenderer"] as? [String: Any])?["musicThumbnailRenderer"]
            as? [String: Any]).flatMap {
                ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            }
        let thumbURL = thumbs?.last?["url"] as? String

        guard let id = browseId, !title.isEmpty else { return nil }
        // Categorise by browseId prefix. UC = artist, VLPL = playlist,
        // MPREb / OLAK = album. Mixes (VLRDA…) are surfaced as playlists.
        let kind: NativeShellViewModel.SearchKind
        if id.hasPrefix("UC") {
            kind = .artist
        } else if id.hasPrefix("VLPL") || id.hasPrefix("VLRDA") {
            kind = .playlist
        } else if id.hasPrefix("MPRE") || id.hasPrefix("OLAK") {
            kind = .album
        } else {
            return nil
        }
        return NativeShellViewModel.SearchResult(
            id: id, kind: kind, title: title, subtitle: subtitle, thumbnailURL: thumbURL
        )
    }
}
