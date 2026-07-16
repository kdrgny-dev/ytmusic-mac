import XCTest
@testable import YTMusicMac

final class PlayHistoryStoreTests: XCTestCase {
    private var store: PlayHistoryStore!
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        store = try PlayHistoryStore(path: ":memory:")
    }

    private func record(_ artist: String, _ title: String, daysAgo: Double = 0, playedMs: Int64 = 60_000,
                        artworkURL: String? = nil) {
        store.record(PlayRecord(
            videoId: "id-\(title)", title: title, artist: artist, album: nil,
            durationMs: 200_000, playedMs: playedMs,
            startedAt: epoch.addingTimeInterval(-daysAgo * 86_400),
            artworkURL: artworkURL))
    }

    func testTopArtistsRanksByPlayCount() {
        record("Radiohead", "Reckoner")
        record("Radiohead", "Nude")
        record("Portishead", "Roads")

        let top = store.topArtists(since: epoch.addingTimeInterval(-86_400))
        XCTAssertEqual(top.map(\.artist), ["Radiohead", "Portishead"])
        XCTAssertEqual(top.first?.plays, 2)
        XCTAssertEqual(top.first?.listenedMs, 120_000)
    }

    func testStatsRespectTheTimeWindow() {
        record("Old", "Ancient", daysAgo: 40)
        record("New", "Fresh", daysAgo: 1)

        let lastMonth = store.topArtists(since: epoch.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(lastMonth.map(\.artist), ["New"])
        XCTAssertEqual(store.playCount(since: epoch.addingTimeInterval(-30 * 86_400)), 1)
    }

    // MARK: - Radio / archive queries

    func testTopTrackPerArtistPicksEachArtistsBiggestTrack() {
        record("Radiohead", "Nude")
        record("Radiohead", "Nude")
        record("Radiohead", "Nude")
        record("Radiohead", "Reckoner")
        record("Portishead", "Roads")
        record("Portishead", "Roads")

        let seeds = store.topTrackPerArtist(since: epoch.addingTimeInterval(-86_400))
        XCTAssertEqual(seeds.map(\.artist), ["Radiohead", "Portishead"])
        XCTAssertEqual(seeds.map(\.title), ["Nude", "Roads"])
    }

    /// Ordering is by the artist's total plays, not by their top track's —
    /// an artist you play constantly across many songs must outrank one you
    /// played a single song by slightly more often.
    func testTopTrackPerArtistOrdersByArtistTotalNotTrackTotal() {
        for _ in 0..<4 { record("OneHit", "Only Song") }
        for _ in 0..<3 { record("Broad", "A") }
        for _ in 0..<3 { record("Broad", "B") }

        let seeds = store.topTrackPerArtist(since: epoch.addingTimeInterval(-86_400))
        XCTAssertEqual(seeds.first?.artist, "Broad")   // 6 plays total vs 4
    }

    /// A seed with no videoId would navigate to a broken watch URL.
    func testTopTrackPerArtistSkipsRowsWithoutAVideoId() {
        store.record(PlayRecord(videoId: "", title: "Ghost", artist: "Nobody", album: nil,
                                durationMs: 200_000, playedMs: 60_000, startedAt: epoch))
        record("Real", "Song")

        let seeds = store.topTrackPerArtist(since: epoch.addingTimeInterval(-86_400))
        XCTAssertEqual(seeds.map(\.artist), ["Real"])
    }

    func testTopTrackPerArtistRespectsTheWindow() {
        record("Old", "Ancient", daysAgo: 40)
        record("New", "Fresh", daysAgo: 1)

        let seeds = store.topTrackPerArtist(since: epoch.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(seeds.map(\.artist), ["New"])
    }

    func testTracksPlayedBetweenIsHalfOpen() {
        record("A", "Inside", daysAgo: 5)
        record("B", "OnTheEdge", daysAgo: 3)   // exactly at `end`
        record("C", "Outside", daysAgo: 1)

        let start = epoch.addingTimeInterval(-6 * 86_400)
        let end = epoch.addingTimeInterval(-3 * 86_400)
        let tracks = store.tracksPlayedBetween(start: start, end: end)
        // `end` is exclusive, so the row sitting exactly on it is out.
        XCTAssertEqual(tracks.map(\.title), ["Inside"])
    }

    func testTracksPlayedBetweenReturnsNothingForAnEmptyWindow() {
        record("A", "Song", daysAgo: 5)
        let t = epoch.addingTimeInterval(-100 * 86_400)
        XCTAssertTrue(store.tracksPlayedBetween(start: t, end: t).isEmpty)
    }

    func testForgottenFavoritesNeedsBothAgeAndPlayCount() {
        // Played a lot, long ago → forgotten favourite.
        for _ in 0..<4 { record("Loved", "Anthem", daysAgo: 200) }
        // Played once, long ago → not a favourite, just noise.
        record("Skipped", "Meh", daysAgo: 200)
        // Played a lot, recently → not forgotten.
        for _ in 0..<4 { record("Current", "Hit", daysAgo: 1) }

        let forgotten = store.forgottenFavorites(playedBefore: epoch.addingTimeInterval(-90 * 86_400),
                                                 minPlays: 3)
        XCTAssertEqual(forgotten.map(\.title), ["Anthem"])
    }

    /// A track played long ago AND recently isn't forgotten — the cutoff has
    /// to test the most recent play, not any play.
    func testForgottenFavoritesExcludesTracksRevivedRecently() {
        for _ in 0..<4 { record("Revived", "Comeback", daysAgo: 200) }
        record("Revived", "Comeback", daysAgo: 2)

        let forgotten = store.forgottenFavorites(playedBefore: epoch.addingTimeInterval(-90 * 86_400),
                                                 minPlays: 3)
        XCTAssertTrue(forgotten.isEmpty)
    }

    func testTopTracksGroupsTheSameSongAcrossVideoIds() {
        // Same song reached from an album and from a playlist: different ids.
        store.record(PlayRecord(videoId: "aaa", title: "Roads", artist: "Portishead",
                                album: nil, durationMs: 200_000, playedMs: 60_000, startedAt: epoch))
        store.record(PlayRecord(videoId: "bbb", title: "Roads", artist: "Portishead",
                                album: nil, durationMs: 200_000, playedMs: 60_000, startedAt: epoch))

        let top = store.topTracks(since: epoch.addingTimeInterval(-86_400))
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top.first?.plays, 2)
    }

    func testTotalListenedMs() {
        record("A", "one", playedMs: 30_000)
        record("B", "two", playedMs: 45_000)
        XCTAssertEqual(store.totalListenedMs(since: epoch.addingTimeInterval(-86_400)), 75_000)
    }

    func testEmptyStoreReturnsZeroes() {
        XCTAssertEqual(store.playCount(since: epoch.addingTimeInterval(-86_400)), 0)
        XCTAssertEqual(store.totalListenedMs(since: epoch.addingTimeInterval(-86_400)), 0)
        XCTAssertTrue(store.topArtists(since: epoch.addingTimeInterval(-86_400)).isEmpty)
    }

    /// The real store lives on disk and is reopened on every launch, so
    /// migrate() has to be a no-op the second time around.
    func testDataSurvivesReopenAndMigrationIsIdempotent() throws {
        let path = NSTemporaryDirectory() + "ytm-history-test-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = try PlayHistoryStore(path: path)
        first.record(PlayRecord(videoId: "x", title: "Roads", artist: "Portishead",
                                album: nil, durationMs: 200_000, playedMs: 60_000, startedAt: epoch))
        XCTAssertEqual(first.playCount(since: epoch.addingTimeInterval(-86_400)), 1)

        let reopened = try PlayHistoryStore(path: path)
        XCTAssertEqual(reopened.playCount(since: epoch.addingTimeInterval(-86_400)), 1)
        XCTAssertEqual(reopened.topArtists(since: epoch.addingTimeInterval(-86_400)).first?.artist,
                       "Portishead")
    }

    func testSchemaVersionIsStamped() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        XCTAssertEqual(db.userVersion, 0)
        db.userVersion = 1
        XCTAssertEqual(db.userVersion, 1)
    }

    /// Anyone who ran the first build has a v1 file with no artwork column.
    /// Opening it must add the column and keep every row.
    func testMigratesExistingV1FileWithoutLosingRows() throws {
        let path = NSTemporaryDirectory() + "ytm-v1-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let old = try SQLiteDatabase(path: path)
        try old.execute("""
            CREATE TABLE plays (
              id INTEGER PRIMARY KEY, video_id TEXT NOT NULL, title TEXT NOT NULL,
              artist TEXT NOT NULL, album TEXT, duration_ms INTEGER NOT NULL DEFAULT 0,
              played_ms INTEGER NOT NULL DEFAULT 0, started_at INTEGER NOT NULL);
            """)
        try old.run("INSERT INTO plays (video_id,title,artist,duration_ms,played_ms,started_at) VALUES (?,?,?,?,?,?);",
                    [.text("v"), .text("Roads"), .text("Portishead"), .int(200_000), .int(60_000),
                     .int(Int64(epoch.timeIntervalSince1970))])
        old.userVersion = 1

        let migrated = try PlayHistoryStore(path: path)
        XCTAssertEqual(migrated.playCount(since: epoch.addingTimeInterval(-86_400)), 1)
        // The new column exists and is simply empty for the pre-existing row.
        XCTAssertNil(migrated.topArtists(since: epoch.addingTimeInterval(-86_400)).first?.artworkURL)
    }

    func testArtworkComesFromTheMostRecentPlay() {
        record("Portishead", "Roads", daysAgo: 3, artworkURL: "old.jpg")
        record("Portishead", "Glory Box", daysAgo: 1, artworkURL: "new.jpg")

        let top = store.topArtists(since: epoch.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(top.first?.artworkURL, "new.jpg")
    }

    func testSnapshotAggregatesEverythingForTheRange() {
        record("A", "one", daysAgo: 1, playedMs: 60_000)
        record("A", "two", daysAgo: 2, playedMs: 60_000)
        record("B", "three", daysAgo: 40, playedMs: 60_000)  // outside the month

        let stats = store.snapshot(range: .month, now: epoch)
        XCTAssertEqual(stats.playCount, 2)
        XCTAssertEqual(stats.distinctArtists, 1)
        XCTAssertEqual(stats.totalMs, 120_000)
        XCTAssertFalse(stats.isEmpty)
        XCTAssertEqual(stats.daily.count, 31, "30-day window is inclusive of both ends")
    }

    func testSnapshotHidesDailyBarsOnLongRanges() {
        record("A", "one")
        XCTAssertTrue(store.snapshot(range: .year, now: epoch).daily.isEmpty)
        XCTAssertTrue(store.snapshot(range: .all, now: epoch).daily.isEmpty)
        XCTAssertFalse(store.snapshot(range: .week, now: epoch).daily.isEmpty)
    }

    /// A day with no plays must still appear, at zero — otherwise a quiet day
    /// silently disappears and the week reads as six days long.
    func testFillMissingDaysInsertsZeroDays() {
        let day = { (offset: Double) in self.epoch.addingTimeInterval(-offset * 86_400) }
        let sparse = [DayStat(day: day(3), listenedMs: 5_000),
                      DayStat(day: day(0), listenedMs: 9_000)]

        let filled = PlayHistoryStore.fillMissingDays(sparse, since: day(3), now: day(0))
        XCTAssertEqual(filled.count, 4)
        XCTAssertEqual(filled.map(\.listenedMs), [5_000, 0, 0, 9_000])
    }

    func testEmptyStatsSnapshot() {
        let stats = store.snapshot(range: .month, now: epoch)
        XCTAssertTrue(stats.isEmpty)
        XCTAssertTrue(stats.topArtists.isEmpty)
    }
}

