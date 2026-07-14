# Liste/Arama/Söz düzenlemeleri — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native shell'de dört düzenleme — çalan parçayı videoId ile işaretle, aramayı dialogtan ana sekmeye taşı, liste satırlarında hover play + klip ikonu göster, klipsiz klip modunu süreye oranlı Star Wars söz akışına çevir (ve akışı sözlerin gösterildiği her yere uygula).

**Architecture:** Mevcut `MainSection` enum + `goX()` + `MainContent` switch navigasyon deseni ve tek ortak `TrackRow` bileşeni korunur. Eşleştirme/akış/dallanma mantığı saf, test edilebilir fonksiyonlara çıkarılır (`NowPlaying.isCurrentTrack(id:)`, `LyricsCrawl` enum, `NativeShellViewModel.clipEntry`). Görsel akış tek yeni bileşen `LyricsCrawlView`'de toplanır.

**Tech Stack:** Swift 5, SwiftUI, AppKit köprüleri, XCTest (SwiftPM). Test: `swift test`. Build: `./build.sh`.

## Global Constraints

- Türkçe UI metinleri; mevcut kopya tonu korunur.
- Kodda gereksiz/uzun yorum yok; yorum yalnızca "neden" için, kısa.
- Mevcut özellikleri bozma (hard rule) — özellikle Queue/history/artist listelerinin çalışan davranışı.
- Harici bağımlılık eklenmez. Sözler zaman damgasız düz metin; akış süreye oranlıdır (kelime vurgusu yok).
- Test dosyaları `Tests/YTMusicMacTests/` altına, `@testable import YTMusicMac` ile.

---

### Task 1: Çalan parça tespiti — isim yerine videoId

