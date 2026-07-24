import XCTest
@testable import YTMusicMac

/// The genre/decade rows on the radio page. Pure input → output, so these tests
/// cover the real rules without a database or a network.
final class RadioSectionsBuilderTests: XCTestCase {

    private func track(_ artist: String, plays: Int, id: String? = nil) -> TrackStat {
        TrackStat(videoId: id ?? "v-\(artist)", title: "\(artist) hit", artist: artist,
                  plays: plays, listenedMs: Int64(plays) * 180_000,
                  artworkURL: "https://img/\(artist)")
    }

    private func digest(_ genres: [String], _ decades: [Int] = []) -> TagTaxonomy.Digest {
        TagTaxonomy.Digest(genres: genres, decades: decades)
    }

    private let day = Date(timeIntervalSince1970: 1_753_000_000)

    /// Enough artists in one genre to clear the minimum-3 rule.
    private func rockLibrary(count: Int = 4) -> ([TrackStat], [String: TagTaxonomy.Digest]) {
        let tracks = (1...count).map { track("Rock\($0)", plays: 100 - $0) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        return (tracks, tags)
    }

    // MARK: - Genre rows

    func testBuildsAGenreRowFromTaggedArtists() {
        let (tracks, tags) = rockLibrary()
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.id, "genre:Rock")
        XCTAssertEqual(sections.first?.stations.count, 4)
    }

    /// A one- or two-card row reads as a rendering bug, not a section.
    func testAGenreBelowTheMinimumProducesNoRow() {
        let tracks = [track("A", plays: 10), track("B", plays: 9)]
        let tags = ["A": digest(["Jazz"]), "B": digest(["Jazz"])]
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertTrue(sections.isEmpty, "2 artists must not become a row")
    }

    func testExactlyTheMinimumProducesARow() {
        let tracks = (1...3).map { track("A\($0)", plays: $0) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Jazz"])) })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(sections.count, 1)
    }

    /// Genres are ranked by how much the user actually plays them, not
    /// alphabetically and not by artist count.
    func testGenresAreOrderedByPlayWeight() {
        var tracks: [TrackStat] = []
        var tags: [String: TagTaxonomy.Digest] = [:]
        // Jazz: 3 artists x 100 plays = 300. Rock: 4 artists x 10 = 40.
        for i in 1...3 {
            let t = track("J\(i)", plays: 100); tracks.append(t); tags[t.artist] = digest(["Jazz"])
        }
        for i in 1...4 {
            let t = track("R\(i)", plays: 10); tracks.append(t); tags[t.artist] = digest(["Rock"])
        }
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(sections.map(\.id), ["genre:Jazz", "genre:Rock"])
    }

    func testKeepsOnlyTheTopGenres() {
        var tracks: [TrackStat] = []
        var tags: [String: TagTaxonomy.Digest] = [:]
        for (weight, genre) in ["Rock", "Pop", "Jazz", "Metal", "Funk", "Blues", "Soul"].enumerated() {
            for i in 1...3 {
                let t = track("\(genre)\(i)", plays: (10 - weight) * 10)
                tracks.append(t); tags[t.artist] = digest([genre])
            }
        }
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        let genreRows = sections.filter { $0.id.hasPrefix("genre:") }
        XCTAssertEqual(genreRows.count, RadioSectionsBuilder.maxGenreSections)
        XCTAssertEqual(genreRows.first?.id, "genre:Rock", "heaviest genre leads")
    }

    /// An artist tagged rock+metal belongs in both rows — that's the point of
    /// the per-artist cap being 3 rather than 1.
    func testAnArtistCanAppearInMoreThanOneGenre() {
        var tracks = (1...3).map { track("Both\($0)", plays: 50) }
        var tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock", "Metal"])) })
        tracks.append(track("Solo", plays: 5)); tags["Solo"] = digest(["Rock"])
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(Set(sections.map(\.id)), ["genre:Rock", "genre:Metal"])
    }

    /// One artist's radio twice in a row is a duplicate to the user's eye even
    /// if the seed tracks differ.
    func testAnArtistAppearsOnlyOnceWithinARow() {
        let tracks = (1...4).map { track("A\($0)", plays: 10) } + [track("A1", plays: 3, id: "other")]
        let tags = Dictionary(tracks.map { ($0.artist, digest(["Rock"])) }, uniquingKeysWith: { a, _ in a })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        let artists = sections.first?.stations.map(\.title) ?? []
        XCTAssertEqual(Set(artists).count, artists.count, "same artist twice in one row")
    }

    /// YT credits features in the byline, so one act reaches history under
    /// several names. Two cards for the same band is a duplicate to the eye.
    func testACreditedFeatureDoesNotDuplicateTheLeadArtist() {
        let tracks = [track("Dedublüman", plays: 20),
                      track("Dedublüman ve Aleyna Tilki", plays: 18, id: "v-feat"),
                      track("Zakkum", plays: 15),
                      track("Teoman", plays: 12)]
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        let titles = sections.first?.stations.map(\.title) ?? []
        XCTAssertEqual(titles.filter { $0.hasPrefix("Dedublüman") }.count, 1)
        XCTAssertTrue(titles.contains("Dedublüman"), "the more played credit wins")
    }

    /// YT's own metadata isn't consistent about capitalisation — a real library
    /// carried both "gripin" and "Gripin" and showed two cards for one band.
    func testCasingAloneDoesNotMakeTwoArtists() {
        let tracks = [track("gripin", plays: 20), track("Gripin", plays: 8, id: "v-caps"),
                      track("Zakkum", plays: 15), track("Teoman", plays: 12)]
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        let titles = sections.first?.stations.map(\.title) ?? []
        XCTAssertEqual(titles.filter { $0.lowercased() == "gripin" }.count, 1)
    }

    func testRowIsCappedInLength() {
        let tracks = (1...40).map { track("A\($0)", plays: 41 - $0) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(sections.first?.stations.count, RadioSectionsBuilder.stationsPerSection)
    }

    /// A station with no videoId can't seed RDAMVM — it would build a broken
    /// watch URL, the same rule the rest of RadioCatalog follows.
    func testArtistsWithoutASeedVideoAreDropped() {
        var tracks = (1...3).map { track("A\($0)", plays: 10) }
        tracks.append(track("Ghost", plays: 99, id: ""))
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertFalse(sections.first?.stations.contains(where: { $0.title == "Ghost" }) ?? true)
    }

    func testUntaggedArtistsAreSimplyAbsent() {
        let (tracks, tags) = rockLibrary()
        let withStranger = tracks + [track("Unknown", plays: 999)]
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: withStranger, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertFalse(sections.first?.stations.contains(where: { $0.title == "Unknown" }) ?? true)
    }

    func testNoTagsAtAllMeansNoSections() {
        let (tracks, _) = rockLibrary()
        XCTAssertTrue(RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: [:],
                                                 reroll: 0, on: day).isEmpty)
    }

    // MARK: - Decade row

    func testDecadesShareASingleRow() {
        let tracks = (1...6).map { track("A\($0)", plays: 10) }
        var tags: [String: TagTaxonomy.Digest] = [:]
        for (i, t) in tracks.enumerated() {
            tags[t.artist] = digest([], [i < 3 ? 1990 : 1980])
        }
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.id, "decades")
    }

