import XCTest
@testable import YTMusicMac

/// The Last.fm tag cache living inside history.sqlite. Backed by a real
/// temporary database — the point of these tests is the SQL and the migration,
/// so an in-memory fake would test nothing.
final class ArtistTagCacheTests: XCTestCase {
    private var store: PlayHistoryStore!
    private var path: String!

    override func setUpWithError() throws {
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tagcache-\(UUID().uuidString).sqlite").path
        store = try PlayHistoryStore(path: path)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(atPath: path)
    }

    private func digest(_ genres: [String], _ decades: [Int] = []) -> TagTaxonomy.Digest {
        TagTaxonomy.Digest(genres: genres, decades: decades)
    }

    func testRoundTripsGenresAndDecades() {
        store.saveTags(artist: "Radiohead", digest: digest(["Alternative", "Rock"], [1990, 2000]))
        let loaded = store.tags(for: ["Radiohead"])
        XCTAssertEqual(loaded["Radiohead"], digest(["Alternative", "Rock"], [1990, 2000]))
    }

    func testUnknownArtistsAreSimplyAbsent() {
        XCTAssertTrue(store.tags(for: ["Nobody"]).isEmpty)
    }

    /// The whole reason the cache exists: without storing the empty answer we'd
    /// re-ask Last.fm about the same unknown artist on every page open.
    func testAnEmptyResultIsCachedRatherThanTreatedAsMissing() {
        store.saveTags(artist: "Obscure", digest: digest([]))
        XCTAssertTrue(store.hasTags(for: "Obscure"), "an empty answer must still count as answered")
        XCTAssertEqual(store.tags(for: ["Obscure"])["Obscure"], digest([]))
    }

    func testSavingAgainReplacesRatherThanDuplicates() {
        store.saveTags(artist: "Miles Davis", digest: digest(["Jazz"]))
        store.saveTags(artist: "Miles Davis", digest: digest(["Jazz", "Bebop"], [1950]))
        XCTAssertEqual(store.tags(for: ["Miles Davis"])["Miles Davis"], digest(["Jazz", "Bebop"], [1950]))
    }

    func testReadsManyArtistsInOneGo() {
        store.saveTags(artist: "A", digest: digest(["Rock"]))
        store.saveTags(artist: "B", digest: digest(["Jazz"]))
        store.saveTags(artist: "C", digest: digest(["Pop"]))
        let loaded = store.tags(for: ["A", "C", "Missing"])
        XCTAssertEqual(Set(loaded.keys), ["A", "C"])
    }

    /// Artist names arrive from the player bar with odd spacing and casing; the
    /// cache key has to match the same artist string the plays table stores.
    func testLookupIsExactOnTheStoredName() {
        store.saveTags(artist: "Björk", digest: digest(["Electronic"]))
        XCTAssertNotNil(store.tags(for: ["Björk"])["Björk"])
    }

    func testAQuoteInAnArtistNameDoesNotBreakTheQuery() {
        store.saveTags(artist: "Guns N' Roses", digest: digest(["Hard Rock"]))
        XCTAssertEqual(store.tags(for: ["Guns N' Roses"])["Guns N' Roses"], digest(["Hard Rock"]))
    }

    func testAskingForNothingReturnsNothingWithoutQuerying() {
        XCTAssertTrue(store.tags(for: []).isEmpty)
    }

    /// An existing v2 database must gain the table without losing its plays.
    func testMigrationPreservesExistingHistory() throws {
        store.record(PlayRecord(videoId: "v1", title: "Song", artist: "A", album: nil,
                                durationMs: 200_000, playedMs: 200_000, startedAt: Date(),
                                artworkURL: nil))
        store.waitForPendingWrites()
        store = nil

        let reopened = try PlayHistoryStore(path: path)
        XCTAssertEqual(reopened.topTracks(since: Date(timeIntervalSince1970: 0)).count, 1)
        reopened.saveTags(artist: "A", digest: digest(["Rock"]))
        XCTAssertEqual(reopened.tags(for: ["A"])["A"], digest(["Rock"]))
        store = reopened
    }

    func testUntaggedArtistsAreReportedAsNeedingAFetch() {
        store.saveTags(artist: "Known", digest: digest(["Rock"]))
        XCTAssertEqual(store.artistsMissingTags(from: ["Known", "New", "Other"]), ["New", "Other"])
    }
}