**Files:**
- Modify: `Sources/YTMusicMac/MediaController.swift:31-32` (NowPlaying'e helper ekle)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:2979-2982` (`PlaylistDetailView.isCurrentTrack`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:2131-2134` (`ChartSectionView.isCurrent`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:1560-1563` (`ArtistView.isCurrent`)
- Test: `Tests/YTMusicMacTests/NowPlayingMatchTests.swift`

**Interfaces:**
- Produces: `NowPlaying.isCurrentTrack(id: String) -> Bool` — `hasTrack && !videoId.isEmpty && videoId == id`.

- [ ] **Step 1: Write the failing test**

Create `Tests/YTMusicMacTests/NowPlayingMatchTests.swift`:

```swift
import XCTest
@testable import YTMusicMac

final class NowPlayingMatchTests: XCTestCase {

    func testMatchesByVideoId() {
        var np = NowPlaying()
        np.title = "There She Goes"
        np.videoId = "abc123"
        XCTAssertTrue(np.isCurrentTrack(id: "abc123"))
    }

    func testSameTitleDifferentVideoIdDoesNotMatch() {
        var np = NowPlaying()
        np.title = "There She Goes"   // aynı isim, farklı klip
        np.videoId = "abc123"
        XCTAssertFalse(np.isCurrentTrack(id: "zzz999"))
    }

    func testEmptyVideoIdNeverMatches() {
        var np = NowPlaying()
        np.title = "There She Goes"
        np.videoId = ""
        XCTAssertFalse(np.isCurrentTrack(id: ""),
                       "boş videoId ile eşleşme yanlış çoklu işaretlemeye yol açar")
    }

    func testNoTrackNeverMatches() {
        let np = NowPlaying()   // hasTrack == false
        XCTAssertFalse(np.isCurrentTrack(id: "abc123"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NowPlayingMatchTests`
Expected: FAIL — `value of type 'NowPlaying' has no member 'isCurrentTrack'`.

- [ ] **Step 3: Add the helper to NowPlaying**

`MediaController.swift`, `NowPlaying` struct içinde (`trackKey` satırından hemen sonra, ~satır 32):

```swift
    var hasTrack: Bool { !title.isEmpty }
    var trackKey: String { "\(title)|\(artist)" }

    /// True when this is the track currently playing. Matches by videoId —
    /// title alone falsely flags every same-named cover as "now playing".
    func isCurrentTrack(id: String) -> Bool {
        hasTrack && !videoId.isEmpty && videoId == id
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NowPlayingMatchTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Swap the three view call sites to videoId**

`NativeShellView.swift:2979-2982` →

```swift
    private func isCurrentTrack(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        media.nowPlaying.isCurrentTrack(id: t.id)
    }
```

`NativeShellView.swift:2131-2134` →

```swift
    private func isCurrent(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        media.nowPlaying.isCurrentTrack(id: t.id)
    }
```

`NativeShellView.swift:1560-1563` →

```swift
    private func isCurrent(_ t: NativeShellViewModel.TrackSummary) -> Bool {
        media.nowPlaying.isCurrentTrack(id: t.id)
    }
```

- [ ] **Step 6: Build to confirm the swaps compile**

Run: `swift build 2>&1 | tail -5`
Expected: no errors referencing these lines.

- [ ] **Step 7: Commit**

```bash
git add Sources/YTMusicMac/MediaController.swift Sources/YTMusicMac/NativeShell/NativeShellView.swift Tests/YTMusicMacTests/NowPlayingMatchTests.swift
git commit -m "Fix: match now-playing row by videoId, not title

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: TrackRow — hover play ikonu + klip ikonu

Görsel değişiklik; SwiftUI view render'ı birim testine uygun değil, canlı doğrulanır (Task 7). Klip ikonunun tıklama davranışı Task 4'teki `clipEntry` ile test edilir.

**Files:**
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:3065-3145` (`TrackRow`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:2947-2953` (PlaylistDetailView'da TrackRow init)

**Interfaces:**
- Produces: `TrackRow` iki yeni parametre — `showClipIcon: Bool = false`, `onClip: (() -> Void)? = nil`.
- Consumes: `NativeShellViewModel.enterClip()` (Task 4'te dallanır; bu task'ta mevcut hâliyle çağrılabilir).

- [ ] **Step 1: Add the two params to TrackRow**

`NativeShellView.swift`, `TrackRow` alan listesine (`fallbackThumbnailURL` satırından sonra, ~3074):

```swift
    var fallbackThumbnailURL: String? = nil
    /// Only the now-playing row whose track has a music-video counterpart
    /// shows the clip icon (hasVideo is known only for the current track).
    var showClipIcon: Bool = false
    var onClip: (() -> Void)? = nil
```

- [ ] **Step 2: Make the index column three-state (playing → hover → number)**

`NativeShellView.swift:3094-3104` ZStack'i şununla değiştir:

```swift
            ZStack {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.accentColor)
                } else if isHovered {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.7))
                } else {
                    Text("\(index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.4))
                }
            }
            .frame(width: 28, alignment: .trailing)
```

- [ ] **Step 3: Add the clip icon before the duration**

`NativeShellView.swift`, duration `Text(track.duration ?? "")` bloğundan (~3134) HEMEN ÖNCE:

```swift
            if showClipIcon {
                Button(action: { onClip?() }) {
                    Image(systemName: "film")
                        .font(.system(size: 12))
                        .foregroundColor(Color.accentColor)
                        .frame(width: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Klibi oynat")
            }

            Text(track.duration ?? "")
```

- [ ] **Step 4: Wire clip icon in PlaylistDetailView's TrackRow init**

`NativeShellView.swift:2947-2953` TrackRow init'ine, `fallbackThumbnailURL:` satırından sonra iki argüman ekle:

```swift
                            TrackRow(index: idx + 1,
                                     track: track,
                                     isPlaying: isCurrentTrack(track),
                                     zebra: idx.isMultiple(of: 2),
                                     showAlbum: showAlbumColumn,
                                     selected: selectedIDs.contains(track.id),
                                     fallbackThumbnailURL: playlist.thumbnailURL,
                                     showClipIcon: isCurrentTrack(track) && media.nowPlaying.hasVideo,
                                     onClip: { vm.enterClip() })
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -5`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/YTMusicMac/NativeShell/NativeShellView.swift
git commit -m "TrackRow: hover play icon + clip icon on now-playing row

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Aramayı dialogtan ana sekmeye taşı

**Files:**
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift:163-172` (MainSection enum)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift:252-269` (`apply(section:)`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift:598-610` (`retryCurrentSection()`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift:1495-1504` (`toggleSearch` → `goSearch`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift:1559-1580` (`openSearchResult` temizliği)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:65-70` (body overlay bloğunu kaldır)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:237-268` (`SearchOverlay` → `SearchView`)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:314-325` (⎋ butonunu kaldır)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:1347-1364` (MainContent switch)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:539` (Sidebar topItem)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:780` (isTopActive)
- Modify: `Sources/YTMusicMac/App.swift:306-315` (focusSearch → goSearch)
- Test: `Tests/YTMusicMacTests/NativeShellViewModelTests.swift` (yeni testler ekle)

**Interfaces:**
- Produces: `MainSection.search` case; `NativeShellViewModel.goSearch()`.
- `isSearchVisible` @Published kaldırılır; görünürlük `mainSection == .search`'e devredilir.

- [ ] **Step 1: Write the failing navigation tests**

`Tests/YTMusicMacTests/NativeShellViewModelTests.swift` sonuna (son `}`'dan önce) ekle:

```swift
    // MARK: - Search as a tab

    func testGoSearchSetsMainSection() {
        vm.goSearch()
        XCTAssertEqual(vm.mainSection, .search)
    }

    func testGoSearchPushesHistorySoBackReturns() {
        // start on home (reset default), navigate to search, then back
        vm.goSearch()
        XCTAssertEqual(vm.mainSection, .search)
        vm.goBack()
        XCTAssertEqual(vm.mainSection, .home,
                       "back from search should return to the prior section")
    }

    func testOpenSongResultKeepsQuery() {
        vm.goSearch()
        vm.searchQuery = "there she goes"
        let song = NativeShellViewModel.SearchResult(
            id: "vid1", kind: .song, title: "There She Goes",
            subtitle: "The La's", thumbnailURL: nil)
        vm.openSearchResult(song)
        XCTAssertEqual(vm.searchQuery, "there she goes",
                       "opening a song plays it but must not wipe the search")
        XCTAssertEqual(vm.mainSection, .search,
                       "a song result plays in place; stay on the search tab")
    }
```

> NOT: `SearchResult` memberwise init'tir (`NativeShellViewModel.swift:434`): `SearchResult(id:kind:title:subtitle:thumbnailURL:)`, `subtitle` non-optional String. Yukarıdaki test bu imzayla derlenir.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NativeShellViewModelTests 2>&1 | tail -20`
Expected: FAIL — `goSearch` yok / `.search` case yok.

- [ ] **Step 3: Add `.search` to MainSection**

`NativeShellViewModel.swift:163-172`:

```swift
    enum MainSection: Equatable {
        case empty
        case home
        case explore
        case history
        case statistics
        case search
        case playlist(PlaylistSummary)
        case category(GenreChip)
        case artist(String)   // browseId; full data lives in artistDetail
    }
```

- [ ] **Step 4: Add `goSearch()` and rework search lifecycle**

`NativeShellViewModel.swift`, `toggleSearch()` (1495-1504) tamamını şununla değiştir:

```swift
    /// Search is a normal main-section tab now (not a modal). Navigating in
    /// keeps the last query so returning to the tab restores it.
    func goSearch() {
        pushHistory()
        mainSection = .search
        selectedPlaylist = nil
    }
```

`openSearchResult(_:)` sonundaki (1576-1579) dört satırı — `isSearchVisible = false` / `searchQuery = ""` / `searchResults = []` / `searchCache.removeAll()` — **kaldır**. `recordSearch` ve switch aynı kalır. Playlist/album/artist dalları zaten `openPlaylist`/`openArtist` ile `pushHistory` yapıp `mainSection`'ı değiştiriyor; song dalı yerinde çalar ve arama sekmesi korunur.

- [ ] **Step 5: Remove the isSearchVisible property and update its references**

`NativeShellViewModel.swift:442` civarındaki `@Published var isSearchVisible: Bool = false` satırını **kaldır**.

`apply(section:)` (252-269) switch'ine ekle:

```swift
        case .search: break
```

`retryCurrentSection()` (598-610) switch'ine ekle:

```swift
        case .search:  break
```

Grep ile kalan referansları temizle:

Run: `grep -rn "isSearchVisible\|toggleSearch" Sources`
Expected kalanlar ve düzeltmeleri:
- `NativeShellView.swift:65` body overlay → Step 6'da kaldırılır.
- `NativeShellView.swift:133` `.animation(..., value: vm.isSearchVisible)` → kaldır.
- `NativeShellView.swift:246` ve `:314` (SearchOverlay dismiss) → Step 7'de kaldırılır.
- `NativeShellView.swift:539` Sidebar → Step 8.
- `NativeShellView.swift:780` isTopActive → Step 8.
- `App.swift:311` → Step 9.

- [ ] **Step 6: Remove the search overlay from the body**

`NativeShellView.swift:65-70` bloğunu (`if vm.isSearchVisible { SearchOverlay(...) }`) tamamen **sil**. Ayrıca `:133` satırı `.animation(.easeInOut(duration: 0.18), value: vm.isSearchVisible)`'ı **sil**.

- [ ] **Step 7: Turn SearchOverlay into an inline SearchView**

`NativeShellView.swift:237-268`, `SearchOverlay` struct'ının adını `SearchView` yap ve `body`'sini dialog kabuğundan arındır:

```swift
private struct SearchView: View {
    @ObservedObject var vm: NativeShellViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().background(Color.primary.opacity(0.08))
            tabBar
            Divider().background(Color.primary.opacity(0.08))
            resultsArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }
```

`searchField` içindeki `⎋` kapatma butonunu (`:314-325`, `Button(action: { vm.toggleSearch() }) { Text("⎋") ... }`) **kaldır** (sekmede kapatma yok; geri butonu var).

- [ ] **Step 8: Render SearchView in MainContent + fix sidebar**

`NativeShellView.swift:1347-1364` switch'ine (`.history` dalından sonra) ekle:

```swift
            case .search:
                SearchView(vm: vm)
```

`NativeShellView.swift:539` Sidebar topItem action:

```swift
            .init(id: "search",  icon: "magnifyingglass",       label: "Ara",  action: { vm.goSearch() }),
```

`NativeShellView.swift:780` isTopActive:

```swift
        case "search":  return vm.mainSection == .search
```

- [ ] **Step 9: Route ⌘K to goSearch**

`App.swift:306-315` `focusSearch()`:

```swift
    @objc func focusSearch() {
        if Preferences.shared.nativeUIMode {
            Task { @MainActor in NativeShellViewModel.shared.goSearch() }
        } else {
            WebViewHolder.shared.focusSearch()
        }
    }
```

- [ ] **Step 10: Build, then run the tests**

Run: `swift build 2>&1 | tail -8`
Expected: no errors (özellikle SearchOverlay→SearchView yeniden adlandırmasından kaynaklı kalıntı referans yok).

Run: `swift test --filter NativeShellViewModelTests 2>&1 | tail -20`
Expected: PASS (yeni 3 test dahil).

- [ ] **Step 11: Commit**

```bash
git add Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift Sources/YTMusicMac/NativeShell/NativeShellView.swift Sources/YTMusicMac/App.swift Tests/YTMusicMacTests/NativeShellViewModelTests.swift
git commit -m "Search: promote from modal dialog to a main-section tab

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Klip modu dallanması — video yoksa akış moduna gir

**Files:**
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift:1296-1330` (`enterClip`, yeni `ClipEntry`/`clipEntry`/`isClipCrawlVisible`/`exitClipCrawl`)
- Test: `Tests/YTMusicMacTests/NativeShellViewModelTests.swift`

**Interfaces:**
- Produces: `NativeShellViewModel.ClipEntry` (`.noTrack | .video | .crawl`), static `clipEntry(hasTrack:hasVideo:) -> ClipEntry`, `@Published private(set) var isClipCrawlVisible: Bool`, `exitClipCrawl()`.
- Consumes: `MediaController.shared.nowPlaying.hasVideo`, `loadLyricsForCurrentTrack()`.

- [ ] **Step 1: Write the failing test**

`NativeShellViewModelTests.swift` sonuna ekle:

```swift
    // MARK: - Clip entry branching

    func testClipEntryNoTrack() {
        XCTAssertEqual(
            NativeShellViewModel.clipEntry(hasTrack: false, hasVideo: false),
            .noTrack)
    }

    func testClipEntryVideoWhenAvailable() {
        XCTAssertEqual(
            NativeShellViewModel.clipEntry(hasTrack: true, hasVideo: true),
            .video)
    }

    func testClipEntryCrawlWhenNoVideo() {
        XCTAssertEqual(
            NativeShellViewModel.clipEntry(hasTrack: true, hasVideo: false),
            .crawl,
            "no music video → lyric crawl, not a black screen")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NativeShellViewModelTests 2>&1 | tail -15`
Expected: FAIL — `clipEntry` / `ClipEntry` yok.

- [ ] **Step 3: Add ClipEntry + rework enterClip**

`NativeShellViewModel.swift`, `enterClip()` (1300-1313) ve komşularını şununla değiştir (mevcut `isClipMode` ve `clipUnavailable`/`exitClip` korunur):

```swift
    /// Clip (music-video) mode — the WebView is brought forward to play the
    /// video full-window. Reversible: exitClip restores everything.
    @Published private(set) var isClipMode: Bool = false

    /// Shown instead of a black screen when "Klip" is opened on a track with
    /// no music video: a full-window lyric crawl.
    @Published private(set) var isClipCrawlVisible: Bool = false

    enum ClipEntry: Equatable { case noTrack, video, crawl }

    /// Pure decision so the branch is unit-testable without touching singletons.
    static func clipEntry(hasTrack: Bool, hasVideo: Bool) -> ClipEntry {
        guard hasTrack else { return .noTrack }
        return hasVideo ? .video : .crawl
    }

    func enterClip() {
        guard !isClipMode, !isClipCrawlVisible else { return }
        let np = MediaController.shared.nowPlaying
        switch Self.clipEntry(hasTrack: np.hasTrack, hasVideo: np.hasVideo) {
        case .noTrack:
            showToast("Çalan şarkı yok")
        case .video:
            isClipMode = true
            showToast("Klip açılıyor…")
            FeatureBridge.shared.set("hideYTApp", enabled: false)
            FeatureBridge.shared.set("videoOnly", enabled: true)
            PrefBridge.shared.enterClip()
            MainWindowController.shared.setClipMode(true)
        case .crawl:
            isClipCrawlVisible = true
            loadLyricsForCurrentTrack()
        }
    }

    func exitClipCrawl() { isClipCrawlVisible = false }
```

`clipUnavailable()` ve `exitClip()` (1315-1330) **değişmeden kalır** — video probe'u sonradan başarısız olursa hâlâ temizler.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NativeShellViewModelTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/YTMusicMac/NativeShell/NativeShellViewModel.swift Tests/YTMusicMacTests/NativeShellViewModelTests.swift
git commit -m "Clip: branch to lyric crawl when the track has no music video

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: LyricsCrawl matematiği + LyricsCrawlView + ClipCrawlScreen + body bağlama

**Files:**
- Create: `Sources/YTMusicMac/NativeShell/LyricsCrawlView.swift`
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:96-100` (body'ye ClipCrawlScreen overlay)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:132` civarı (animation)
- Test: `Tests/YTMusicMacTests/LyricsCrawlTests.swift`

**Interfaces:**
- Produces: `enum LyricsCrawl` — `static func progress(time:duration:) -> Double`, `static func offset(progress:content:viewport:) -> CGFloat`; `struct LyricsCrawlView` (`init(text:textColor:)`); `struct ClipCrawlScreen` (`init(vm:)`).
- Consumes: `PlaybackClock.shared.time`, `MediaController.nowPlaying.duration`, `vm.isClipCrawlVisible`, `vm.exitClipCrawl()`, `vm.lyrics/lyricsLoading/lyricsError`.

- [ ] **Step 1: Write the failing math test**

Create `Tests/YTMusicMacTests/LyricsCrawlTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import YTMusicMac

final class LyricsCrawlTests: XCTestCase {

    func testProgressZeroWhenDurationZero() {
        XCTAssertEqual(LyricsCrawl.progress(time: 30, duration: 0), 0)
    }

    func testProgressClampsToUnitInterval() {
        XCTAssertEqual(LyricsCrawl.progress(time: -5, duration: 100), 0)
        XCTAssertEqual(LyricsCrawl.progress(time: 250, duration: 100), 1)
        XCTAssertEqual(LyricsCrawl.progress(time: 50, duration: 100), 0.5, accuracy: 0.0001)
    }

    func testOffsetStartsBelowViewport() {
        // progress 0 → content sits just below the viewport (offset == viewport)
        XCTAssertEqual(
            LyricsCrawl.offset(progress: 0, content: 400, viewport: 200),
            200, accuracy: 0.0001)
    }

    func testOffsetEndsAboveViewport() {
        // progress 1 → content fully exited the top (offset == -content)
        XCTAssertEqual(
            LyricsCrawl.offset(progress: 1, content: 400, viewport: 200),
            -400, accuracy: 0.0001)
    }

    func testOffsetMidpoint() {
        // viewport 200, content 100 → 200 - 0.5*(300) = 50
        XCTAssertEqual(
            LyricsCrawl.offset(progress: 0.5, content: 100, viewport: 200),
            50, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LyricsCrawlTests`
Expected: FAIL — `LyricsCrawl` yok.

- [ ] **Step 3: Create LyricsCrawlView.swift**

```swift
import SwiftUI

/// Pure crawl math, isolated so it's unit-testable without a view.
enum LyricsCrawl {
    /// 0…1 through the song. Guards divide-by-zero.
    static func progress(time: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    /// Vertical offset so lyrics crawl bottom→top over the song.
    /// progress 0 → content sits just below the viewport (offset == viewport);
    /// progress 1 → content has fully exited the top (offset == -content).
    static func offset(progress: Double, content: CGFloat, viewport: CGFloat) -> CGFloat {
        viewport - CGFloat(progress) * (content + viewport)
    }
}

private struct CrawlHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Star-Wars-style lyric crawl. Plain text (no timestamps) scrolled bottom→top
/// paced by playback position, so it stays roughly in sync and honors seek/pause.
/// Timestamps are unavailable from YTM, so there is no per-line highlight.
struct LyricsCrawlView: View {
    let text: String
    var textColor: Color = .primary

    @ObservedObject private var clock = PlaybackClock.shared
    @EnvironmentObject private var media: MediaController
    @State private var contentHeight: CGFloat = 0

    private var lines: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        GeometryReader { geo in
            let p = LyricsCrawl.progress(time: clock.time,
                                         duration: media.nowPlaying.duration)
            let y = LyricsCrawl.offset(progress: p,
                                       content: contentHeight,
                                       viewport: geo.size.height)
            VStack(spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(GeometryReader { g in
                Color.clear.preference(key: CrawlHeightKey.self, value: g.size.height)
            })
            .frame(width: geo.size.width, alignment: .top)
            .offset(y: y)
            .animation(.linear(duration: 0.25), value: y)
        }
        .onPreferenceChange(CrawlHeightKey.self) { contentHeight = $0 }
        .clipped()
        .mask(
            LinearGradient(colors: [.clear, .black, .black, .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

/// Full-window crawl surface shown when "Klip" is opened on a track with no
/// music video — a black screen would be worse than lyrics flowing up.
struct ClipCrawlScreen: View {
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    var body: some View {
        ZStack {
            backdrop
            content
            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onExitCommand { vm.exitClipCrawl() }
        .onAppear { vm.loadLyricsForCurrentTrack() }
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable().scaledToFill()
                    .blur(radius: 90).opacity(0.35)
                    .overlay(Color.black.opacity(0.55))
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if let l = vm.lyrics {
            LyricsCrawlView(text: l.text, textColor: .white.opacity(0.9))
                .padding(.horizontal, 60)
        } else if vm.lyricsLoading {
            ProgressView().tint(.white)
        } else {
            Text(vm.lyricsError ?? "Sözler bulunamadı")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Button(action: { vm.exitClipCrawl() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Kapat")
                Spacer()
            }
            Spacer()
        }
        .padding(20)
    }
}
```

- [ ] **Step 4: Run math test to verify it passes**

Run: `swift test --filter LyricsCrawlTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Wire ClipCrawlScreen into the body**

`NativeShellView.swift`, `if vm.isNowPlayingVisible { NowPlayingScreen... }` bloğundan (96-100) sonra ekle:

```swift
            if vm.isClipCrawlVisible {
                ClipCrawlScreen(vm: vm)
                    .transition(.opacity)
                    .zIndex(45)
            }
```

Ve `.animation` blokları arasına (~132, `isNowPlayingVisible` animation'ından sonra):

```swift
        .animation(.easeInOut(duration: 0.22), value: vm.isClipCrawlVisible)
```

- [ ] **Step 6: Build**

Run: `swift build 2>&1 | tail -8`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add Sources/YTMusicMac/NativeShell/LyricsCrawlView.swift Sources/YTMusicMac/NativeShell/NativeShellView.swift Tests/YTMusicMacTests/LyricsCrawlTests.swift
git commit -m "Add LyricsCrawlView + ClipCrawlScreen (Star Wars lyric crawl)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Söz gösterimlerini akışa çevir (yan panel + büyük player)

Görsel; canlı doğrulanır (Task 7). "Her yerde sync" gereğini uygular.

**Files:**
- Modify: `Sources/YTMusicMac/NativeShell/NowPlayingScreen.swift:264-272` (lyricsColumn)
- Modify: `Sources/YTMusicMac/NativeShell/NativeShellView.swift:3558-3577` (LyricsPanel.content)

- [ ] **Step 1: Big player — swap ScrollView(Text) for the crawl**

`NowPlayingScreen.swift:264-272`, `else if let lyrics = vm.lyrics { ScrollView { Text(...) } }` dalını şununla değiştir:

```swift
            } else if let lyrics = vm.lyrics {
                LyricsCrawlView(text: lyrics.text, textColor: .white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 2: Side panel — swap ScrollView(Text) for the crawl**

`NativeShellView.swift:3558-3577`, `else if let lyrics = vm.lyrics { ScrollView(...) { ... } }` dalını şununla değiştir:

```swift
        } else if let lyrics = vm.lyrics {
            LyricsCrawlView(text: lyrics.text, textColor: .primary.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
```

> NOT: `lyrics.source` alt yazısı bu dalda düşer (akış tam alanı kullanır). Kaynak bilgisi hâlâ modelde; ileride küçük bir footer olarak geri eklenebilir (YAGNI: şimdilik gerekmiyor).

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -8`
Expected: no errors.

- [ ] **Step 4: Run the full test suite**

Run: `swift test 2>&1 | tail -15`
Expected: tüm testler PASS (mevcut 31 + yeni ~15).

- [ ] **Step 5: Commit**

```bash
git add Sources/YTMusicMac/NativeShell/NowPlayingScreen.swift Sources/YTMusicMac/NativeShell/NativeShellView.swift
git commit -m "Lyrics: use the Star Wars crawl in the side panel and big player

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Canlı build + doğrulama

**Files:** yok (doğrulama).

- [ ] **Step 1: Release build + paketle**

Run: `./build.sh 2>&1 | tail -20`
Expected: "✓" ile biten başarı; `build/YTMusic.app` üretilir.

- [ ] **Step 2: Uygulamayı çalıştır ve gözle doğrula**

`verify` skill'i / `run` skill'i ile uygulamayı aç. Kontrol listesi:
- Aynı isimli parçalar listesinde **yalnızca gerçekten çalan** satır hoparlör ikonlu.
- Bir satırın üzerine gelince numara yerine **play ikonu**.
- Sol menüden "Ara" tıklayınca arama **tam ekran sekme** olarak açılıyor (dialog değil); ⌘K aynı sekmeyi açıyor; bir sonuç açıp geri gelince arama korunuyor.
- Klibi olan bir parça çalarken listede **film ikonu** görünüyor; tıklayınca klip açılıyor.
- Klibi olmayan bir parçada büyük player'daki "Klip"e basınca **siyah ekran yerine** sözler alttan yukarı akıyor.
- Yan panelde ve büyük player'da sözler akış halinde; pause'da duruyor, seek'te atlıyor.

- [ ] **Step 3: Kullanıcıya sun**

Sonucu ve doğrulanan davranışları özetle; canlı denemesi için kullanıcıya bırak.

---

## Self-Review

**Spec kapsamı:**
- Çalan parça (videoId) → Task 1 ✓
- Arama dialog→sekme → Task 3 ✓
- Hover play ikonu → Task 2 ✓
- Klip ikonu (now-playing, hasVideo) → Task 2 (icon) + Task 4 (branch) ✓
- Klipsiz fallback = akış → Task 4 + Task 5 ✓
- Sözler her yerde akış → Task 6 ✓
- İstatistik → bilinçli kapsam dışı ✓

**Placeholder taraması:** Yok — her adımda tam kod var. Task 3 Step 1'de `SearchResult` init imzası doğrulama notu var (kod tabanındaki gerçek imzaya uyarlanacak); bu bir plan boşluğu değil, dış imza kontrolü.

**Tip tutarlılığı:** `NowPlaying.isCurrentTrack(id:)`, `LyricsCrawl.progress/offset`, `NativeShellViewModel.clipEntry/ClipEntry/isClipCrawlVisible/exitClipCrawl`, `LyricsCrawlView(text:textColor:)`, `ClipCrawlScreen(vm:)`, `TrackRow.showClipIcon/onClip` — tanım ve kullanım adları eşleşiyor.
