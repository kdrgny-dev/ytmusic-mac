import XCTest
@testable import YTMusicMac

final class PlayTrackerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private var scrobbles: [PlayRecord] = []

    private func makeTracker() -> PlayTracker {
        scrobbles = []
        return PlayTracker(now: { self.clock }, onScrobble: { self.scrobbles.append($0) })
    }

    private func snap(_ id: String, position: Double, duration: Double = 200) -> PlayTracker.Snapshot {
        PlayTracker.Snapshot(videoId: id, title: "T-\(id)", artist: "A-\(id)",
                             duration: duration, position: position)
    }

    /// Feed positions in steps small enough to look like real playback.
    private func play(_ t: PlayTracker, _ id: String, upTo seconds: Double, duration: Double = 200) {
        var p: Double = 0
        t.update(snap(id, position: p, duration: duration))
        while p < seconds {
            p = min(p + 4, seconds)
            t.update(snap(id, position: p, duration: duration))
        }
    }

    func testSkippedTrackIsNotRecorded() {
        let t = makeTracker()
        play(t, "a", upTo: 20)   // under the 30s floor
        play(t, "b", upTo: 0)
        XCTAssertTrue(scrobbles.isEmpty)
    }

    func testTrackPassing30SecondsIsRecorded() {
        let t = makeTracker()
        play(t, "a", upTo: 32)
        play(t, "b", upTo: 0)
        XCTAssertEqual(scrobbles.count, 1)
        XCTAssertEqual(scrobbles.first?.videoId, "a")
        XCTAssertEqual(scrobbles.first?.startedAt, clock)
    }

    func testShortTrackUsesHalfDurationThreshold() {
        let t = makeTracker()
        // 20s track: threshold is 10s, so 12s counts even though it's under 30.
        play(t, "short", upTo: 12, duration: 20)
        t.flush()
        XCTAssertEqual(scrobbles.count, 1)
        XCTAssertEqual(scrobbles.first?.durationMs, 20_000)
    }

    func testSeekingForwardDoesNotCountAsListening() {
        let t = makeTracker()
        t.update(snap("a", position: 0))
        t.update(snap("a", position: 5))
        t.update(snap("a", position: 180))  // a 175s jump: seek, not playback
        t.flush()
        XCTAssertTrue(scrobbles.isEmpty, "a scrub to the end must not scrobble")
    }

    func testReplayingSameTrackRecordsTwoListens() {
        let t = makeTracker()
        play(t, "a", upTo: 40)
        // repeat-one: same identity, playhead snaps back to the top
        play(t, "a", upTo: 40)
        t.flush()
        XCTAssertEqual(scrobbles.count, 2)
    }

    func testFlushRecordsTheTrackInProgress() {
        let t = makeTracker()
        play(t, "a", upTo: 60)
        XCTAssertTrue(scrobbles.isEmpty, "nothing until the track ends")
        t.flush()
        XCTAssertEqual(scrobbles.count, 1)
        XCTAssertEqual(scrobbles.first?.playedMs, 60_000)
    }

    func testFallsBackToTitleArtistWhenVideoIdMissing() {
        let t = makeTracker()
        var a = snap("", position: 0); a.title = "One"; a.artist = "X"
        var b = snap("", position: 0); b.title = "Two"; b.artist = "X"
        t.update(a)
        for p in stride(from: 4.0, through: 40.0, by: 4.0) {
            var s = a; s.position = p; t.update(s)
        }
        t.update(b)
        XCTAssertEqual(scrobbles.count, 1)
        XCTAssertEqual(scrobbles.first?.title, "One")
    }

    func testBylineIsReducedToTheArtist() {
        XCTAssertEqual(ArtistName.primary("Radiohead • In Rainbows • 2007"), "Radiohead")
        // Seen in the wild: a video's byline carries live view/like counts.
        XCTAssertEqual(ArtistName.primary("Zaman Atlası • 168 B görüntüleme • 1,6 B beğeni"),
                       "Zaman Atlası")
        XCTAssertEqual(ArtistName.primary("Portishead"), "Portishead")
        XCTAssertEqual(ArtistName.primary(""), "")
    }

    /// The whole point of normalising: a byline whose tail keeps changing must
    /// still land on one artist, not one row per view count.
    func testDriftingViewCountStillGroupsUnderOneArtist() {
        let t = makeTracker()
        // No videoId, so identity falls back to title+artist: an unnormalised
        // byline would look like a different track on every single update.
        func snapshot(_ views: Int, position: Double) -> PlayTracker.Snapshot {
            PlayTracker.Snapshot(videoId: "", title: "Live Set",
                                 artist: "Zaman Atlası • \(views) B görüntüleme",
                                 duration: 200, position: position)
        }
        t.update(snapshot(168, position: 0))
        var p = 0.0
        var views = 168
        while p < 40 { p += 4; views += 1; t.update(snapshot(views, position: p)) }
        t.flush()

        XCTAssertEqual(scrobbles.count, 1, "the changing byline must not split the listen")
        XCTAssertEqual(scrobbles.first?.artist, "Zaman Atlası")
    }

    /// Artwork is empty on a track's first bridge event and arrives a beat
    /// later; the record must carry the URL that eventually showed up.
    func testArtworkArrivingLateIsStillRecorded() {
        let t = makeTracker()
        var s = snap("a", position: 0)
        s.artworkURL = ""
        t.update(s)
        for p in stride(from: 4.0, through: 40.0, by: 4.0) {
            var later = snap("a", position: p)
            later.artworkURL = "https://cover.jpg"
            t.update(later)
        }
        t.flush()
        XCTAssertEqual(scrobbles.first?.artworkURL, "https://cover.jpg")
    }

    func testMissingArtworkStaysNil() {
        let t = makeTracker()
        play(t, "a", upTo: 40)
        t.flush()
        XCTAssertNil(scrobbles.first?.artworkURL)
    }

    func testEmptyTitleIsIgnored() {
        let t = makeTracker()
        var s = snap("a", position: 0); s.title = ""
        t.update(s)
        t.flush()
        XCTAssertTrue(scrobbles.isEmpty)
    }
}
