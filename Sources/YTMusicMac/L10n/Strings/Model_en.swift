/// NativeShellViewModel — toasts, inline load errors, banners and the
/// enum labels the shell renders (search tabs, playlist privacy).
let modelEN: [String: String] = [
    // Counted nouns — composed into the toasts below so a count reads
    // naturally in both languages without duplicating each sentence.
    "vm.count.songs.one": "%d song",
    "vm.count.songs.other": "%d songs",

    // Search tabs
    "vm.search.tab.playlists": "Playlists",
    "vm.search.tab.songs": "Songs",
    "vm.search.tab.artists": "Artists",
    "vm.search.tab.albums": "Albums",

    // Playlist privacy
    "vm.privacy.public": "Public",
    "vm.privacy.unlisted": "Unlisted (anyone with the link)",
    "vm.privacy.private": "Private",

    // Failure banner
    "vm.banner.offline": "No internet connection.",
    "vm.banner.signedOut": "Your YT Music session expired. Your library and likes can't load.",
    "vm.banner.signIn": "Sign in",

    // Inline load errors
    "vm.error.entityFailed": "Couldn't load %@.",
    "vm.error.artistFailed": "Couldn't load the artist.",
    "vm.error.libraryNeedsSignIn": "Sign in to YT Music to see your library.",
    "vm.error.noPlaylists": "You don't have any playlists yet.",
    "vm.error.libraryFailed": "Couldn't load your library.",
    "vm.error.categoryEmpty": "No playlists in this category.",
    "vm.error.categoryFailed": "Couldn't load this category.",
    "vm.error.playlistEmpty": "This playlist is empty.",
    "vm.error.tracksFailed": "Couldn't load the songs.",
    "vm.error.homeFailed": "Couldn't load Home.",
    "vm.error.historyNeedsSignIn": "Sign in to YT Music to see your history.",
    "vm.error.historyEmpty": "Your history is empty.",
    "vm.error.historyFailed": "Couldn't load your history.",
    "vm.error.exploreFailed": "Couldn't load Explore.",
    "vm.error.searchEmpty": "No results.",
    "vm.error.searchFailed": "Search failed",
    "vm.error.noTrackPlaying": "Nothing is playing",

    // Lyrics
    "vm.lyrics.unavailable": "No lyrics for this song",
    "vm.lyrics.notFound": "No lyrics found",
    "vm.lyrics.failed": "Couldn't load the lyrics",

    // Similar-track playlist (Last.fm)
    "vm.similar.defaultTitle": "%@ — Similar",
    "vm.similar.description": "%@ • %@ — similar tracks from Last.fm",

    // Toasts — playlists
    "vm.toast.orderReset": "Order reset",
    "vm.toast.playlistNameRequired": "A playlist name is required",
    "vm.toast.playlistCreated": "“%@” created",
    "vm.toast.playlistCreatedWithTracks": "“%@” created — %@ added",
    "vm.toast.playlistCreateFailed": "Couldn't create the playlist",
    "vm.toast.playlistCreateFailedHTTP": "Couldn't create the playlist (HTTP %d)",
    "vm.toast.playlistNotEditable": "%@ can't be edited",
    "vm.toast.playlistSaved": "“%@” saved to your library",
    "vm.toast.playlistRemoved": "“%@” removed from your library",
    "vm.toast.renamed": "Renamed: %@",
    "vm.toast.renameFailed": "Couldn't rename it",
    "vm.toast.renameFailedHTTP": "Couldn't rename it (HTTP %d)",
    "vm.toast.deleted": "Deleted: %@",
    "vm.toast.deleteFailed": "Couldn't delete it",
    "vm.toast.deleteFailedHTTP": "Couldn't delete it (HTTP %d)",
    "vm.toast.reorderSaveFailed": "Couldn't save the new order",
    "vm.toast.emptyList": "Empty playlist",

    // Toasts — albums
    "vm.toast.albumNotSavable": "This album can't be saved",
    "vm.toast.albumSaved": "Album added to your library",
    "vm.toast.albumRemoved": "Album removed from your library",

    // Toasts — artists
    "vm.toast.artistNotFound": "Artist not found",
    "vm.toast.artistOpenFailed": "Couldn't open the artist",

    // Toasts — tracks in playlists
    "vm.toast.tracksNotRemovable": "These tracks can't be removed from the playlist",
    "vm.toast.removedFromPlaylist": "Removed from the playlist",
    "vm.toast.tracksRemovedFromPlaylist": "%@ removed from the playlist",
    "vm.toast.removeFailed": "Couldn't remove it",
    "vm.toast.removeFailedHTTP": "Couldn't remove it (HTTP %d)",
    "vm.toast.tracksAddedToPlaylist": "%@ added to “%@”",
    "vm.toast.trackAddedToPlaylist": "“%@” → %@",
    "vm.toast.trackLikedMusic": "“%@” added to Liked Music",
    "vm.toast.addFailed": "Couldn't add it",
    "vm.toast.addFailedHTTP": "Couldn't add it (HTTP %d)",
    "vm.toast.saveFailed": "Couldn't save it",
    "vm.toast.saveFailedHTTP": "Couldn't save it (HTTP %d)",

    // Toasts — queue
    "vm.toast.playNext": "Up next: %@",
    "vm.toast.addedToQueue": "Added to queue: %@",
    "vm.toast.tracksQueued": "%@ added to the queue",
    "vm.toast.queueAddFailed": "Couldn't add to the queue",
    "vm.toast.queueCleared": "Queue cleared",

    // Toasts — likes
    "vm.toast.liked": "Liked: %@",
    "vm.toast.likeFailed": "Couldn't like it",
    "vm.toast.likeFailedHTTP": "Couldn't like it (HTTP %d)",
    "vm.toast.disliked": "Disliked: %@",
    "vm.toast.signInToLike": "Sign in to YT Music to like tracks",
    "vm.toast.dislikeMarked": "Marked as disliked",
    "vm.toast.dislikeCleared": "Mark removed",
    "vm.toast.likeAdded": "Added to your likes",
    "vm.toast.likeRemoved": "Like removed",
    "vm.toast.likeAPIRejected": "Like API refused it (HTTP %d) — retried on the page",
    "vm.toast.likeSendFailed": "Couldn't send the like — retried on the page",
    "vm.toast.tracksLiked": "%@ added to your likes",

    // Toasts — similar playlist
    "vm.toast.signInForPlaylist": "Sign in to YT Music to build a playlist",
    "vm.toast.lastfmKeyMissing": "No Last.fm key configured",
    "vm.toast.similarNotPossible": "Can't build a playlist from this track",
    "vm.toast.noSimilarTracks": "No similar tracks found",
    "vm.toast.noMatchedTracks": "No matching tracks found",

    // Toasts — misc
    "vm.toast.radioStarting": "Starting radio",
    "vm.toast.linkCopied": "Link copied",
    "vm.toast.actionFailed": "Action failed",
    "vm.toast.actionFailedHTTP": "Action failed (HTTP %d)",
    "vm.error.radioFailed": "Radio couldn't be loaded.",
    "vm.radio.discovery.title": "Daily discovery",
    "vm.radio.discovery.subtitle": "Six radios seeded from your library — a new set every day",
    "vm.radio.artists.title": "Artist radio",
    "vm.radio.artists.subtitle": "Built around the artists you play most",
    "vm.radio.artistStation": "%@ radio",
    "vm.radio.forYou.title": "Your favourites on radio",
    "vm.radio.forYou.subtitle": "Start from a song you love and keep going",
    "vm.radio.ytMixes.title": "YouTube mixes",
    "vm.radio.ytMixes.subtitle": "Mixes YouTube put together for you",
    "vm.home.weeklyMix.title": "Your weekly mix",
    "vm.home.weeklyMix.subtitle": "A fresh selection from your library every week",
    "vm.home.yearAgo.title": "A year ago today",
    "vm.home.yearAgo.subtitle": "What you were playing on this day last year",
    "vm.home.sixMonths.title": "Six months ago",
    "vm.home.sixMonths.subtitle": "The month you had on repeat half a year back",
    "vm.home.forgotten.title": "Forgotten favourites",
    "vm.home.forgotten.subtitle": "You played these a lot, then stopped",
    "vm.toast.mixQueued.one": "Playing %d track",
    "vm.toast.mixQueued.other": "Playing %d tracks",
]
