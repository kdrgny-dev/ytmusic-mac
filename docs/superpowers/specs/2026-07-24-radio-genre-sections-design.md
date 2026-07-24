# Radio page: genre sections, decade row, and a refresh that does something

Date: 2026-07-24
Status: approved

## Problem

The radio page has three personal sections (Discovery, Artists, For you) and YT's
own mixes. All of them are flat lists of "a track to seed a radio from". There is
no way to say "play me something rocky" — the only grouping on the page is YT's
mood/genre chips, and those open YT category *pages*, not radios.

Separately, the page's refresh button is effectively a no-op:

| Part | What refresh actually does |
|---|---|
| Discovery | Nothing. `dailyDiscovery` is deterministic per calendar day |
| Artists / For you | Re-reads SQLite; changes only if you listened since |
| YT mixes | Reuses the cached Home shelves |
| Genre chips | `guard genreSections.isEmpty` — never refetched |

Pressing it in the same session changes nothing visible.

## Why this needs an outside data source

YT Music exposes no genre for a track or artist, and the app's SQLite history
stores only what the player bar shows (title, artist, album, artwork). So genre
has to come from somewhere else.

Last.fm is already a dependency: `LastfmClient` powers the "build a playlist from
similar tracks" feature and the API key already ships in the binary via the
gitignored `LastfmSecret.swift`. `artist.getTopTags` is one more call on that same
client — no new auth, no new key, no new service.

## Decisions

1. **Personal, not a catalog.** Sections group radios seeded from artists the user
   actually listens to. A "Rock" section is *their* rock, not a global station.
2. **Top 5 genres get their own row.** A genre needs at least 3 stations to appear;
   a one-card row reads as a bug.
3. **Decades collapse into one row.** "90s", "80s" are decade tags, not genres.
   They share a single "By decade" section, ordered by play count.
4. **Mood tags are dropped entirely.** Last.fm's folksonomy is mostly noise
   ("seen live", "favourites", "female vocalists", "awesome"). A whitelist keeps
   only real genres; everything unrecognised is discarded.
5. **Refresh rerolls.** It re-picks discovery seeds and the cards inside genre
   rows, so pressing it mid-day surfaces different music. It does not refetch
   tags — those don't change month to month.
6. **Existing sections keep their order.** New rows are appended after
   For you and before YT mixes. Nothing above moves.

## Architecture

Four units. Everything except the store and the client method is pure and
testable without network or database.

### `LastfmClient.topTags(artist:)`

One new method on the existing client. Calls `artist.getTopTags`, returns
`[(name: String, count: Int)]` where `count` is Last.fm's 0–100 relative weight.
Reuses the private `get(_:)` transport and the `isConfigured` gate: with no API
key it returns empty and the new sections simply never appear, matching how the
similar-tracks feature already degrades.

### `TagTaxonomy` (pure)

Classifies one raw Last.fm tag:

| Input | Output |
|---|---|
| `rock`, `jazz`, `heavy metal` | `.genre("Rock")` — canonical name from the whitelist |
| `hip hop`, `hiphop`, `rap` | `.genre("Hip-Hop")` — aliases collapse to one name |
| `90s`, `1990s`, `80s` | `.decade(1990)` |
| `seen live`, `favourites`, `turkish` | `.noise` — discarded |

The whitelist is a compiled-in table of ~40 genres plus an alias map. Decades are
matched by pattern (`^(19|20)?\d0s$`) and normalised to a four-digit year, so
`90s` and `1990s` are the same bucket.

Thresholds, both applied here:
- a tag counts only at Last.fm weight >= 20 — below that it's one person's opinion
- at most 3 genres per artist — otherwise every artist lands in every row

Being pure and deterministic, this is where the interesting tests live: no
network, no clock, no database.

### `ArtistTagStore` — migration v3 on `history.sqlite`

```sql
CREATE TABLE artist_tags (
  artist     TEXT PRIMARY KEY,
  genres     TEXT,      -- JSON array of canonical names
  decades    TEXT,      -- JSON array of ints
  fetched_at INTEGER
);
```

