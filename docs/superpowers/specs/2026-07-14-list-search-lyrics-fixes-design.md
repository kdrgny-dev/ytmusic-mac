# Liste/Arama/Söz düzenlemeleri — Tasarım

Tarih: 2026-07-14

Native shell'de dört bağımsız düzenleme. İstatistik "Tüm zamanlar" konusu bilinçli
olarak kapsam dışı (sorgu mantığında bug bulunamadı; kullanıcı pas geçti).

## 1. Çalan parça tespiti — isim yerine videoId

**Sorun:** Listelerde "şu an çalıyor" işareti şarkı ADI ile eşleştiriliyor, bu yüzden
aynı isimli birden çok parça ("There She Goes") hep birden çalıyor görünüyor.

**Kök neden:** `NativeShellView.swift` içinde üç fonksiyon title karşılaştırması yapıyor:
- `PlaylistDetailView.isCurrentTrack` (~2979): `np.title.caseInsensitiveCompare(t.title) == .orderedSame`
- `ChartSectionView.isCurrent` (~2131): aynı
- `ArtistView.isCurrent` (~1560): aynı

`NowPlaying.videoId` (MediaController.swift) ve `TrackSummary.id == videoId`
(NativeShellViewModel.swift) zaten mevcut. Queue'daki `isCurrentQueueItem` (~3885)
doğru deseni kullanıyor.

**Çözüm:** Üç fonksiyonu şu mantığa çevir:
```swift
let np = media.nowPlaying
return np.hasTrack && !np.videoId.isEmpty && np.videoId == t.id
```
Title fallback tamamen kalkar. `videoId` boşsa işaretleme yapılmaz (yanlış çoklu
işaretlemeyi önlemek için). Aynı `videoId`'ye sahip satırlar (history'de tekrar
dinleme) doğru şekilde birlikte işaretlenir — bu istenen davranış.

## 2. Arama: dialog → ana sekme

**Amaç:** Aramayı modal overlay/dialog olmaktan çıkarıp keşfet/geçmiş gibi normal bir
ana alan (sekme) yapmak. Kullanım mantığı ve UI akışı korunur.

**Mevcut yapı:** `MainSection` enum + `goX()` fonksiyonları + `MainContent` switch +
Sidebar topItems deseni. home/explore/history/statistics bu kalıbı izliyor. Arama şu an
bu kalıbın dışında bir overlay (`vm.isSearchVisible` + `SearchOverlay`).

**Değişiklikler:**
- `MainSection` enum'a `case search` ekle; `apply(section:)` ve `retryCurrentSection()`
  dallarını ekle.
- `goSearch()` fonksiyonu (goHome deseni: `pushHistory()`, `mainSection = .search`,
  `selectedPlaylist = nil`).
- `SearchOverlay` → `SearchView`: dialog artifaktlarını kaldır — dim backdrop +
  dış-tık-kapatma, sabit `maxWidth: 680`/`maxHeight: 560`/gölge, `⎋` kapatma butonu,
  zorlanan `.environment(\.colorScheme, .dark)`. İçerik (searchField + tabBar +
  resultsArea) `MainContent` switch'inde tam alanda render edilir.
- `body` içindeki `if vm.isSearchVisible { SearchOverlay ... }` bloğu ve overlay geçiş
  animasyonu kaldırılır.
- Sidebar "Ara" item action `{ vm.goSearch() }`; `isTopActive` "search" → `mainSection
  == .search`.
- `App.swift` `focusSearch()` native modda `goSearch()` çağırır; ⌘K korunur.
- Lifecycle temizliği:
  - `toggleSearch()` içindeki "kapanınca query/results/cache/tab sıfırla" mantığı sekme
    kavramına uymaz; sıfırlama ayrılır. Sekmeye tekrar girince önceki arama korunur.
  - `openSearchResult(_:)` sonuç açınca `isSearchVisible = false` + temizlik yerine
    `pushHistory` ile ilgili sayfaya gider; arama sorgusu korunur (geri gelince arama
    ekranı eski haliyle durur).
  - `isSearchVisible` bayrağı `mainSection == .search`'e devredilir.
- `.search`'e girişte arama alanına odak verilir.

**Kabul kriteri:** Sidebar'dan/⌘K ile arama sekmesi açılır; sonuç açıp geri gelince
arama korunur; geri/ileri stack arama sekmesini içerir; tema uyumludur.

