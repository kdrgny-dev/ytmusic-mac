import Foundation

/// Which names to try when asking Last.fm about an artist.
///
/// YT Music's byline credits everyone: "Oceanvs Orientalis ve Idil Mese",
/// "KÖFN, Simge, Salman Tin ve BKE". Last.fm has no such artist, so a probe over
/// a real library came back empty for 13 of the top 60 artists — falling back to
/// the lead artist recovered 9 of them. The name we *store* never changes: the
/// history rows and the cache key have to keep matching each other.
enum LastfmArtistQuery {

    /// The original name first, then the lead artist if that's a different name.
    static func candidates(for artist: String) -> [String] {
        let full = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return [] }
        guard let lead = ArtistName.lead(full), lead != full else { return [full] }
        return [full, lead]
    }
}
