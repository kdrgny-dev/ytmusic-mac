import SwiftUI

/// Full-window native "Now Playing" surface — big blurred-artwork backdrop,
/// large cover, transport, scrubber, volume, and an optional lyrics column.
/// Opened with Cmd-F (see `toggleNowPlaying`). All state comes from
/// MediaController + PlaybackClock, so it needs no WebView cooperation.
struct NowPlayingScreen: View {
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var prefs = Preferences.shared

    @State private var showLyrics = false

    private var accent: Color { prefs.theme.accentColor }
    private var np: NowPlaying { media.nowPlaying }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 48) {
                    playerColumn
                        .frame(maxWidth: showLyrics ? 460 : 560)
                    if showLyrics {
                        lyricsColumn
                            .frame(maxWidth: 420)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 48)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark) // this surface is always a dark HUD
        .animation(.easeInOut(duration: 0.22), value: showLyrics)
        .onExitCommand { vm.isNowPlayingVisible = false } // Esc closes
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            Color.black
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 80)
                    .opacity(0.55)
                    .overlay(Color.black.opacity(0.45))
            } else {
                LinearGradient(colors: [accent.opacity(0.35), .black],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        // Safety net: clicking the empty backdrop closes the screen even if
        // the top bar ends up somewhere unexpected.
        .contentShape(Rectangle())
        .onTapGesture { vm.isNowPlayingVisible = false }
    }

    // MARK: Player column

    private var playerColumn: some View {
        VStack(spacing: 28) {
            artwork
            VStack(spacing: 6) {
                Text(np.hasTrack ? np.title : "Çalan şarkı yok")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Button(action: {
                    guard !np.artist.isEmpty else { return }
                    vm.isNowPlayingVisible = false
                    vm.openArtistByName(np.artist)
                }) {
                    Text(np.artist)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(np.artist.isEmpty)
            }
            scrubber
            transport
            bottomRow
            actionRow
        }
    }

    /// Close / Klip / Sözler as labeled pills, placed inside the player column
    /// (which reliably renders) rather than a top bar.
    private var actionRow: some View {
        HStack(spacing: 12) {
            pill("chevron.down", "Kapat", filled: true) { vm.isNowPlayingVisible = false }
            pill("film", "Klip") { vm.enterClip() }
            pill("quote.bubble", showLyrics ? "Sözleri gizle" : "Sözler", active: showLyrics) {
                showLyrics.toggle()
            }
        }
        .padding(.top, 6)
    }

    private func pill(_ icon: String, _ label: String, filled: Bool = false,
                      active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(filled ? .black : (active ? accent : .white))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.14)))
            .overlay(Capsule().stroke(Color.white.opacity(filled ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The player-bar artwork we cache is tiny (~60px); upscaled to 300px it
    /// looks like mud. YT's image URLs take a size suffix, so bump it to a
    /// crisp 544px and load that fresh for this big display.
    private var hiResArtURL: URL? {
        let raw = np.artworkURL
        guard !raw.isEmpty else { return nil }
        let hi = raw.replacingOccurrences(of: #"=w\d+-h\d+"#,
                                          with: "=w544-h544",
                                          options: .regularExpression)
        return URL(string: hi)
    }

    private var artwork: some View {
        Group {
            if let url = hiResArtURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        // Show the cached low-res art while the hi-res loads.
                        if let art = media.artwork {
                            Image(nsImage: art).resizable().scaledToFill()
                        } else {
                            artPlaceholder
                        }
                    }
                }
            } else if let art = media.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                artPlaceholder
            }
        }
        .frame(width: 300, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
    }

    private var artPlaceholder: some View {
        Color.white.opacity(0.08)
            .overlay(Image(systemName: "music.note").font(.system(size: 48)).foregroundColor(.white.opacity(0.3)))
    }

    // MARK: Scrubber

    @State private var displayedTime: Double = 0
    @State private var isDragging = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { displayedTime },
                set: { displayedTime = $0 }
            ), in: 0...max(np.duration, 1)) { editing in
                isDragging = editing
                if !editing { media.run("seek", value: displayedTime) }
            }
            .tint(accent)
            HStack {
                Text(format(displayedTime))
                Spacer()
                Text(format(np.duration))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: 520)
        .onAppear { displayedTime = clock.time }
        .onChange(of: clock.time) { v in if !isDragging { displayedTime = v } }
        .onChange(of: np.title) { _ in if !isDragging { displayedTime = clock.time } }
        .onReceive(tick) { _ in
            guard !isDragging, np.isPlaying else { return }
            let total = np.duration
            displayedTime = min(displayedTime + 0.5, total > 0 ? total : displayedTime + 0.5)
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 32) {
            iconButton("shuffle", active: np.shuffle, size: 18) { media.run("shuffle") }
            iconButton("backward.fill", size: 24) { media.run("prev") }
            Button(action: { media.run("playpause") }) {
                Image(systemName: np.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)
            iconButton("forward.fill", size: 24) { media.run("next") }
            iconButton(repeatIcon, active: np.repeatMode != "NONE", size: 18) { media.run("repeat") }
        }
    }

    private var repeatIcon: String { np.repeatMode == "ONE" ? "repeat.1" : "repeat" }

    // MARK: Bottom row — like + volume

    private var bottomRow: some View {
        HStack(spacing: 20) {
            iconButton(np.liked ? "heart.fill" : "heart", active: np.liked, size: 18) { media.run("like") }
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            Slider(value: Binding(
                get: { localVolume },
                set: { localVolume = $0; media.run("volume", value: $0) }
            ), in: 0...1)
            .tint(.white.opacity(0.85))
            .frame(width: 160)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: 520)
        .onAppear { localVolume = np.volume }
        .onChange(of: np.volume) { v in localVolume = v }
    }

    @State private var localVolume: Double = 1

    // MARK: Lyrics column

    private var lyricsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sözler")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            if vm.lyricsLoading {
                ProgressView().controlSize(.small).tint(.white)
            } else if let err = vm.lyricsError {
                Text(err).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            } else if let lyrics = vm.lyrics {
                ScrollView {
                    Text(lyrics.text)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Text("Sözler yükleniyor…").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 420, alignment: .topLeading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    // MARK: Helpers

    private func iconButton(_ name: String, active: Bool = false, size: CGFloat,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(active ? accent : .white.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func format(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
