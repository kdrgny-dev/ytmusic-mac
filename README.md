# YTMusic for macOS

A native macOS app that wraps [music.youtube.com](https://music.youtube.com) and bolts on
the OS integrations Google never shipped — media keys, Now Playing, a menu
bar item, a floating mini player, sleep timer, global hotkeys.

> YouTube Music has mobile apps and a web player. There's no official
> desktop app, on any platform. Running it in a browser tab works but
> Chrome/Safari each eat 400–700 MB and the experience isn't great. This
> is a thin native shell around the existing web app that fixes that.

## Features

- **Login + persistent session** — log in once, stays logged in
- **Media keys** — F7/F8/F9 control playback even when the app is in the
  background, via `MPRemoteCommandCenter`
- **Now Playing** — current track, artist, and artwork show up in
  Control Center, on the lock screen, and on AirPods double-tap
- **Menu bar status item** — see what's playing without bringing the
  window forward, with play/pause/next/prev in the dropdown
- **Mini player** — floating, resizable, always-on-top window with
  artwork, title, like/dislike, and transport controls
- **Sleep timer** — pause after 5/15/30/60 min or at the end of the
  current track
- **Global hotkeys** — ⌃⌥⌘K focus search, ⌃⌥⌘M toggle mini player
  (no Accessibility permission needed; uses Carbon `RegisterEventHotKey`)
- **Track-change notifications** — opt-in macOS notifications when the
  song changes
- **Spotify-like player bar** — optional CSS reflow moves transport
  controls to the center, song info to the left
- **Hides Premium upsell banners** — optional CSS cleanup
- **Settings panel** — toggle the above; preferences persist
- **Single-instance window lifecycle** — ⌘W hides, ⌘Q quits, dock click
  brings the window back

## Install

Pre-built `.app` is not currently distributed. Build it yourself — it
takes about a minute.

### Requirements

- macOS 13 (Ventura) or newer
- Xcode Command Line Tools (`xcode-select --install`) — no full Xcode needed
- Swift 5.9+ (ships with recent CLT)

### Build

```bash
git clone https://github.com/kdrgny-dev/ytmusic-mac.git
cd ytmusic-mac
./build.sh
```

This produces `build/YTMusic.app`. Move it to your Applications folder:

```bash
cp -r build/YTMusic.app /Applications/
open /Applications/YTMusic.app
```

The first time it runs, log in with **password** — passkeys don't work
in `WKWebView` without a special browser entitlement. After the first
login the session is persistent.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘Space` | Play / pause |
| `⌘→` / `⌘←` | Next / previous track |
| `⌘K` | Focus search (when window is frontmost) |
| `⌘R` | Reload page |
| `⌘⇧M` | Show mini player |
| `⌘0` | Show main window |
| `⌘W` | Hide window (app keeps running) |
| `⌘Q` | Quit |
| `⌘,` | Settings |
| `⌘⇧⌫` | Sign out and clear all data |
| `⌃⌥⌘K` | Global: focus search, bring window forward |
| `⌃⌥⌘M` | Global: toggle mini player |
| F7 / F8 / F9 | Media keys (play/pause, next, prev) |

## How it works

The app is a single `WKWebView` loading `music.youtube.com`, wrapped in
Swift/SwiftUI. The native side and the web page communicate via:

- A small **JS bridge** ([PlayerBridge.swift](Sources/YTMusicMac/PlayerBridge.swift))
  that polls the YT Music player every 1.5 s for current track state,
  and exposes `window.__ytmCmd(cmd, arg)` so the native side can
  trigger play/pause/seek/like/etc.
- **CSS injections** wrapped in toggleable `<style>` tags so prefs can
  flip features live without reloading the page
- **Media key + Now Playing** integration via `MPRemoteCommandCenter`
  and `MPNowPlayingInfoCenter` ([MediaController.swift](Sources/YTMusicMac/MediaController.swift))
- A **shared singleton WebView** ([ContentView.swift](Sources/YTMusicMac/ContentView.swift))
  so closing/reopening the main window doesn't kill the player

The main window and mini player are plain `NSWindow`s, not SwiftUI
`WindowGroup`s — that gives us proper close-as-hide semantics and a
single-instance lifecycle that SwiftUI's scene model fights against.

## Caveats

- **Private WebKit SPI**: we disable Intelligent Tracking Prevention
  (`_setResourceLoadStatisticsEnabled:`) so the
  `accounts.google.com → youtube.com` cookie chain survives login. This
  is private API; could break on future macOS versions. See
  [WebViewTweaks.swift](Sources/YTMusicMac/WebViewTweaks.swift).
- **Passkey login is not supported** — WKWebView needs a special
  browser entitlement for WebAuthn. Use password sign-in.
- **DOM-coupled**: the JS bridge reads `ytmusic-player-bar` internals.
  If YT Music ships a major UI rewrite, selectors in
  [PlayerBridge.swift](Sources/YTMusicMac/PlayerBridge.swift) and the
  cleanup CSS will need updating.
- **Not code-signed**: ad-hoc signed only. macOS may warn the first time
  you open it — right-click → Open to bypass.
- **Unofficial**: not affiliated with Google or YouTube. Uses the
  public web player; doesn't reverse-engineer any private APIs.

## Project layout

```
Sources/YTMusicMac/
  App.swift                    SwiftUI App entry, main menu, AppDelegate
  ContentView.swift            WebView wrapper + WebViewHolder singleton
  MainWindowController.swift   NSWindow for the main browser
  MiniPlayer.swift             Floating mini player window + SwiftUI view
  SettingsView.swift           SwiftUI settings panel
  SettingsWindowController.swift
  StatusBarController.swift    Menu bar item + dropdown menu
  MediaController.swift        Now Playing + remote command center
  PlayerBridge.swift           Injected JS: state polling + commands + CSS
  Preferences.swift            UserDefaults-backed prefs (ObservableObject)
  SleepTimer.swift             Sleep timer logic
  GlobalHotkeys.swift          Carbon RegisterEventHotKey wrapper
  WebViewTweaks.swift          Private SPI to disable ITP / storage blocking
scripts/
  make_icon.swift              Programmatic AppIcon renderer
  build_icon.sh                Slices PNG into .iconset and builds .icns
build.sh                       swift build + bundle into .app
Info.plist                     Bundle metadata
```

## License

MIT — see [LICENSE](LICENSE). Personal project, no warranty, no support
promises. PRs welcome but not actively solicited.
