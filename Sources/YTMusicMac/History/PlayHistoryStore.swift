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
        case .week:  return "Bu hafta"
        case .month: return "Bu ay"
        case .year:  return "Bu yıl"
        case .all:   return "Tüm zamanlar"
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
                       artworkURL: $0["artwork_url"]?.stringValue)
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
        return rows.map {
            TrackStat(videoId: $0["video_id"]?.stringValue ?? "",
                      title: $0["title"]?.stringValue ?? "",
                      artist: $0["artist"]?.stringValue ?? "",
                      plays: Int($0["plays"]?.intValue ?? 0),
                      listenedMs: $0["listened"]?.intValue ?? 0,
                      artworkURL: $0["artwork_url"]?.stringValue)
        }
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
