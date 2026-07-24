import XCTest
@testable import YTMusicMac

/// YT Music's byline names every credited artist ("Oceanvs Orientalis ve Idil
/// Mese"), and Last.fm knows no such artist — a probe over a real library found
/// 13 of the top 60 artists unrecognised for exactly this reason. So a tag
/// lookup falls back to the lead artist.
final class LastfmArtistQueryTests: XCTestCase {

    func testAPlainNameHasNoFallback() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Pink Floyd"), ["Pink Floyd"])
    }

    func testFallsBackToTheLeadArtistBeforeVe() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Oceanvs Orientalis ve Idil Mese"),
                       ["Oceanvs Orientalis ve Idil Mese", "Oceanvs Orientalis"])
    }

    func testFallsBackAcrossACommaList() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Eypio, Burak King ve Eypio"),
                       ["Eypio, Burak King ve Eypio", "Eypio"])
    }

    /// The lead artist is whatever comes before the *first* separator, so a
    /// three-way credit still resolves to one name.
    func testTakesTheFirstSeparatorNotTheLast() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "KÖFN, Simge, Salman Tin ve BKE").last,
                       "KÖFN")
    }

    /// "Santi & Tuğçe" is one act's real name — splitting on "&" would invent
    /// an artist that doesn't exist, so only " ve " and "," separate.
    func testAmpersandIsPartOfTheNameNotASeparator() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Santi & Tuğçe ve Tuğçe Kurtiş"),
                       ["Santi & Tuğçe ve Tuğçe Kurtiş", "Santi & Tuğçe"])
    }

    /// "Steve Vai" and "Velvet Underground" contain "ve" inside a word; a naive
    /// contains-check would truncate them to nonsense.
    func testDoesNotSplitInsideAWord() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Steve Vai"), ["Steve Vai"])
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "The Velvet Underground"),
                       ["The Velvet Underground"])
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Vetusta Morla"), ["Vetusta Morla"])
    }

    func testEnglishAndIsAlsoASeparator() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "Simon and Garfunkel").last, "Simon")
    }

    func testDoesNotProduceAnEmptyFallback() {
        XCTAssertEqual(LastfmArtistQuery.candidates(for: "ve Idil"), ["ve Idil"])
        XCTAssertEqual(LastfmArtistQuery.candidates(for: ", Idil"), [", Idil"])
    }

    func testEmptyNameYieldsNothing() {
        XCTAssertTrue(LastfmArtistQuery.candidates(for: "").isEmpty)
        XCTAssertTrue(LastfmArtistQuery.candidates(for: "   ").isEmpty)
    }

    func testFallbackIsNotDuplicatedWhenItEqualsTheOriginal() {
        let candidates = LastfmArtistQuery.candidates(for: "Zakkum")
        XCTAssertEqual(candidates.count, 1)
    }
}
