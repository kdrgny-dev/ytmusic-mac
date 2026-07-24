import XCTest
@testable import YTMusicMac

/// End-to-end check of the genre rows against the real Last.fm API and a copy of
/// a real listening history. Skipped unless `YTM_LIVE_LASTFM=1`, so the ordinary
/// test run stays offline and deterministic.
///
/// Run with:
///   YTM_LIVE_LASTFM=1 ./test.sh --filter RadioTasteIntegrationTests
final class RadioTasteIntegrationTests: XCTestCase {

    private var store: PlayHistoryStore!
    private var path: String!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YTM_LIVE_LASTFM"] == "1",
                          "live Last.fm test — set YTM_LIVE_LASTFM=1 to run")

        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.kdrgny.ytmusicmac/history.sqlite")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path),
                          "no local history database to read")

        // A copy, so the live run can't touch the real history.
        path = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-\(UUID().uuidString).sqlite").path
        try FileManager.default.copyItem(atPath: source.path, toPath: path)
        store = try PlayHistoryStore(path: path)
    }

    override func tearDown() {
        store = nil
        if let path { try? FileManager.default.removeItem(atPath: path) }
    }

    /// Walks the exact path the view model's backfill walks — candidate names,
    /// live tags, taxonomy, cache write — then builds the sections and prints
    /// them. Asserts the pipeline produces real rows rather than pinning names,
    /// which depend on whoever's history this is.
    func testBuildsGenreRowsFromLiveTags() async throws {
        let client = LastfmClient()
        try XCTSkipUnless(client.isConfigured, "LastfmSecret.swift has no API key")

        let seeds = store.topTrackPerArtist(since: StatsRange.all.start(from: Date()), limit: 60)
        XCTAssertFalse(seeds.isEmpty, "history has no artists to work with")

        var recovered = 0
        for artist in seeds.map(\.artist) where !artist.isEmpty {
            var digest = TagTaxonomy.Digest()
            var usedFallback = false
            for (index, candidate) in LastfmArtistQuery.candidates(for: artist).enumerated() {
                digest = TagTaxonomy.digest(from: await client.topTags(artist: candidate))
                if !digest.genres.isEmpty || !digest.decades.isEmpty {
                    usedFallback = index > 0
                    break
                }
            }
            if usedFallback { recovered += 1 }
            store.saveTags(artist: artist, digest: digest)
        }

        let tags = store.tags(for: seeds.map(\.artist))
        XCTAssertEqual(tags.count, seeds.filter { !$0.artist.isEmpty }.count,
                       "every artist must end up cached, empty digest included")

        let sections = RadioSectionsBuilder.build(topTrackPerArtist: seeds, tags: tags,
                                                 reroll: 0, on: Date())
        print("\n=== live radio taste rows ===")
        print("artists: \(seeds.count), tagged: \(tags.filter { !$0.value.genres.isEmpty }.count), "
              + "recovered via lead-artist fallback: \(recovered)")
        for section in sections {
            print("  \(section.id.padding(toLength: 26, withPad: " ", startingAt: 0)) "
                  + "\(section.stations.count) cards — \(section.stations.map(\.title).prefix(4).joined(separator: ", "))")
        }

        XCTAssertFalse(sections.isEmpty, "a real library must produce at least one row")
        XCTAssertTrue(sections.allSatisfy { $0.stations.count >= RadioSectionsBuilder.minStationsPerSection },
                      "no row may be shorter than the minimum")
        XCTAssertTrue(sections.filter { $0.id.hasPrefix("genre:") }.count <= RadioSectionsBuilder.maxGenreSections)

        // The rows are what the refresh button rerolls; prove it moves.
        let rerolled = RadioSectionsBuilder.build(topTrackPerArtist: seeds, tags: tags,
                                                 reroll: 1, on: Date())
        XCTAssertEqual(sections.map(\.id), rerolled.map(\.id), "reroll must not reshape the page")
        XCTAssertNotEqual(sections.first?.stations.map(\.id), rerolled.first?.stations.map(\.id),
                          "reroll must change the cards")
    }
}