Keyed by `ArtistName.primary(...)`-normalised artist, the same normalisation the
`plays` table already uses, so the join is exact.

Empty results are cached too. If Last.fm doesn't know an artist, we must not ask
again on every page open.

`fetched_at` is recorded but not enforced — there is no TTL. Genre tags are stable
and a re-fetch buys nothing.

Reads and writes go through `PlayHistoryStore`'s existing serial queue.
`SQLiteDatabase` is not thread-safe and this shares its connection.

### `RadioSectionsBuilder` (pure)

Turns `(topTrackPerArtist, tags, rerollCount, date)` into `[RadioSection]`.

- Group artists by genre; a genre's weight is the sum of its artists' play counts
- Take the top 5 genres with >= 3 artists
- Each row holds up to 12 stations, one per artist, seeded by that artist's most
  played track — same `RadioStation` shape the page already renders
- Decades follow the same rule in a single row, ordered by weight
- Card selection is deterministic in `(date, rerollCount)`: stable across redraws
  and relaunches, different after a refresh

**This unit also fixes a real problem.** `NativeShellViewModel` is 3857 lines and
`loadRadio()` builds sections inline. Adding genre logic there makes it worse, so
all section construction moves into this new file and `loadRadio()` becomes a thin
orchestrator. The `@Published` properties and every view binding stay exactly
where they are — the view layer does not change shape, which keeps the regression
surface at zero.

## Data flow

```
radio page opens
  → PlayHistoryStore.topTrackPerArtist(limit: 60)      [off main thread]
  → ArtistTagStore.tags(for: those artists)            [cache read]
  → render sections from whatever is cached             ← page is usable here
  → for cache misses: LastfmClient.topTags, 5 at a time [background]
      → TagTaxonomy classifies → ArtistTagStore writes
      → rebuild sections as results land
```

First open on a fresh install issues up to 60 small requests and the genre rows
fill in progressively. Every later open is zero network.

`refresh` bumps `rerollCount` and rebuilds from cache. No network, instant.

## Failure handling

Every failure degrades to "the new rows aren't there", never to a broken page:

- **No API key** — `isConfigured` is false, no fetch, no genre rows. Existing
  page unchanged.
- **Offline / Last.fm down** — cached tags still render; misses stay missing and
  are retried on the next open. Nothing is written on failure, so a network blip
  doesn't poison the cache with empties.
- **History disabled** — already gated by `Preferences.shared.historyEnabled`,
  same as the other personal sections.
- **Thin library** — genres below 3 artists don't become rows. A brand-new user
  sees today's page, not empty scaffolding.

## Testing

`TagTaxonomy` and `RadioSectionsBuilder` are pure, so they carry the real tests:

- canonicalisation: `hip hop` / `hiphop` / `rap` all land on `Hip-Hop`
- decade normalisation: `90s` and `1990s` are one bucket
- noise rejection: `seen live`, `favourites`, `female vocalists` never become genres
- weight threshold: a tag at weight 10 is ignored, at 30 counts
- per-artist cap: an artist with 8 genre tags contributes to at most 3
- a genre with 2 artists produces no row; with 3 it does
- one artist cannot appear twice in the same row
- reroll: same `(date, rerollCount)` gives identical output; bumping the count
  changes it; the day rolling over changes it
- decade row ordering follows play weight

`ArtistTagStore` gets round-trip tests against an in-memory database, including
that an empty result is cached rather than re-requested.

`LastfmClient.topTags` is tested by parsing a captured `artist.getTopTags`
response — the existing `LastfmClientTests` already does exactly this for
similar-tracks, so it follows that pattern.

## Out of scope

- Tagging artists as they're played (`PlayTracker` hook). The cache built here is
  the same cache that would need, so it can be added later in a few lines.
- Making YT's mood/genre chips launch radios instead of category pages.
- Playlist folders and the Last.fm scrobbler — separate specs.
