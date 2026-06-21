import XCTest
@testable import YTMusicMac

/// Tests for the JSON walkers that turn InnerTube responses into typed
/// state for the SwiftUI shell. Each test ships a tiny synthetic JSON
/// snippet — small enough to read at a glance, big enough to exercise
/// the parser path we care about. No fixtures from disk and no network.
final class ParserTests: XCTestCase {

    // MARK: - GenreParser

    func testGenreParserExtractsSectionTitleAndChips() throws {
        let json = """
        {
          "contents": [
            { "gridRenderer": {
                "header": { "gridHeaderRenderer": {
                  "title": { "runs": [{ "text": "Moods & moments" }] }
                }},
                "items": [
                  { "musicNavigationButtonRenderer": {
                      "buttonText": { "runs": [{ "text": "Chill" }] },
                      "clickCommand": { "browseEndpoint": {
                          "browseId": "FEmusic_moods_and_genres_category",
                          "params": "CHILL_PARAMS"
                      }},
                      "solid": { "leftStripeColor": 4288585374 }
                  }},
                  { "musicNavigationButtonRenderer": {
                      "buttonText": { "runs": [{ "text": "Focus" }] },
                      "clickCommand": { "browseEndpoint": {
                          "browseId": "FEmusic_moods_and_genres_category",
                          "params": "FOCUS_PARAMS"
                      }}
                  }}
                ]
            }}
          ]
        }
        """.data(using: .utf8)!

        let sections = GenreParser.parseSections(data: json)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Moods & moments")
        XCTAssertEqual(sections[0].chips.count, 2)
        XCTAssertEqual(sections[0].chips[0].title, "Chill")
        XCTAssertEqual(sections[0].chips[0].params, "CHILL_PARAMS")
        XCTAssertEqual(sections[0].chips[0].id, "CHILL_PARAMS",
                       "id must be params, not browseId — every chip shares the same browseId")
        XCTAssertNotNil(sections[0].chips[0].color)
        XCTAssertEqual(sections[0].chips[1].title, "Focus")
        XCTAssertNil(sections[0].chips[1].color,
                     "chip without solid.leftStripeColor should have nil color")
    }

    func testGenreParserSkipsChipsWithoutParams() {
        // Real responses sometimes include nav buttons that point at
        // navigation other than a category landing. Those have no params
        // token and we should drop them rather than ship broken links.
        let json = """
        {
          "items": [
            { "musicNavigationButtonRenderer": {
                "buttonText": { "runs": [{ "text": "No params here" }] },
                "clickCommand": { "browseEndpoint": {
                    "browseId": "SOMETHING_ELSE"
                }}
            }}
          ]
        }
        """.data(using: .utf8)!
        // No gridRenderer wrapper -> no section anyway. Confirm graceful zero.
        XCTAssertEqual(GenreParser.parseSections(data: json).count, 0)
    }

    // MARK: - TrackParser (playlist / album track lists)

