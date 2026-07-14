import SwiftUI

/// Pure crawl math, isolated so it's unit-testable without a view.
enum LyricsCrawl {
    /// 0…1 through the song. Guards divide-by-zero.
    static func progress(time: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    /// Best-effort "current line" index. Lyrics carry no timestamps, so we map
    /// playback progress uniformly onto the line count — approximate but keeps
    /// the highlighted line roughly in step with the song.
    static func activeIndex(progress: Double, lineCount: Int) -> Int {
        guard lineCount > 0 else { return 0 }
        return min(max(Int(progress * Double(lineCount)), 0), lineCount - 1)
    }
}

/// Karaoke-style lyric view: the estimated current line sits centered, large and
/// crisp; neighbors shrink and fade above and below, with a soft top/bottom edge
/// fade. Advances line-by-line with playback (no per-word highlight — YTM gives
/// plain text with no timestamps).
struct LyricsCrawlView: View {
    let text: String
    var textColor: Color = .primary

    @ObservedObject private var clock = PlaybackClock.shared
    @EnvironmentObject private var media: MediaController

    private var lines: [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var activeIndex: Int {
        LyricsCrawl.activeIndex(
            progress: LyricsCrawl.progress(time: clock.time,
                                           duration: media.nowPlaying.duration),
            lineCount: lines.count)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 18) {
                        Color.clear.frame(height: geo.size.height * 0.44)
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            lineView(i, line).id(i)
                        }
                        Color.clear.frame(height: geo.size.height * 0.44)
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: activeIndex) { idx in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
                .onAppear { proxy.scrollTo(activeIndex, anchor: .center) }
            }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.30),
                .init(color: .black, location: 0.70),
                .init(color: .clear, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    @ViewBuilder
    private func lineView(_ i: Int, _ line: String) -> some View {
        let d = abs(i - activeIndex)
        let isActive = d == 0
        Text(line)
            .font(.system(size: isActive ? 25 : 17,
                          weight: isActive ? .bold : .medium))
            .foregroundColor(textColor.opacity(isActive ? 1 : max(0.18, 0.55 - Double(d) * 0.12)))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.3), value: isActive)
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
            topBar
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
            LyricsCrawlView(text: l.text, textColor: .white.opacity(0.92))
                .padding(.horizontal, 60)
                .padding(.top, 40)
        } else if vm.lyricsLoading {
            ProgressView().tint(.white)
        } else {
            Text(vm.lyricsError ?? "Sözler bulunamadı")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 14) {
                Button(action: { vm.exitClipCrawl() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Kapat")

                if media.nowPlaying.hasTrack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(media.nowPlaying.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(media.nowPlaying.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            Spacer()
        }
        .padding(20)
    }
}
