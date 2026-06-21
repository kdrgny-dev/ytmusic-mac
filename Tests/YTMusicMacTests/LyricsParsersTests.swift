import XCTest
@testable import YTMusicMac

/// Lyrics live behind a two-hop dance on InnerTube: /next returns a tab
/// whose endpoint browseId points at a /browse response with the
/// actual text. We test both walkers separately so each hop is
/// pinned independently.
final class LyricsParsersTests: XCTestCase {

    // MARK: - WatchNextParser

    func testWatchNextParserFindsLyricsBrowseId() {
        let json = """
        { "contents": {
            "singleColumnMusicWatchNextResultsRenderer": {
              "tabbedRenderer": { "watchNextTabbedResultsRenderer": {
                "tabs": [
                  { "tabRenderer": {
                      "title": { "runs": [{ "text": "Up next" }] }
                  }},
                  { "tabRenderer": {
                      "title": { "runs": [{ "text": "Lyrics" }] },
                      "endpoint": { "browseEndpoint": {
                          "browseId": "MPLYt_target"
                      }}
                  }},
                  { "tabRenderer": {
                      "title": { "runs": [{ "text": "Related" }] }
                  }}
                ]
              }}
            }
        }}
        """.data(using: .utf8)!
        XCTAssertEqual(WatchNextParser.extractLyricsBrowseId(data: json), "MPLYt_target")
    }

    func testWatchNextParserReturnsNilWhenLyricsTabAbsent() {
        let json = """
        { "contents": { "singleColumnMusicWatchNextResultsRenderer": {
            "tabbedRenderer": { "watchNextTabbedResultsRenderer": {
              "tabs": [
                { "tabRenderer": { "title": { "runs": [{ "text": "Up next" }] } } }
              ]
            }}
        }}}
        """.data(using: .utf8)!
        XCTAssertNil(WatchNextParser.extractLyricsBrowseId(data: json))
    }

    func testWatchNextParserMatchesTitleCaseInsensitively() {
        // YT sometimes returns "LYRICS" all-caps on certain locales.
        let json = """
        { "contents": { "tabs": [
            { "tabRenderer": {
                "title": { "runs": [{ "text": "LYRICS" }] },
                "endpoint": { "browseEndpoint": { "browseId": "MPL_id" } }
            }}
        ]}}
        """.data(using: .utf8)!
        XCTAssertEqual(WatchNextParser.extractLyricsBrowseId(data: json), "MPL_id")
    }

    // MARK: - LyricsParser

    func testLyricsParserExtractsTextAndSource() {
        let json = """
        { "contents": { "sectionListRenderer": { "contents": [
            { "musicDescriptionShelfRenderer": {
                "description": { "runs": [
                    { "text": "Line one\\nLine two\\nLine three" }
                ]},
                "footer": { "runs": [
                    { "text": "Source: Musixmatch" }
                ]}
            }}
        ]}}}
        """.data(using: .utf8)!
        let result = LyricsParser.parse(data: json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "Line one\nLine two\nLine three")
        XCTAssertEqual(result?.source, "Source: Musixmatch")
    }

    func testLyricsParserReturnsNilWhenNoDescriptionShelf() {
        // YT returns an empty section list when no lyrics for the track.
        let json = """
        { "contents": { "sectionListRenderer": { "contents": [] } } }
        """.data(using: .utf8)!
        XCTAssertNil(LyricsParser.parse(data: json))
    }
}
