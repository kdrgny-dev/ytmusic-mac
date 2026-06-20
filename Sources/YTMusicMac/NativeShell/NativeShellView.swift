import SwiftUI

/// The SwiftUI shell that takes over the main window when Native Mode is on.
/// WebView stays alive underneath as the audio engine but its UI is hidden
/// via CSS — what the user sees is this view, end-to-end.
///
/// Layout: three rows (header + body + player bar), body is two columns
/// (sidebar + main). Tokens follow a near-black palette with slightly
/// lighter surface tints — Apple Music / Spotify / Notion family.
struct NativeShellView: View {
    @EnvironmentObject private var media: MediaController
    @StateObject private var vm = NativeShellViewModel.shared

    // Surface tokens. Distinct enough that each region is visible against
    // its neighbour without being noisy. Tweak in one place.
    private let bgBase    = Color(red: 0.043, green: 0.043, blue: 0.051) // app
    private let bgSurface = Color(red: 0.094, green: 0.094, blue: 0.106) // sidebar / player bar
    private let bgRaised  = Color(red: 0.137, green: 0.137, blue: 0.149) // hover / chips
    private let strokeColor = Color.white.opacity(0.08)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Sidebar(bg: bgSurface, stroke: strokeColor, vm: vm)
                Divider().background(strokeColor)
                MainContent(bg: bgBase, vm: vm)
                if vm.isQueueVisible {
                    Divider().background(strokeColor)
                    QueuePanel(bg: bgSurface, raised: bgRaised, vm: vm)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(strokeColor)

            PlayerBar(bg: bgSurface, raised: bgRaised, vm: vm)
                .frame(height: 96)
        }
        .background(bgBase)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: vm.isQueueVisible)
        .onAppear { vm.loadPlaylistsIfNeeded() }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    let bg: Color
    let stroke: Color
    @ObservedObject var vm: NativeShellViewModel

    private let topItems: [(String, String)] = [
        ("house.fill",        "Home"),
        ("magnifyingglass",   "Explore"),
        ("heart.fill",        "Liked songs")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Browse")
                    ForEach(topItems, id: \.1) { icon, name in
                        sidebarRow(icon: icon, label: name)
                    }

                    HStack {
                        sectionHeader("Your playlists")
                        Spacer()
                        Button(action: { vm.reload() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                    .padding(.top, 18)

                    playlistSection
                }
                .padding(.vertical, 14)
            }
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    @ViewBuilder
    private var playlistSection: some View {
        if vm.loadingPlaylists && vm.playlists.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        } else if let msg = vm.errorMessage, vm.playlists.isEmpty {
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .lineLimit(3)
        } else {
            ForEach(vm.playlists) { p in
                Button(action: { vm.openPlaylist(p) }) {
                    playlistRow(p)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }

    private func sidebarRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundColor(.white.opacity(0.7))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func playlistRow(_ p: NativeShellViewModel.PlaylistSummary) -> some View {
        HStack(spacing: 10) {
            thumbnail(for: p)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(p.title)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnail(for p: NativeShellViewModel.PlaylistSummary) -> some View {
        if let urlString = p.thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                )
        }
    }
}

// MARK: - Main content

private struct MainContent: View {
    let bg: Color
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            if let p = vm.selectedPlaylist {
                PlaylistDetailView(playlist: p, vm: vm)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.35))
            Text("Pick a playlist")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Text("Choose one from the sidebar to see its tracks.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
    }
}

private struct PlaylistDetailView: View {
    let playlist: NativeShellViewModel.PlaylistSummary
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            tracksList
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            cover
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text("PLAYLIST")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.5))
                Text(playlist.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if !vm.tracks.isEmpty {
                    Text("\(vm.tracks.count) tracks")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var cover: some View {
        if let s = playlist.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }

    @ViewBuilder
    private var tracksList: some View {
        if vm.loadingTracks && vm.tracks.isEmpty {
            VStack {
                ProgressView()
                Text("Loading tracks…")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.tracksError, vm.tracks.isEmpty {
            Text(msg)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.tracks.enumerated()), id: \.element.id) { idx, track in
                        Button(action: { vm.playTrack(track) }) {
                            TrackRow(index: idx + 1, track: track)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

private struct TrackRow: View {
    let index: Int
    let track: NativeShellViewModel.TrackSummary

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 28, alignment: .trailing)
            cover
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
            if let dur = track.duration {
                Text(dur)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(Color.white.opacity(0.0001)) // hover targets
    }

    @ViewBuilder
    private var cover: some View {
        if let s = track.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.06)
                }
            }
        } else {
            Color.white.opacity(0.06)
        }
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @EnvironmentObject private var media: MediaController
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel

    // Local display state for the progress slider. Updated event-driven
    // from MediaController + a 0.5s tick timer between updates so it
    // doesn't visibly stall waiting for the 4s safety-net poll.
    @State private var displayedTime: Double = 0
    @State private var isDragging: Bool = false

    private let tickTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            progressRow
            controlsRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(bg)
        .onAppear { displayedTime = media.nowPlaying.currentTime }
        .onChange(of: media.nowPlaying.currentTime) { newValue in
            if !isDragging { displayedTime = newValue }
        }
        .onChange(of: media.nowPlaying.title) { _ in
            if !isDragging { displayedTime = media.nowPlaying.currentTime }
        }
        .onReceive(tickTimer) { _ in
            guard !isDragging, media.nowPlaying.isPlaying else { return }
            let total = media.nowPlaying.duration
            displayedTime = min(displayedTime + 0.5, total > 0 ? total : displayedTime + 0.5)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(format(displayedTime))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 38, alignment: .trailing)
            Slider(
                value: $displayedTime,
                in: 0...max(media.nowPlaying.duration, 1),
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        media.run("seek", value: displayedTime)
                    }
                }
            )
            .controlSize(.mini)
            Text(format(media.nowPlaying.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 38, alignment: .leading)
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(media.nowPlaying.hasTrack ? media.nowPlaying.title : "Not Playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(media.nowPlaying.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            transport
            queueToggle
        }
    }

    private var queueToggle: some View {
        Button(action: { vm.toggleQueue() }) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(vm.isQueueVisible ? .white : .white.opacity(0.55))
                .frame(width: 30, height: 30)
                .background(vm.isQueueVisible ? Color.white.opacity(0.15) : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Toggle Queue (⌘E)")
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var artwork: some View {
        Group {
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                raised.overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.35))
                )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var transport: some View {
        HStack(spacing: 14) {
            iconButton("backward.fill") { media.run("prev") }
            iconButton(media.nowPlaying.isPlaying ? "pause.fill" : "play.fill", large: true) {
                media.run("playpause")
            }
            iconButton("forward.fill") { media.run("next") }
        }
    }

    private func iconButton(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 16 : 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: large ? 38 : 30, height: large ? 38 : 30)
                .background(large ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue panel

private struct QueuePanel: View {
    let bg: Color
    let raised: Color
    @ObservedObject var vm: NativeShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            content
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(bg)
    }

    private var header: some View {
        HStack {
            Text("Queue")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            if !vm.queue.isEmpty {
                Text("\(vm.queue.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            Button(action: { vm.toggleQueue() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if vm.queue.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.white.opacity(0.3))
                Text("Queue is empty")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                Text("Play something to fill it.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.queue) { item in
                        Button(action: { vm.jumpToQueueIndex(item.id) }) {
                            QueueRow(item: item, raised: raised)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct QueueRow: View {
    let item: NativeShellViewModel.QueueItem
    let raised: Color

    var body: some View {
        HStack(spacing: 10) {
            cover
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: item.isPlaying ? .semibold : .regular))
                    .foregroundColor(item.isPlaying ? .green : .white)
                    .lineLimit(1)
                Text(item.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(item.isPlaying ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cover: some View {
        if let s = item.thumbnailURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    raised
                }
            }
        } else {
            raised
        }
    }
}
