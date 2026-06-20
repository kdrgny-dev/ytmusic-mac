import Foundation

/// Native calls into YouTube's internal "InnerTube" API used by
/// music.youtube.com. We act as the WEB_REMIX client (id 67) and use the
/// cookies the user already logged in with via the WebView, so the
/// responses match what the YT Music web app sees.
///
/// Used for: library list, playlist contents, search, home shelves.
/// NOT used for: stream resolution (the WebView handles audio).
actor InnerTubeClient {
    enum APIError: Error {
        case invalidResponse
        case httpStatus(Int, body: String)
    }

    /// Diagnostic snapshot of the last call, surfaced in the UI when a
    /// browse/search returns nothing so we can tell what went wrong.
    struct LastCall: Sendable {
        let endpoint: String
        let responseStatus: Int
        let bodyPreview: String
    }
    private(set) var lastCall: LastCall?

    private let origin = "https://music.youtube.com"
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1")!
    private let session: URLSession
    private let auth: AuthSession

    init(auth: AuthSession) {
        self.auth = auth
        self.session = auth.session
    }

    /// `/browse` — fetches a YT Music "browse" page response. The browseId
    /// identifies what we want: `FEmusic_liked_playlists` for the user's
    /// playlist list, a playlist ID for its contents, etc.
    func browse(browseId: String, params: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context": ["client": clientDict()],
            "browseId": browseId
        ]
        if let params = params { body["params"] = params }
        return try await post("browse", body: body)
    }

    /// `/search` — full-text search across YT Music.
    func search(query: String, params: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context": ["client": clientDict()],
            "query": query
        ]
        if let params = params { body["params"] = params }
        return try await post("search", body: body)
    }

    /// Like / dislike actions on a videoId. YT's web app posts to these
    /// same endpoints — we just need the right body shape.
    @discardableResult
    func like(videoId: String) async throws -> Data {
        try await post("like/like", body: [
            "context": ["client": clientDict()],
            "target": ["videoId": videoId]
        ])
    }

    @discardableResult
    func dislike(videoId: String) async throws -> Data {
        try await post("like/dislike", body: [
            "context": ["client": clientDict()],
            "target": ["videoId": videoId]
        ])
    }

    @discardableResult
    func removeLike(videoId: String) async throws -> Data {
        try await post("like/removelike", body: [
            "context": ["client": clientDict()],
            "target": ["videoId": videoId]
        ])
    }

    /// "Save to library" for an entire playlist — same /like/like endpoint
    /// but with a playlistId target instead of videoId. Adds the playlist
    /// to the user's library so it shows up in the sidebar next refresh.
    @discardableResult
    func savePlaylist(playlistId: String) async throws -> Data {
        try await post("like/like", body: [
            "context": ["client": clientDict()],
            "target": ["playlistId": playlistId]
        ])
    }

    @discardableResult
    func removePlaylist(playlistId: String) async throws -> Data {
        try await post("like/removelike", body: [
            "context": ["client": clientDict()],
            "target": ["playlistId": playlistId]
        ])
    }

    /// Add a track to one of the user's playlists. playlistId is the bare
    /// "PL..." form (no "VL" prefix). dedupeOption is required by current
    /// YT — leaving it out triggers INVALID_ARGUMENT even on valid PLs.
    @discardableResult
    func addToPlaylist(playlistId: String, videoId: String) async throws -> Data {
        try await post("browse/edit_playlist", body: [
            "context": ["client": clientDict()],
            "playlistId": playlistId,
            "actions": [[
                "action": "ACTION_ADD_VIDEO",
                "addedVideoId": videoId,
                "dedupeOption": "DEDUPE_OPTION_SKIP"
            ]]
        ])
    }

    private func clientDict() -> [String: Any] {
        [
            "clientName": "WEB_REMIX",
            "clientVersion": "1.20240801.01.00",
            "hl": "en",
            "gl": "US"
        ]
    }

    private func post(_ endpoint: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        // X-Youtube-Client-Name=67 is WEB_REMIX. Some endpoints key on
        // this matching the context.client.clientName block.
        req.setValue("67", forHTTPHeaderField: "X-Youtube-Client-Name")
        req.setValue("1.20240801.01.00", forHTTPHeaderField: "X-Youtube-Client-Version")
        if let header = auth.sapisidHashHeader(origin: origin) {
            req.setValue(header, forHTTPHeaderField: "Authorization")
            req.setValue(origin, forHTTPHeaderField: "X-Origin")
            req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        lastCall = LastCall(
            endpoint: endpoint,
            responseStatus: http.statusCode,
            bodyPreview: String(data: data.prefix(300), encoding: .utf8) ?? ""
        )
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