    /// The row is a mix of decades, so each card has to say which one it is.
    func testDecadeStationsAreLabelledWithTheirDecade() {
        let tracks = (1...3).map { track("A\($0)", plays: 10) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest([], [1990])) })
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertTrue(sections.first?.stations.allSatisfy { $0.subtitle.contains("90") } ?? false,
                      "a decade card must name its decade")
    }

    func testADecadeBelowTheMinimumIsExcludedFromTheRow() {
        var tracks = (1...3).map { track("N\($0)", plays: 10) }
        var tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest([], [1990])) })
        tracks.append(track("Lonely", plays: 99)); tags["Lonely"] = digest([], [1960])
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertFalse(sections.first?.stations.contains(where: { $0.title == "Lonely" }) ?? true)
    }

    func testGenreRowsComeBeforeTheDecadeRow() {
        var tracks = (1...3).map { track("R\($0)", plays: 10) }
        var tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"], [1990])) })
        tracks.append(track("Extra", plays: 8)); tags["Extra"] = digest([], [1990])
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        XCTAssertEqual(sections.map(\.id), ["genre:Rock", "decades"])
    }

    // MARK: - Reroll

    /// Stable output is what stops the page reshuffling on every redraw and
    /// relaunch — the same rule the daily discovery rotation follows.
    func testSameDayAndRerollGivesIdenticalOutput() {
        let tracks = (1...30).map { track("A\($0)", plays: 31 - $0) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let a = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 0, on: day)
        let b = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 0, on: day)
        XCTAssertEqual(a.first?.stations.map(\.id), b.first?.stations.map(\.id))
    }

    /// The whole point of the refresh button: pressing it must change the cards.
    func testRerollChangesTheCards() {
        let tracks = (1...30).map { track("A\($0)", plays: 31 - $0) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let first = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 0, on: day)
        let second = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 1, on: day)
        XCTAssertNotEqual(first.first?.stations.map(\.id), second.first?.stations.map(\.id),
                          "refresh must surface different music")
    }

    func testANewDayChangesTheCardsWithoutARefresh() {
        let tracks = (1...30).map { track("A\($0)", plays: 31 - $0) }
        let tags = Dictionary(uniqueKeysWithValues: tracks.map { ($0.artist, digest(["Rock"])) })
        let today = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 0, on: day)
        let tomorrow = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 0,
                                                 on: day.addingTimeInterval(86_400))
        XCTAssertNotEqual(today.first?.stations.map(\.id), tomorrow.first?.stations.map(\.id))
    }

    /// Rerolling picks different cards but must not change which rows exist —
    /// the page shouldn't reshape under the user's cursor.
    func testRerollKeepsTheSameSections() {
        var tracks: [TrackStat] = []
        var tags: [String: TagTaxonomy.Digest] = [:]
        for genre in ["Rock", "Jazz"] {
            for i in 1...5 {
                let t = track("\(genre)\(i)", plays: 20); tracks.append(t); tags[t.artist] = digest([genre])
            }
        }
        let a = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 0, on: day)
        let b = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags, reroll: 7, on: day)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    // MARK: - Station shape

    /// The rows render with the page's existing card component, so the stations
    /// have to carry the same fields the other sections' stations do.
    func testStationsCarrySeedAndArtwork() {
        let (tracks, tags) = rockLibrary()
        let sections = RadioSectionsBuilder.build(topTrackPerArtist: tracks, tags: tags,
                                                 reroll: 0, on: day)
        let station = sections.first?.stations.first
        XCTAssertFalse(station?.seedVideoId.isEmpty ?? true)
        XCTAssertNotNil(station?.artworkURL)
        XCTAssertEqual(station?.kind, .artist)
    }

    func testEmptyInputProducesNoSections() {
        XCTAssertTrue(RadioSectionsBuilder.build(topTrackPerArtist: [], tags: [:],
                                                 reroll: 0, on: day).isEmpty)
    }
}
