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

    func testCategoryParserReadsSubtitleAndTrackCount() {
        // YT only sometimes ends the subtitle with a count run; the card
        // shows a badge when it's there and nothing when it isn't.
        let json = """
        {
          "contents": [
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "Counted" }] },
                "subtitle": { "runs": [
                    { "text": "Playlist" }, { "text": " • " }, { "text": "50 songs" }
                ]},
                "navigationEndpoint": { "browseEndpoint": { "browseId": "VLPLa" } }
            }},
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "Turkish" }] },
                "subtitle": { "runs": [{ "text": "12 şarkı" }] },
                "navigationEndpoint": { "browseEndpoint": { "browseId": "VLPLb" } }
            }},
            { "musicTwoRowItemRenderer": {
                "title": { "runs": [{ "text": "Uncounted" }] },
                "subtitle": { "runs": [{ "text": "Ashnikko, Rico Nasty" }] },
                "navigationEndpoint": { "browseEndpoint": { "browseId": "VLPLc" } }
            }}
          ]
        }
        """.data(using: .utf8)!
        let playlists = CategoryParser.parse(data: json)
        XCTAssertEqual(playlists.count, 3)
        XCTAssertEqual(playlists[0].trackCount, 50)
        XCTAssertEqual(playlists[0].subtitle, "Playlist • 50 songs")
        XCTAssertEqual(playlists[1].trackCount, 12)
        XCTAssertNil(playlists[2].trackCount)
        XCTAssertEqual(playlists[2].subtitle, "Ashnikko, Rico Nasty")
    }

    // MARK: - WatchNextParser (queue)

    func testWatchNextQueueParsesRowsAndCollapsesCounterparts() {
        // The wrapper carries the song and its music-video counterpart with
        // the same videoId back to back — the queue should show it once.
        let json = """
        {
          "playlistPanelRenderer": { "contents": [
            { "playlistPanelVideoRenderer": {
                "videoId": "aaa",
                "title": { "runs": [{ "text": "Save Tonight" }] },
                "longBylineText": { "runs": [
                    { "text": "Eagle-Eye Cherry" }, { "text": " • " }, { "text": "Desireless" }
                ]},
                "thumbnail": { "thumbnails": [{ "url": "https://small" }, { "url": "https://big" }] }
            }},
            { "playlistPanelVideoWrapperRenderer": { "primaryRenderer": {
                "playlistPanelVideoRenderer": {
                    "videoId": "aaa",
                    "title": { "runs": [{ "text": "Save Tonight" }] },
                    "longBylineText": { "runs": [{ "text": "Eagle-Eye Cherry" }] }
                }
            }}},
            { "playlistPanelVideoRenderer": {
                "videoId": "bbb",
                "title": { "runs": [{ "text": "Cino" }] },
                "longBylineText": { "runs": [{ "text": "Rozz Kalliope" }] }
            }}
          ]}
        }
        """.data(using: .utf8)!
        let q = WatchNextParser.queue(data: json)
        XCTAssertEqual(q.map(\.videoId), ["aaa", "bbb"])
        XCTAssertEqual(q[0].artist, "Eagle-Eye Cherry",
                       "only the first byline run — the rest is album/year")
        XCTAssertEqual(q[0].thumbnailURL, "https://big", "highest-res thumbnail")
        XCTAssertEqual(q.map(\.id), [0, 1], "ids are positions")
    }

    func testWatchNextQueueIsEmptyForUnreadableResponse() {
        let json = "{ \"contents\": {} }".data(using: .utf8)!
        XCTAssertTrue(WatchNextParser.queue(data: json).isEmpty,
                      "callers fall back to the DOM copy on an empty parse")
    }

    // MARK: - SearchSuggestionsParser

    func testSearchSuggestionsJoinsRunsAndSkipsHistoryEntries() {
        // YT splits the suggestion across a typed run and a completion run,
        // and mixes in the account's own past searches — which we don't want,
        // the shell keeps its own recent-search list.
        let json = """
        {
          "contents": [
            { "searchSuggestionsSectionRenderer": { "contents": [
                { "historySuggestionRenderer": {
                    "suggestion": { "runs": [{ "text": "eski arama" }] } }},
                { "searchSuggestionRenderer": {
                    "suggestion": { "runs": [{ "text": "desire" }, { "text": "less" }] } }},
                { "searchSuggestionRenderer": {
                    "suggestion": { "runs": [{ "text": "desireless voyage" }] } }},
                { "searchSuggestionRenderer": {
                    "suggestion": { "runs": [{ "text": "Desireless" }] } }}
            ]}}
          ]
        }
        """.data(using: .utf8)!
        let out = SearchSuggestionsParser.parse(data: json)
        XCTAssertEqual(out, ["desireless", "desireless voyage"],
                       "runs join, history is skipped, case-insensitive dupes collapse")
    }

    func testSearchSuggestionsRespectsLimit() {
        let items = (0..<12).map {
            "{ \"searchSuggestionRenderer\": { \"suggestion\": { \"runs\": [{ \"text\": \"q\($0)\" }] } } }"
        }.joined(separator: ",")
        let json = "{ \"contents\": [\(items)] }".data(using: .utf8)!
        XCTAssertEqual(SearchSuggestionsParser.parse(data: json, limit: 5).count, 5)
    }

    // MARK: - HistoryParser

    func testHistoryParserGroupsByDayAndKeepsRepeats() {
        // FEmusic_history returns one musicShelfRenderer per day bucket.
        // The same track played twice today must appear twice.
        let json = """
        {
          "contents": [
            { "musicShelfRenderer": {
                "title": { "runs": [{ "text": "Bugün" }] },
                "contents": [
                  { "musicResponsiveListItemRenderer": {
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Save Tonight" }] }}},
                        { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Eagle-Eye Cherry" }] }}}
                      ],
                      "playlistItemData": { "videoId": "aaa" }
                  }},
                  { "musicResponsiveListItemRenderer": {
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Save Tonight" }] }}},
                        { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Eagle-Eye Cherry" }] }}}
                      ],
                      "playlistItemData": { "videoId": "aaa" }
                  }}
                ]
            }},
            { "musicShelfRenderer": {
                "title": { "runs": [{ "text": "Dün" }] },
                "contents": [
                  { "musicResponsiveListItemRenderer": {
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Cino" }] }}},
                        { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Rozz Kalliope" }] }}}
                      ],
                      "playlistItemData": { "videoId": "bbb" }
                  }}
                ]
            }}
          ]
        }
        """.data(using: .utf8)!
        let sections = HistoryParser.parse(data: json)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Bugün")
        XCTAssertEqual(sections[0].tracks.count, 2, "repeats within a day must survive")
        XCTAssertEqual(sections[1].title, "Dün")
        XCTAssertEqual(sections[1].tracks[0].artist, "Rozz Kalliope")
    }

    // MARK: - ChartsParser (Explore → charts)

    func testChartsParserExtractsRankedSongShelf() {
        // A carousel "Top songs" with song rows. Rank == position, order
        // preserved, thumbnail takes the highest-res (last) entry.
        let json = """
        {
          "contents": [
            { "musicCarouselShelfRenderer": {
                "header": { "musicCarouselShelfBasicHeaderRenderer": {
                    "title": { "runs": [{ "text": "Top songs" }] }
                }},
                "contents": [
                  { "musicResponsiveListItemRenderer": {
                      "playlistItemData": { "videoId": "v1" },
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "First Song" }] } } },
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "Artist One" }] } } }
                      ],
                      "thumbnail": { "musicThumbnailRenderer": { "thumbnail": {
                          "thumbnails": [{ "url": "https://s" }, { "url": "https://l" }]
                      }}}
                  }},
                  { "musicResponsiveListItemRenderer": {
                      "playlistItemData": { "videoId": "v2" },
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "Second Song" }] } } },
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "Artist Two" }] } } }
                      ]
                  }}
                ]
            }}
          ]
        }
        """.data(using: .utf8)!
        let sections = ChartsParser.parse(data: json)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Top songs")
        XCTAssertEqual(sections[0].tracks.map { $0.id }, ["v1", "v2"],
                       "order must be preserved — position is the rank")
        XCTAssertEqual(sections[0].tracks[0].title, "First Song")
        XCTAssertEqual(sections[0].tracks[0].artist, "Artist One")
        XCTAssertEqual(sections[0].tracks[0].thumbnailURL, "https://l")
    }

    func testChartsParserReadsMusicShelfRendererTitleAndOverlayVideoId() {
        // The non-carousel shelf variant puts title.runs directly on the
        // renderer, and some rows only carry the videoId in the play-button
        // overlay endpoint (no playlistItemData).
        let json = """
        {
          "contents": [
            { "musicShelfRenderer": {
                "title": { "runs": [{ "text": "Trending" }] },
                "contents": [
                  { "musicResponsiveListItemRenderer": {
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "Hot Track" }] } } }
                      ],
                      "overlay": { "musicItemThumbnailOverlayRenderer": { "content": {
                          "musicPlayButtonRenderer": { "playNavigationEndpoint": {
                              "watchEndpoint": { "videoId": "ov1" }
                          }}
                      }}}
                  }}
                ]
            }}
          ]
        }
        """.data(using: .utf8)!
        let sections = ChartsParser.parse(data: json)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Trending")
        XCTAssertEqual(sections[0].tracks.count, 1)
        XCTAssertEqual(sections[0].tracks[0].id, "ov1")
        XCTAssertEqual(sections[0].tracks[0].title, "Hot Track")
    }

    func testChartsParserSkipsCardOnlyShelvesAndDedupes() {
        // "Top artists" is cards (no videoId) -> no tracks -> skipped.
        // A song shelf with a duplicate videoId keeps only the first.
        let json = """
        {
          "contents": [
            { "musicCarouselShelfRenderer": {
                "header": { "musicCarouselShelfBasicHeaderRenderer": {
                    "title": { "runs": [{ "text": "Top artists" }] }
                }},
                "contents": [
                  { "musicTwoRowItemRenderer": {
                      "title": { "runs": [{ "text": "Some Artist" }] },
                      "navigationEndpoint": { "browseEndpoint": { "browseId": "UCabc" } }
                  }}
                ]
            }},
            { "musicCarouselShelfRenderer": {
                "header": { "musicCarouselShelfBasicHeaderRenderer": {
                    "title": { "runs": [{ "text": "Top music videos" }] }
                }},
                "contents": [
                  { "musicResponsiveListItemRenderer": {
                      "playlistItemData": { "videoId": "dup" },
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "A" }] } } } ]
                  }},
                  { "musicResponsiveListItemRenderer": {
                      "playlistItemData": { "videoId": "dup" },
                      "flexColumns": [
                        { "musicResponsiveListItemFlexColumnRenderer": {
                            "text": { "runs": [{ "text": "A again" }] } } } ]
                  }}
                ]
            }}
          ]
        }
        """.data(using: .utf8)!
        let sections = ChartsParser.parse(data: json)
        XCTAssertEqual(sections.count, 1, "card-only artist shelf must be skipped")
        XCTAssertEqual(sections[0].title, "Top music videos")
        XCTAssertEqual(sections[0].tracks.map { $0.id }, ["dup"], "duplicate videoId dropped")
    }
}
