import XCTest
@testable import YTMusicMac

/// Last.fm's tags are a folksonomy: anyone can write anything, and the top tags
/// for an artist mix real genres with decades, moods and outright junk. These
/// tests pin down what survives that filter.
final class TagTaxonomyTests: XCTestCase {

    // MARK: - Classification

    func testRecognisesPlainGenres() {
        XCTAssertEqual(TagTaxonomy.classify("rock"), .genre("Rock"))
        XCTAssertEqual(TagTaxonomy.classify("jazz"), .genre("Jazz"))
        XCTAssertEqual(TagTaxonomy.classify("heavy metal"), .genre("Heavy Metal"))
    }

    func testGenreMatchIsCaseAndSpaceInsensitive() {
        XCTAssertEqual(TagTaxonomy.classify("  ROCK "), .genre("Rock"))
        XCTAssertEqual(TagTaxonomy.classify("Progressive  Rock"), .genre("Progressive Rock"))
    }

    /// The same genre reaches us under several spellings; if they don't collapse
    /// the page grows a "Hip Hop" row and a "Rap" row holding the same artists.
    func testAliasesCollapseToOneCanonicalName() {
        for spelling in ["hip hop", "hip-hop", "hiphop", "rap"] {
            XCTAssertEqual(TagTaxonomy.classify(spelling), .genre("Hip-Hop"), spelling)
        }
        for spelling in ["rnb", "r&b", "r and b"] {
            XCTAssertEqual(TagTaxonomy.classify(spelling), .genre("R&B"), spelling)
        }
        for spelling in ["electronica", "electronic", "electro"] {
            XCTAssertEqual(TagTaxonomy.classify(spelling), .genre("Electronic"), spelling)
        }
    }

    func testRecognisesDecades() {
        XCTAssertEqual(TagTaxonomy.classify("90s"), .decade(1990))
        XCTAssertEqual(TagTaxonomy.classify("80s"), .decade(1980))
        XCTAssertEqual(TagTaxonomy.classify("00s"), .decade(2000))
        XCTAssertEqual(TagTaxonomy.classify("10s"), .decade(2010))
    }

    /// "90s" and "1990s" are the same bucket — otherwise the decade row shows
    /// the same ten years twice.
    func testTwoAndFourDigitDecadesAreOneBucket() {
        XCTAssertEqual(TagTaxonomy.classify("1990s"), .decade(1990))
        XCTAssertEqual(TagTaxonomy.classify("1990's"), .decade(1990))
        XCTAssertEqual(TagTaxonomy.classify("2000s"), .decade(2000))
    }

    /// Two-digit decades are ambiguous: "20s" could be the 1920s or the 2020s.
    /// Anchored at 1930 so the common cases (60s–90s) land in the 20th century
    /// and 00s/10s/20s land in the 21st.
    func testAmbiguousTwoDigitDecadesResolveSensibly() {
        XCTAssertEqual(TagTaxonomy.classify("60s"), .decade(1960))
        XCTAssertEqual(TagTaxonomy.classify("30s"), .decade(1930))
        XCTAssertEqual(TagTaxonomy.classify("20s"), .decade(2020))
    }

    /// The reason a whitelist exists at all. These are among the most common
    /// tags on Last.fm and none of them is a genre.
    func testDiscardsNoise() {
        for junk in ["seen live", "favourites", "favorite songs", "awesome",
                     "female vocalists", "male vocalists", "beautiful",
                     "under 2000 listeners", "albums i own", "turkish",
                     "guilty pleasure", "sexy", "10 out of 10"] {
            XCTAssertEqual(TagTaxonomy.classify(junk), .noise, junk)
        }
    }

    /// How a track was recorded isn't what kind of music it is. Left in, these
    /// outranked every real genre on a real library and took the top row.
    func testRecordingStyleIsNotAGenre() {
        XCTAssertEqual(TagTaxonomy.classify("acoustic"), .noise)
        XCTAssertEqual(TagTaxonomy.classify("instrumental"), .noise)
    }

