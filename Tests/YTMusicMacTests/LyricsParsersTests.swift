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

    // MARK: - TimedLyricsParser

    func testTimedLyricsParserExtractsLinesAndTimes() {
        let json = """
        { "contents": { "elementRenderer": { "newElement": { "type": { "componentType": { "model": {
            "timedLyricsModel": { "lyricsData": {
                "timedLyricsData": [
                  { "lyricLine": "First line",
                    "cueRange": { "startTimeMilliseconds": "0", "endTimeMilliseconds": "3000", "metadata": { "id": "1" } } },
                  { "lyricLine": "Second line",
                    "cueRange": { "startTimeMilliseconds": "3200", "endTimeMilliseconds": "6000", "metadata": { "id": "2" } } }
                ],
                "sourceMessage": "Source: LyricFind"
            }}
        }}}}}}}
        """.data(using: .utf8)!
        let r = TimedLyricsParser.parse(data: json)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.lines.count, 2)
        XCTAssertEqual(r?.lines.first?.text, "First line")
        XCTAssertEqual(r?.lines.first?.start ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(r?.lines.last?.start ?? -1, 3.2, accuracy: 0.001)
        XCTAssertEqual(r?.source, "Source: LyricFind")
    }

    func testTimedLyricsParserReturnsNilForPlainResponse() {
        let json = """
        { "contents": { "sectionListRenderer": { "contents": [
            { "musicDescriptionShelfRenderer": { "description": { "runs": [ { "text": "plain" } ] } } }
        ]}}}
        """.data(using: .utf8)!
        XCTAssertNil(TimedLyricsParser.parse(data: json))
    }
}
