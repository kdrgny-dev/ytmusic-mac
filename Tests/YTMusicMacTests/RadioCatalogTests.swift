import XCTest
@testable import YTMusicMac

final class RadioCatalogTests: XCTestCase {

    private func track(_ id: String, _ title: String, _ artist: String, plays: Int = 1) -> TrackStat {
        TrackStat(videoId: id, title: title, artist: artist, plays: plays,
                  listenedMs: Int64(plays) * 180_000, artworkURL: "https://img/\(id)")
    }

    private var pool: [TrackStat] {
        (1...40).map { track("v\($0)", "Song \($0)", "Artist \($0 % 7)", plays: 41 - $0) }
    }

    /// Pinned rather than `.current`: the weekly rotation turns over on the
    /// calendar's own week start, which is locale-dependent (Monday in TR,
    /// Sunday in the US). Production uses `.current` so the mix refreshes on
    /// the user's Monday; the tests fix it to Monday-start to be reproducible.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        c.firstWeekday = 2          // Monday
        c.minimumDaysInFirstWeek = 4 // ISO 8601
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    // MARK: - Seeds

    /// A station with no videoId can't seed RDAMVM — it would navigate to a
    /// broken watch URL.
    func testStationsWithoutAVideoIdAreDropped() {
        let tracks = [track("", "No id", "Artist"), track("v1", "Fine", "Artist")]
        let stations = RadioCatalog.forYou(topTracks: tracks)
        XCTAssertEqual(stations.map(\.seedVideoId), ["v1"])
    }

    func testArtistStationsDropRowsWithoutAnArtist() {
        let tracks = [track("v1", "Song", ""), track("v2", "Song", "Real")]
        let stations = RadioCatalog.byArtist(topTrackPerArtist: tracks) { _ in "radio" }
        XCTAssertEqual(stations.map(\.title), ["Real"])
    }

    func testArtistStationIsTitledByArtistAndSeededByTheirTrack() {
        let stations = RadioCatalog.byArtist(topTrackPerArtist: [track("v9", "Big Hit", "Selda")]) {
            "\($0.artist) radio"
        }
        XCTAssertEqual(stations.first?.title, "Selda")
        XCTAssertEqual(stations.first?.subtitle, "Selda radio")
        XCTAssertEqual(stations.first?.seedVideoId, "v9")
    }

