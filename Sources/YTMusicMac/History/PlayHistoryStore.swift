import Foundation

/// One completed listen. `playedMs` is how much of the track actually rolled
/// past, which is not the same as `durationMs` when the user skips near the end.
struct PlayRecord: Equatable {
    var videoId: String
    var title: String
    var artist: String
    var album: String?
    var durationMs: Int64
    var playedMs: Int64
    var startedAt: Date
    var artworkURL: String?
}

struct ArtistStat: Equatable, Identifiable {
    let artist: String
    let plays: Int
    let listenedMs: Int64
    let artworkURL: String?

    var id: String { artist }
}

struct TrackStat: Equatable, Identifiable {
    let videoId: String
    let title: String
    let artist: String
    let plays: Int
    let listenedMs: Int64
    let artworkURL: String?

    var id: String { "\(title)|\(artist)" }
}

/// Everything the statistics page renders, for one time window.
struct ListeningStats: Equatable {
    let range: StatsRange
    let totalMs: Int64
    let playCount: Int
    let distinctArtists: Int
    let topArtists: [ArtistStat]
    let topTracks: [TrackStat]
    let daily: [DayStat]

    var isEmpty: Bool { playCount == 0 }

    static func empty(_ range: StatsRange) -> ListeningStats {
        ListeningStats(range: range, totalMs: 0, playCount: 0, distinctArtists: 0,
                       topArtists: [], topTracks: [], daily: [])
    }
}

/// One calendar day's listening total, for the activity bars.
struct DayStat: Equatable, Identifiable {
    let day: Date
    let listenedMs: Int64

    var id: TimeInterval { day.timeIntervalSince1970 }
}

/// The window a statistics page is showing.
enum StatsRange: String, CaseIterable, Identifiable {
    case week, month, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:  return L10n.t("stats.range.week")
        case .month: return L10n.t("stats.range.month")
        case .year:  return L10n.t("stats.range.year")
        case .all:   return L10n.t("stats.range.all")
        }
    }

    func start(from now: Date) -> Date {
        switch self {
        case .week:  return now.addingTimeInterval(-7 * 86_400)
        case .month: return now.addingTimeInterval(-30 * 86_400)
        case .year:  return now.addingTimeInterval(-365 * 86_400)
        case .all:   return Date(timeIntervalSince1970: 0)
        }
    }

    /// Day-by-day bars only make sense over a short window; a year would be
    /// 365 slivers.
    var showsDailyActivity: Bool { self == .week || self == .month }
}

/// Local listening history. YouTube Music exposes no per-month/per-week stats
/// of its own, so we accumulate our own from what the player bridge already
/// reports on every track change.
final class PlayHistoryStore {
    static let shared: PlayHistoryStore? = {
        do {
            return try PlayHistoryStore(path: PlayHistoryStore.defaultURL().path)
        } catch {
            NSLog("[history] disabled, could not open store: \(error)")
            return nil
        }
    }()

    private let db: SQLiteDatabase
    /// SQLiteDatabase isn't thread-safe and `record(_:)` is called from
    /// whatever thread the JS bridge happens to deliver on.
    private let queue = DispatchQueue(label: "com.ytmusicmac.history")