    /// A language or a country says nothing about the music, but "Turkish Pop"
    /// is a genre in its own right — and on a Turkish library it's the only
    /// usable tag several artists carry.
    func testDistinguishesALanguageTagFromARealGenre() {
        XCTAssertEqual(TagTaxonomy.classify("turkish"), .noise)
        XCTAssertEqual(TagTaxonomy.classify("Turkish Pop"), .genre("Turkish Pop"))
        XCTAssertEqual(TagTaxonomy.classify("turkce pop"), .genre("Turkish Pop"))
        XCTAssertEqual(TagTaxonomy.classify("türkçe pop"), .genre("Turkish Pop"))
    }

    func testAnatolianRockReachesTheTurkishCanonicalName() {
        XCTAssertEqual(TagTaxonomy.classify("anatolian rock"), .genre("Anadolu Rock"))
    }

    func testDiscardsEmptyAndPunctuationOnlyTags() {
        XCTAssertEqual(TagTaxonomy.classify(""), .noise)
        XCTAssertEqual(TagTaxonomy.classify("   "), .noise)
        XCTAssertEqual(TagTaxonomy.classify("---"), .noise)
    }

    // MARK: - Per-artist digest

    private func tag(_ name: String, _ count: Int) -> (name: String, count: Int) {
        (name: name, count: count)
    }

    /// A tag one person applied says nothing about the artist. Last.fm's count
    /// is a 0-100 relative weight, so the threshold is on that.
    func testTagsBelowTheWeightThresholdAreIgnored() {
        let digest = TagTaxonomy.digest(from: [tag("rock", 100), tag("polka", 10)])
        XCTAssertEqual(digest.genres, ["Rock"], "a weight-10 tag must not define the artist")
    }

    func testTagsAtTheThresholdCount() {
        let digest = TagTaxonomy.digest(from: [tag("jazz", 20)])
        XCTAssertEqual(digest.genres, ["Jazz"])
    }

    /// Without a cap, a well-tagged artist lands in every genre row and the
    /// sections stop meaning anything.
    func testCapsGenresPerArtist() {
        let many = [tag("rock", 100), tag("alternative", 95), tag("indie", 90),
                    tag("pop", 85), tag("electronic", 80), tag("punk", 75)]
        XCTAssertEqual(TagTaxonomy.digest(from: many).genres.count, 3)
    }

    func testKeepsTheHeaviestGenresWhenCapping() {
        let many = [tag("pop", 40), tag("rock", 100), tag("jazz", 60),
                    tag("metal", 90), tag("blues", 55)]
        XCTAssertEqual(TagTaxonomy.digest(from: many).genres, ["Rock", "Metal", "Jazz"])
    }

    /// Decades are a separate row, so they must not eat a genre slot.
    func testDecadesDoNotCountAgainstTheGenreCap() {
        let mixed = [tag("rock", 100), tag("90s", 95), tag("80s", 90),
                     tag("metal", 85), tag("punk", 80)]
        let digest = TagTaxonomy.digest(from: mixed)
        XCTAssertEqual(digest.genres, ["Rock", "Metal", "Punk"])
        XCTAssertEqual(digest.decades, [1990, 1980])
    }

    func testCollapsesDuplicateGenresFromAliases() {
        // Real shape: an artist tagged both "hip hop" and "rap".
        let digest = TagTaxonomy.digest(from: [tag("hip hop", 100), tag("rap", 90), tag("jazz", 80)])
        XCTAssertEqual(digest.genres, ["Hip-Hop", "Jazz"])
    }

    func testDigestOfNothingIsEmptyRatherThanAFailure() {
        let digest = TagTaxonomy.digest(from: [])
        XCTAssertTrue(digest.genres.isEmpty)
        XCTAssertTrue(digest.decades.isEmpty)
    }

    func testAnArtistTaggedOnlyWithJunkHasNoGenres() {
        let digest = TagTaxonomy.digest(from: [tag("seen live", 100), tag("favourites", 90)])
        XCTAssertTrue(digest.genres.isEmpty, "junk must not become a genre row")
    }
}
