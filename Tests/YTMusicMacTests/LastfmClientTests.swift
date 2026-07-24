import XCTest
@testable import YTMusicMac

final class LastfmClientTests: XCTestCase {
    private func c(_ artist: String, _ track: String, _ score: Double) -> SimilarCandidate {
        SimilarCandidate(artist: artist, track: track, score: score)
    }

    func testMergeSortsByScoreDescending() {
        let merged = LastfmClient.merge([c("A", "one", 0.3), c("B", "two", 0.9), c("C", "three", 0.6)])
        XCTAssertEqual(merged.map(\.track), ["two", "three", "one"])
    }

    func testMergeDropsDuplicatesKeepingHigherScore() {
        // Same song from track-similar (0.4) and artist-fallback (0.8).
        let merged = LastfmClient.merge([c("Radiohead", "Nude", 0.4), c("radiohead", "nude", 0.8)])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.score, 0.8)
    }

    func testMergeIsCaseInsensitiveOnTheKey() {
        let merged = LastfmClient.merge([c("Björk", "Jóga", 0.5), c("BJÖRK", "JÓGA", 0.5)])
        XCTAssertEqual(merged.count, 1)
    }

    func testMergeDropsEmptyFields() {
        let merged = LastfmClient.merge([c("", "ghost", 0.9), c("Real", "", 0.9), c("Real", "song", 0.5)])
        XCTAssertEqual(merged.map(\.track), ["song"])
    }

    func testMergeTiebreakIsDeterministic() {
        let a = LastfmClient.merge([c("Z", "z", 0.5), c("A", "a", 0.5)])
        let b = LastfmClient.merge([c("A", "a", 0.5), c("Z", "z", 0.5)])
        XCTAssertEqual(a.map(\.key), b.map(\.key), "equal scores must order identically regardless of input order")
    }

    // MARK: - Top tags

    /// Shape of a real `artist.gettoptags` payload: count arrives as a number
    /// here but as a string on some responses, hence doubleValue.
    func testParsesTopTagsWithWeights() {
        let payload: Any = [["name": "rock", "count": 100],
                            ["name": "90s", "count": "63"],
                            ["name": "seen live", "count": 41]]
        let tags = LastfmClient.parseTags(payload)
        XCTAssertEqual(tags.map(\.name), ["rock", "90s", "seen live"])
        XCTAssertEqual(tags.map(\.count), [100, 63, 41])
    }

    func testParsesTopTagsFromASingleObject() {
        XCTAssertEqual(LastfmClient.parseTags(["name": "jazz", "count": 80]).count, 1)
    }

    func testDropsTagsWithoutAName() {
        let tags = LastfmClient.parseTags([["count": 90], ["name": "", "count": 90],
                                           ["name": "pop", "count": 90]])
        XCTAssertEqual(tags.map(\.name), ["pop"])
    }

    /// A tag with no count must not be read as a heavy tag — it defaults to 0,
    /// which lands below TagTaxonomy's threshold.
    func testAMissingCountIsZeroNotHigh() {
        XCTAssertEqual(LastfmClient.parseTags([["name": "obscure"]]).first?.count, 0)
    }

    func testEmptyTagPayloadIsNotAnError() {
        XCTAssertTrue(LastfmClient.parseTags(nil).isEmpty)
        XCTAssertTrue(LastfmClient.parseTags([]).isEmpty)
    }

    // Last.fm collapses a single result to a bare object; the parser must
    // treat that as a one-element list.
    func testArrayValueHandlesSingleObject() {
        XCTAssertEqual(LastfmClient.arrayValue([["name": "x"]]).count, 1)
        XCTAssertEqual(LastfmClient.arrayValue(["name": "x"]).count, 1)
        XCTAssertEqual(LastfmClient.arrayValue(nil).count, 0)
    }

    func testDoubleValueAcceptsStringAndNumber() {
        XCTAssertEqual(LastfmClient.doubleValue("0.9312"), 0.9312, accuracy: 0.0001)
        XCTAssertEqual(LastfmClient.doubleValue(0.5), 0.5)
        XCTAssertEqual(LastfmClient.doubleValue(NSNumber(value: 1)), 1)
        XCTAssertEqual(LastfmClient.doubleValue(nil), 0)
        XCTAssertEqual(LastfmClient.doubleValue("garbage"), 0)
    }

    func testUnconfiguredClientReturnsNothing() async {
        let client = LastfmClient(apiKey: "")
        XCTAssertFalse(client.isConfigured)
        let recs = await client.recommendations(artist: "Radiohead", track: "Nude")
        XCTAssertTrue(recs.isEmpty)
    }
}
