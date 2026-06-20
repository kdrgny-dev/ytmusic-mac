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
                MainContent(bg: bgBase)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(strokeColor)

            PlayerBar(bg: bgSurface, raised: bgRaised)
                .frame(height: 84)
        }
        .background(bgBase)
        .preferredColorScheme(.dark)
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

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.white.opacity(0.35))
                Text("Native shell ready")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("Sidebar, queue and search come next. Playback already works.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Player bar

private struct PlayerBar: View {
    @EnvironmentObject private var media: MediaController
    let bg: Color
    let raised: Color

    var body: some View {
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
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(bg)
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
