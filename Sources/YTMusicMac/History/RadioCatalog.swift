import Foundation

/// One tappable radio. Every station is ultimately a seed for YT's own radio
/// (`RDAMVM<videoId>`), which is the only radio mechanism this app has actually
/// verified — YT hands out artist/album radio ids only through endpoints we
/// don't parse. So a station is "a track to seed from" plus how to present it.
struct RadioStation: Identifiable, Equatable {
    enum Kind: Equatable {
        case track       // radio around one song
        case artist      // radio seeded by an artist's biggest song
        case discovery   // today's rotating pick
    }

    let id: String
    let title: String
    let subtitle: String
    let seedVideoId: String
    let artworkURL: String?
    let kind: Kind
}

/// Turns local listening history into radios and mixes.
///
/// Pure and deterministic: every entry point takes the reference date, so the
/// daily/weekly rotations can be tested outright rather than by waiting a day.
/// Nothing here touches the network — YT Music exposes no such recommendations
/// and the app's own SQLite history is the only source.
enum RadioCatalog {

    // MARK: - Stations

    /// Radios seeded by the tracks you play most.
    static func forYou(topTracks: [TrackStat], limit: Int = 12) -> [RadioStation] {
        topTracks
            .filter { !$0.videoId.isEmpty }
            .prefix(limit)
            .map { track in
                RadioStation(id: "track:\(track.videoId)",
                             title: track.title,
                             subtitle: track.artist,
                             seedVideoId: track.videoId,
                             artworkURL: track.artworkURL,
                             kind: .track)
            }
    }

    /// One radio per artist, seeded by that artist's biggest track.
    /// `subtitleFor` supplies the localized "<Artist> radio" caption.
    static func byArtist(topTrackPerArtist: [TrackStat],
                         limit: Int = 12,
                         subtitleFor: (TrackStat) -> String) -> [RadioStation] {
        topTrackPerArtist
            .filter { !$0.videoId.isEmpty && !$0.artist.isEmpty }
            .prefix(limit)
            .map { track in
                RadioStation(id: "artist:\(track.artist)",
                             title: track.artist,
                             subtitle: subtitleFor(track),
                             seedVideoId: track.videoId,
                             artworkURL: track.artworkURL,
                             kind: .artist)
            }
    }

    /// Today's discovery picks.
    ///
    /// These are radios, not a fixed track list — that's what makes them
    /// discovery rather than a replay. YT fills a radio with tracks adjacent to
    /// the seed, so rotating which of your own songs gets to be the seed each
    /// day surfaces different neighbours without us needing a recommender.
    ///
    /// Drawn from beyond your top few so the rotation isn't the same handful
    /// every day, and deterministic per day so it doesn't reshuffle on every
    /// redraw or app relaunch.
    static func dailyDiscovery(pool: [TrackStat],
                               on date: Date,
                               count: Int = 6,
                               calendar: Calendar = .current) -> [RadioStation] {
        let candidates = pool.filter { !$0.videoId.isEmpty }
        guard !candidates.isEmpty else { return [] }
        let picks = rotate(candidates, count: count, seed: dayNumber(of: date, calendar: calendar))
        return picks.map { track in
            RadioStation(id: "discovery:\(track.videoId)",
                         title: track.title,
                         subtitle: track.artist,
                         seedVideoId: track.videoId,
                         artworkURL: track.artworkURL,
                         kind: .discovery)
        }
    }

    // MARK: - Weekly mix

    /// A fixed set of tracks for the week — a playable list, not a radio.
    /// Re-seeds every week so it feels new on Monday but never changes under
    /// the user mid-week.
    static func weeklyMix(pool: [TrackStat],
                          on date: Date,
                          count: Int = 25,
                          calendar: Calendar = .current) -> [TrackStat] {
        let candidates = pool.filter { !$0.videoId.isEmpty }
        guard !candidates.isEmpty else { return [] }
        return rotate(candidates, count: count, seed: weekNumber(of: date, calendar: calendar))
    }

    // MARK: - Rotation

    /// Deterministically picks `count` distinct entries for `seed`.
    ///
    /// A plain `seed % count` stride would walk the list in order and, when the
    /// stride shares a factor with the count, revisit the same few entries
    /// forever. Shuffling the whole list with a seeded generator gives every
    /// track a turn and keeps consecutive days unrelated.
    static func rotate<T>(_ items: [T], count: Int, seed: UInt64) -> [T] {
        guard !items.isEmpty, count > 0 else { return [] }
        var rng = SeededGenerator(seed: seed)
        return Array(items.shuffled(using: &rng).prefix(count))
    }

    /// Days since the epoch, in the user's calendar — the rotation must turn
    /// over at the user's midnight, not UTC's.
    static func dayNumber(of date: Date, calendar: Calendar = .current) -> UInt64 {
        let start = calendar.startOfDay(for: date)
        return UInt64(max(0, Int(start.timeIntervalSince1970) / 86_400))
    }

    /// A week identity that doesn't reset each January — `weekOfYear` alone
    /// would repeat week 1 every year and hand back an old mix.
    static func weekNumber(of date: Date, calendar: Calendar = .current) -> UInt64 {
        let components = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return UInt64(max(0, year * 53 + week))
    }

    // MARK: - Archive windows

    /// The same calendar day, `yearsAgo` years back. Returns nil when that day
    /// doesn't exist (Feb 29) rather than silently sliding to the 28th.
    static func sameDay(yearsAgo: Int, from date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let target = calendar.date(byAdding: .year, value: -yearsAgo, to: date) else { return nil }
        let start = calendar.startOfDay(for: target)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The whole calendar month `monthsAgo` months back.
    static func month(monthsAgo: Int, from date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let target = calendar.date(byAdding: .month, value: -monthsAgo, to: date),
              let interval = calendar.dateInterval(of: .month, for: target) else { return nil }
        return interval
    }
}

/// Small deterministic PRNG (SplitMix64). `SystemRandomNumberGenerator` can't
/// be seeded, and the rotations must reproduce the same picks for the same day
/// across relaunches.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Any seed works, but 0 makes SplitMix64's first outputs degenerate.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