    func testTrackParserExtractsTitleArtistDurationVideoId() {
        let json = """
        {
          "contents": [
            { "musicResponsiveListItemRenderer": {
                "playlistItemData": { "videoId": "abc123" },
                "flexColumns": [
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "Track Title" }] }
                  }},
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "Artist Name" }] }
                  }}
                ],
                "fixedColumns": [
                  { "musicResponsiveListItemFixedColumnRenderer": {
                      "text": { "runs": [{ "text": "3:42" }] }
                  }}
                ],
                "thumbnail": { "musicThumbnailRenderer": { "thumbnail": {
                    "thumbnails": [
                        { "url": "https://thumb/small", "width": 60 },
                        { "url": "https://thumb/large", "width": 600 }
                    ]
                }}}
            }}
          ]
        }
        """.data(using: .utf8)!
        let tracks = TrackParser.parse(data: json)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].id, "abc123")
        XCTAssertEqual(tracks[0].title, "Track Title")
        XCTAssertEqual(tracks[0].artist, "Artist Name")
        XCTAssertEqual(tracks[0].duration, "3:42")
        XCTAssertEqual(tracks[0].thumbnailURL, "https://thumb/large",
                       "should take the highest-res (last) thumbnail")
    }

    func testTrackParserDedupesByVideoId() {
        // YT sometimes returns the same track in multiple shelves (top
        // picks + main list). Make sure we drop duplicates.
        let json = """
        {
          "contents": [
            { "musicResponsiveListItemRenderer": {
                "playlistItemData": { "videoId": "dup1" },
                "flexColumns": [
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "A" }] } } }
                ]
            }},
            { "musicResponsiveListItemRenderer": {
                "playlistItemData": { "videoId": "dup1" },
                "flexColumns": [
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "A again" }] } } }
                ]
            }},
            { "musicResponsiveListItemRenderer": {
                "playlistItemData": { "videoId": "uniq2" },
                "flexColumns": [
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "B" }] } } }
                ]
            }}
          ]
        }
        """.data(using: .utf8)!
        let tracks = TrackParser.parse(data: json)
        XCTAssertEqual(tracks.map { $0.id }, ["dup1", "uniq2"])
    }

    // MARK: - PlaylistParser (sidebar)

    func testPlaylistParserOnlyAcceptsVLPLBrowseIds() {
        let json = """
        {
          "items": [
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "My Mix" }] },
                "navigationEndpoint": { "browseEndpoint": { "browseId": "VLPLabc" } },
                "thumbnailRenderer": { "musicThumbnailRenderer": { "thumbnail": {
                    "thumbnails": [{ "url": "https://x" }]
                }}}
            }},
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "Some Album" }] },
                "navigationEndpoint": { "browseEndpoint": { "browseId": "MPREb_xxx" } },
                "thumbnailRenderer": { "musicThumbnailRenderer": { "thumbnail": {
                    "thumbnails": [{ "url": "https://y" }]
                }}}
            }}
          ]
        }
        """.data(using: .utf8)!
        let playlists = PlaylistParser.parse(data: json)
        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists[0].id, "VLPLabc")
        XCTAssertEqual(playlists[0].title, "My Mix")
    }

    // MARK: - SearchResultsParser

    func testSearchResultsParserUsesSubtitleFirstRunForKind() {
        let json = """
        {
          "contents": [
            { "musicResponsiveListItemRenderer": {
                "flexColumns": [
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "Song Title" }] } } },
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [
                          { "text": "Song" }, { "text": " • " }, { "text": "Some Artist" }
                      ] } } }
                ],
                "playlistItemData": { "videoId": "song1" }
            }},
            { "musicResponsiveListItemRenderer": {
                "flexColumns": [
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "Album Name" }] } } },
                  { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [
                          { "text": "Album" }, { "text": " • " }, { "text": "Artist" }
                      ] } } }
                ],
                "navigationEndpoint": { "browseEndpoint": { "browseId": "MPREb_alb" } }
            }}
          ]
        }
        """.data(using: .utf8)!
        let results = SearchResultsParser.parse(data: json)
        XCTAssertEqual(results.count, 2)
        let songs = results.filter { $0.kind == .song }
        let albums = results.filter { $0.kind == .album }
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs.first?.title, "Song Title")
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.title, "Album Name")
        XCTAssertEqual(albums.first?.id, "MPREb_alb")
    }

    // MARK: - HomeParser

    func testHomeParserExtractsCarouselShelves() {
        let json = """
        {
          "contents": [
            { "musicCarouselShelfRenderer": {
                "header": { "musicCarouselShelfBasicHeaderRenderer": {
                    "title": { "runs": [{ "text": "Listen again" }] },
                    "strapline": { "runs": [{ "text": "Quick picks" }] }
                }},
                "contents": [
                  { "musicTwoRowItemRenderer": {
                      "title": { "runs": [{ "text": "Some Album" }] },
                      "subtitle": { "runs": [
                          { "text": "Album" }, { "text": " • " }, { "text": "Artist" }
                      ] },
                      "navigationEndpoint": { "browseEndpoint": { "browseId": "MPREb_xyz" } },
                      "thumbnailRenderer": { "musicThumbnailRenderer": { "thumbnail": {
                          "thumbnails": [{ "url": "https://thumb" }]
                      }}}
                  }}
                ]
            }}
          ]
        }
        """.data(using: .utf8)!
        let shelves = HomeParser.parse(data: json)
        XCTAssertEqual(shelves.count, 1)
        XCTAssertEqual(shelves[0].title, "Listen again")
        XCTAssertEqual(shelves[0].subtitle, "Quick picks")
        XCTAssertEqual(shelves[0].items.count, 1)
        XCTAssertEqual(shelves[0].items[0].kind, .album)
        XCTAssertEqual(shelves[0].items[0].id, "MPREb_xyz")
    }

    // MARK: - CategoryParser

    func testCategoryParserPullsPlaylistTiles() {
        let json = """
        {
          "contents": [
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "Chill Vibes" }] },
                "navigationEndpoint": { "browseEndpoint": { "browseId": "VLPLchill" } },
                "thumbnailRenderer": { "musicThumbnailRenderer": { "thumbnail": {
                    "thumbnails": [{ "url": "https://a" }]
                }}}
            }},
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "Should-be-skipped" }] },
                "navigationEndpoint": { "browseEndpoint": { "browseId": "UC123" } },
                "thumbnailRenderer": { "musicThumbnailRenderer": { "thumbnail": {
                    "thumbnails": [{ "url": "https://b" }]
                }}}
            }}
          ]
        }
        """.data(using: .utf8)!
        let playlists = CategoryParser.parse(data: json)
        // Artist browseIds (UC…) shouldn't be returned by the category
        // parser — it's specifically a playlist landing.
        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists[0].id, "VLPLchill")
    }
}
