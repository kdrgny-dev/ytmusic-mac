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
}
