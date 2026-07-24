import Foundation

/// Turns Last.fm's tags into genres and decades.
///
/// YT Music exposes no genre for a track or an artist, so the radio page's genre
/// rows are built from Last.fm's `artist.getTopTags`. Those tags are a
/// folksonomy — the top tags for a well-known artist routinely include "seen
/// live", "favourites" and "female vocalists" alongside the real genres. So the
/// mapping is whitelist-driven: a tag becomes a genre only if we recognise it,
/// and everything else is discarded rather than guessed at.
///
/// Pure and deterministic — no network, no clock, no database.
enum TagTaxonomy {

    enum Classification: Equatable {
        case genre(String)   // canonical display name
        case decade(Int)     // four-digit start year, e.g. 1990
        case noise
    }

    /// The digest we cache per artist.
    struct Digest: Equatable {
        var genres: [String] = []
        var decades: [Int] = []
    }

    /// Last.fm's tag count is a 0-100 relative weight. Below this a tag is one
    /// or two people's opinion, not a description of the artist.
    static let minWeight = 20

    /// An artist tagged with eight genres would otherwise appear in every row,
    /// which makes the rows stop meaning anything.
    static let maxGenresPerArtist = 3

    // MARK: - Classification

    static func classify(_ raw: String) -> Classification {
        let key = normalize(raw)
        guard !key.isEmpty else { return .noise }
        if let decade = decade(from: key) { return .decade(decade) }
        if let canonical = genres[key] { return .genre(canonical) }
        return .noise
    }

    /// Lowercased, punctuation dropped, runs of whitespace collapsed. Handles
    /// "Progressive  Rock", "hip-hop" and "R&B" landing on one another.
    private static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let cleaned = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            if ch == "&" { return ch }      // kept: distinguishes "r&b"
            return " "
        }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Decade tags: "90s", "1990s", "1990's". Two-digit forms are ambiguous —
    /// "20s" is far more likely the 2020s than the 1920s in a listening history,
    /// while "60s" is certainly the 1960s. Anchored at 1930: 30-99 read as
    /// 20th century, 00-29 as 21st.
    private static func decade(from key: String) -> Int? {
        // normalize() has already stripped the apostrophe, so "1990's" is "1990 s".
        let compact = key.replacingOccurrences(of: " ", with: "")
        guard compact.hasSuffix("s") else { return nil }
        let digits = String(compact.dropLast())
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }

        if digits.count == 4 {
            guard let year = Int(digits), year % 10 == 0 else { return nil }
            return year
        }
        if digits.count == 2 {
            guard let short = Int(digits), short % 10 == 0 else { return nil }
            return short >= 30 ? 1900 + short : 2000 + short
        }
        return nil
    }

    // MARK: - Per-artist digest

    /// Collapses one artist's tag list into the genres and decades worth caching.
    /// Input order doesn't matter: both lists come out sorted by tag weight, so
    /// capping keeps the heaviest.
    static func digest(from tags: [(name: String, count: Int)]) -> Digest {
        let strong = tags.filter { $0.count >= minWeight }
                         .sorted { $0.count > $1.count }

        var genres: [String] = []
        var decades: [Int] = []
        for tag in strong {
            switch classify(tag.name) {
            case .genre(let name):
                // Aliases mean two tags can yield the same canonical name.
                guard genres.count < maxGenresPerArtist, !genres.contains(name) else { continue }
                genres.append(name)
            case .decade(let year):
                guard !decades.contains(year) else { continue }
                decades.append(year)
            case .noise:
                continue
            }
        }
        return Digest(genres: genres, decades: decades)
    }

    // MARK: - Whitelist

    /// Normalized tag → canonical display name. Aliases are extra keys pointing
    /// at the same name, which is what collapses "rap"/"hiphop" into one row.
    private static let genres: [String: String] = {
        var map: [String: String] = [:]

        /// `canonical` is itself registered, so listing aliases is optional.
        func add(_ canonical: String, _ aliases: String...) {
            map[normalize(canonical)] = canonical
            for alias in aliases { map[normalize(alias)] = canonical }
        }

        add("Rock")
        add("Pop")
        add("Jazz")
        add("Blues")
        add("Metal")
        add("Heavy Metal")
        add("Death Metal")
        add("Black Metal")
        add("Hard Rock")
        add("Progressive Rock", "prog rock", "progressive")
        add("Psychedelic Rock", "psychedelic", "psychedelic rock")
        add("Classic Rock")
        add("Alternative", "alternative rock", "alt rock")
        add("Indie", "indie rock", "indie pop")
        add("Punk", "punk rock")
        add("Post-Punk", "post punk")
        add("Grunge")
        add("Hip-Hop", "hip hop", "hiphop", "rap")
        add("R&B", "rnb", "r and b", "rhythm and blues")
        add("Soul")
        add("Funk")
        add("Disco")
        add("Reggae")
        add("Ska")
        add("Electronic", "electronica", "electro", "edm")
        add("House", "deep house")
        add("Techno")
        add("Trance")
        add("Drum and Bass", "dnb", "drum n bass")
        add("Dubstep")
        add("Ambient")
        add("Trip-Hop", "trip hop", "triphop")
        add("Synthpop", "synth pop", "synthwave")
        add("New Wave")
        add("Folk", "folk rock", "indie folk")
        add("Singer-Songwriter", "singer songwriter")
        add("Country")
        add("Classical")
        add("Opera")
        add("Soundtrack", "film score", "score")
        add("Latin")
        add("Salsa")
        add("Bossa Nova")
        add("Flamenco")
        add("Arabesk")
        add("Anadolu Rock", "anatolian rock")
        // A probe over a real library found six artists whose only usable tag
        // was this one — without it, plain "turkish" is all that comes back and
        // that's a language, not a genre.
        add("Turkish Pop", "turkce pop", "türkçe pop", "turkish pop")
        add("Minimal Techno", "minimal")
        add("Dub")
        add("Gothic", "gothic rock", "goth")
        add("Industrial")
        add("Emo")
        add("Hardcore")
        add("Lo-Fi", "lo fi", "lofi")
        add("Shoegaze")
        add("Dream Pop")
        add("Math Rock")
        add("Post-Rock", "post rock")
        add("Jazz Fusion", "fusion")
        add("Bebop")
        add("Swing")
        add("Gospel")
        add("Afrobeat")
        add("K-Pop", "kpop")
        add("J-Pop", "jpop")
        add("Rock and Roll", "rock n roll", "rock roll", "rockabilly")

        return map
    }()
}