    func testStationIdsAreUnique() {
        let ids = RadioCatalog.forYou(topTracks: pool).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testForYouRespectsItsLimit() {
        XCTAssertEqual(RadioCatalog.forYou(topTracks: pool, limit: 5).count, 5)
    }

    // MARK: - Daily rotation

    func testDailyDiscoveryIsStableWithinADay() {
        let morning = RadioCatalog.dailyDiscovery(pool: pool, on: date("2026-07-16 08:00"), calendar: calendar)
        let night = RadioCatalog.dailyDiscovery(pool: pool, on: date("2026-07-16 23:30"), calendar: calendar)
        XCTAssertEqual(morning.map(\.id), night.map(\.id))
    }

    func testDailyDiscoveryChangesTheNextDay() {
        let today = RadioCatalog.dailyDiscovery(pool: pool, on: date("2026-07-16 12:00"), calendar: calendar)
        let tomorrow = RadioCatalog.dailyDiscovery(pool: pool, on: date("2026-07-17 12:00"), calendar: calendar)
        XCTAssertNotEqual(today.map(\.id), tomorrow.map(\.id))
    }

    func testDailyDiscoveryReturnsDistinctTracks() {
        let picks = RadioCatalog.dailyDiscovery(pool: pool, on: date("2026-07-16 12:00"),
                                                count: 6, calendar: calendar)
        XCTAssertEqual(Set(picks.map(\.seedVideoId)).count, 6)
    }

    /// Asking for more than the pool holds must clamp, not crash or repeat.
    func testDailyDiscoveryClampsToPoolSize() {
        let small = [track("v1", "A", "X"), track("v2", "B", "Y")]
        let picks = RadioCatalog.dailyDiscovery(pool: small, on: date("2026-07-16 12:00"),
                                                count: 10, calendar: calendar)
        XCTAssertEqual(picks.count, 2)
    }

    func testEmptyPoolYieldsNoStations() {
        XCTAssertTrue(RadioCatalog.dailyDiscovery(pool: [], on: date("2026-07-16 12:00"),
                                                  calendar: calendar).isEmpty)
        XCTAssertTrue(RadioCatalog.weeklyMix(pool: [], on: date("2026-07-16 12:00"),
                                             calendar: calendar).isEmpty)
    }

    /// Over a month the rotation must reach well beyond the same few tracks —
    /// this is the whole point of rotating rather than showing the top N.
    func testDailyDiscoverySpreadsAcrossThePoolOverTime() {
        var seen = Set<String>()
        for day in 1...28 {
            let d = date(String(format: "2026-07-%02d 12:00", day))
            seen.formUnion(RadioCatalog.dailyDiscovery(pool: pool, on: d, calendar: calendar).map(\.seedVideoId))
        }
        XCTAssertGreaterThan(seen.count, 20, "rotation is stuck on a small subset")
    }

    // MARK: - Weekly rotation

    func testWeeklyMixIsStableWithinAWeek() {
        // Both dates fall in the same ISO week (Mon 13 – Sun 19 July 2026).
        let monday = RadioCatalog.weeklyMix(pool: pool, on: date("2026-07-13 09:00"), calendar: calendar)
        let sunday = RadioCatalog.weeklyMix(pool: pool, on: date("2026-07-19 22:00"), calendar: calendar)
        XCTAssertEqual(monday.map(\.videoId), sunday.map(\.videoId))
    }

    func testWeeklyMixChangesTheFollowingWeek() {
        let thisWeek = RadioCatalog.weeklyMix(pool: pool, on: date("2026-07-16 12:00"), calendar: calendar)
        let nextWeek = RadioCatalog.weeklyMix(pool: pool, on: date("2026-07-23 12:00"), calendar: calendar)
        XCTAssertNotEqual(thisWeek.map(\.videoId), nextWeek.map(\.videoId))
    }

    /// weekOfYear alone repeats every January, which would serve last year's
    /// mix back.
    func testWeekNumberDoesNotCollideAcrossYears() {
        let a = RadioCatalog.weekNumber(of: date("2026-01-07 12:00"), calendar: calendar)
        let b = RadioCatalog.weekNumber(of: date("2027-01-06 12:00"), calendar: calendar)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Day boundaries

    func testDayNumberTurnsOverAtLocalMidnightNotUTC() {
        // 00:30 Istanbul on the 17th is still 21:30 UTC on the 16th. The
        // rotation must follow the user's day.
        let lateNight = RadioCatalog.dayNumber(of: date("2026-07-16 23:30"), calendar: calendar)
        let afterMidnight = RadioCatalog.dayNumber(of: date("2026-07-17 00:30"), calendar: calendar)
        XCTAssertEqual(afterMidnight, lateNight + 1)
    }

    // MARK: - Archive windows

    func testSameDayLastYearSpansExactlyThatDay() {
        let interval = RadioCatalog.sameDay(yearsAgo: 1, from: date("2026-07-16 15:00"), calendar: calendar)
        XCTAssertEqual(interval?.start, date("2025-07-16 00:00"))
        XCTAssertEqual(interval?.end, date("2025-07-17 00:00"))
    }

    func testMonthsAgoSpansAWholeCalendarMonth() {
        let interval = RadioCatalog.month(monthsAgo: 6, from: date("2026-07-16 15:00"), calendar: calendar)
        XCTAssertEqual(interval?.start, date("2026-01-01 00:00"))
        XCTAssertEqual(interval?.end, date("2026-02-01 00:00"))
    }

    /// Windows must never be inverted — an end <= start silently returns no
    /// rows from the store instead of failing.
    func testArchiveWindowsAreForwardOrdered() {
        for yearsAgo in 1...5 {
            let interval = RadioCatalog.sameDay(yearsAgo: yearsAgo, from: date("2026-07-16 15:00"),
                                                calendar: calendar)
            XCTAssertNotNil(interval)
            XCTAssertLessThan(interval!.start, interval!.end)
        }
    }

    // MARK: - Generator

    func testSeededGeneratorIsReproducible() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    func testSeededGeneratorDiffersBySeed() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        XCTAssertNotEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }

    /// A zero seed must not degenerate — day 0 and week 0 are reachable.
    func testSeededGeneratorHandlesZeroSeed() {
        var g = SeededGenerator(seed: 0)
        let values = (0..<5).map { _ in g.next() }
        XCTAssertEqual(Set(values).count, 5)
        XCTAssertFalse(values.contains(0))
    }
}
