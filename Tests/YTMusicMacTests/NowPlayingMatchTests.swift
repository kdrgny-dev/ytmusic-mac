import XCTest
@testable import YTMusicMac

final class NowPlayingMatchTests: XCTestCase {

    func testMatchesByVideoId() {
        var np = NowPlaying()
        np.title = "There She Goes"
        np.videoId = "abc123"
        XCTAssertTrue(np.isCurrentTrack(id: "abc123"))
    }

    func testSameTitleDifferentVideoIdDoesNotMatch() {
        var np = NowPlaying()
        np.title = "There She Goes"   // aynı isim, farklı klip
        np.videoId = "abc123"
        XCTAssertFalse(np.isCurrentTrack(id: "zzz999"))
    }

    func testEmptyVideoIdNeverMatches() {
        var np = NowPlaying()
        np.title = "There She Goes"
        np.videoId = ""
        XCTAssertFalse(np.isCurrentTrack(id: ""),
                       "boş videoId ile eşleşme yanlış çoklu işaretlemeye yol açar")
    }

    func testNoTrackNeverMatches() {
        let np = NowPlaying()   // hasTrack == false
        XCTAssertFalse(np.isCurrentTrack(id: "abc123"))
    }
}
