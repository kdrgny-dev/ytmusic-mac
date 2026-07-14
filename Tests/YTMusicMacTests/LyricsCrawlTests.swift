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

    func testOffsetStartsBelowViewport() {
        // progress 0 → content sits just below the viewport (offset == viewport)
        XCTAssertEqual(
            LyricsCrawl.offset(progress: 0, content: 400, viewport: 200),
            200, accuracy: 0.0001)
    }

    func testOffsetEndsAboveViewport() {
        // progress 1 → content fully exited the top (offset == -content)
        XCTAssertEqual(
            LyricsCrawl.offset(progress: 1, content: 400, viewport: 200),
            -400, accuracy: 0.0001)
    }

    func testOffsetMidpoint() {
        // viewport 200, content 100 → 200 - 0.5*(300) = 50
        XCTAssertEqual(
            LyricsCrawl.offset(progress: 0.5, content: 100, viewport: 200),
            50, accuracy: 0.0001)
    }
}
