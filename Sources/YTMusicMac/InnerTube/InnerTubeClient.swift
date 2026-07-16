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
    /// Cookie-less, auth-less session for requests that must be anonymous
    /// (timed lyrics — see `post`).
    private let anonSession = URLSession(configuration: .ephemeral)

    init(auth: AuthSession) {
        self.auth = auth
        self.session = auth.session
    }

    /// `/browse` — fetches a YT Music "browse" page response. The browseId
    /// identifies what we want: `FEmusic_liked_playlists` for the user's
    /// playlist list, a playlist ID for its contents, etc.
    /// `mobile: true` sends the ANDROID_MUSIC client context, which is the
    /// only way YT returns timestamped (karaoke) lyrics — the web client
    /// only ever gives plain text.
    func browse(browseId: String, params: String? = nil, mobile: Bool = false) async throws -> Data {
        var body: [String: Any] = [
            "context": ["client": clientDict(mobile: mobile)],
            "browseId": browseId
        ]
        if let params = params { body["params"] = params }
        return try await post("browse", body: body, mobile: mobile)
    }

    /// `/browse` continuation — loads the next page of a list. The token
    /// comes from `continuationItemRenderer.continuationEndpoint.
    /// continuationCommand.token` in the previous response.
    func continuation(token: String) async throws -> Data {
        try await post("browse", body: [
            "context": ["client": clientDict()],
            "continuation": token
        ])
    }

    /// `/next` — watchNextResponse for a videoId. Contains the queue,
    /// the lyrics tab pointer, and related tracks. We use it primarily
    /// to grab the lyrics browseId (see WatchNextParser).
    /// Pass `playlistId` to get the queue for that list rather than an
    /// autoplay mix seeded by the single video.
    func next(videoId: String, playlistId: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context": ["client": clientDict()],
            "videoId": videoId
        ]
        if let playlistId, !playlistId.isEmpty { body["playlistId"] = playlistId }
        return try await post("next", body: body)
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

    /// Autocomplete for the search field. Same endpoint YT's own box uses.
    func searchSuggestions(query: String) async throws -> Data {
        try await post("music/get_search_suggestions", body: [
            "context": ["client": clientDict()],
            "input": query
        ])
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

    /// Create a new playlist. `privacy` is "PUBLIC" | "UNLISTED" | "PRIVATE".
    /// Optionally seed it with videoIds (e.g. the track the user was adding).
    /// Returns the new playlist's id ("VL…"/"PL…") on success.
    @discardableResult
    func createPlaylist(title: String,
                        description: String?,
                        privacy: String,
                        videoIds: [String]?) async throws -> String? {
        var body: [String: Any] = [
            "context": ["client": clientDict()],
            "title": title,
            "privacyStatus": privacy
        ]
        if let d = description, !d.isEmpty { body["description"] = d }
        if let v = videoIds, !v.isEmpty { body["videoIds"] = v }
        let data = try await post("playlist/create", body: body)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        // YT returns the bare id under "playlistId" (sometimes nested).
        if let id = json?["playlistId"] as? String { return id }
        return nil
    }

    /// `/feedback` — applies a feedback token (YT's mechanism for
    /// add/remove album to library, "not interested", etc.).
    @discardableResult
    func sendFeedback(token: String) async throws -> Data {
        try await post("feedback", body: [
            "context": ["client": clientDict()],
            "feedbackTokens": [token]
        ])
    }

    /// Remove rows from a playlist. Each item needs its videoId AND the
    /// playlist-entry setVideoId (from playlistItemData.playlistSetVideoId).
    @discardableResult
    func removeFromPlaylist(playlistId: String, items: [(videoId: String, setVideoId: String)]) async throws -> Data {
        let actions = items.map { item in
            [
                "action": "ACTION_REMOVE_VIDEO",
                "removedVideoId": item.videoId,
                "setVideoId": item.setVideoId
            ]
        }
        return try await post("browse/edit_playlist", body: [
            "context": ["client": clientDict()],
            "playlistId": playlistId,
            "actions": actions
        ])
    }

    /// Move a track within a playlist. `setVideoId` is the moved row; it lands
    /// right before `successorSetVideoId` (nil → moves to the end).
    @discardableResult
    func moveInPlaylist(playlistId: String, setVideoId: String, successorSetVideoId: String?) async throws -> Data {
        var action: [String: Any] = [
            "action": "ACTION_MOVE_VIDEO_BEFORE",
            "setVideoId": setVideoId
        ]
        if let s = successorSetVideoId { action["movedSetVideoIdSuccessor"] = s }
        return try await post("browse/edit_playlist", body: [
            "context": ["client": clientDict()],
            "playlistId": playlistId,
            "actions": [action]
        ])
    }

    /// Permanently delete one of the user's own playlists. playlistId is the
    /// bare "PL…" form (no "VL").
    @discardableResult
    func deletePlaylist(playlistId: String) async throws -> Data {
        try await post("playlist/delete", body: [
            "context": ["client": clientDict()],
            "playlistId": playlistId
        ])
    }

    /// Rename one of the user's own playlists.
    @discardableResult
    func renamePlaylist(playlistId: String, name: String) async throws -> Data {
        try await post("browse/edit_playlist", body: [
            "context": ["client": clientDict()],
            "playlistId": playlistId,
            "actions": [[
                "action": "ACTION_SET_PLAYLIST_NAME",
                "playlistName": name
            ]]
        ])
    }

    /// Add several tracks to a playlist in one edit_playlist call.
    @discardableResult
    func addToPlaylist(playlistId: String, videoIds: [String]) async throws -> Data {
        let actions = videoIds.map { vid in
            [
                "action": "ACTION_ADD_VIDEO",
                "addedVideoId": vid,
                "dedupeOption": "DEDUPE_OPTION_SKIP"
            ]
        }
        return try await post("browse/edit_playlist", body: [
            "context": ["client": clientDict()],
            "playlistId": playlistId,
            "actions": actions
        ])
    }

    /// ANDROID_MUSIC version used only for timed-lyrics requests. YT rejects
    /// stale mobile clients, so keep this easy to bump.
    static let androidMusicVersion = "7.21.50"

    private func clientDict(mobile: Bool = false) -> [String: Any] {
        if mobile {
            // Pinned to en/US. This client only exists for timed lyrics and it
            // is fragile — the working configuration was found by trial (see
            // the anonymous-session note in `post`). The user's language has
            // no business here: lyrics come back in whatever language the
            // track is in, not `hl`.
            return [
                "clientName": "ANDROID_MUSIC",
                "clientVersion": Self.androidMusicVersion,
                "hl": "en",
                "gl": "US"
            ]
        }
        return [
            "clientName": "WEB_REMIX",
            "clientVersion": "1.20240801.01.00",
            "hl": LocaleSnapshot.language.code,
            "gl": LocaleSnapshot.region.code
        ]
    }

    private func post(_ endpoint: String, body: [String: Any], mobile: Bool = false) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        // X-Youtube-Client-Name=67 is WEB_REMIX, 21 is ANDROID_MUSIC. Some
        // endpoints key on this matching the context.client.clientName block.
        req.setValue(mobile ? "21" : "67", forHTTPHeaderField: "X-Youtube-Client-Name")
        req.setValue(mobile ? Self.androidMusicVersion : "1.20240801.01.00",
                     forHTTPHeaderField: "X-Youtube-Client-Version")
        // The mobile (timed-lyrics) request MUST be anonymous: the web session's
        // SAPISIDHASH auth + cookies conflict with the ANDROID_MUSIC client and
        // YT silently drops the timed lyrics. Everything else keeps the user's
        // auth. `anonSession` is cookie-less so no session cookies leak either.
        if !mobile, let header = auth.sapisidHashHeader(origin: origin) {
            req.setValue(header, forHTTPHeaderField: "Authorization")
            req.setValue(origin, forHTTPHeaderField: "X-Origin")
            req.setValue("0", forHTTPHeaderField: "X-Goog-AuthUser")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await (mobile ? anonSession : session).data(for: req)
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
