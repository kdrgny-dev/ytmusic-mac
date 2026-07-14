import XCTest
import CoreGraphics
@testable import YTMusicMac

final class LyricsCrawlTests: XCTestCase {

    func testProgressZeroWhenDurationZero() {
        XCTAssertEqual(LyricsCrawl.progress(time: 30, duration: 0), 0)
    }

    func testProgressClampsToUnitInterval() {
        XCTAssertEqual(LyricsCrawl.progress(time: -5, duration: 100), 0)
        XCTAssertEqual(LyricsCrawl.progress(time: 250, duration: 100), 1)
        XCTAssertEqual(LyricsCrawl.progress(time: 50, duration: 100), 0.5, accuracy: 0.0001)
    }

    func testActiveIndexEmptyIsZero() {
        XCTAssertEqual(LyricsCrawl.activeIndex(progress: 0.5, lineCount: 0), 0)
    }

    func testActiveIndexStart() {
        XCTAssertEqual(LyricsCrawl.activeIndex(progress: 0, lineCount: 10), 0)
    }

    func testActiveIndexEndClampsToLastLine() {
        // progress 1 must not overflow to lineCount
        XCTAssertEqual(LyricsCrawl.activeIndex(progress: 1, lineCount: 10), 9)
    }

    func testActiveIndexMidpoint() {
        XCTAssertEqual(LyricsCrawl.activeIndex(progress: 0.5, lineCount: 10), 5)
    }

    // MARK: - Timestamped (real sync)

    private let synced = [
        LyricsLine(text: "a", start: 0),
        LyricsLine(text: "b", start: 10),
        LyricsLine(text: "c", start: 20),
    ]

    func testSyncedActiveIndexBeforeFirstIsZero() {
        XCTAssertEqual(LyricsCrawl.activeIndex(synced: synced, time: 0), 0)
        XCTAssertEqual(LyricsCrawl.activeIndex(synced: synced, time: 9.9), 0)
    }

    func testSyncedActiveIndexAdvancesAtStartTime() {
        XCTAssertEqual(LyricsCrawl.activeIndex(synced: synced, time: 10), 1)
        XCTAssertEqual(LyricsCrawl.activeIndex(synced: synced, time: 25), 2)
    }

    func testSyncedActiveIndexEmptyIsZero() {
        XCTAssertEqual(LyricsCrawl.activeIndex(synced: [], time: 5), 0)
    }
}
