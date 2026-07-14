import Foundation
import AppKit
import Combine
import WebKit

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
        /// YT's second line — usually a description or sample artists.
        var subtitle: String? = nil
        /// Only some shelves carry a "N songs" run; nil when YT omits it.
        var trackCount: Int? = nil

        /// The "PL..." form used in /watch?list= URLs.
        var playlistURLId: String {
            id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        }

        /// Identity is the browseId. The same playlist reaches us from
        /// several shelves with different amounts of metadata, and views
        /// compare instances across those sources (sidebar row vs open page).
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    struct TrackSummary: Identifiable, Hashable {
        let id: String           // videoId
        let title: String
        let artist: String
        let duration: String?
        let thumbnailURL: String?
        var album: String? = nil
        var artistId: String? = nil   // UC… browseId for "Go to artist"
        var albumId: String? = nil    // MPRE…/OLAK… browseId for "Go to album"
        var setVideoId: String? = nil // playlist-entry id, needed to remove the row
    }

    @Published private(set) var playlists: [PlaylistSummary] = []

    /// User's own sidebar ordering, as browseIds. Purely local — YT has no
    /// concept of an ordered playlist library, so there's nothing to sync.
    @Published private(set) var playlistOrder: [String] = []
    private let playlistOrderKey = "pref.playlistOrder"

    /// `playlists` arranged by `playlistOrder`. Playlists created or saved
    /// since the last drag have no rank yet and surface at the top, where
    /// they're easiest to find.
    var orderedPlaylists: [PlaylistSummary] {
        guard !playlistOrder.isEmpty else { return playlists }
        var rank: [String: Int] = [:]
        for (i, id) in playlistOrder.enumerated() { rank[id] = i }
        let ranked = playlists.filter { rank[$0.id] != nil }
                              .sorted { rank[$0.id]! < rank[$1.id]! }
        let unranked = playlists.filter { rank[$0.id] == nil }
        return unranked + ranked
    }

    var hasCustomPlaylistOrder: Bool { !playlistOrder.isEmpty }

    /// Drag-to-reorder: drop the dragged playlist at the target's position.
    func movePlaylist(fromId: String, toId: String) {
        guard fromId != toId else { return }
        var ids = orderedPlaylists.map(\.id)
        guard let from = ids.firstIndex(of: fromId) else { return }
        let moved = ids.remove(at: from)
        let to = ids.firstIndex(of: toId) ?? ids.count
        ids.insert(moved, at: to)
        playlistOrder = ids
        UserDefaults.standard.set(ids, forKey: playlistOrderKey)
    }

    /// Back to whatever order YT hands us.
    func resetPlaylistOrder() {
        playlistOrder = []
        UserDefaults.standard.removeObject(forKey: playlistOrderKey)
        showToast("Sıralama sıfırlandı")
    }

    @Published private(set) var loadingPlaylists = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticated: Bool

    @Published private(set) var selectedPlaylist: PlaylistSummary?
    @Published private(set) var tracks: [TrackSummary] = []
    @Published private(set) var loadingTracks = false
    @Published private(set) var tracksError: String?

    /// The `list=` value that makes /watch build a queue for `selectedPlaylist`.
    /// Usually just its bare id, but albums browse under MPRE… and play under
    /// OLAK5uy… — see `loadTracks`.
    private var watchPlaylistId: String?

    /// browseId of the collection the current track is playing out of, so the
    /// sidebar can mark the row the user is listening to. Nil once playback
    /// leaves it (radio, a queued track, a song card).
    @Published private(set) var nowPlayingCollectionId: String?

    /// True when `p` is the collection currently feeding the player.
    func isNowPlayingCollection(_ p: PlaylistSummary) -> Bool {
        nowPlayingCollectionId == p.id
    }

    /// Album library (save/unsave) state for the currently-open album.
    @Published private(set) var isAlbumSaved: Bool = false
    private var albumAddToken: String?
    private var albumRemoveToken: String?

    func isAlbumId(_ id: String) -> Bool { id.hasPrefix("MPRE") || id.hasPrefix("OLAK") }

    /// Toggle the open album in/out of the library via its feedback token.
    func toggleAlbumSaved() {
        let token = isAlbumSaved ? albumRemoveToken : albumAddToken
        guard let token else { showToast("Bu albüm kaydedilemiyor"); return }
        let willSave = !isAlbumSaved
        isAlbumSaved = willSave
        Task {
            do {
                _ = try await client.sendFeedback(token: token)
                showToast(willSave ? "Albüm kitaplığa eklendi" : "Albüm kitaplıktan çıkarıldı")
                await loadPlaylists() // refresh sidebar
            } catch {
                isAlbumSaved = !willSave // revert on failure
                showToast("İşlem başarısız")
            }
        }
    }

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
        case explore
        case history
        case statistics
        case search
        case playlist(PlaylistSummary)
        case category(GenreChip)
        case artist(String)   // browseId; full data lives in artistDetail
    }

    /// Multi-shelf artist page. Built by ArtistParser from a /browse UC…
    /// response. Reuses HomeCard for album/single carousels and
    /// TrackSummary for the top-songs list so the views can reuse
    /// existing rendering.
    struct ArtistDetail: Equatable {
        let id: String
        let name: String
        let thumbnailURL: String?
        let subscriberText: String?
        let topSongs: [TrackSummary]
        let albums: [HomeCard]
        let singles: [HomeCard]
        var allSongsBrowseId: String? = nil // VL… playlist with the artist's full songs
    }

    @Published private(set) var artistDetail: ArtistDetail?
    @Published private(set) var artistLoading: Bool = false
    @Published private(set) var artistError: String?

    /// Lyrics side panel — mirrors the queue panel pattern (right side,
    /// toggleable). Mutually exclusive with isQueueVisible so the right
    /// column never tries to show both at once.
    @Published var isLyricsVisible: Bool = false
    @Published private(set) var lyrics: LyricsParser.Lyrics?
    @Published private(set) var lyricsLoading: Bool = false
    @Published private(set) var lyricsError: String?
    /// videoId we last fetched lyrics for, so we don't refetch on
    /// every onAppear when the same track is still playing.
    private var lyricsLoadedFor: String?
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
        case .explore: if !exploreLoaded { Task { await loadExplore() } }
        case .history: Task { await loadHistory() }
        case .statistics: loadStatistics()
        case .search: break
        case .playlist(let p):
            selectedPlaylist = p
            Task { await loadTracks(for: p) }
        case .category(let g):
            categoryTitle = g.title
            Task { await loadCategory(g) }
        case .artist(let id):
            Task { await loadArtist(browseId: id, title: artistDetail?.name ?? "") }
        }
    }

    /// Open an artist page from just a name (e.g. the player bar). We don't
    /// have the artist browseId there, so search the artist facet and open
    /// the first match.
    func openArtistByName(_ rawName: String) {
        // Take the primary artist if YT joined several with separators.
        let name = rawName
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawName
        guard !name.isEmpty else { return }
        Task {
            do {
                let data = try await client.search(query: name, params: SearchKind.artist.filterParam)
                let results = SearchResultsParser.parse(data: data).filter { $0.kind == .artist }
                guard let first = results.first else { showToast("Sanatçı bulunamadı"); return }
                openArtist(browseId: first.id, name: first.title)
            } catch {
                showToast("Sanatçı açılamadı")
            }
        }
    }

    /// Open a native artist page. Same history flow as openPlaylist.
    func openArtist(browseId: String, name: String) {
        pushHistory()
        mainSection = .artist(browseId)
        artistDetail = nil
        artistError = nil
        Task { await loadArtist(browseId: browseId, title: name) }
    }

    /// Bumped on every artist load so a fast A→B navigation lets only the
    /// latest request write results / clear the spinner. The old
    /// `guard !artistLoading` dropped the second navigation entirely,
    /// leaving a permanently blank artist page.
    private var artistRequestID = 0

    private func loadArtist(browseId: String, title: String) async {
        artistRequestID += 1
        let reqID = artistRequestID
        artistLoading = true
        defer { if reqID == artistRequestID { artistLoading = false } }
        do {
            let data = try await client.browse(browseId: browseId)
            let parsed = ArtistParser.parse(data: data, browseId: browseId)
            guard reqID == artistRequestID else { return }
            artistDetail = parsed
            artistError = parsed == nil ? "\(title.isEmpty ? "Sanatçı" : title) yüklenemedi." : nil
        } catch {
            guard reqID == artistRequestID else { return }
            noteFailure(error)
            artistError = "Sanatçı yüklenemedi."
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

    // MARK: Explore

    /// A ranked chart shelf — "Top songs", "Top music videos", "Trending".
    /// Reuses TrackSummary so it renders with the same row component, the
    /// position in `tracks` being the rank.
    struct ChartSection: Identifiable {
        let id: String
        let title: String
        let tracks: [TrackSummary]
    }

    @Published private(set) var exploreNewReleases: [HomeShelf] = []
    @Published private(set) var exploreCharts: [ChartSection] = []
    @Published private(set) var exploreLoading: Bool = false
    @Published private(set) var exploreError: String?
    private var exploreLoaded: Bool = false

    /// Listening history, grouped by YT's own day headers ("Today", "Bugün",
    /// "Last week"…). Unlike home/explore this is refetched on every visit —
    /// a stale history is worse than a slow one.
    @Published private(set) var historySections: [ChartSection] = []
    @Published private(set) var historyLoading: Bool = false
    @Published private(set) var historyError: String?

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

    /// User-managed queue. Independent of YT's internal queue — when the
    /// current track ends, we navigate the (hidden) WebView to the next
    /// videoId from this list. Lets Add to queue / Play next work for
    /// real without depending on YT's brittle internal API.
    struct OwnQueueItem: Identifiable, Hashable {
        let id: UUID = UUID()
        let videoId: String
        let title: String
        let artist: String
        let thumbnailURL: String?
    }
    @Published private(set) var ownQueue: [OwnQueueItem] = []

    enum SearchKind: String, CaseIterable, Identifiable {
        case playlist, song, artist, album
        var id: String { rawValue }

        /// Title shown in the tab picker.
        var label: String {
            switch self {
            case .playlist: return "Çalma listeleri"
            case .song:     return "Şarkılar"
            case .artist:   return "Sanatçılar"
            case .album:    return "Albümler"
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

    /// Track counts for playlist search results, keyed by browseId. The
    /// /search response never carries a song count for playlists (only
    /// "author • N views"), so we lazily browse each visible playlist row
    /// and pull the count from its header. Cached so we browse once per id.
    @Published private(set) var playlistTrackCounts: [String: Int] = [:]
    private var trackCountInFlight: Set<String> = []

    /// Kick off a one-shot header browse for a playlist search row (called
    /// as rows appear). No-op for non-playlists or ids we already have /
    /// are already fetching.
    func fetchPlaylistTrackCount(for result: SearchResult) {
        guard result.kind == .playlist else { return }
        let id = result.id
        guard playlistTrackCounts[id] == nil, !trackCountInFlight.contains(id) else { return }
        trackCountInFlight.insert(id)
        Task { @MainActor in
            defer { trackCountInFlight.remove(id) }
            guard let data = try? await client.browse(browseId: id),
                  let count = PlaylistHeaderParser.trackCount(data: data) else { return }
            playlistTrackCounts[id] = count
        }
    }

    /// Autocomplete for whatever is in the search field. Tab-independent —
    /// YT suggests queries, not results — so it survives tab flips.
    @Published private(set) var searchSuggestions: [String] = []
    private var suggestTask: Task<Void, Never>?

    private func scheduleSuggestions(for query: String) {
        suggestTask?.cancel()
        guard query.count >= 2 else { searchSuggestions = []; return }
        suggestTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            guard let data = try? await client.searchSuggestions(query: query) else { return }
            guard !Task.isCancelled else { return }
            // Drop the suggestion that only restates what's already typed.
            searchSuggestions = SearchSuggestionsParser.parse(data: data)
                .filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        }
    }

    /// Recent search queries (most-recent first), persisted across launches.
    @Published private(set) var searchHistory: [String] = []
    private let searchHistoryKey = "pref.searchHistory"
    private let searchHistoryLimit = 12

    func recordSearch(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var h = searchHistory.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        h.insert(q, at: 0)
        if h.count > searchHistoryLimit { h = Array(h.prefix(searchHistoryLimit)) }
        searchHistory = h
        UserDefaults.standard.set(h, forKey: searchHistoryKey)
    }

    func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: searchHistoryKey)
    }

    /// Re-run a tapped recent query (didSet on searchQuery schedules it).
    func applyRecentSearch(_ q: String) { searchQuery = q }

    private var searchTask: Task<Void, Never>?

    private func cacheKey(query: String, tab: SearchKind) -> String {
        "\(tab.rawValue)|\(query.lowercased())"
    }

    private let auth = AuthSession()
    private let client: InnerTubeClient

    // MARK: - Failure banner

    /// A condition that breaks the whole app rather than one page, so it gets
    /// a persistent bar instead of an inline "couldn't load" string.
    enum Banner: Equatable {
        case offline
        case signedOut

        var message: String {
            switch self {
            case .offline:  return "İnternet bağlantısı yok."
            case .signedOut: return "YT Music oturumun düşmüş. Kitaplığın ve beğenilerin yüklenemiyor."
            }
        }

        var actionTitle: String {
            switch self {
            case .offline:  return "Yeniden dene"
            case .signedOut: return "Giriş yap"
            }
        }
    }

    @Published private(set) var banner: Banner?

    /// Classify a failed InnerTube call. Page-level errors (a bad browseId, an
    /// empty shelf) stay inline — only app-wide breakage raises the bar.
    func noteFailure(_ error: Error) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .dataNotAllowed, .cannotConnectToHost, .timedOut:
                banner = .offline
            default:
                break
            }
            return
        }
        if case InnerTubeClient.APIError.httpStatus(let code, _) = error, code == 401 || code == 403 {
            banner = .signedOut
        }
    }

    /// Any successful call proves both conditions are over.
    func noteSuccess() {
        if banner != nil { banner = nil }
    }

    /// The banner's action button.
    func resolveBanner() {
        switch banner {
        case .offline:
            banner = nil
            retryCurrentSection()
        case .signedOut:
            // The sign-in flow lives in YT's own web UI, which Native Mode
            // hides. Drop back to it; the user can flip the mode back on.
            banner = nil
            Preferences.shared.nativeUIMode = false
            if let url = URL(string: "https://music.youtube.com/") {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        case nil:
            break
        }
    }

    /// Refetch whatever the main area is showing.
    func retryCurrentSection() {
        reload()
        switch mainSection {
        case .home:     reloadHome()
        case .explore:  reloadExplore()
        case .history:  reloadHistory()
        case .statistics: loadStatistics()
        case .search:   break
        case .category(let g): Task { await loadCategory(g) }
        case .artist(let id):  Task { await loadArtist(browseId: id, title: artistDetail?.name ?? "") }
        case .playlist(let p): Task { await loadTracks(for: p) }
        case .empty:    break
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.client = InnerTubeClient(auth: auth)
        self.isAuthenticated = auth.isAuthenticated
        self.searchHistory = UserDefaults.standard.stringArray(forKey: searchHistoryKey) ?? []
        self.playlistOrder = UserDefaults.standard.stringArray(forKey: playlistOrderKey) ?? []

        // Lyrics used to be fetched only when a lyrics surface was opened, so
        // they stayed pinned to whatever track was playing at that moment.
        MediaController.shared.$nowPlaying
            .map(\.videoId)
            .removeDuplicates()
            .sink { [weak self] videoId in
                Task { @MainActor in self?.currentTrackChanged(to: videoId) }
            }
            .store(in: &cancellables)

        // Reachability beats inferring offline from a failed request: a page
        // with cached content would otherwise look healthy.
        ConnectionMonitor.shared.$isOnline
            .removeDuplicates()
            .sink { [weak self] online in
                Task { @MainActor in
                    guard let self else { return }
                    if online {
                        if self.banner == .offline { self.banner = nil }
                    } else {
                        self.banner = .offline
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func currentTrackChanged(to videoId: String) {
        refreshQueue(for: videoId)
        guard lyricsLoadedFor != videoId else { return }
        lyrics = nil
        lyricsError = nil
        lyricsLoadedFor = nil
        // Refetch right away when the user is looking at lyrics; otherwise the
        // reset above is enough and the next open pulls the new track's words.
        guard !videoId.isEmpty, isLyricsVisible || isNowPlayingVisible else { return }
        loadLyricsForCurrentTrack()
    }

    /// Test-only setter for the sidebar playlist list. We need this
    /// because the real path goes through loadPlaylists -> network and
    /// tests need to inject fixed data deterministically.
    internal func _testSetPlaylists(_ list: [PlaylistSummary]) {
        self.playlists = list
    }

    /// Test-only state reset. Test target sees this via @testable import.
    /// Production code never calls it.
    internal func _testReset() {
        playlists = []
        selectedPlaylist = nil
        tracks = []
        loadingTracks = false
        tracksError = nil
        ownQueue = []
        queue = []
        domQueue = []
        queueContextId = nil
        queuePlayingIndex = -1
        mainSection = .home
        backStack = []
        forwardStack = []
        canGoBack = false
        canGoForward = false
        homeShelves = []
        homeLoading = false
        homeError = nil
        homeLoaded = false
        genreSections = []
        exploreNewReleases = []
        exploreCharts = []
        exploreLoading = false
        exploreError = nil
        exploreLoaded = false
        historySections = []
        historyLoading = false
        historyError = nil
        categoryPlaylists = []
        categoryLoading = false
        categoryError = nil
        categoryTitle = ""
        artistDetail = nil
        artistLoading = false
        artistError = nil
        banner = nil
        isLyricsVisible = false
        lyrics = nil
        lyricsLoading = false
        lyricsError = nil
        lyricsLoadedFor = nil
        searchQuery = ""
        searchResults = []
        searchLoading = false
        searchError = nil
        searchCache.removeAll()
        searchTab = .playlist
        isQueueVisible = false
        toast = nil
        toastTask?.cancel()
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
            errorMessage = "Kitaplığını görmek için YT Music'e giriş yap."
            return
        }
        loadingPlaylists = true
        defer { loadingPlaylists = false }
        do {
            // FEmusic_liked_playlists is the YT Music "playlists you own /
            // liked" landing page — same data backing the web sidebar.
            let data = try await client.browse(browseId: "FEmusic_liked_playlists")
            playlists = PlaylistParser.parse(data: data)
            errorMessage = playlists.isEmpty ? "Henüz çalma listen yok." : nil
            noteSuccess()
        } catch {
            noteFailure(error)
            errorMessage = "Kitaplık yüklenemedi."
        }
    }

    /// Show a playlist in the main content area: fetch its tracks via
    /// InnerTube and update state. Does NOT navigate the WebView yet —
    /// that happens when the user actually plays a track, so the audio
    /// engine doesn't reshuffle just because someone clicked a playlist
    /// to look at its contents.
    func openPlaylist(_ p: PlaylistSummary, autoplay: Bool = false) {
        pushHistory()
        selectedPlaylist = p
        mainSection = .playlist(p)
        tracks = []
        tracksError = nil
        watchPlaylistId = nil
        Task { await loadTracks(for: p, autoplay: autoplay) }
    }

    /// Play a whole collection (playlist/album) without leaving the current
    /// page — opens it and starts from the first track. Used by the hover
    /// play button on home/explore cards and the collection context menus.
    func playHomeCard(_ c: HomeCard) {
        switch c.kind {
        case .song:
            openHomeCard(c) // song branch already starts playback
        case .playlist, .album:
            let p = PlaylistSummary(id: c.id, title: c.title, thumbnailURL: c.thumbnailURL)
            openPlaylist(p, autoplay: true)
        case .artist:
            openArtist(browseId: c.id, name: c.title)
        }
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

    /// See `artistRequestID` — same fix. The old guard both dropped the
    /// second chip's load AND (having no staleness check on completion) let
    /// a stale response overwrite the newer category's playlists.
    private var categoryRequestID = 0

    private func loadCategory(_ g: GenreChip) async {
        categoryRequestID += 1
        let reqID = categoryRequestID
        categoryLoading = true
        defer { if reqID == categoryRequestID { categoryLoading = false } }
        categoryPlaylists = []
        categoryError = nil
        do {
            let data = try await client.browse(
                browseId: g.browseId.isEmpty ? "FEmusic_moods_and_genres_category" : g.browseId,
                params: g.params
            )
            let cards = CategoryParser.parse(data: data)
            guard reqID == categoryRequestID else { return }
            categoryPlaylists = cards
            categoryError = cards.isEmpty ? "Bu kategoride çalma listesi yok." : nil
        } catch {
            guard reqID == categoryRequestID else { return }
            noteFailure(error)
            categoryError = "Bu kategori yüklenemedi."
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
                nowPlayingCollectionId = nil
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        case .playlist, .album:
            // Albums use the same PlaylistDetail flow — their browse
            // response is the same track-list shape under the hood. The
            // view decides whether to label the header "ALBUM" or
            // "PLAYLIST" from the id prefix.
            let p = PlaylistSummary(id: c.id, title: c.title, thumbnailURL: c.thumbnailURL)
            openPlaylist(p)
        case .artist:
            openArtist(browseId: c.id, name: c.title)
        }
    }

    // MARK: Library (saved albums + followed artists)

    @Published private(set) var savedAlbums: [PlaylistSummary] = []
    @Published private(set) var followedArtists: [PlaylistSummary] = []

    func loadLibraryIfNeeded() {
        Task { await loadLibrary() }
    }

    private func loadLibrary() async {
        guard auth.isAuthenticated else { return }
        async let albumsTask: [PlaylistSummary] = {
            do { return LibraryParser.parse(data: try await self.client.browse(browseId: "FEmusic_liked_albums"),
                                            prefixes: ["MPRE", "OLAK"]) }
            catch { return [] }
        }()
        async let artistsTask: [PlaylistSummary] = {
            do { return LibraryParser.parse(data: try await self.client.browse(browseId: "FEmusic_library_corpus_artists"),
                                            prefixes: ["UC"]) }
            catch { return [] }
        }()
        savedAlbums = await albumsTask
        followedArtists = await artistsTask
    }

    private func loadTracks(for p: PlaylistSummary, autoplay: Bool = false) async {
        loadingTracks = true
        defer { loadingTracks = false }
        do {
            let data = try await client.browse(browseId: p.id)
            var all = TrackParser.parse(data: data)
            // Guard against a race where the user clicked a different
            // playlist while this one was loading.
            guard selectedPlaylist?.id == p.id else { return }
            tracks = all
            tracksError = all.isEmpty ? "Bu liste boş." : nil
            // An album's browseId (MPRE…) is not a valid /watch?list= value,
            // so YT would drop the queue and leave Next dead. Its real
            // playlist (OLAK5uy_…) is in the browse response — dig it out
            // before anything can start playing.
            if isAlbumId(p.id) {
                watchPlaylistId = WatchPlaylistIdParser.playlistId(data: data)
                let tk = AlbumLibraryParser.tokens(data: data)
                albumAddToken = tk.add
                albumRemoveToken = tk.remove
                isAlbumSaved = false // best-effort: assume not saved until toggled
            } else {
                watchPlaylistId = p.playlistURLId
                albumAddToken = nil; albumRemoveToken = nil; isAlbumSaved = false
            }
            // Hover "play" on a card: kick off the first track right away
            // (don't wait for the remaining pages to paginate in).
            if autoplay, let first = all.first { playTrack(first) }
            // Paginate: YT returns ~100 rows per page. Keep pulling while a
            // real track-list continuation token exists. Append progressively
            // so the list grows in front of the user. Capped to avoid runaway.
            var seen = Set(all.map { $0.id })
            var token = TrackParser.continuationToken(data: data)
            var rounds = 0
            while let t = token, all.count < 1000, rounds < 20 {
                rounds += 1
                guard let cdata = try? await client.continuation(token: t) else { break }
                guard selectedPlaylist?.id == p.id else { return }
                let page = TrackParser.parse(data: cdata).filter { seen.insert($0.id).inserted }
                token = TrackParser.continuationToken(data: cdata)
                if page.isEmpty { break }
                all.append(contentsOf: page)
                tracks = all
            }
        } catch {
            guard selectedPlaylist?.id == p.id else { return }
            noteFailure(error)
            tracksError = "Şarkılar yüklenemedi."
        }
    }

    /// Play a specific track inside the current playlist. We navigate the
    /// hidden WebView to /watch?v=<videoId>&list=<playlistId> so YT's
    /// audio engine treats it as "the user clicked this row" — playback
    /// starts immediately and prev/next stay within the playlist.
    func playTrack(_ t: TrackSummary) {
        // Charts, history and other list-less surfaces have no open playlist
        // to play "inside of" — used to silently do nothing.
        guard let p = selectedPlaylist else { playStandaloneTrack(t); return }
        var urlStr = "https://music.youtube.com/watch?v=\(t.id)"
        // Omitting `list` beats sending a bogus one: YT then seeds an
        // autoplay queue instead of loading a dead single-track page.
        if let list = watchPlaylistId, !list.isEmpty {
            urlStr += "&list=\(list)"
        }
        guard let url = URL(string: urlStr) else { return }
        nowPlayingCollectionId = p.id
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
    }

    /// Play one track with no list context. YT seeds its own autoplay queue
    /// from it, so Next still works.
    func playStandaloneTrack(_ t: TrackSummary) {
        guard let url = URL(string: "https://music.youtube.com/watch?v=\(t.id)") else { return }
        nowPlayingCollectionId = nil
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
    }

    /// Start an endless radio seeded by this track. YT Music's radio for a
    /// song lives at the well-known `RDAMVM<videoId>` playlist, so we just
    /// navigate the WebView to /watch?v=<id>&list=RDAMVM<id> — YT fills the
    /// queue with an auto-generated mix and starts playing.
    func startRadio(_ t: TrackSummary) {
        let urlStr = "https://music.youtube.com/watch?v=\(t.id)&list=RDAMVM\(t.id)"
        guard let url = URL(string: urlStr) else { return }
        nowPlayingCollectionId = nil
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
        showToast("Radyo başlatılıyor")
    }

    // MARK: - Similar-track playlist (Last.fm)

    private let lastfm = LastfmClient()

    /// Progress through the build, driving the overlay's animation.
    enum SimilarStage: Equatable {
        case form                          // naming / privacy, before we start
        case fetching                      // asking Last.fm
        case matching(done: Int, total: Int)
        case creating                      // writing the YT playlist
        case done(count: Int)              // success — waiting for the user's OK
    }

    /// Non-nil while the "similar playlist" overlay is up; carries the seed.
    @Published private(set) var similarSeed: TrackSummary?
    @Published private(set) var similarStage: SimilarStage = .form
    /// The finished list, held until the user taps "Tamam" so we open it then.
    private var pendingSimilarSummary: PlaylistSummary?
    /// Its tracks (from the matching step), so the page renders without waiting.
    private var pendingSimilarTracks: [TrackSummary] = []
    /// A sensible default the overlay pre-fills; the user can edit it.
    var similarDefaultTitle: String {
        guard let s = similarSeed else { return "" }
        return "\(s.title) — Benzerler"
    }

    /// Open the naming overlay. The heavy work waits for `confirmSimilarPlaylist`.
    func startSimilarPlaylist(seed: TrackSummary) {
        guard auth.isAuthenticated else { showToast("Liste için YT Music'e giriş yap"); return }
        guard lastfm.isConfigured else { showToast("Last.fm anahtarı ayarlı değil"); return }
        guard !ArtistName.primary(seed.artist).isEmpty, !seed.title.isEmpty else {
            showToast("Bu parça için liste yapılamıyor"); return
        }
        similarStage = .form
        similarSeed = seed
    }

    func cancelSimilarPlaylist() {
        // Only dismissable from the form step; a build in flight keeps running.
        guard similarStage == .form else { return }
        similarSeed = nil
    }

    /// "Tamam" on the success card: close the overlay and NOW open the list
    /// (without playing it). Deferring the open to here also gives YT a few
    /// seconds to index the new playlist, so its tracks actually load.
    func finishSimilarPlaylist() {
        guard case .done = similarStage else { return }
        let summary = pendingSimilarSummary
        let known = pendingSimilarTracks
        pendingSimilarSummary = nil
        pendingSimilarTracks = []
        similarSeed = nil
        if let summary { openCreatedPlaylist(summary, known: known) }
    }

    /// The real work: Last.fm → match → PERMANENT playlist → play it. Unlike
    /// `startRadio` this IS a saved playlist. Recommendations come from Last.fm
    /// (community data), not YT's opaque radio — the whole point.
    func confirmSimilarPlaylist(title: String, privacy: PlaylistPrivacy) {
        guard let seed = similarSeed else { return }
        let artist = ArtistName.primary(seed.artist)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? similarDefaultTitle
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        similarStage = .fetching
        Task {
            let candidates = await lastfm.recommendations(artist: artist, track: seed.title, target: 30)
            guard !candidates.isEmpty else {
                similarSeed = nil; showToast("Benzer parça bulunamadı"); return
            }

            similarStage = .matching(done: 0, total: candidates.count)
            let matched = await matchToTracks(candidates) { [weak self] done, total in
                self?.similarStage = .matching(done: done, total: total)
            }

            // Seed leads; YT's DEDUPE_OPTION_SKIP backs this up, but dedup here
            // too so the seed can't reappear and the count stays honest. Keep
            // the full TrackSummary so the list can render before YT indexes it.
            var chosen = [seed]
            var seen: Set<String> = [seed.id]
            for t in matched where !seen.contains(t.id) { seen.insert(t.id); chosen.append(t) }
            guard chosen.count > 1 else {
                similarSeed = nil; showToast("Eşleşen parça bulunamadı"); return
            }
            let ids = chosen.map(\.id)

            similarStage = .creating
            do {
                // createPlaylist takes an initial batch; the rest follows in an edit.
                let head = Array(ids.prefix(90))
                let tail = Array(ids.dropFirst(90))
                guard let playlistId = try await client.createPlaylist(
                    title: name,
                    description: "\(seed.title) • \(artist) — Last.fm benzerleri",
                    privacy: privacy.rawValue,
                    videoIds: head)
                else { similarSeed = nil; showToast("Liste oluşturulamadı"); return }

                if !tail.isEmpty {
                    _ = try? await client.addToPlaylist(playlistId: playlistId, videoIds: tail)
                }

                let summary = PlaylistSummary(id: playlistId, title: name,
                                              thumbnailURL: seed.thumbnailURL)
                // Optimistic: YT's library index lags a few seconds behind
                // create, so drop it into the sidebar now instead of waiting.
                if !playlists.contains(where: { $0.id == playlistId }) {
                    playlists.insert(summary, at: 0)
                }
                // Hold the list AND its tracks; "Tamam" opens it. Don't play —
                // the user asked to just save, not start playback.
                pendingSimilarSummary = summary
                pendingSimilarTracks = chosen
                similarStage = .done(count: chosen.count)
                Task { await loadPlaylists() }  // reconcile with the server later
            } catch {
                similarSeed = nil; showToast("Liste oluşturulamadı")
            }
        }
    }

    /// Open a just-created playlist natively (no playback). We already know its
    /// tracks from the matching step, so render them immediately — no waiting
    /// on YT's index, no "Şarkılar yüklenemedi". Then reconcile in the
    /// background so setVideoId/duration fill in (needed to remove/reorder).
    private func openCreatedPlaylist(_ p: PlaylistSummary, known: [TrackSummary]) {
        pushHistory()
        selectedPlaylist = p
        mainSection = .playlist(p)
        tracks = known
        tracksError = nil
        loadingTracks = false
        watchPlaylistId = p.playlistURLId
        Task {
            for delaySec in [2.0, 3.0, 5.0, 8.0] {
                try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
                guard selectedPlaylist?.id == p.id else { return } // user navigated away
                if let data = try? await client.browse(browseId: p.id) {
                    let real = TrackParser.parse(data: data)
                    if !real.isEmpty, selectedPlaylist?.id == p.id {
                        tracks = real   // now with setVideoId + durations
                        return
                    }
                }
            }
        }
    }

    /// Resolve each Last.fm candidate to a YouTube videoId via InnerTube song
    /// search, ~6 lookups at a time (a friendly cap for YT). Preserves the
    /// candidates' score order and drops the ones with no match. `onProgress`
    /// fires after each batch so the overlay can count up.
    private func matchToTracks(_ candidates: [SimilarCandidate],
                               onProgress: @escaping (Int, Int) -> Void) async -> [TrackSummary] {
        let indexed = Array(candidates.enumerated())
        let total = indexed.count
        var found: [(Int, TrackSummary)] = []
        var completed = 0
        let batch = 6
        var i = 0
        while i < indexed.count {
            let slice = indexed[i..<min(i + batch, indexed.count)]
            let part = await withTaskGroup(of: (Int, TrackSummary?).self) { group -> [(Int, TrackSummary)] in
                for (idx, cand) in slice {
                    group.addTask { [self] in
                        (idx, await firstSongMatch(artist: cand.artist, track: cand.track))
                    }
                }
                var acc: [(Int, TrackSummary)] = []
                for await (idx, t) in group { if let t { acc.append((idx, t)) } }
                return acc
            }
            found.append(contentsOf: part)
            completed += slice.count
            onProgress(completed, total)
            i += batch
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The full search hit, not just its id — we keep title/artist/thumbnail so
    /// the new playlist renders instantly, without waiting for YT to index it.
    private func firstSongMatch(artist: String, track: String) async -> TrackSummary? {
        guard let data = try? await client.search(query: "\(artist) \(track)",
                                                  params: SearchKind.song.filterParam),
              let r = SearchResultsParser.parse(data: data).first(where: { $0.kind == .song })
        else { return nil }
        return TrackSummary(id: r.id, title: r.title, artist: r.subtitle,
                            duration: nil, thumbnailURL: r.thumbnailURL)
    }

    /// Called by WebViewHolder when the JS bridge pushes a queue update.
    /// Body shape: `{ items: [{title, artist, thumbnail, isPlaying, index}], playingIndex, total }`.
    /// The DOM scrape is now only a safety net: if `/next` gives us nothing
    /// for this queue shape, we show whatever the page managed to render.
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
        domQueue = mapped
        if queue.isEmpty {
            queue = mapped
            queuePlayingIndex = playingIdx
        }
    }

    /// Last DOM-scraped queue, kept as the fallback for `/next` misses.
    private var domQueue: [QueueItem] = []
    /// The `list=` the current `queue` was built for. nil means "autoplay mix
    /// seeded by one video", which is regenerated per track.
    private var queueContextId: String?
    private var queueTask: Task<Void, Never>?

    /// Rebuild the queue from `/next` when the player moved somewhere the
    /// current queue doesn't cover. Staying inside the same list is a no-op —
    /// the rows don't change, only which one is highlighted, and the view
    /// derives that from `nowPlaying.videoId`.
    private func refreshQueue(for videoId: String) {
        guard !videoId.isEmpty else { return }
        let list = currentWatchListId()
        let sameContext = (list != nil && list == queueContextId)
        if sameContext, queue.contains(where: { $0.videoId == videoId }) { return }

        queueTask?.cancel()
        queueTask = Task { @MainActor in
            guard let data = try? await client.next(videoId: videoId, playlistId: list) else { return }
            guard !Task.isCancelled else { return }
            let parsed = WatchNextParser.queue(data: data)
            // Bail rather than blank the panel — the DOM copy is better
            // than nothing if YT hands us a queue shape we can't read.
            guard !parsed.isEmpty else {
                if queue.isEmpty { queue = domQueue }
                return
            }
            queue = parsed
            queueContextId = list
            queuePlayingIndex = parsed.firstIndex(where: { $0.videoId == videoId }) ?? -1
        }
    }

    /// Jump playback to the n-th item in the current queue.
    ///
    /// Synthesising a click on YT's own queue row doesn't take — the row's
    /// handler is a Polymer gesture listener that ignores untrusted events.
    /// So we do what every other play path here does: navigate the WebView to
    /// the track, carrying the page's current `list=` so YT rebuilds the same
    /// queue and playback continues in order from that point.
    func jumpToQueueIndex(_ index: Int) {
        guard let item = queue.first(where: { $0.id == index }) else { return }
        playQueueItem(item)
    }

    func playQueueItem(_ item: QueueItem) {
        guard let videoId = item.videoId, !videoId.isEmpty else {
            // No videoId scraped for this row — fall back to the DOM click.
            let js = "window.__ytmJumpQueue && window.__ytmJumpQueue(\(item.id))"
            WebViewHolder.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
            return
        }
        var urlStr = "https://music.youtube.com/watch?v=\(videoId)"
        if let list = currentWatchListId(), !list.isEmpty {
            urlStr += "&list=\(list)"
        }
        guard let url = URL(string: urlStr) else { return }
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
    }

    /// The `list=` the hidden WebView is currently playing out of, read off
    /// its live URL (YT's SPA keeps it in sync via pushState).
    private func currentWatchListId() -> String? {
        guard let url = WebViewHolder.shared.webView?.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "list" })?.value
    }

    func toggleQueue() {
        isQueueVisible.toggle()
        if isQueueVisible {
            isLyricsVisible = false
            isThemePickerVisible = false
            // Opening the panel before any track change (e.g. right after
            // launch) would otherwise show whatever the DOM last scraped.
            if queue.isEmpty { refreshQueue(for: MediaController.shared.nowPlaying.videoId) }
        }
    }

    func toggleLyrics() {
        isLyricsVisible.toggle()
        if isLyricsVisible {
            isQueueVisible = false
            isThemePickerVisible = false
            loadLyricsForCurrentTrack()
        }
    }

    /// Full-screen native Now Playing surface (big artwork + controls +
    /// lyrics). Toggled by Cmd-F; only meaningful with a track loaded.
    @Published var isNowPlayingVisible: Bool = false
    func toggleNowPlaying() {
        // In clip mode, the first Cmd-F drops back to the artwork screen
        // rather than closing everything.
        if isClipMode { exitClip(); return }
        if !isNowPlayingVisible {
            guard MediaController.shared.nowPlaying.hasTrack else {
                showToast("Çalan şarkı yok"); return
            }
            isNowPlayingVisible = true
            loadLyricsForCurrentTrack() // so lyrics are ready if the user opens them
        } else {
            isNowPlayingVisible = false
        }
    }

    /// Clip (music-video) mode — the WebView is brought forward to play the
    /// video full-window. Reversible: exitClip restores everything.
    @Published private(set) var isClipMode: Bool = false

    /// Shown instead of a black screen when "Klip" is opened on a track with
    /// no music video: a full-window lyric crawl.
    @Published private(set) var isClipCrawlVisible: Bool = false

    enum ClipEntry: Equatable { case noTrack, video, crawl }

    /// Pure decision so the branch is unit-testable without touching singletons.
    static func clipEntry(hasTrack: Bool, hasVideo: Bool) -> ClipEntry {
        guard hasTrack else { return .noTrack }
        return hasVideo ? .video : .crawl
    }

    func enterClip() {
        guard !isClipMode, !isClipCrawlVisible else { return }
        let np = MediaController.shared.nowPlaying
        switch Self.clipEntry(hasTrack: np.hasTrack, hasVideo: np.hasVideo) {
        case .noTrack:
            showToast("Çalan şarkı yok")
        case .video:
            // Crawl-first: show lyrics immediately and load the video in the
            // (still-hidden) WebView underneath. Only raise it once JS reports
            // a real frame (clipReady). No black screen while it buffers, and
            // false "hasVideo" tracks simply stay on the crawl forever.
            isClipCrawlVisible = true
            loadLyricsForCurrentTrack()
            FeatureBridge.shared.set("hideYTApp", enabled: false)
            FeatureBridge.shared.set("videoOnly", enabled: true)
            PrefBridge.shared.enterClip()
        case .crawl:
            isClipCrawlVisible = true
            loadLyricsForCurrentTrack()
        }
    }

    /// JS confirmed a real video frame — promote from the crawl to the raised
    /// full-window video.
    func clipReady() {
        guard isClipCrawlVisible, !isClipMode else { return }
        isClipCrawlVisible = false
        isClipMode = true
        MainWindowController.shared.setClipMode(true)
    }

    func exitClipCrawl() {
        isClipCrawlVisible = false
        // Undo the video machinery in case a video track was loading underneath
        // (harmless no-ops for audio-only tracks).
        PrefBridge.shared.exitClip()
        FeatureBridge.shared.set("videoOnly", enabled: false)
        FeatureBridge.shared.set("hideYTApp", enabled: Preferences.shared.nativeUIMode)
    }

    /// JS never saw a real video frame — keep the lyric crawl and unwind the
    /// WebView clip machinery so the hidden WebView returns to normal.
    func clipUnavailable() {
        PrefBridge.shared.exitClip()
        FeatureBridge.shared.set("videoOnly", enabled: false)
        FeatureBridge.shared.set("hideYTApp", enabled: Preferences.shared.nativeUIMode)
        if !isClipCrawlVisible {
            isClipCrawlVisible = true
            loadLyricsForCurrentTrack()
        }
    }

    func exitClip() {
        guard isClipMode else { return }
        isClipMode = false
        PrefBridge.shared.exitClip()
        FeatureBridge.shared.set("videoOnly", enabled: false)
        // Restore the native shell's hidden-WebView state.
        FeatureBridge.shared.set("hideYTApp", enabled: Preferences.shared.nativeUIMode)
        MainWindowController.shared.setClipMode(false)
    }

    /// Theme picker side panel — like lyrics/queue, mutually exclusive.
    @Published var isThemePickerVisible: Bool = false
    func toggleThemePicker() {
        isThemePickerVisible.toggle()
        if isThemePickerVisible {
            isQueueVisible = false
            isLyricsVisible = false
        }
    }

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
            ? "Ana sayfa yüklenemedi."
            : nil
        homeLoaded = true
    }

    func goExplore() {
        pushHistory()
        mainSection = .explore
        selectedPlaylist = nil
        if !exploreLoaded { Task { await loadExplore() } }
    }

    func goHistory() {
        pushHistory()
        mainSection = .history
        selectedPlaylist = nil
        Task { await loadHistory() }
    }

    // MARK: - Listening statistics

    @Published var statsRange: StatsRange = .month {
        didSet { if statsRange != oldValue { loadStatistics() } }
    }
    @Published private(set) var stats: ListeningStats?
    @Published private(set) var statsLoading = false

    func goStatistics() {
        pushHistory()
        mainSection = .statistics
        selectedPlaylist = nil
        loadStatistics()
    }

    /// Reads run against SQLite on a serial queue; keep them off the main
    /// thread so a long history can't stutter the UI.
    func loadStatistics() {
        guard let store = PlayHistoryStore.shared else {
            stats = .empty(statsRange)
            return
        }
        let range = statsRange
        statsLoading = true
        Task.detached(priority: .userInitiated) {
            let snapshot = store.snapshot(range: range)
            await MainActor.run {
                // A range switch mid-flight would otherwise paint stale numbers.
                guard self.statsRange == range else { return }
                self.stats = snapshot
                self.statsLoading = false
            }
        }
    }

    func reloadHistory() { Task { await loadHistory() } }

    private func loadHistory() async {
        guard !historyLoading else { return }
        guard auth.isAuthenticated else {
            historyError = "Geçmişi görmek için YT Music'e giriş yap."
            return
        }
        historyLoading = true
        defer { historyLoading = false }
        do {
            let data = try await client.browse(browseId: "FEmusic_history")
            let sections = HistoryParser.parse(data: data)
            historySections = sections
            historyError = sections.isEmpty ? "Geçmiş boş." : nil
            noteSuccess()
        } catch {
            noteFailure(error)
            historyError = "Geçmiş yüklenemedi."
        }
    }

    func reloadExplore() { exploreLoaded = false; Task { await loadExplore() } }

    private func loadExplore() async {
        guard !exploreLoading else { return }
        exploreLoading = true
        defer { exploreLoading = false }
        // New releases (album/single carousels), charts (ranked song lists),
        // and the moods & genres chips — fetched concurrently so the page
        // arrives in one pass instead of three visible pops.
        async let releasesTask: [HomeShelf] = {
            do { return HomeParser.parse(data: try await self.client.browse(browseId: "FEmusic_new_releases")) }
            catch { return [] }
        }()
        async let chartsTask: [ChartSection] = {
            do { return ChartsParser.parse(data: try await self.client.browse(browseId: "FEmusic_charts")) }
            catch { return [] }
        }()
        let existingGenres = genreSections // read on the main actor up front
        async let genresTask: [GenreSection] = {
            // Reuse what Home already loaded; only fetch if empty.
            if !existingGenres.isEmpty { return existingGenres }
            do { return GenreParser.parseSections(data: try await self.client.browse(browseId: "FEmusic_moods_and_genres")) }
            catch { return [] }
        }()
        let releases = await releasesTask
        let charts = await chartsTask
        let genres = await genresTask
        exploreNewReleases = releases
        exploreCharts = charts
        if genreSections.isEmpty { genreSections = genres }
        exploreError = (releases.isEmpty && charts.isEmpty && genreSections.isEmpty)
            ? "Keşfet yüklenemedi."
            : nil
        exploreLoaded = true
    }

    private func navigateWebView(to urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        WebViewHolder.shared.webView?.load(URLRequest(url: url))
    }

    /// Search is a normal main-section tab now (not a modal). Navigating in
    /// keeps the last query so returning to the tab restores it.
    func goSearch() {
        pushHistory()
        mainSection = .search
        selectedPlaylist = nil
    }

    /// Debounce typing so we don't fire a /search call per keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleSuggestions(for: query)
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
            searchError = cached.isEmpty ? "Sonuç yok." : nil
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
                searchError = parsed.isEmpty ? "Sonuç yok." : nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            noteFailure(error)
            searchError = "Arama başarısız"
        }
    }

    /// Route a search result to the right action: songs play, playlists/
    /// albums load in main content, artists navigate the WebView for now.
    func openSearchResult(_ r: SearchResult) {
        recordSearch(searchQuery) // remember what led here
        switch r.kind {
        case .song:
            let urlStr = "https://music.youtube.com/watch?v=\(r.id)"
            if let url = URL(string: urlStr) {
                WebViewHolder.shared.webView?.load(URLRequest(url: url))
            }
        case .playlist, .album:
            // Album browseIds (MPRE…/OLAK…) work with the same
            // PlaylistDetail flow — TrackParser handles both.
            let p = PlaylistSummary(id: r.id, title: r.title,
                                    thumbnailURL: r.thumbnailURL)
            openPlaylist(p)
        case .artist:
            openArtist(browseId: r.id, name: r.title)
        }
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
                showToast("Beğenildi: \(title)")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Beğenilemedi (HTTP \(code))")
            } catch {
                showToast("Beğenilemedi")
            }
        }
    }

    func dislikeTrack(videoId: String, title: String) {
        Task {
            do {
                _ = try await client.dislike(videoId: videoId)
                showToast("Beğenilmedi: \(title)")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("İşlem başarısız (HTTP \(code))")
            } catch {
                showToast("İşlem başarısız")
            }
        }
    }

    /// Toggle like (or dislike) on the currently-playing track. Called by
    /// every heart in the app — player bar, Now Playing screen, mini player,
    /// menu bar, Dock menu — via `MediaController.run("like")`.
    ///
    /// We hit InnerTube rather than clicking YT's own button: in Native Mode
    /// the page is hidden, and its like button is a `yt-button-shape` whose
    /// click handler sits on an inner `<button>`, so `.click()` on the
    /// renderer silently did nothing.
    func toggleNowPlayingLike(dislike: Bool = false) {
        let np = MediaController.shared.nowPlaying
        let videoId = np.videoId
        // Both of these used to return silently, which looked exactly like a
        // dead button. Fall through to clicking YT's own control instead.
        guard !videoId.isEmpty else {
            MediaController.shared.clickLikeInPage(dislike: dislike)
            return
        }
        guard auth.isAuthenticated else {
            MediaController.shared.clickLikeInPage(dislike: dislike)
            showToast("Beğenmek için YT Music'e giriş yap")
            return
        }

        let wasLiked = np.liked, wasDisliked = np.disliked
        let liked: Bool, disliked: Bool
        if dislike {
            disliked = !wasDisliked
            liked = disliked ? false : wasLiked
        } else {
            liked = !wasLiked
            disliked = liked ? false : wasDisliked
        }
        MediaController.shared.setLikeState(videoId: videoId, liked: liked, disliked: disliked)

        Task {
            do {
                if liked {
                    _ = try await client.like(videoId: videoId)
                } else if disliked {
                    _ = try await client.dislike(videoId: videoId)
                } else {
                    _ = try await client.removeLike(videoId: videoId)
                }
                if dislike {
                    showToast(disliked ? "Beğenilmedi olarak işaretlendi" : "İşaret kaldırıldı")
                } else {
                    showToast(liked ? "Beğenilenlere eklendi" : "Beğeni kaldırıldı")
                }
            } catch {
                // Don't revert the heart yet: the page click may still land.
                // Name the status so a recurring failure is diagnosable rather
                // than "the button doesn't work".
                MediaController.shared.clickLikeInPage(dislike: dislike)
                if case InnerTubeClient.APIError.httpStatus(let code, _) = error {
                    showToast("Beğeni API'si reddetti (HTTP \(code)) — sayfadan denendi")
                } else {
                    showToast("Beğeni gönderilemedi — sayfadan denendi")
                }
                // Give the click a moment to land, then stop pinning the heart
                // so the page's real like-status decides what it shows.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                MediaController.shared.clearLikeOverride()
            }
        }
    }

    /// Real Add to queue / Play next, backed by ownQueue. Append at the
    /// end for Add to queue, prepend for Play next. When the current YT
    /// track ends (signalled via the JS bridge), handleTrackEnded pops
    /// the head and navigates the WebView to it.
    func addToQueue(videoId: String, title: String, artist: String = "",
                    thumbnailURL: String? = nil, playNext: Bool = false) {
        let item = OwnQueueItem(videoId: videoId, title: title,
                                artist: artist, thumbnailURL: thumbnailURL)
        if playNext {
            ownQueue.insert(item, at: 0)
            showToast("Sıradaki: \(title)")
        } else {
            ownQueue.append(item)
            showToast("Kuyruğa eklendi: \(title)")
        }
    }

    /// Convenience for the TrackRow context menu which already has the
    /// full TrackSummary.
    func addToQueue(track: TrackSummary, playNext: Bool = false) {
        addToQueue(videoId: track.id,
                   title: track.title,
                   artist: track.artist,
                   thumbnailURL: track.thumbnailURL,
                   playNext: playNext)
    }

    /// Append a batch of already-loaded tracks to ownQueue (open playlist).
    func addTracksToQueue(_ list: [TrackSummary]) {
        guard !list.isEmpty else { return }
        ownQueue.append(contentsOf: list.map {
            OwnQueueItem(videoId: $0.id, title: $0.title, artist: $0.artist, thumbnailURL: $0.thumbnailURL)
        })
        showToast("\(list.count) şarkı kuyruğa eklendi")
    }

    /// Fetch a collection (playlist/album) and append its tracks to ownQueue,
    /// without navigating there. First page only (~100) — plenty for a queue.
    func addCollectionToQueue(id: String, title: String) {
        Task {
            do {
                let data = try await client.browse(browseId: id)
                let list = TrackParser.parse(data: data)
                guard !list.isEmpty else { showToast("Boş liste"); return }
                addTracksToQueue(list)
            } catch {
                showToast("Kuyruğa eklenemedi")
            }
        }
    }

    /// User pressed Next. If ownQueue has anything, pop the head and
    /// navigate to it. Returns true if we acted (so the caller skips
    /// the fall-through to YT's own next-track command).
    @discardableResult
    func consumeOwnQueueNext() -> Bool {
        guard !ownQueue.isEmpty else { return false }
        let next = ownQueue.removeFirst()
        let urlStr = "https://music.youtube.com/watch?v=\(next.videoId)"
        if let url = URL(string: urlStr) {
            nowPlayingCollectionId = nil
            WebViewHolder.shared.webView?.load(URLRequest(url: url))
        }
        return true
    }

    /// Called from the JS bridge when the currently-playing video ends.
    /// Pulls the head of ownQueue (if any) and navigates to it.
    ///
    /// Guard: only act if something was actually playing in YT's player
    /// (hasTrack == true). The JS-side filter on duration / currentTime
    /// catches src-clear spurious ends, but this is the second line of
    /// defense — and if MediaController says we never had a track, then
    /// there's nothing to chain.
    func handleTrackEnded() {
        guard MediaController.shared.nowPlaying.hasTrack else { return }
        guard !ownQueue.isEmpty else { return }
        let next = ownQueue.removeFirst()
        let urlStr = "https://music.youtube.com/watch?v=\(next.videoId)"
        if let url = URL(string: urlStr) {
            nowPlayingCollectionId = nil
            WebViewHolder.shared.webView?.load(URLRequest(url: url))
        }
    }

    /// Jump to a specific position in ownQueue — plays that item now and
    /// drops everything before it. Used when the user clicks a row in
    /// the own-queue section of the queue panel.
    func playOwnQueueItem(_ item: OwnQueueItem) {
        guard let idx = ownQueue.firstIndex(of: item) else { return }
        let urlStr = "https://music.youtube.com/watch?v=\(item.videoId)"
        ownQueue.removeFirst(idx + 1)
        if let url = URL(string: urlStr) {
            nowPlayingCollectionId = nil
            WebViewHolder.shared.webView?.load(URLRequest(url: url))
        }
    }

    /// Remove an item from ownQueue (swipe / context menu).
    func removeFromOwnQueue(_ item: OwnQueueItem) {
        ownQueue.removeAll(where: { $0.id == item.id })
    }

    /// Drag-to-reorder: move the dragged item to the target's position.
    func moveOwnQueueItem(fromId: UUID, toId: UUID) {
        guard fromId != toId,
              let fromIdx = ownQueue.firstIndex(where: { $0.id == fromId }) else { return }
        let item = ownQueue.remove(at: fromIdx)
        let toIdx = ownQueue.firstIndex(where: { $0.id == toId }) ?? ownQueue.count
        ownQueue.insert(item, at: toIdx)
    }

    /// Clear everything the user manually queued.
    func clearOwnQueue() {
        ownQueue.removeAll()
        showToast("Kuyruk temizlendi")
    }

    // MARK: Create playlist

    enum PlaylistPrivacy: String, CaseIterable, Identifiable {
        case publicListed = "PUBLIC"
        case unlisted = "UNLISTED"
        case privateListed = "PRIVATE"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .publicListed: return "Herkese açık"
            case .unlisted:     return "Liste dışı (bağlantısı olan)"
            case .privateListed:return "Özel"
            }
        }
    }

    @Published var isCreatePlaylistVisible: Bool = false
    /// When the create dialog was opened from track(s), seed the new playlist
    /// with these videoIds.
    private(set) var createPlaylistPendingVideoIds: [String] = []

    func beginCreatePlaylist(addingVideoIds: [String] = []) {
        createPlaylistPendingVideoIds = addingVideoIds
        isCreatePlaylistVisible = true
    }

    func beginCreatePlaylist(addingVideoId: String) {
        beginCreatePlaylist(addingVideoIds: [addingVideoId])
    }

    func cancelCreatePlaylist() {
        isCreatePlaylistVisible = false
        createPlaylistPendingVideoIds = []
    }

    // MARK: Rename / delete playlist

    /// Only "VLPL…" (user/created) playlists are editable; radio (VLRDCLAK),
    /// Liked Music (VLLM) etc. aren't.
    func isEditablePlaylist(_ p: PlaylistSummary) -> Bool { p.id.hasPrefix("VLPL") }

    @Published var renameTarget: PlaylistSummary?
    @Published var deleteTarget: PlaylistSummary?

    func beginRename(_ p: PlaylistSummary) { renameTarget = p }
    func cancelRename() { renameTarget = nil }
    func beginDelete(_ p: PlaylistSummary) { deleteTarget = p }
    func cancelDelete() { deleteTarget = nil }

    private func barePlaylistId(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    func renamePlaylist(_ p: PlaylistSummary, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !name.isEmpty, name != p.title else { return }
        Task {
            do {
                _ = try await client.renamePlaylist(playlistId: barePlaylistId(p.id), name: name)
                showToast("Yeniden adlandırıldı: \(name)")
                await loadPlaylists()
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Adlandırılamadı (HTTP \(code))")
            } catch {
                showToast("Adlandırılamadı")
            }
        }
    }

    func confirmDeletePlaylist() {
        guard let p = deleteTarget else { return }
        deleteTarget = nil
        Task {
            do {
                _ = try await client.deletePlaylist(playlistId: barePlaylistId(p.id))
                showToast("Silindi: \(p.title)")
                if mainSection == .playlist(p) { goHome() }
                await loadPlaylists()
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Silinemedi (HTTP \(code))")
            } catch {
                showToast("Silinemedi")
            }
        }
    }

    func createPlaylist(title: String, description: String, privacy: PlaylistPrivacy) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let videoIds = createPlaylistPendingVideoIds
        isCreatePlaylistVisible = false
        createPlaylistPendingVideoIds = []
        guard !name.isEmpty else { showToast("Liste adı gerekli"); return }
        Task {
            do {
                _ = try await client.createPlaylist(title: name,
                                                    description: desc,
                                                    privacy: privacy.rawValue,
                                                    videoIds: videoIds.isEmpty ? nil : videoIds)
                showToast(videoIds.isEmpty ? "“\(name)” oluşturuldu"
                                           : "“\(name)” oluşturuldu, \(videoIds.count) şarkı eklendi")
                await loadPlaylists() // refresh sidebar so the new list shows
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Liste oluşturulamadı (HTTP \(code))")
            } catch {
                showToast("Liste oluşturulamadı")
            }
        }
    }

    /// Live (local-only) reorder while dragging: move one row to sit right
    /// before another. No network — `commitTrackMove` persists on drop.
    func localMoveTrack(fromSetVideoId: String, toSetVideoId: String) {
        guard fromSetVideoId != toSetVideoId,
              let from = tracks.firstIndex(where: { $0.setVideoId == fromSetVideoId }) else { return }
        let item = tracks.remove(at: from)
        let dest = tracks.firstIndex(where: { $0.setVideoId == toSetVideoId }) ?? tracks.count
        tracks.insert(item, at: dest)
    }

    /// Persist the dragged row's new position (called once on drop).
    func commitTrackMove(setVideoId: String, in p: PlaylistSummary) {
        guard let idx = tracks.firstIndex(where: { $0.setVideoId == setVideoId }) else { return }
        let successor = tracks.indices.contains(idx + 1) ? tracks[idx + 1].setVideoId : nil
        Task {
            do {
                _ = try await client.moveInPlaylist(playlistId: barePlaylistId(p.id),
                                                    setVideoId: setVideoId,
                                                    successorSetVideoId: successor)
            } catch {
                showToast("Sıralama kaydedilemedi")
                await loadTracks(for: p) // resync from server
            }
        }
    }

    /// Header "Play": play the list in order (shuffle off).
    func playPlaylist(_ tracks: [TrackSummary]) {
        guard let first = tracks.first else { return }
        MediaController.shared.run("shuffleoff")
        playTrack(first)
    }

    /// Header "Shuffle": shuffle on + start from a random entry.
    func shufflePlay(_ tracks: [TrackSummary]) {
        guard let t = tracks.randomElement() else { return }
        MediaController.shared.run("shuffleon")
        playTrack(t)
    }

    /// Remove tracks from the user's own playlist (needs each row's setVideoId).
    func removeFromPlaylist(tracks: [TrackSummary], from p: PlaylistSummary) {
        let items = tracks.compactMap { t -> (videoId: String, setVideoId: String)? in
            guard let sv = t.setVideoId else { return nil }
            return (t.id, sv)
        }
        guard !items.isEmpty else { showToast("Bu parçalar listeden çıkarılamıyor"); return }
        Task {
            do {
                _ = try await client.removeFromPlaylist(playlistId: barePlaylistId(p.id), items: items)
                showToast(items.count == 1 ? "Listeden çıkarıldı"
                                           : "\(items.count) şarkı listeden çıkarıldı")
                await loadTracks(for: p) // refresh the list
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Çıkarılamadı (HTTP \(code))")
            } catch {
                showToast("Çıkarılamadı")
            }
        }
    }

    /// Add several tracks (e.g. a multi-selection from any playlist) to one of
    /// the user's playlists.
    func addTracksToPlaylist(videoIds: [String], playlistId: String, playlistTitle: String) {
        guard !videoIds.isEmpty else { return }
        Task {
            do {
                let bare = barePlaylistId(playlistId)
                if bare == "LM" {
                    for v in videoIds { _ = try await client.like(videoId: v) }
                    showToast("\(videoIds.count) şarkı Beğenilenlere eklendi")
                    return
                }
                guard bare.hasPrefix("PL") else { showToast("\(playlistTitle) düzenlenemiyor"); return }
                _ = try await client.addToPlaylist(playlistId: bare, videoIds: videoIds)
                showToast("\(videoIds.count) şarkı “\(playlistTitle)”e eklendi")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Eklenemedi (HTTP \(code))")
            } catch {
                showToast("Eklenemedi")
            }
        }
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
                    showToast("“\(trackTitle)” Beğenilen Müzikler'e eklendi")
                    return
                }

                guard bareId.hasPrefix("PL") else {
                    showToast("\(playlistTitle) düzenlenemez")
                    return
                }
                _ = try await client.addToPlaylist(playlistId: bareId, videoId: videoId)
                showToast("“\(trackTitle)” → \(playlistTitle)")
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Kaydedilemedi (HTTP \(code))")
            } catch {
                showToast("Kaydedilemedi")
            }
        }
    }

    /// Fetch lyrics for whatever's playing right now. Two-hop:
    /// /next → lyrics browseId → /browse → text. Caches the last
    /// fetched videoId so re-opening the overlay on the same track
    /// doesn't re-hit the network.
    func loadLyricsForCurrentTrack() {
        let np = MediaController.shared.nowPlaying
        guard !np.videoId.isEmpty else {
            lyricsError = "Çalan şarkı yok"
            lyrics = nil
            return
        }
        if lyricsLoadedFor == np.videoId { return }
        lyricsLoadedFor = np.videoId
        Task { await loadLyrics(videoId: np.videoId) }
    }

    private func loadLyrics(videoId: String) async {
        lyricsLoading = true
        defer { lyricsLoading = false }
        lyrics = nil
        lyricsError = nil
        do {
            let nextData = try await client.next(videoId: videoId)
            guard let browseId = WatchNextParser.extractLyricsBrowseId(data: nextData) else {
                lyricsError = "Bu şarkı için sözler yok"
                return
            }
            let lyricsData = try await client.browse(browseId: browseId)
            guard MediaController.shared.nowPlaying.videoId == videoId else { return }
            if let parsed = LyricsParser.parse(data: lyricsData) {
                lyrics = parsed
            } else {
                lyricsError = "Sözler bulunamadı"
            }
        } catch {
            lyricsError = "Sözler yüklenemedi"
            // Transient failure (network) — clear the dedupe key so
            // reopening the panel retries. "No lyrics"/"not found" above
            // are deterministic and intentionally stay cached.
            if lyricsLoadedFor == videoId { lyricsLoadedFor = nil }
        }
    }

    func openInBrowser(videoId: String) {
        let urlStr = "https://music.youtube.com/watch?v=\(videoId)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Copy a shareable music.youtube.com link to the pasteboard.
    func copyLink(videoId: String) {
        let urlStr = "https://music.youtube.com/watch?v=\(videoId)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
        showToast("Bağlantı kopyalandı")
    }

    /// Navigate to an album (a playlist-like browse target, MPRE…/OLAK…).
    func openAlbum(albumId: String, title: String, thumbnailURL: String?) {
        openPlaylist(.init(id: albumId, title: title, thumbnailURL: thumbnailURL))
    }

    /// True when the collection is already in the user's library. Compares on
    /// the bare id: the same playlist arrives as `VLPL…` from the library
    /// browse and `PL…` from some card renderers. Albums live in a separate
    /// shelf, so check both.
    func isPlaylistSaved(_ p: PlaylistSummary) -> Bool {
        let target = p.playlistURLId
        return playlists.contains(where: { $0.playlistURLId == target })
            || savedAlbums.contains(where: { $0.playlistURLId == target })
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
                showToast("“\(p.title)” kitaplığa kaydedildi")
                await loadPlaylists()
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Kaydedilemedi (HTTP \(code))")
            } catch {
                showToast("Kaydedilemedi")
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
                showToast("“\(p.title)” kitaplıktan çıkarıldı")
                await loadPlaylists()
            } catch InnerTubeClient.APIError.httpStatus(let code, _) {
                showToast("Çıkarılamadı (HTTP \(code))")
            } catch {
                showToast("Çıkarılamadı")
            }
        }
    }

    func copyPlaylistLink(_ p: PlaylistSummary) {
        let url = "https://music.youtube.com/playlist?list=\(p.playlistURLId)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showToast("Bağlantı kopyalandı")
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

    /// The "load more tracks in THIS playlist" token, if any. Only the
    /// `continuationItemRenderer.continuationCommand.token` form means real
    /// extra tracks — the older `nextContinuationData` is the related-radio
    /// continuation (present even on complete short playlists), so we ignore it.
    static func continuationToken(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var token: String?
        func walk(_ node: Any) {
            if token != nil { return }
            if let d = node as? [String: Any] {
                if let cir = d["continuationItemRenderer"] as? [String: Any],
                   let ep = cir["continuationEndpoint"] as? [String: Any],
                   let cc = ep["continuationCommand"] as? [String: Any],
                   let t = cc["token"] as? String {
                    token = t; return
                }
                for v in d.values { walk(v) }
            } else if let a = node as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(json)
        return token
    }

    private static func extract(_ renderer: [String: Any]) -> NativeShellViewModel.TrackSummary? {
        let flex = (renderer["flexColumns"] as? [[String: Any]]) ?? []
        let fixed = (renderer["fixedColumns"] as? [[String: Any]]) ?? []
        let title = textInFlexColumn(flex, index: 0)
        // Artist + album sometimes share a column with bullet separators;
        // we grab the first run which is the artist name.
        let artist = textInFlexColumn(flex, index: 1)
        // The album column isn't at a fixed index — depending on the list
        // type, column 2 may instead be "74M plays", a date, etc. The album
        // is the run that links to an album browse target (MPRE…/OLAK…), so
        // detect it by that link rather than by position. No link → no album.
        let albumLink = albumRun(in: flex)
        let albumText = albumLink?.0
        let albumId = albumLink?.1
        let artistId = browseId(in: flex, prefixes: ["UC"])
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
        // Per-entry id needed to remove this row from a playlist.
        let setVideoId = (renderer["playlistItemData"] as? [String: Any])?["playlistSetVideoId"] as? String

        guard let id = videoId, !title.isEmpty else { return nil }
        return .init(id: id, title: title, artist: artist, duration: duration,
                     thumbnailURL: thumbURL,
                     album: (albumText?.isEmpty == false) ? albumText : nil,
                     artistId: artistId, albumId: albumId, setVideoId: setVideoId)
    }

    private static func textInFlexColumn(_ columns: [[String: Any]], index: Int) -> String {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = inner["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    /// Scan every flex column's runs for the album link (text + MPRE…/OLAK…
    /// browseId). Returns the run's text so callers get the real album name
    /// regardless of which column it lands in.
    private static func albumRun(in columns: [[String: Any]]) -> (String, String)? {
        for col in columns {
            guard let inner = col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                  let text = inner["text"] as? [String: Any],
                  let runs = text["runs"] as? [[String: Any]] else { continue }
            for run in runs {
                if let nav = run["navigationEndpoint"] as? [String: Any],
                   let browse = nav["browseEndpoint"] as? [String: Any],
                   let id = browse["browseId"] as? String,
                   id.hasPrefix("MPRE") || id.hasPrefix("OLAK"),
                   let name = run["text"] as? String {
                    return (name, id)
                }
            }
        }
        return nil
    }

    /// First run browseId across all flex columns matching a prefix
    /// (e.g. "UC" for artist navigation).
    private static func browseId(in columns: [[String: Any]], prefixes: [String]) -> String? {
        for col in columns {
            guard let inner = col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                  let text = inner["text"] as? [String: Any],
                  let runs = text["runs"] as? [[String: Any]] else { continue }
            for run in runs {
                if let nav = run["navigationEndpoint"] as? [String: Any],
                   let browse = nav["browseEndpoint"] as? [String: Any],
                   let id = browse["browseId"] as? String,
                   prefixes.contains(where: { id.hasPrefix($0) }) {
                    return id
                }
            }
        }
        return nil
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
/// Pulls the song count out of a playlist's `/browse` response. The count
/// lives in `musicResponsiveHeaderRenderer.secondSubtitle`, e.g.
/// "1.2M views • 197 tracks • 13+ hours" — we grab the "N tracks"/"N songs"
/// run. Used to annotate playlist search rows, which have no count of their own.
enum PlaylistHeaderParser {
    static func trackCount(data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let header = findHeader(json) else { return nil }
        let runs = ((header["secondSubtitle"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
        for run in runs {
            if let text = run["text"] as? String, let n = count(from: text) { return n }
        }
        return nil
    }

    private static func findHeader(_ node: Any) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let h = dict["musicResponsiveHeaderRenderer"] as? [String: Any] { return h }
            for value in dict.values { if let h = findHeader(value) { return h } }
        } else if let arr = node as? [Any] {
            for value in arr { if let h = findHeader(value) { return h } }
        }
        return nil
    }

    /// "197 tracks" / "50 songs" → the integer; nil for "1.2M views" etc.
    private static func count(from text: String) -> Int? {
        let lower = text.lowercased()
        guard lower.contains("track") || lower.contains("song") else { return nil }
        let digits = text.filter { $0.isNumber }
        return Int(digits)
    }
}

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
        case "song", "video": return .song
        case "single", "ep":
            // Single / EP can be either a single track (with videoId) or
            // a release (album-like, navigated to via browseEndpoint).
            // Without a videoId, treat as an album so the click still
            // routes somewhere meaningful.
            return hasVideoId ? .song : .album
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

/// Walks a /next watchNextResponse to find the Lyrics tab's browseId.
/// Lyrics are accessed via a separate /browse call against that id;
/// without this hop we can't get the actual text.
enum WatchNextParser {
    /// The player queue, straight out of `/next`. Beats scraping
    /// `ytmusic-player-queue-item` off the hidden page: it survives YT's
    /// markup churn and carries the videoId, which the DOM doesn't reliably
    /// expose.
    ///
    /// Rows arrive as `playlistPanelVideoRenderer`, sometimes wrapped so that
    /// a song and its music-video counterpart sit side by side — those show up
    /// as consecutive duplicates and get collapsed.
    static func queue(data: Data) -> [NativeShellViewModel.QueueItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var rows: [(videoId: String, title: String, artist: String, thumb: String?)] = []
        walk(json) { dict in
            guard let r = dict["playlistPanelVideoRenderer"] as? [String: Any] else { return }
            let title = runsText(r["title"])
            guard !title.isEmpty else { return }
            let videoId = r["videoId"] as? String ?? ""
            // longBylineText is "Artist • Album • Year"; only the first run
            // fits a narrow queue row.
            let artist = ((r["longBylineText"] as? [String: Any])?["runs"] as? [[String: Any]])?
                .first?["text"] as? String ?? ""
            let thumb = ((r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                .last?["url"] as? String
            if let last = rows.last, !videoId.isEmpty, last.videoId == videoId { return }
            rows.append((videoId, title, artist, thumb))
        }
        return rows.enumerated().map { idx, r in
            .init(id: idx,
                  videoId: r.videoId.isEmpty ? nil : r.videoId,
                  title: r.title,
                  artist: r.artist,
                  thumbnailURL: r.thumb,
                  isPlaying: false)
        }
    }

    private static func runsText(_ node: Any?) -> String {
        guard let runs = (node as? [String: Any])?["runs"] as? [[String: Any]] else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    static func extractLyricsBrowseId(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var found: String?
        walk(json) { dict in
            guard found == nil,
                  let tab = dict["tabRenderer"] as? [String: Any],
                  let title = tabTitle(tab).lowercased() as String?,
                  title == "lyrics" || title == "şarkı sözleri",
                  let endpoint = tab["endpoint"] as? [String: Any],
                  let browse = endpoint["browseEndpoint"] as? [String: Any],
                  let id = browse["browseId"] as? String
            else { return }
            found = id
        }
        return found
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let arr = node as? [Any] {
            for value in arr { walk(value, visit: visit) }
        }
    }

    private static func tabTitle(_ tab: [String: Any]) -> String {
        // Title is either a plain string or a runs-wrapper depending on
        // which Polymer version YT served us.
        if let s = tab["title"] as? String { return s }
        if let wrap = tab["title"] as? [String: Any],
           let runs = wrap["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }
}

/// Pulls lyric text + attribution out of a /browse <MPLYt…> response.
/// The body is a sectionList containing exactly one
/// musicDescriptionShelfRenderer with the text in `description.runs`
/// and the source/attribution in `footer.runs`.
enum LyricsParser {
    struct Lyrics: Equatable {
        let text: String
        let source: String?
    }

    static func parse(data: Data) -> Lyrics? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var found: Lyrics?
        walk(json) { dict in
            guard found == nil,
                  let shelf = dict["musicDescriptionShelfRenderer"] as? [String: Any]
            else { return }
            let text = runsText(shelf["description"])
            guard !text.isEmpty else { return }
            let source = runsText(shelf["footer"])
            found = Lyrics(text: text, source: source.isEmpty ? nil : source)
        }
        return found
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let arr = node as? [Any] {
            for value in arr { walk(value, visit: visit) }
        }
    }

    private static func runsText(_ node: Any?) -> String {
        guard let dict = node as? [String: Any],
              let runs = dict["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }
}

/// Builds a NativeShellViewModel.ArtistDetail from a /browse UC… response.
/// The header lives at `header.musicImmersiveHeaderRenderer`. The body
/// is sectionListRenderer.contents with shelves of two kinds:
///   - musicShelfRenderer (lists of songs)
///   - musicCarouselShelfRenderer (cards of albums / singles / related)
/// Categorisation is by the shelf's header title.
enum ArtistParser {
    static func parse(data: Data, browseId: String) -> NativeShellViewModel.ArtistDetail? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let header = (json["header"] as? [String: Any])?["musicImmersiveHeaderRenderer"]
            as? [String: Any]
        else { return nil }
        let name = ((header["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined() ?? ""
        guard !name.isEmpty else { return nil }
        let subscriberText: String? = {
            guard let sub = header["subscriptionButton"] as? [String: Any],
                  let btn = sub["subscribeButtonRenderer"] as? [String: Any],
                  let count = btn["subscriberCountText"] as? [String: Any],
                  let runs = count["runs"] as? [[String: Any]]
            else { return nil }
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }()
        let thumbs = ((header["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"]
            as? [String: Any]).flatMap {
                ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            }
        let thumbURL = thumbs?.last?["url"] as? String

        var topSongs: [NativeShellViewModel.TrackSummary] = []
        var albums: [NativeShellViewModel.HomeCard] = []
        var singles: [NativeShellViewModel.HomeCard] = []
        var allSongsBrowseId: String?
        walk(json) { dict in
            if let songsShelf = dict["musicShelfRenderer"] as? [String: Any] {
                let title = shelfTitle(in: songsShelf).lowercased()
                if title.contains("song") {
                    let data = try? JSONSerialization.data(withJSONObject: songsShelf)
                    topSongs.append(contentsOf:
                        data.map { TrackParser.parse(data: $0) } ?? [])
                    // "Tüm şarkılar" target — the shelf's bottom endpoint is a
                    // VL… playlist with the artist's full song list.
                    if let bid = ((songsShelf["bottomEndpoint"] as? [String: Any])?["browseEndpoint"]
                        as? [String: Any])?["browseId"] as? String, bid.hasPrefix("VL") {
                        allSongsBrowseId = bid
                    }
                }
            }
            if let carousel = dict["musicCarouselShelfRenderer"] as? [String: Any] {
                let title = carouselTitle(in: carousel).lowercased()
                let cards = extractCards(carousel: carousel)
                if title.contains("album") {
                    albums.append(contentsOf: cards)
                } else if title.contains("single") {
                    singles.append(contentsOf: cards)
                }
            }
        }

        return .init(id: browseId,
                     name: name,
                     thumbnailURL: thumbURL,
                     subscriberText: subscriberText,
                     topSongs: topSongs,
                     albums: albums,
                     singles: singles,
                     allSongsBrowseId: allSongsBrowseId)
    }

    private static func walk(_ node: Any, visit: ([String: Any]) -> Void) {
        if let dict = node as? [String: Any] {
            visit(dict)
            for value in dict.values { walk(value, visit: visit) }
        } else if let arr = node as? [Any] {
            for value in arr { walk(value, visit: visit) }
        }
    }

    private static func shelfTitle(in shelf: [String: Any]) -> String {
        ((shelf["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }.joined() ?? ""
    }

    private static func carouselTitle(in carousel: [String: Any]) -> String {
        guard let headerWrap = carousel["header"] as? [String: Any],
              let basic = headerWrap["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
              let titleWrap = basic["title"] as? [String: Any],
              let runs = titleWrap["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private static func extractCards(carousel: [String: Any]) -> [NativeShellViewModel.HomeCard] {
        let contents = (carousel["contents"] as? [[String: Any]]) ?? []
        // Reuse HomeParser's per-card walker by wrapping each item in a
        // synthetic shelf and re-running it.
        let shelf: [String: Any] = [
            "musicCarouselShelfRenderer": [
                "header": ["musicCarouselShelfBasicHeaderRenderer": [
                    "title": ["runs": [["text": "x"]]]
                ]],
                "contents": contents
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: shelf) else { return [] }
        return HomeParser.parse(data: data).flatMap { $0.items }
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
        let runs = (renderer["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
        let subtitle = runs.compactMap { $0["text"] as? String }.joined()
        return .init(id: id, title: title, thumbnailURL: thumbURL,
                     subtitle: subtitle.isEmpty ? nil : subtitle,
                     trackCount: trackCount(in: runs))
    }

    /// YT sometimes ends the subtitle with a "50 songs" / "50 şarkı" run.
    /// When it doesn't, there's no count anywhere in a category response —
    /// short of browsing all 400-odd playlists — so we just show nothing.
    private static func trackCount(in runs: [[String: Any]]) -> Int? {
        for run in runs {
            guard let text = run["text"] as? String else { continue }
            let parts = text.split(separator: " ")
            guard parts.count >= 2, let n = Int(parts[0]) else { continue }
            let unit = parts[1].lowercased()
            if unit.hasPrefix("song") || unit.hasPrefix("şarkı")
                || unit.hasPrefix("track") || unit.hasPrefix("parça") {
                return n
            }
        }
        return nil
    }
}

/// Library items (saved albums / followed artists) — `musicTwoRowItemRenderer`
/// tiles whose browseId matches the wanted prefix. Returns id/title/thumb as
/// PlaylistSummary (reused for both; click routes by id prefix).
enum LibraryParser {
    static func parse(data: Data, prefixes: [String]) -> [NativeShellViewModel.PlaylistSummary] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [NativeShellViewModel.PlaylistSummary] = []
        var seen = Set<String>()
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                if let r = d["musicTwoRowItemRenderer"] as? [String: Any],
                   let item = extractTwoRow(r, prefixes: prefixes), seen.insert(item.id).inserted {
                    out.append(item)
                } else if let r = d["musicResponsiveListItemRenderer"] as? [String: Any],
                          let item = extractListItem(r, prefixes: prefixes), seen.insert(item.id).inserted {
                    out.append(item)
                }
                for v in d.values { walk(v) }
            } else if let a = node as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(json)
        return out
    }

    private static func browseIdMatching(_ nav: Any?, _ prefixes: [String]) -> String? {
        guard let id = ((nav as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String,
              prefixes.contains(where: { id.hasPrefix($0) }) else { return nil }
        return id
    }
    private static func thumbURL(_ r: [String: Any], key: String) -> String? {
        ((r[key] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])
            .flatMap { ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] }?
            .last?["url"] as? String
    }

    private static func extractTwoRow(_ r: [String: Any], prefixes: [String]) -> NativeShellViewModel.PlaylistSummary? {
        guard let browseId = browseIdMatching(r["navigationEndpoint"], prefixes) else { return nil }
        let title = ((r["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }.joined() ?? ""
        guard !title.isEmpty else { return nil }
        return .init(id: browseId, title: title, thumbnailURL: thumbURL(r, key: "thumbnailRenderer"))
    }

    private static func extractListItem(_ r: [String: Any], prefixes: [String]) -> NativeShellViewModel.PlaylistSummary? {
        guard let browseId = browseIdMatching(r["navigationEndpoint"], prefixes) else { return nil }
        let flex = (r["flexColumns"] as? [[String: Any]]) ?? []
        let title = (flex.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])
            .flatMap { ($0["text"] as? [String: Any])?["runs"] as? [[String: Any]] }?
            .compactMap { $0["text"] as? String }.joined() ?? ""
        guard !title.isEmpty else { return nil }
        return .init(id: browseId, title: title, thumbnailURL: thumbURL(r, key: "thumbnail"))
    }
}

/// Extracts the album-level "Save to library" feedback tokens from an album
/// browse response. The album header's toggle is the FIRST
/// `toggleMenuServiceItemRenderer` whose label mentions "library" (the header
/// precedes the per-track menus that share the same wording).
/// An album browses under `MPRE…` but plays under a real playlist id
/// (`OLAK5uy_…`). YT hands that id back in the response — on the header's
/// play button, and again on every track row's watch endpoint. Prefer the
/// explicit `audioPlaylistId` and fall back to the endpoints.
enum WatchPlaylistIdParser {
    static func playlistId(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstValue(in: json) { d in
            (d["audioPlaylistId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        } ?? firstValue(in: json) { d in
            for key in ["watchEndpoint", "watchPlaylistEndpoint"] {
                guard let ep = d[key] as? [String: Any],
                      let pid = ep["playlistId"] as? String else { continue }
                if pid.hasPrefix("OLAK") || pid.hasPrefix("PL") { return pid }
            }
            return nil
        }
    }

    /// Depth-first scan for the first dict where `pick` yields a value.
    private static func firstValue(in node: Any, pick: ([String: Any]) -> String?) -> String? {
        if let d = node as? [String: Any] {
            if let hit = pick(d) { return hit }
            for v in d.values {
                if let hit = firstValue(in: v, pick: pick) { return hit }
            }
        } else if let a = node as? [Any] {
            for v in a {
                if let hit = firstValue(in: v, pick: pick) { return hit }
            }
        }
        return nil
    }
}

enum AlbumLibraryParser {
    static func tokens(data: Data) -> (add: String?, remove: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return (nil, nil) }
        var result: (add: String?, remove: String?) = (nil, nil)
        func token(_ ep: Any?) -> String? {
            ((ep as? [String: Any])?["feedbackEndpoint"] as? [String: Any])?["feedbackToken"] as? String
        }
        func walk(_ node: Any) {
            if result.add != nil { return }
            if let d = node as? [String: Any] {
                if let tm = d["toggleMenuServiceItemRenderer"] as? [String: Any] {
                    let label = (((tm["defaultText"] as? [String: Any])?["runs"] as? [[String: Any]])?
                        .first?["text"] as? String ?? "").lowercased()
                    if label.contains("library") || label.contains("kitapl") {
                        result = (token(tm["defaultServiceEndpoint"]), token(tm["toggledServiceEndpoint"]))
                        return
                    }
                }
                for v in d.values { walk(v) }
            } else if let a = node as? [Any] {
                for v in a { walk(v) }
            }
        }
        walk(json)
        return result
    }
}

/// Pulls ranked chart shelves out of the FEmusic_charts browse response.
/// Each chart ("Top songs", "Top music videos", "Trending") is a shelf
/// (carousel or music-shelf) whose header carries the title and whose
/// contents are `musicResponsiveListItemRenderer` song rows. Position in
/// the returned list is the rank. Shelves with no playable rows (e.g.
/// "Top artists", which are cards) are skipped.
enum ChartsParser {
    static func parse(data: Data) -> [NativeShellViewModel.ChartSection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var sections: [NativeShellViewModel.ChartSection] = []
        var idx = 0
        walk(json) { dict in
            guard let renderer = (dict["musicCarouselShelfRenderer"]
                                  ?? dict["musicShelfRenderer"]) as? [String: Any] else { return }
            let title = headerTitle(renderer)
            let contents = (renderer["contents"] as? [[String: Any]]) ?? []
            var seen = Set<String>()
            let tracks: [NativeShellViewModel.TrackSummary] = contents.compactMap { item in
                guard let r = item["musicResponsiveListItemRenderer"] as? [String: Any],
                      let t = extractTrack(r), seen.insert(t.id).inserted else { return nil }
                return t
            }
            guard !title.isEmpty, !tracks.isEmpty else { return }
            sections.append(.init(id: "chart-\(idx)-\(title)", title: title, tracks: tracks))
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

    /// Both shelf types carry their title behind a header renderer — a
    /// carousel uses `musicCarouselShelfBasicHeaderRenderer`, a music-shelf
    /// puts `title.runs` directly on the renderer.
    static func headerTitle(_ renderer: [String: Any]) -> String {
        if let basic = (renderer["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any],
           let runs = (basic["title"] as? [String: Any])?["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        if let runs = (renderer["title"] as? [String: Any])?["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    static func extractTrack(_ renderer: [String: Any]) -> NativeShellViewModel.TrackSummary? {
        let flex = (renderer["flexColumns"] as? [[String: Any]]) ?? []
        let title = textInFlex(flex, index: 0)
        let artist = textInFlex(flex, index: 1)
        let videoId: String? = {
            if let v = (renderer["playlistItemData"] as? [String: Any])?["videoId"] as? String { return v }
            // Fallback: the play-button overlay's watch endpoint.
            let overlay = renderer["overlay"] as? [String: Any]
            let content = (overlay?["musicItemThumbnailOverlayRenderer"] as? [String: Any])?["content"] as? [String: Any]
            let play = content?["musicPlayButtonRenderer"] as? [String: Any]
            let nav = play?["playNavigationEndpoint"] as? [String: Any]
            return (nav?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
        }()
        let thumbs = ((renderer["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])
            .flatMap { ($0["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] }
        guard let id = videoId, !title.isEmpty else { return nil }
        return .init(id: id, title: title, artist: artist, duration: nil,
                     thumbnailURL: thumbs?.last?["url"] as? String)
    }

    private static func textInFlex(_ columns: [[String: Any]], index: Int) -> String {
        guard columns.indices.contains(index),
              let inner = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let runs = (inner["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }
}

/// Search autocomplete. `music/get_search_suggestions` answers with
/// `searchSuggestionRenderer` nodes; the query text is split across bold and
/// plain runs ("dire" + "less"), so the runs have to be joined back together.
/// The response also carries the user's own past searches as
/// `historySuggestionRenderer` — we skip those, the shell keeps its own.
enum SearchSuggestionsParser {
    static func parse(data: Data, limit: Int = 8) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [String] = []
        var seen = Set<String>()
        walk(json) { dict in
            guard out.count < limit,
                  let r = dict["searchSuggestionRenderer"] as? [String: Any] else { return }
            let runs = (r["suggestion"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
            let text = runs.compactMap { $0["text"] as? String }.joined()
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { return }
            out.append(text)
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
}

/// Listening history. `FEmusic_history` comes back as one `musicShelfRenderer`
/// per day bucket ("Today", "Yesterday", "Last week"…) — the same shelf shape
/// the charts use, so the row/title extraction is shared with `ChartsParser`.
/// Repeats are kept: playing a song three times today is three history rows.
enum HistoryParser {
    static func parse(data: Data) -> [NativeShellViewModel.ChartSection] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var sections: [NativeShellViewModel.ChartSection] = []
        var idx = 0
        walk(json) { dict in
            guard let renderer = dict["musicShelfRenderer"] as? [String: Any] else { return }
            let title = ChartsParser.headerTitle(renderer)
            let contents = (renderer["contents"] as? [[String: Any]]) ?? []
            let tracks: [NativeShellViewModel.TrackSummary] = contents.compactMap { item in
                guard let r = item["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
                return ChartsParser.extractTrack(r)
            }
            guard !title.isEmpty, !tracks.isEmpty else { return }
            sections.append(.init(id: "history-\(idx)-\(title)", title: title, tracks: tracks))
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
