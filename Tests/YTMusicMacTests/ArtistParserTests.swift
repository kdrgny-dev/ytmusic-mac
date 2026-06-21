import XCTest
@testable import YTMusicMac

/// Spec the ArtistParser contract before implementing it. Each test
/// pins one shape we expect from real /browse UC… responses (verified
/// against ytmusicapi's reference fixtures), shrunk to the smallest
/// JSON that still exercises the path.
final class ArtistParserTests: XCTestCase {

    func testParsesHeaderNameAndSubscriberText() {
        let json = """
        {
          "header": { "musicImmersiveHeaderRenderer": {
              "title": { "runs": [{ "text": "Test Artist" }] },
              "subscriptionButton": { "subscribeButtonRenderer": {
                  "subscriberCountText": { "runs": [{ "text": "1.2M abonements" }] }
              }},
              "thumbnail": { "musicThumbnailRenderer": { "thumbnail": {
                  "thumbnails": [{ "url": "https://t" }]
              }}}
          }},
          "contents": {}
        }
        """.data(using: .utf8)!
        let artist = ArtistParser.parse(data: json, browseId: "UCabc")
        XCTAssertNotNil(artist)
        XCTAssertEqual(artist?.id, "UCabc")
        XCTAssertEqual(artist?.name, "Test Artist")
        XCTAssertEqual(artist?.subscriberText, "1.2M abonements")
        XCTAssertEqual(artist?.thumbnailURL, "https://t")
    }

    func testParsesTopSongsShelf() {
        // Top songs live inside a musicShelfRenderer that's nested in
        // sectionListRenderer.contents.
        let json = """
        {
          "header": { "musicImmersiveHeaderRenderer": {
              "title": { "runs": [{ "text": "X" }] }
          }},
          "contents": { "singleColumnBrowseResultsRenderer": {
              "tabs": [{ "tabRenderer": { "content": {
                  "sectionListRenderer": { "contents": [
                    { "musicShelfRenderer": {
                        "title": { "runs": [{ "text": "Songs" }] },
                        "contents": [
                          { "musicResponsiveListItemRenderer": {
                              "playlistItemData": { "videoId": "song1" },
                              "flexColumns": [
                                { "musicResponsiveListItemFlexColumnRenderer": {
                                    "text": { "runs": [{ "text": "Track 1" }] } } },
                                { "musicResponsiveListItemFlexColumnRenderer": {
                                    "text": { "runs": [{ "text": "Test Artist" }] } } }
                              ]
                          }},
                          { "musicResponsiveListItemRenderer": {
                              "playlistItemData": { "videoId": "song2" },
                              "flexColumns": [
                                { "musicResponsiveListItemFlexColumnRenderer": {
                                    "text": { "runs": [{ "text": "Track 2" }] } } }
                              ]
                          }}
                        ]
                    }}
                  ]}
              }}}]
          }}
        }
        """.data(using: .utf8)!
        let artist = ArtistParser.parse(data: json, browseId: "UCabc")
        XCTAssertEqual(artist?.topSongs.count, 2)
        XCTAssertEqual(artist?.topSongs.first?.id, "song1")
        XCTAssertEqual(artist?.topSongs.first?.title, "Track 1")
    }

    func testCategorisesAlbumsVsSinglesByShelfTitle() {
        let json = """
        {
          "header": { "musicImmersiveHeaderRenderer": {
              "title": { "runs": [{ "text": "X" }] }
          }},
          "contents": { "singleColumnBrowseResultsRenderer": {
              "tabs": [{ "tabRenderer": { "content": {
                  "sectionListRenderer": { "contents": [
                    { "musicCarouselShelfRenderer": {
                        "header": { "musicCarouselShelfBasicHeaderRenderer": {
                            "title": { "runs": [{ "text": "Albums" }] }
                        }},
                        "contents": [
                          { "musicTwoRowItemRenderer": {
                              "title": { "runs": [{ "text": "Album One" }] },
                              "subtitle": { "runs": [
                                  { "text": "Album" }, { "text": " • " }, { "text": "2020" }
                              ] },
                              "navigationEndpoint": { "browseEndpoint": {
                                  "browseId": "MPREb_one"
                              }},
                              "thumbnailRenderer": { "musicThumbnailRenderer": {
                                  "thumbnail": { "thumbnails": [{ "url": "https://a" }] }
                              }}
                          }}
                        ]
                    }},
                    { "musicCarouselShelfRenderer": {
                        "header": { "musicCarouselShelfBasicHeaderRenderer": {
                            "title": { "runs": [{ "text": "Singles" }] }
                        }},
                        "contents": [
                          { "musicTwoRowItemRenderer": {
                              "title": { "runs": [{ "text": "Single One" }] },
                              "subtitle": { "runs": [
                                  { "text": "Single" }, { "text": " • " }, { "text": "2024" }
                              ] },
                              "navigationEndpoint": { "browseEndpoint": {
                                  "browseId": "MPREb_single"
                              }},
                              "thumbnailRenderer": { "musicThumbnailRenderer": {
                                  "thumbnail": { "thumbnails": [{ "url": "https://b" }] }
                              }}
                          }}
                        ]
                    }}
                  ]}
              }}}]
          }}
        }
        """.data(using: .utf8)!
        let artist = ArtistParser.parse(data: json, browseId: "UCabc")
        XCTAssertEqual(artist?.albums.count, 1)
        XCTAssertEqual(artist?.albums.first?.title, "Album One")
        XCTAssertEqual(artist?.singles.count, 1)
        XCTAssertEqual(artist?.singles.first?.title, "Single One")
    }

    func testReturnsNilOnUnparseableJson() {
        let badData = Data("not json".utf8)
        XCTAssertNil(ArtistParser.parse(data: badData, browseId: "UC"))
    }

    func testReturnsNilWhenHeaderMissing() {
        let json = """
        { "contents": {} }
        """.data(using: .utf8)!
        // No name to display → nothing useful to render → nil.
        XCTAssertNil(ArtistParser.parse(data: json, browseId: "UC"))
    }
}