final class StatsFormatTests: XCTestCase {
    // Output is language-dependent now, so pin it rather than inheriting the
    // test machine's system locale.
    override func tearDown() {
        L10n._testLanguageOverride = nil
        super.tearDown()
    }

    func testDurationFormattingInTurkish() {
        L10n._testLanguageOverride = .turkish
        XCTAssertEqual(StatsFormat.duration(0), "0 dk")
        XCTAssertEqual(StatsFormat.duration(90_000), "1 dk")          // 90s rounds down
        XCTAssertEqual(StatsFormat.duration(47 * 60_000), "47 dk")
        XCTAssertEqual(StatsFormat.duration(60 * 60_000), "1 sa")     // no "0 dk" tail
        XCTAssertEqual(StatsFormat.duration(192 * 60_000), "3 sa 12 dk")
    }

    func testDurationFormattingInEnglish() {
        L10n._testLanguageOverride = .english
        XCTAssertEqual(StatsFormat.duration(0), "0m")
        XCTAssertEqual(StatsFormat.duration(90_000), "1m")
        XCTAssertEqual(StatsFormat.duration(47 * 60_000), "47m")
        XCTAssertEqual(StatsFormat.duration(60 * 60_000), "1h")
        XCTAssertEqual(StatsFormat.duration(192 * 60_000), "3h 12m")
    }
}