    init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try migrate()
    }

    static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = support.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "YTMusicMac", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }

    /// Each step is guarded by its own version check, so an existing v1 file
    /// gets only the ALTER and a fresh file walks through both steps.
    private func migrate() throws {
        if db.userVersion < 1 {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS plays (
                  id          INTEGER PRIMARY KEY,
                  video_id    TEXT    NOT NULL,
                  title       TEXT    NOT NULL,
                  artist      TEXT    NOT NULL,
                  album       TEXT,
                  duration_ms INTEGER NOT NULL DEFAULT 0,
                  played_ms   INTEGER NOT NULL DEFAULT 0,
                  started_at  INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_plays_started ON plays(started_at);
                CREATE INDEX IF NOT EXISTS idx_plays_artist  ON plays(artist, started_at);
                """)
            db.userVersion = 1
        }
        if db.userVersion < 2 {
            try db.execute("ALTER TABLE plays ADD COLUMN artwork_url TEXT;")
            db.userVersion = 2
        }
        if db.userVersion < 3 {
            // Last.fm genre tags, cached per artist. YT Music exposes no genre
            // at all, so the radio page's genre rows have nowhere else to come
            // from — and refetching on every page open would mean dozens of
            // requests for data that changes maybe once a year.
            try db.execute("""
                CREATE TABLE IF NOT EXISTS artist_tags (
                  artist     TEXT PRIMARY KEY,
                  genres     TEXT,
                  decades    TEXT,
                  fetched_at INTEGER NOT NULL DEFAULT 0
                );
                """)
            db.userVersion = 3
        }
    }

    // MARK: - Writing

    /// Fire-and-forget: a failed insert must never interrupt playback.
    func record(_ play: PlayRecord) {
        queue.async { [db] in
            do {
                try db.run("""
                    INSERT INTO plays (video_id, title, artist, album, duration_ms, played_ms, started_at, artwork_url)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                    """, [
                        .text(play.videoId),
                        .text(play.title),
                        .text(play.artist),
                        play.album.map { SQLValue.text($0) } ?? .null,
                        .int(play.durationMs),
                        .int(play.playedMs),
                        .int(Int64(play.startedAt.timeIntervalSince1970)),
                        play.artworkURL.map { SQLValue.text($0) } ?? .null
                    ])
            } catch {
                NSLog("[history] insert failed: \(error)")
            }
        }
    }

    /// Block until every enqueued insert has landed. `record(_:)` is async, so
    /// on app quit the process would otherwise exit before the last listen of
    /// the session is written.
    func waitForPendingWrites() {
        queue.sync {}
    }

    // MARK: - Reading

    /// `artwork_url` is a bare column next to `MAX(started_at)`. SQLite defines
    /// that to mean "the value from the row that produced the max", so each
    /// artist shows the cover of whatever you played by them most recently.
    func topArtists(since: Date, limit: Int = 10) -> [ArtistStat] {
        let rows = read("""
            SELECT artist, COUNT(*) AS plays, SUM(played_ms) AS listened,
                   MAX(started_at) AS last_at, artwork_url
            FROM plays WHERE started_at >= ? AND artist <> ''
            GROUP BY artist ORDER BY plays DESC, listened DESC LIMIT ?;
            """, [.int(Int64(since.timeIntervalSince1970)), .int(Int64(limit))])
        return rows.map {
            ArtistStat(artist: $0["artist"]?.stringValue ?? "",
                       plays: Int($0["plays"]?.intValue ?? 0),
                       listenedMs: $0["listened"]?.intValue ?? 0,
                       artworkURL: YTImageURL.resized($0["artwork_url"]?.stringValue, to: Self.coverSize))
        }
    }

    func topTracks(since: Date, limit: Int = 10) -> [TrackStat] {
        // Group by title+artist rather than video_id: the same song reached
        // from an album and from a playlist can carry different ids.
        let rows = read("""
            SELECT title, artist, MIN(video_id) AS video_id,
                   COUNT(*) AS plays, SUM(played_ms) AS listened,
                   MAX(started_at) AS last_at, artwork_url
            FROM plays WHERE started_at >= ? AND title <> ''
            GROUP BY title, artist ORDER BY plays DESC, listened DESC LIMIT ?;
            """, [.int(Int64(since.timeIntervalSince1970)), .int(Int64(limit))])
        return rows.map(Self.trackStat)
    }

    /// Each of your most-played artists paired with their single most-played
    /// track, ordered by how much you play the artist overall.
    ///
    /// This is what seeds artist radios. YT only hands out an artist-radio id
    /// through its own artist page, which we don't parse, so a radio is always
    /// seeded from a track — the artist's biggest one is the closest stand-in.
    /// Rows without a `video_id` are useless as a seed and dropped.
    func topTrackPerArtist(since: Date, limit: Int = 12) -> [TrackStat] {
        let rows = read("""
            SELECT artist, title, video_id, plays, listened, artwork_url FROM (
                SELECT artist, title, MIN(video_id) AS video_id,
                       COUNT(*) AS plays, SUM(played_ms) AS listened, artwork_url,
                       ROW_NUMBER() OVER (
                           PARTITION BY artist ORDER BY COUNT(*) DESC, SUM(played_ms) DESC
                       ) AS rn,
                       SUM(COUNT(*)) OVER (PARTITION BY artist) AS artist_plays
                FROM plays
                WHERE started_at >= ? AND artist <> '' AND title <> '' AND video_id <> ''
                GROUP BY artist, title
            )
            WHERE rn = 1
            ORDER BY artist_plays DESC, listened DESC
            LIMIT ?;
            """, [.int(Int64(since.timeIntervalSince1970)), .int(Int64(limit))])
        return rows.map(Self.trackStat)
    }

    /// Tracks played inside a window. Drives the archive shelves ("a year ago
    /// today"), so the window is usually a single day far in the past.
    func tracksPlayedBetween(start: Date, end: Date, limit: Int = 20) -> [TrackStat] {
        let rows = read("""
            SELECT title, artist, MIN(video_id) AS video_id,
                   COUNT(*) AS plays, SUM(played_ms) AS listened,
                   MAX(started_at) AS last_at, artwork_url
            FROM plays
            WHERE started_at >= ? AND started_at < ? AND title <> '' AND video_id <> ''
            GROUP BY title, artist
            ORDER BY plays DESC, listened DESC LIMIT ?;
            """, [.int(Int64(start.timeIntervalSince1970)),
                  .int(Int64(end.timeIntervalSince1970)),
                  .int(Int64(limit))])
        return rows.map(Self.trackStat)
    }

    /// The last distinct tracks you played, newest first. `topTracks` groups the
    /// same way but ranks by play count, which answers "what do you love", not
    /// "what were you just listening to".
    func recentlyPlayed(limit: Int = 20) -> [TrackStat] {
        let rows = read("""
            SELECT title, artist, MIN(video_id) AS video_id,
                   COUNT(*) AS plays, SUM(played_ms) AS listened,
                   MAX(started_at) AS last_at, artwork_url
            FROM plays
            WHERE title <> '' AND video_id <> ''
            GROUP BY title, artist
            ORDER BY last_at DESC LIMIT ?;
            """, [.int(Int64(limit))])
        return rows.map(Self.trackStat)
    }

    /// Tracks you played a lot once and haven't touched since `playedBefore`.
    /// `minPlays` is what separates a forgotten favourite from something you
    /// skipped past once a year ago.
    func forgottenFavorites(playedBefore: Date, minPlays: Int = 3, limit: Int = 20) -> [TrackStat] {
        let rows = read("""
            SELECT title, artist, MIN(video_id) AS video_id,
                   COUNT(*) AS plays, SUM(played_ms) AS listened,
                   MAX(started_at) AS last_at, artwork_url
            FROM plays
            WHERE title <> '' AND video_id <> ''
            GROUP BY title, artist
            HAVING MAX(started_at) < ? AND COUNT(*) >= ?
            ORDER BY plays DESC, listened DESC LIMIT ?;
            """, [.int(Int64(playedBefore.timeIntervalSince1970)),
                  .int(Int64(minPlays)),
                  .int(Int64(limit))])
        return rows.map(Self.trackStat)
    }

    /// What the player bar was showing gets stored, and that's a 60px
    /// thumbnail — every consumer of these rows renders covers far bigger than
    /// that. Upgrading the URL's size suffix here fixes the rows already on
    /// disk as well as new ones.
    static let coverSize = 544

    private static func trackStat(_ row: SQLRow) -> TrackStat {
        TrackStat(videoId: row["video_id"]?.stringValue ?? "",
                  title: row["title"]?.stringValue ?? "",
                  artist: row["artist"]?.stringValue ?? "",
                  plays: Int(row["plays"]?.intValue ?? 0),
                  listenedMs: row["listened"]?.intValue ?? 0,
                  artworkURL: YTImageURL.resized(row["artwork_url"]?.stringValue, to: coverSize))
    }

    func totalListenedMs(since: Date) -> Int64 {
        read("SELECT COALESCE(SUM(played_ms), 0) AS total FROM plays WHERE started_at >= ?;",
             [.int(Int64(since.timeIntervalSince1970))])
            .first?["total"]?.intValue ?? 0
    }

    func playCount(since: Date) -> Int {
        Int(read("SELECT COUNT(*) AS n FROM plays WHERE started_at >= ?;",
                 [.int(Int64(since.timeIntervalSince1970))])
            .first?["n"]?.intValue ?? 0)
    }

    func distinctArtistCount(since: Date) -> Int {
        Int(read("SELECT COUNT(DISTINCT artist) AS n FROM plays WHERE started_at >= ? AND artist <> '';",
                 [.int(Int64(since.timeIntervalSince1970))])
            .first?["n"]?.intValue ?? 0)
    }

    /// Listening totals per calendar day, in the user's local timezone —
    /// grouping on UTC would smear late-night listening into the next day.
    func dailyActivity(since: Date) -> [DayStat] {
        let rows = read("""
            SELECT date(started_at, 'unixepoch', 'localtime') AS day,
                   SUM(played_ms) AS listened
            FROM plays WHERE started_at >= ?
            GROUP BY day ORDER BY day;
            """, [.int(Int64(since.timeIntervalSince1970))])

        let parser = DateFormatter()
        // A fixed-format formatter must pin a POSIX locale, otherwise the
        // user's regional calendar drives parsing and "yyyy" is read as a
        // non-Gregorian year — on a Mac set to e.g. an Islamic or Buddhist
        // calendar every row would fail to parse and the chart would silently
        // come up empty. The SQL emits Gregorian ISO dates regardless.
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        return rows.compactMap { row in
            guard let day = row["day"]?.stringValue.flatMap({ parser.date(from: $0) }) else { return nil }
            return DayStat(day: day, listenedMs: row["listened"]?.intValue ?? 0)
        }
    }

    /// Everything one statistics page needs, gathered in a single hop off the
    /// main thread. `now` is injectable so the tests aren't clock-dependent.
    func snapshot(range: StatsRange, now: Date = Date()) -> ListeningStats {
        let since = range.start(from: now)
        return ListeningStats(
            range: range,
            totalMs: totalListenedMs(since: since),
            playCount: playCount(since: since),
            distinctArtists: distinctArtistCount(since: since),
            topArtists: topArtists(since: since),
            topTracks: topTracks(since: since),
            daily: range.showsDailyActivity
                ? Self.fillMissingDays(dailyActivity(since: since), since: since, now: now)
                : [])
    }

    /// A day nobody listened produces no row, but the chart needs a zero-height
    /// bar there — otherwise a quiet Tuesday just vanishes and the week reads
    /// as six days long.
    static func fillMissingDays(_ stats: [DayStat], since: Date, now: Date) -> [DayStat] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let byDay = Dictionary(stats.map { (calendar.startOfDay(for: $0.day), $0.listenedMs) },
                               uniquingKeysWith: +)

        var days: [DayStat] = []
        var cursor = calendar.startOfDay(for: since)
        let last = calendar.startOfDay(for: now)
        while cursor <= last {
            days.append(DayStat(day: cursor, listenedMs: byDay[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Synchronous read on the serial queue so callers see every write that
    /// `record(_:)` has already enqueued.
    // MARK: - Artist tag cache

    /// Cached Last.fm genres/decades for the artists asked about. Artists we've
    /// never looked up are absent from the result; artists Last.fm didn't know
    /// come back with an empty digest, which is the difference that stops us
    /// asking about them again.
    func tags(for artists: [String]) -> [String: TagTaxonomy.Digest] {
        guard !artists.isEmpty else { return [:] }
        let placeholders = Array(repeating: "?", count: artists.count).joined(separator: ",")
        let rows = read("SELECT artist, genres, decades FROM artist_tags WHERE artist IN (\(placeholders));",
                        artists.map { SQLValue.text($0) })
        var out: [String: TagTaxonomy.Digest] = [:]
        for row in rows {
            guard let artist = row["artist"]?.stringValue else { continue }
            out[artist] = TagTaxonomy.Digest(
                genres: Self.decodeList(row["genres"]?.stringValue) ?? [],
                decades: Self.decodeList(row["decades"]?.stringValue) ?? [])
        }
        return out
    }

    func hasTags(for artist: String) -> Bool {
        !read("SELECT 1 FROM artist_tags WHERE artist = ? LIMIT 1;", [.text(artist)]).isEmpty
    }

    /// Which of these artists we still have to ask Last.fm about.
    func artistsMissingTags(from artists: [String]) -> [String] {
        guard !artists.isEmpty else { return [] }
        let known = Set(tags(for: artists).keys)
        return artists.filter { !known.contains($0) }
    }

    /// Synchronous, unlike `record(_:)`: the caller is a background task that
    /// wants the write visible to its own next read.
    func saveTags(artist: String, digest: TagTaxonomy.Digest) {
        guard !artist.isEmpty else { return }
        queue.sync { [db] in
            do {
                try db.run("""
                    INSERT INTO artist_tags (artist, genres, decades, fetched_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(artist) DO UPDATE SET
                      genres = excluded.genres,
                      decades = excluded.decades,
                      fetched_at = excluded.fetched_at;
                    """, [
                        .text(artist),
                        .text(Self.encodeList(digest.genres)),
                        .text(Self.encodeList(digest.decades)),
                        .int(Int64(Date().timeIntervalSince1970))
                    ])
            } catch {
                NSLog("[history] tag write failed: \(error)")
            }
        }
    }

    private static func encodeList<T: Encodable>(_ list: [T]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeList<T: Decodable>(_ json: String?) -> [T]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }

    private func read(_ sql: String, _ params: [SQLValue]) -> [SQLRow] {
        queue.sync { [db] in
            do { return try db.query(sql, params) }
            catch {
                NSLog("[history] query failed: \(error)")
                return []
            }
        }
    }
}
