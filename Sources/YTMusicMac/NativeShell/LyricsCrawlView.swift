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
