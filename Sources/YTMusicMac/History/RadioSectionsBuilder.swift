import Foundation

/// Builds the radio page's genre and decade rows out of listening history plus
/// cached Last.fm tags.
///
/// Pure: every input is a parameter, including the date and the reroll counter,
/// so the rotation can be tested outright instead of by waiting a day. Lives
/// outside the view model deliberately — `NativeShellViewModel` is already far
/// too large, and none of this needs to be in an ObservableObject.
enum RadioSectionsBuilder {

    /// Enough cards that a row looks like a row. Below this it reads as a
    /// rendering bug rather than a section.
    static let minStationsPerSection = 3
    /// The page already carries four rows before these; five more is the point
    /// where scrolling starts to cost more than the discovery is worth.
    static let maxGenreSections = 5
    static let stationsPerSection = 12

    typealias Section = NativeShellViewModel.RadioSection

    static func build(topTrackPerArtist: [TrackStat],
                      tags: [String: TagTaxonomy.Digest],
                      reroll: Int,
                      on date: Date,
                      calendar: Calendar = .current,
                      genreTitle: (String) -> String = { L10n.t("vm.radio.genreSection", $0) },
                      genreSubtitle: (String) -> String = { L10n.t("vm.radio.genreSection.subtitle", $0) },
                      decadeName: (Int) -> String = defaultDecadeName) -> [Section] {

        // A seed track is what makes a station playable; without a videoId the
        // radio URL would be broken, so those artists can't take part at all.
        let seeds = topTrackPerArtist.filter { !$0.videoId.isEmpty && !$0.artist.isEmpty }
        guard !seeds.isEmpty, !tags.isEmpty else { return [] }

        let day = RadioCatalog.dayNumber(of: date, calendar: calendar)

        var sections = genreSections(seeds: seeds, tags: tags, day: day, reroll: reroll,
                                     title: genreTitle, subtitle: genreSubtitle)
        if let decades = decadeSection(seeds: seeds, tags: tags, day: day, reroll: reroll,
                                      name: decadeName) {
            sections.append(decades)
        }
        return sections
    }

    // MARK: - Genres

    private static func genreSections(seeds: [TrackStat],
                                      tags: [String: TagTaxonomy.Digest],
                                      day: UInt64,
                                      reroll: Int,
                                      title: (String) -> String,
                                      subtitle: (String) -> String) -> [Section] {
        var byGenre: [String: [TrackStat]] = [:]
        for seed in seeds {
            for genre in tags[seed.artist]?.genres ?? [] {
                byGenre[genre, default: []].append(seed)
            }
        }

        // Ranked by how much the user actually plays the genre, not by how many
        // artists happen to carry the tag. Name breaks ties so the order can't
        // wobble between launches.
        let ranked = byGenre
            .filter { $0.value.count >= minStationsPerSection }
            .map { (genre: $0.key, artists: $0.value, weight: $0.value.reduce(0) { $0 + $1.plays }) }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.genre < $1.genre }
            .prefix(maxGenreSections)