final class ThemeContrastTests: XCTestCase {
    func testOnAccentPicksReadableInk() {
        XCTAssertEqual(Theme.relativeLuminance(ofHex: "#ffffff"), 1.0, accuracy: 0.001)
        XCTAssertEqual(Theme.relativeLuminance(ofHex: "#000000"), 0.0, accuracy: 0.001)
        // A pale accent must not get white text on it.
        XCTAssertTrue(Theme.relativeLuminance(ofHex: "#f2e9d8") > 0.179)
        // Spotify green: mid-luminance, but black ink beats white on it.
        XCTAssertTrue(Theme.relativeLuminance(ofHex: "#1DB954") > 0.179)
    }

    /// Whatever ink each theme picks, it has to actually contrast with its own
    /// accent — this is what hardcoded `.white` was quietly failing at.
    func testEveryThemeAccentHasContrastingInk() {
        for theme in Theme.allCases {
            let luminance = Theme.relativeLuminance(ofHex: theme.palette.accent)
            let inkLuminance: Double = luminance > 0.179 ? 0 : 1  // must mirror onAccentColor
            let ratio = (max(luminance, inkLuminance) + 0.05) / (min(luminance, inkLuminance) + 0.05)
            XCTAssertGreaterThan(ratio, 3.0, "\(theme.rawValue) accent has low-contrast ink")
        }
    }
}
