/// AppKit menus (main menu, Dock menu, status bar), transport verbs and the
/// small shared vocabulary every domain reuses.
let menuEN: [String: String] = [
    // Shared vocabulary — reused across domains. Reference these rather than
    // redefining "Cancel" in each catalog.
    "common.ok": "OK",
    "common.cancel": "Cancel",
    "common.close": "Close",
    "common.save": "Save",
    "common.delete": "Delete",
    "common.rename": "Rename",
    "common.open": "Open",
    "common.retry": "Try again",
    "common.create": "Create",
    "common.done": "Done",

    // Transport verbs — shared by the Dock menu, status bar and shell.
    "transport.play": "Play",
    "transport.pause": "Pause",
    "transport.next": "Next",
    "transport.prev": "Previous",
    "transport.like": "Like",
    "transport.unlike": "Remove like",

    // App menu
    "menu.app.about": "About YouTube Music",
    "menu.app.checkUpdates": "Check for Updates…",
    "menu.app.settings": "Settings…",
    "menu.app.hide": "Hide YouTube Music",
    "menu.app.hideOthers": "Hide Others",
    "menu.app.showAll": "Show All",
    "menu.app.quit": "Quit YouTube Music",

    // Edit menu
    "menu.edit.title": "Edit",
    "menu.edit.undo": "Undo",
    "menu.edit.redo": "Redo",
    "menu.edit.cut": "Cut",
    "menu.edit.copy": "Copy",
    "menu.edit.paste": "Paste",
    "menu.edit.selectAll": "Select All",

    // Controls menu
    "menu.controls.title": "Controls",
    "menu.controls.playPause": "Play / Pause",
    "menu.controls.next": "Next Track",
    "menu.controls.prev": "Previous Track",
    "menu.controls.seekForward": "Skip Forward 10s",
    "menu.controls.seekBackward": "Skip Back 10s",
    "menu.controls.like": "Like / Remove Like",
    "menu.controls.shuffle": "Shuffle",
    "menu.controls.repeat": "Repeat",
    "menu.controls.nowPlaying": "Now Playing (Full Screen)",
    "menu.controls.focusSearch": "Focus Search",
    "menu.controls.toggleQueue": "Toggle Queue Panel",
    "menu.controls.toggleLyrics": "Toggle Lyrics",
    "menu.controls.back": "Back",
    "menu.controls.forward": "Forward",
    "menu.controls.reload": "Reload",
    "menu.controls.clearData": "Sign Out and Clear Data",

    // Window menu
    "menu.window.title": "Window",
    "menu.window.minimize": "Minimize",
    "menu.window.close": "Close",
    "menu.window.main": "Main Window",
    "menu.window.mini": "Mini Player",

    // Status bar
    "status.notPlaying": "Not playing",
    "status.showMainWindow": "Show Main Window",
    "status.showMiniPlayer": "Show Mini Player",
    "status.notifyOnTrackChange": "Notify on Track Change",
    "status.memory": "Memory: %@",

    // Sleep timer
    "sleep.title": "Sleep Timer",
    "sleep.minutes.one": "%d minute",
    "sleep.minutes.other": "%d minutes",
    "sleep.hours.one": "%d hour",
    "sleep.hours.other": "%d hours",
    "sleep.endOfTrack": "End of track",
    "sleep.countdown": "Sleep Timer — %@",
    "sleep.activeEndOfTrack": "Sleep Timer — end of track",

    // Updates
    "update.available": "New version available: v%@",
    "update.download": "Download",
    "update.later": "Later",
    "update.upToDate": "You're on the latest version.",
    "update.installedVersion": "Installed version: v%@",
    "update.ok": "OK",
]
