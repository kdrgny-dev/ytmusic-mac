import XCTest
@testable import YTMusicMac

final class YTImageURLTests: XCTestCase {

    /// The exact shape stored in the real history DB — 815 of 846 rows.
    func testUpgradesThePlayerBarThumbnailSize() {
        let stored = "https://yt3.googleusercontent.com/yfqD9WbzLlF4KhHtCyuZpkrO6EafzhXhDiXt_YTHjRKn49RrwNDGGvNbvgSKdJ8swmC8J_JO1i8b3VWl=w60-h60-l90-rj"
        XCTAssertEqual(YTImageURL.resized(stored, to: 544),
                       "https://yt3.googleusercontent.com/yfqD9WbzLlF4KhHtCyuZpkrO6EafzhXhDiXt_YTHjRKn49RrwNDGGvNbvgSKdJ8swmC8J_JO1i8b3VWl=w544-h544-l90-rj")
    }

    func testResizingIsIdempotent() {
        let once = YTImageURL.resized("https://yt3.googleusercontent.com/abc=w60-h60-l90-rj", to: 544)
        let twice = YTImageURL.resized(once, to: 544)
        XCTAssertEqual(once, twice)
    }

    func testDownsizingWorksToo() {
        XCTAssertEqual(YTImageURL.resized("https://yt3.googleusercontent.com/abc=w544-h544-l90-rj", to: 60),
                       "https://yt3.googleusercontent.com/abc=w60-h60-l90-rj")
    }

    // MARK: - Must not touch

    /// This form serves fixed sizes by filename; appending "=w544…" 404s.
    func testLeavesFilenameStyleURLsAlone() {
        let url = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
        XCTAssertEqual(YTImageURL.resized(url, to: 544), url)
    }

    func testLeavesURLsWithoutASuffixAlone() {
        let url = "https://yt3.googleusercontent.com/abcdefg"
        XCTAssertEqual(YTImageURL.resized(url, to: 544), url)
    }

    /// The `=` in an image id is padding, not a size delimiter. Chopping at it
    /// would corrupt the id and break every cover.
    func testDoesNotMistakeIdPaddingForASizeSuffix() {
        let url = "https://lh3.googleusercontent.com/AbC-dEf_GhI123=="
        XCTAssertEqual(YTImageURL.resized(url, to: 544), url)
    }

    /// An id ending in uppercase after an "=" isn't a size suffix either.
    func testDoesNotRewriteMixedCaseTrailingSegment() {
        let url = "https://yt3.googleusercontent.com/abc=W60-H60"
        XCTAssertEqual(YTImageURL.resized(url, to: 544), url)
    }

    /// A trailing segment that isn't a width spec ("=s90-c" style crops) is
    /// left alone rather than blindly replaced.
    func testIgnoresNonWidthSuffixes() {
        let url = "https://yt3.googleusercontent.com/abc=s88-c-k-c0x00ffffff-no-rj"
        XCTAssertEqual(YTImageURL.resized(url, to: 544), url)
    }

    // MARK: - Degenerate input

    func testNilAndEmptyStayNil() {
        XCTAssertNil(YTImageURL.resized(nil, to: 544))
        XCTAssertNil(YTImageURL.resized("", to: 544))
    }

    func testTrailingEqualsAloneIsNotASuffix() {
        let url = "https://yt3.googleusercontent.com/abc="
        XCTAssertEqual(YTImageURL.resized(url, to: 544), url)
    }
}

/// The store is where the rewrite actually lands, so assert it there too —
/// a consumer reading a raw 60px URL is the bug we're fixing.
final class PlayHistoryStoreCoverTests: XCTestCase {
    private var store: PlayHistoryStore!
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        store = try PlayHistoryStore(path: ":memory:")
    }

    private func record(_ artist: String, _ title: String, artworkURL: String?) {
        store.record(PlayRecord(videoId: "id-\(title)", title: title, artist: artist, album: nil,
                                durationMs: 200_000, playedMs: 60_000, startedAt: epoch,
                                artworkURL: artworkURL))
    }

    func testTopTracksReturnFullSizeCovers() {
        record("A", "Song", artworkURL: "https://yt3.googleusercontent.com/abc=w60-h60-l90-rj")
        let cover = store.topTracks(since: epoch.addingTimeInterval(-86_400)).first?.artworkURL
        XCTAssertEqual(cover, "https://yt3.googleusercontent.com/abc=w544-h544-l90-rj")
    }

    func testTopArtistsReturnFullSizeCovers() {
        record("A", "Song", artworkURL: "https://yt3.googleusercontent.com/abc=w60-h60-l90-rj")
        let cover = store.topArtists(since: epoch.addingTimeInterval(-86_400)).first?.artworkURL
        XCTAssertEqual(cover, "https://yt3.googleusercontent.com/abc=w544-h544-l90-rj")
    }

    func testTopTrackPerArtistReturnsFullSizeCovers() {
        record("A", "Song", artworkURL: "https://yt3.googleusercontent.com/abc=w60-h60-l90-rj")
        let cover = store.topTrackPerArtist(since: epoch.addingTimeInterval(-86_400)).first?.artworkURL
        XCTAssertEqual(cover, "https://yt3.googleusercontent.com/abc=w544-h544-l90-rj")
    }

    func testRowsWithoutArtworkStayNil() {
        record("A", "Song", artworkURL: nil)
        XCTAssertNil(store.topTracks(since: epoch.addingTimeInterval(-86_400)).first?.artworkURL)
    }
}