## 3. Hover'da play ikonu

**Amaç:** Liste satırına gelince play ikonu görünsün ki tıklayınca çalacağı anlaşılsın.

**Mevcut:** Ortak `TrackRow` (NativeShellView.swift ~3065-3180). `isHovered` state var
ama sadece arka planı değiştiriyor. Index sütunu: `isPlaying` ? hoparlör : numara.

**Çözüm:** Index sütunu üç durumlu:
- `isPlaying` → `speaker.wave.2.fill` (mevcut)
- `!isPlaying && isHovered` → `play.fill`
- diğer → satır numarası

Tıklama davranışı değişmez (zaten çalmayı tetikliyor). Yalnızca görsel ipucu eklenir.

## 4. Klip ikonu + klipsiz fallback = Star Wars söz akışı (her yerde)

**Kısıt:** YTM InnerTube söz kaynağı yalnızca DÜZ METİN veriyor; satır bazlı zaman
damgası yok. Bu yüzden kelime/satır vurgusu yapan gerçek karaoke mümkün değil. Seçilen
yaklaşım: **süreye oranlı Star Wars akışı** (harici bağımlılık yok).

**(a) Liste klip ikonu:**
Yalnızca ÇALAN satırda ve `media.hasVideo == true` ise küçük "film" ikonu gösterilir
(başlık yanında). Tıklanınca `vm.enterClip()`. `hasVideo` yalnızca çalan parça için
bilindiğinden bu sadece now-playing satırında geçerlidir.

**(b) Klip modu `hasVideo`'ya göre dallanır:**
`enterClip()` artık `MediaController.shared.hasVideo`'yu kontrol eder:
- `hasVideo == true` → bugünküyle aynı (WebView öne, `<video>` pinlenir).
- `hasVideo == false` → siyah ekran/7.5sn timeout yerine tam ekran **söz akışı** modu
  (SwiftUI overlay). WebView öne alınmaz.

Böylece hem büyük player'daki Klip butonu hem liste ikonu her zaman anlamlı sonuç verir.
Klip modundan çıkış (geri butonu) her iki dalda da çalışır.

**(c) Yeni `LyricsCrawlView` (ortak bileşen):**
- Girdi: `lyrics.text` (düz metin), `duration`, `currentTime` (PlaybackClock).
- Metin satırlara bölünür; alttan yukarı otomatik kayar.
- Kaydırma ofseti saf bir fonksiyondan hesaplanır: `progress = currentTime / duration`
  (0'da içerik altta, 1'de üstte). Böylece pause'da durur, seek'te atlar.
- Merkeze yakın satır en parlak, uzaklaştıkça soluklaşır (opacity gradyanı).
- Zaman damgası olmadığından kelime-kelime vurgu yok.

**"Her yerde":**
- `LyricsPanel` (yan panel ~3499) düz `Text(lyrics.text)` yerine `LyricsCrawlView`.
- `NowPlayingScreen.lyricsColumn` (~255) aynı şekilde.
- Klipsiz klip modunda fallback aynı bileşen.
- İncelik (v1 opsiyonel): yan panelde kullanıcı elle kaydırırsa otomatik akış geçici
  durur.

## Testler

- **Playing tespiti:** aynı title/farklı videoId → yalnızca eşleşen satır işaretli; boş
  `np.videoId` → hiçbiri işaretli değil; aynı videoId iki satırda → ikisi de işaretli.
- **Navigasyon:** `MainSection.search` push/geri/ileri; sonuç açınca doğru section;
  arama sekmesine tekrar girince query korunur.
- **LyricsCrawl ofset hesabı (saf fonksiyon):** currentTime=0 → alt; currentTime=duration
  → üst; ara değerler oranlı; duration=0 guard.
- **enterClip dallanması:** hasVideo=false → crawl modu, WebView öne alınmaz, otomatik
  çıkış tetiklenmez; hasVideo=true → mevcut video yolu.

## Kapsam dışı

- İstatistik "Tüm zamanlar" (sorgu doğru, kullanıcı pas geçti).
- Gerçek zaman damgalı/karaoke sözler (harici kaynak gerektirir; seçilmedi).
- Klip ikonunun çalmayan satırlarda gösterilmesi (hasVideo bilinmiyor).