        return ranked.map { entry in
            let picks = rotate(entry.artists, seed: seedValue(day: day, reroll: reroll, salt: entry.genre))
            return Section(id: "genre:\(entry.genre)",
                           title: title(entry.genre),
                           subtitle: subtitle(entry.genre),
                           stations: picks.map { station(for: $0, caption: entry.genre,
                                                         idPrefix: "genre:\(entry.genre)") })
        }
    }

    // MARK: - Decades

    /// One row for every decade, not one row each: "90s" and "80s" are the same
    /// kind of thing and deserve one shelf between them.
    private static func decadeSection(seeds: [TrackStat],
                                      tags: [String: TagTaxonomy.Digest],
                                      day: UInt64,
                                      reroll: Int,
                                      name: (Int) -> String) -> Section? {
        var byDecade: [Int: [TrackStat]] = [:]
        for seed in seeds {
            for decade in tags[seed.artist]?.decades ?? [] {
                byDecade[decade, default: []].append(seed)
            }
        }

        let ranked = byDecade
            .filter { $0.value.count >= minStationsPerSection }
            .map { (decade: $0.key, artists: $0.value, weight: $0.value.reduce(0) { $0 + $1.plays }) }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.decade > $1.decade }
        guard !ranked.isEmpty else { return nil }

        // Round-robin rather than filling from the heaviest decade downwards:
        // a row labelled "by decade" that shows only the 90s is a broken promise.
        var pools = ranked.map { entry in
            (decade: entry.decade,
             artists: rotate(entry.artists,
                             seed: seedValue(day: day, reroll: reroll, salt: "decade\(entry.decade)")))
        }
        var stations: [RadioStation] = []
        var usedArtists = Set<String>()
        var cursor = 0
        while stations.count < stationsPerSection, pools.contains(where: { !$0.artists.isEmpty }) {
            let index = cursor % pools.count
            cursor += 1
            guard !pools[index].artists.isEmpty else { continue }
            let track = pools[index].artists.removeFirst()
            // An artist tagged both 80s and 90s would otherwise show up twice in
            // the same row — as would a solo credit next to a featured one.
            guard usedArtists.insert(identity(of: track.artist)).inserted else { continue }
            stations.append(station(for: track,
                                    caption: name(pools[index].decade),
                                    idPrefix: "decade:\(pools[index].decade)"))
        }
        guard !stations.isEmpty else { return nil }

        return Section(id: "decades",
                       title: L10n.t("vm.radio.decades.title"),
                       subtitle: L10n.t("vm.radio.decades.subtitle"),
                       stations: stations)
    }

    /// Grammar makes this a lookup rather than a format string: Turkish needs
    /// "90'lar" but "2000'ler", which no single template produces. Falls back to
    /// a bare "1930s" for decades we haven't named.
    static func defaultDecadeName(_ decade: Int) -> String {
        let key = "vm.radio.decade.\(decade)"
        let translated = L10n.t(key)
        return translated == key ? "\(decade)s" : translated
    }

    // MARK: - Shared

    private static func station(for track: TrackStat, caption: String, idPrefix: String) -> RadioStation {
        // Titled by artist, captioned by what put it in this row — the decade
        // row mixes decades, so the card has to say which one it is.
        RadioStation(id: "\(idPrefix):\(track.artist)",
                     title: track.artist,
                     subtitle: caption,
                     seedVideoId: track.videoId,
                     artworkURL: track.artworkURL,
                     kind: .artist)
    }

    /// One artist per row, seeded by their most played track — keeping the
    /// most played entry when an artist appears more than once.
    ///
    /// Deduped on the lead artist, not the raw name: YT credits features in the
    /// byline, so "Dedublüman" and "Dedublüman ve Aleyna Tilki" arrive as two
    /// artists and would otherwise sit next to each other as two cards.
    private static func rotate(_ tracks: [TrackStat], seed: UInt64) -> [TrackStat] {
        var seen = Set<String>()
        let unique = tracks
            .sorted { $0.plays > $1.plays }
            .filter { seen.insert(identity(of: $0.artist)).inserted }
        return RadioCatalog.rotate(unique, count: stationsPerSection, seed: seed)
    }

    /// What makes two history rows "the same artist" for display purposes.
    /// Case-folded because YT's own metadata is inconsistent about it — a real
    /// library had both "gripin" and "Gripin", which rendered as two cards.
    static func identity(of artist: String) -> String {
        (ArtistName.lead(artist) ?? artist).lowercased()
    }

    /// `String.hashValue` is seeded per process in Swift, so using it here would
    /// reshuffle every row on each relaunch. FNV-1a is stable forever.
    private static func seedValue(day: UInt64, reroll: Int, salt: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in salt.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash ^ (day &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(bitPattern: Int64(reroll)) &* 0xD1B5_4A32_D192_ED03)
    }
}
