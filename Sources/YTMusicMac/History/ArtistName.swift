import Foundation

enum ArtistName {
    /// The player bar's byline is a bullet-joined line, not an artist name:
    /// "Radiohead • In Rainbows • 2007" for a song, and for a video
    /// "Zaman Atlası • 168 B görüntüleme • 1,6 B beğeni". Only the first
    /// segment names the artist — keeping the rest would file one artist under
    /// a fresh row every time the view count ticks up.
    ///
    /// Applied only on the way into the history database. `NowPlaying.artist`
    /// keeps the full byline, which is what notifications and Now Playing show.
    static func primary(_ byline: String) -> String {
        let head = byline.split(separator: "•", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return head.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turkish "ve" and English "and", plus comma lists. Deliberately NOT "&":
    /// "Santi & Tuğçe" is one act, and splitting it would invent an artist.
    private static let credits = [" ve ", " and ", ","]

    /// The lead artist out of a multi-credit name: "Oceanvs Orientalis ve Idil
    /// Mese" → "Oceanvs Orientalis". nil when the name credits only one act.
    ///
    /// Two callers, both needing the same notion of "who is this really":
    /// Last.fm knows the lead artist but not the credit line, and the radio rows
    /// must not show "Dedublüman" and "Dedublüman ve Aleyna Tilki" as two cards.
    ///
    /// Never applied on the way into the database — the stored artist has to
    /// stay whatever was played, or the history stops adding up.
    static func lead(_ name: String) -> String? {
        var earliest: String.Index?
        for credit in credits {
            guard let range = name.range(of: credit) else { continue }
            if earliest == nil || range.lowerBound < earliest! { earliest = range.lowerBound }
        }
        guard let cut = earliest else { return nil }
        let lead = name[..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
        // A name that *starts* with a credit separator has no lead to fall back to.
        return lead.isEmpty ? nil : lead
    }
}
