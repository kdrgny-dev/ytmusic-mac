import Foundation

/// Decides when a track counts as "listened to" and emits one `PlayRecord`
/// per completed listen. Pure logic, no database and no clock of its own, so
/// the tests can drive it frame by frame.
///
/// The threshold is Last.fm's: 30 seconds, or half the track, whichever comes
/// first. Without it every skipped track would land in your top 10.
final class PlayTracker {
    struct Snapshot {
        var videoId: String
        var title: String
        var artist: String
        var duration: Double  // seconds, 0 when the page hasn't reported it yet
        var position: Double  // seconds
        var artworkURL: String = ""
    }

    /// A position jump larger than this is a seek, not elapsed playback. The
    /// bridge is event-driven with a 4s safety poll behind it, so real gaps
    /// between updates stay well under this.
    private static let maxPlausibleStep: Double = 8

    private struct InFlight {
        var snapshot: Snapshot
        var startedAt: Date
        var listened: Double = 0
        var lastPosition: Double
    }

    private let now: () -> Date
    private let onScrobble: (PlayRecord) -> Void
    private var current: InFlight?

    init(now: @escaping () -> Date = Date.init, onScrobble: @escaping (PlayRecord) -> Void) {
        self.now = now
        self.onScrobble = onScrobble
    }

    func update(_ raw: Snapshot) {
        guard !raw.title.isEmpty else { return }
        // Strip the byline down to the artist before it reaches identity or
        // the database — the tail of it changes while the track doesn't.
        var s = raw
        s.artist = ArtistName.primary(raw.artist)

        guard var live = current, live.snapshot.identity == s.identity else {
            finishCurrent()
            current = InFlight(snapshot: s, startedAt: now(), lastPosition: s.position)
            return
        }

        // Same track, but the playhead jumped back to the top: repeat-one, or
        // the user replayed it. That's a second listen, not a rewind.
        if s.position < 3, live.lastPosition > s.position + 2 {
            finishCurrent()
            current = InFlight(snapshot: s, startedAt: now(), lastPosition: s.position)
            return
        }

        let step = s.position - live.lastPosition
        if step > 0, step <= Self.maxPlausibleStep {
            live.listened += step
        }
        live.lastPosition = s.position
        // Duration and artwork both arrive empty on the first event of a track.
        if s.duration > 0 { live.snapshot.duration = s.duration }
        if !s.artworkURL.isEmpty { live.snapshot.artworkURL = s.artworkURL }
        current = live
    }

    /// Called when playback stops for good — app quit, or the player emptied.
    func flush() {
        finishCurrent()
    }

    /// Throw away the listen in progress without recording it. Used when the
    /// user turns history off mid-track.
    func reset() {
        current = nil
    }

    private func finishCurrent() {
        defer { current = nil }
        guard let live = current, live.listened >= threshold(for: live.snapshot.duration) else { return }

        onScrobble(PlayRecord(
            videoId: live.snapshot.videoId,
            title: live.snapshot.title,
            artist: live.snapshot.artist,
            album: nil,  // YT's bridge payload carries no album for the now-playing track
            durationMs: Int64(live.snapshot.duration * 1000),
            playedMs: Int64(live.listened * 1000),
            startedAt: live.startedAt,
            artworkURL: live.snapshot.artworkURL.isEmpty ? nil : live.snapshot.artworkURL))
    }

    private func threshold(for duration: Double) -> Double {
        duration > 0 ? min(30, duration / 2) : 30
    }
}

private extension PlayTracker.Snapshot {
    /// Prefer the videoId; fall back to title+artist when signed out or when
    /// the page hasn't surfaced an id yet.
    var identity: String {
        videoId.isEmpty ? "\(title)|\(artist)" : videoId
    }
}
