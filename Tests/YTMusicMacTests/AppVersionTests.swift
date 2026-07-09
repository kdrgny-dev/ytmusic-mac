import XCTest
@testable import YTMusicMac

final class AppVersionTests: XCTestCase {

    func testComparesNumericallyNotLexically() {
        // The bug this guards: "0.10" < "0.9" as strings.
        XCTAssertTrue(AppVersion.isNewer("0.10", than: "0.9"))
        XCTAssertFalse(AppVersion.isNewer("0.9", than: "0.10"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(AppVersion.isNewer("0.2", than: "0.2"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(AppVersion.isNewer("1", than: "1.0.0"))
        XCTAssertTrue(AppVersion.isNewer("1.0.1", than: "1"))
    }

    func testTrailingJunkIsIgnored() {
        XCTAssertTrue(AppVersion.isNewer("1.2-beta", than: "1.1"))
        XCTAssertFalse(AppVersion.isNewer("1.1-beta", than: "1.2"))
    }

    func testMajorBeatsMinor() {
        XCTAssertTrue(AppVersion.isNewer("1.0", than: "0.99"))
    }
}
