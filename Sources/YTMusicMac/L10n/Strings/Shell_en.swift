/// The Native Mode SwiftUI shell: sidebar, home/explore/history/category
/// pages, playlist detail, player bar and the queue / lyrics / theme panels.
let shellEN: [String: String] = [
    // Update bar
    "shell.update.available": "New version available: v%@",
    "shell.update.download": "Download",
    "shell.update.skip": "Skip this version",

    // Shared row / context-menu actions
    "shell.action.clear": "Clear",
    "shell.action.refresh": "Refresh",
    "shell.action.copyLink": "Copy link",
    "shell.action.openInBrowser": "Open in browser",
    "shell.action.goToArtist": "Go to artist",
    "shell.action.goToAlbum": "Go to album",
    "shell.action.startRadio": "Start radio",
    "shell.action.similarPlaylist": "Create playlist from similar",
    "shell.action.saveToLiked": "Save to liked songs",
    "shell.action.dislike": "Dislike",
    "shell.action.shuffle": "Shuffle",
    "shell.action.repeat": "Repeat",
    "shell.action.selectAll": "Select all",
    "shell.action.remove": "Remove",
    "shell.action.playClip": "Play video clip",

    // Counts
    "shell.songCount.one": "%d song",
    "shell.songCount.other": "%d songs",
    "shell.trackCount.one": "%d track",
    "shell.trackCount.other": "%d tracks",
    "shell.playlistCount.one": "%d playlist",
    "shell.playlistCount.other": "%d playlists",
    "shell.resultCount.one": "%d result",
    "shell.resultCount.other": "%d results",
    "shell.selectedCount": "%d selected",

    // Durations
    "shell.duration.hoursMinutes": "%dh %dmin",
    "shell.duration.minutes": "%dmin",

    // Loading
    "shell.loading": "Loading…",
    "shell.tracks.loading": "Loading songs…",
    "shell.playlists.loading": "Loading playlists…",

    // Search
    "shell.search.placeholder": "Search songs, artists, albums, playlists…",
    "shell.search.emptyHint": "Type to search %@",
    "shell.search.suggestions": "SUGGESTIONS",
    "shell.search.recent": "RECENT SEARCHES",
    "shell.search.noResultsFor": "No results for “%@”",

    // Sidebar
    "shell.sidebar.home": "Home",
    "shell.sidebar.explore": "Explore",
    "shell.sidebar.radio": "Radio",
    "shell.sidebar.search": "Search",
    "shell.sidebar.history": "History",
    "shell.sidebar.statistics": "Statistics",
    "shell.sidebar.section.browse": "Browse",
    "shell.sidebar.yourPlaylists": "Your playlists",
    "shell.sidebar.artists": "Artists",
    "shell.sidebar.albums": "Albums",
    "shell.sidebar.expand": "Expand sidebar",
    "shell.sidebar.collapse": "Collapse sidebar",
    "shell.sidebar.nowPlayingFrom": "%@ — now playing",
    "shell.sidebar.playingFromThis": "Now playing from this list",

    // Library
    "shell.library.save": "Save to library",
    "shell.library.saveAlbum": "Save album to library",
    "shell.library.remove": "Remove from library",
    "shell.library.saved": "Saved",
    "shell.library.savedBadge": "Saved in your library",

    // Playlists
    "shell.playlist.new": "New playlist",
    "shell.playlist.createNew": "New playlist…",
    "shell.playlist.namePlaceholder": "Playlist name",
    "shell.playlist.descPlaceholder": "Description (optional)",
    "shell.playlist.coverNote": "Note: cover art isn't supported by YT's create API — the playlist picks up an automatic cover from its tracks.",
    "shell.playlist.pickCover": "Choose cover",
    "shell.playlist.deleteTitle": "Delete playlist?",
    "shell.playlist.deleteBody": "“%@” will be permanently deleted. This can't be undone.",
    "shell.playlist.resetOrder": "Reset order",
    "shell.playlist.addTo": "Add to playlist",
    "shell.playlist.removeFrom": "Remove from playlist",
    "shell.playlist.searchPlaceholder": "Search in playlist",

    // Similar-playlist builder
    "shell.similar.title": "Playlist from similar",
    "shell.similar.note": "Builds a permanent playlist from the songs Last.fm finds similar to this track.",
    "shell.similar.matched": "%d / %d matched",
    "shell.similar.stage.fetching": "Finding similar tracks…",
    "shell.similar.stage.matching": "Matching on YouTube…",
    "shell.similar.stage.creating": "Creating your playlist…",
    "shell.similar.done": "Playlist created",
    "shell.similar.doneDetail.one": "%d track • under “Your playlists” in the sidebar",
    "shell.similar.doneDetail.other": "%d tracks • under “Your playlists” in the sidebar",

    // Empty main section
    "shell.empty.title": "Pick a playlist or open Home",
    "shell.empty.subtitle": "For recommendations, Sidebar → Home.",

    // Floating nav
    "shell.nav.back": "Back (⌘ ←)",
    "shell.nav.forward": "Forward (⌘ →)",

    // Artist page
    "shell.artist.kindLabel": "ARTIST",
    "shell.artist.albums": "Albums",
    "shell.artist.singles": "Singles",
    "shell.artist.topSongs": "Popular songs",
    "shell.artist.allSongs": "All songs",

    // History page
    "shell.history.kindLabel": "LIBRARY",
    "shell.history.title": "History",
    "shell.history.subtitle": "What you've played lately, in YT Music's day groups",
    "shell.history.reload": "Refresh history",

    // Category page
    "shell.category.kindLabel": "CATEGORY",

    // Home page
    "shell.home.title": "Made for you",
    "shell.home.subtitle": "Playlists, artists and genres YT Music mixed for you",
    "shell.greeting.morning": "GOOD MORNING",
    "shell.greeting.afternoon": "GOOD AFTERNOON",
    "shell.greeting.evening": "GOOD EVENING",
    "shell.greeting.night": "GOOD NIGHT",
    "shell.home.dailyDiscovery.title": "Daily discovery",
    "shell.home.dailyDiscovery.subtitle": "Radios seeded from your library — a new set every day",

    // Radio page
    "shell.radio.kindLabel": "RADIO",
    "shell.radio.title": "Radio",
    "shell.radio.subtitle": "Endless stations built from what you actually listen to",
    "shell.radio.badge": "Radio",
    "shell.radio.playSeed": "Play just this song",
    "shell.radio.needsHistory.title": "Your stations are still warming up",
    "shell.radio.needsHistory.caption": "Personal radios are built from your listening history. Keep playing and they'll show up here — the genres and moods below work right now.",
    "shell.radio.historyOff.title": "Listening history is off",
    "shell.radio.historyOff.caption": "Personal radios are built from your listening history. To get them, turn recording on under Settings → Listening history. The genres and moods below work either way.",

    // Explore page
    "shell.explore.kindLabel": "EXPLORE",
    "shell.explore.title": "Explore",
    "shell.explore.subtitle": "New releases, charts and genres",
    "shell.explore.newReleases": "New releases",
    "shell.explore.charts": "Charts",
    "shell.explore.genresMoods": "Genres & moods",

    // Playlist / album detail
    "shell.detail.album": "ALBUM",
    "shell.detail.playlist": "PLAYLIST",
    "shell.column.title": "Title",
    "shell.column.album": "Album",

    // Queue panel
    "shell.queue.title": "Queue",
    "shell.queue.empty": "Queue is empty",
    "shell.queue.emptyHint": "Right-click a song → Add to queue.",
    "shell.queue.add": "Add to queue",
    "shell.queue.addAll": "Add all to queue",
    "shell.queue.playNext": "Play next",
    "shell.queue.playNow": "Play now",
    "shell.queue.jumpTo": "Jump to this track",
    "shell.queue.upNext": "UP NEXT",
    "shell.queue.manual": "Manual",
    "shell.queue.toggleHelp": "Toggle queue (⌘E)",

    // Player bar
    "shell.player.notPlaying": "Not playing",
    "shell.player.nowPlayingHelp": "Now playing (⌘F)",

    // Lyrics panel
    "shell.lyrics.title": "Lyrics",
    "shell.lyrics.loading": "Loading lyrics…",
    "shell.lyrics.noTrack": "Nothing playing",
    "shell.lyrics.toggleHelp": "Show lyrics",

    // Theme panel
    "shell.theme.title": "Theme",
    "shell.theme.light": "Light",
    "shell.theme.dark": "Dark",

    // Volume
    "shell.volume.mute": "Mute",

    // Sleep timer
    "shell.sleep.title": "Sleep timer",
    "shell.sleep.header": "SLEEP TIMER",
    "shell.sleep.minutes.one": "%d minute",
    "shell.sleep.minutes.other": "%d minutes",
    "shell.sleep.hours.one": "%d hour",
    "shell.sleep.hours.other": "%d hours",
    "shell.sleep.endOfTrack": "End of track",
    "shell.sleep.eot": "EoT",
]
