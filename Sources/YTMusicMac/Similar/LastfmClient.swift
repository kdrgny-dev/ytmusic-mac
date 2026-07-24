import Foundation

/// A recommended track before we've matched it to a YouTube video.
struct SimilarCandidate: Equatable {
    let artist: String
    let track: String
    /// 1.0 = Last.fm's strongest match; artist-fallback picks are halved so
    /// direct similar tracks always outrank them.
    let score: Double

    /// Dedup key — same song from two sources collapses to one.
    var key: String { "\(artist.lowercased())—\(track.lowercased())" }
}

/// Last.fm similar-track lookups. Ported from the justlist project: prefer
/// `track.getsimilar`, and when that's thin (common for new releases) fall
/// back to similar *artists* and their top tracks. Benzerlik kaynağı YT'nin
/// kapalı radyosu değil, Last.fm topluluk verisi.
final class LastfmClient {
    private let apiKey: String
    private let session: URLSession
    private let base = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    init(apiKey: String = LastfmSecret.apiKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    /// The whole recommendation pipeline for one seed track.
    func recommendations(artist: String, track: String, target: Int = 30) async -> [SimilarCandidate] {
        var out: [SimilarCandidate] = []

        let similar = await similarTracks(artist: artist, track: track, limit: min(target * 2, 100))
        out.append(contentsOf: similar)

        // Thin result → widen to similar artists and their top tracks.
        if out.count < target {
            let artists = await similarArtists(artist: artist, limit: 10)
            for sa in artists {
                if out.count >= target * 2 { break }
                let tops = await artistTopTracks(artist: sa.name, limit: 3)
                for t in tops {
                    out.append(SimilarCandidate(artist: sa.name, track: t, score: sa.match * 0.5))
                }
            }
        }

        return Self.merge(out)
    }

    /// Dedup by artist+track keeping the higher score, then rank. Pure so the
    /// tests can pin the ordering without any network.
    static func merge(_ candidates: [SimilarCandidate]) -> [SimilarCandidate] {
        var best: [String: SimilarCandidate] = [:]
        for c in candidates where !c.artist.isEmpty && !c.track.isEmpty {
            if let existing = best[c.key], existing.score >= c.score { continue }
            best[c.key] = c
        }
        return best.values.sorted {
            $0.score != $1.score ? $0.score > $1.score
                : $0.key < $1.key   // stable tiebreak so output is deterministic
        }
    }

    // MARK: - Endpoints

    private func similarTracks(artist: String, track: String, limit: Int) async -> [SimilarCandidate] {
        let json = await get(["method": "track.getsimilar", "artist": artist, "track": track,
                              "limit": String(limit), "autocorrect": "1"])
        let tracks = ((json?["similartracks"] as? [String: Any])?["track"]) ?? json?["similartracks"]
        return Self.arrayValue(tracks).compactMap { item in
            guard let name = item["name"] as? String,
                  let artistName = (item["artist"] as? [String: Any])?["name"] as? String
            else { return nil }
            return SimilarCandidate(artist: artistName, track: name,
                                    score: Self.doubleValue(item["match"]))
        }
    }

    private func similarArtists(artist: String, limit: Int) async -> [(name: String, match: Double)] {
        let json = await get(["method": "artist.getsimilar", "artist": artist,
                              "limit": String(limit), "autocorrect": "1"])
        let arr = (json?["similarartists"] as? [String: Any])?["artist"]
        return Self.arrayValue(arr).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return (name, Self.doubleValue(item["match"]))
        }
    }

    private func artistTopTracks(artist: String, limit: Int) async -> [String] {
        let json = await get(["method": "artist.gettoptracks", "artist": artist,
                              "limit": String(limit), "autocorrect": "1"])
        let arr = (json?["toptracks"] as? [String: Any])?["track"]
        return Self.arrayValue(arr).compactMap { $0["name"] as? String }
    }

    /// The artist's top tags — the app's only source of genre, since YT Music
    /// exposes none. `count` is Last.fm's 0-100 relative weight, which is what
    /// lets `TagTaxonomy` throw away tags only one person applied.
    func topTags(artist: String) async -> [(name: String, count: Int)] {
        let json = await get(["method": "artist.gettoptags", "artist": artist,
                              "autocorrect": "1"])
        let arr = (json?["toptags"] as? [String: Any])?["tag"]
        return Self.parseTags(arr)
    }

    /// Split out so it can be tested against a captured response without a
    /// network round trip.
    static func parseTags(_ any: Any?) -> [(name: String, count: Int)] {
        arrayValue(any).compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            return (name: name, count: Int(doubleValue(item["count"])))
        }
    }

    // MARK: - Transport

    private func get(_ params: [String: String]) async -> [String: Any]? {
        guard isConfigured else { return nil }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = (params.merging(["api_key": apiKey, "format": "json"]) { a, _ in a })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    // MARK: - Last.fm quirks

    /// Last.fm returns a single result as an object, not a one-element array.
    static func arrayValue(_ any: Any?) -> [[String: Any]] {
        if let arr = any as? [[String: Any]] { return arr }
        if let one = any as? [String: Any] { return [one] }
        return []
    }

    /// `match` arrives as a string ("0.9312"), sometimes a number, sometimes
    /// absent.
    static func doubleValue(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) ?? 0 }
        if let n = any as? NSNumber { return n.doubleValue }
        return 0
    }
}
