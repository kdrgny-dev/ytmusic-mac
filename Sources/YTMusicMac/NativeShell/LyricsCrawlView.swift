import SwiftUI

/// Pure crawl math, isolated so it's unit-testable without a view.
enum LyricsCrawl {
    /// 0…1 through the song. Guards divide-by-zero.
    static func progress(time: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    /// Best-effort "current line" index when lyrics carry no timestamps: map
    /// playback progress uniformly onto the line count. Approximate — drifts on
    /// intros/instrumentals — but keeps the highlight roughly in step.
    static func activeIndex(progress: Double, lineCount: Int) -> Int {
        guard lineCount > 0 else { return 0 }
        return min(max(Int(progress * Double(lineCount)), 0), lineCount - 1)
    }

    /// True line index for timestamped lyrics: the last line whose start time
    /// has passed. Exact sync, honors seek/pause via `time`.
    static func activeIndex(synced lines: [LyricsLine], time: Double) -> Int {
        guard !lines.isEmpty else { return 0 }
        var idx = 0
        for (i, line) in lines.enumerated() {
            if line.start <= time { idx = i } else { break }
        }
        return idx
    }
}

/// Karaoke-style lyric view: the estimated current line sits centered, large and
/// crisp; neighbors shrink and fade above and below, with a soft top/bottom edge
/// fade. Advances line-by-line with playback (no per-word highlight — YTM gives
/// plain text with no timestamps).
struct LyricsCrawlView: View {
    let lyrics: LyricsParser.Lyrics
    var textColor: Color = .primary

    @ObservedObject private var clock = PlaybackClock.shared
    @EnvironmentObject private var media: MediaController

    private var lines: [String] {
        if let s = lyrics.synced, !s.isEmpty { return s.map(\.text) }
        return lyrics.text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var activeIndex: Int {
        if let s = lyrics.synced, !s.isEmpty {
            return LyricsCrawl.activeIndex(synced: s, time: clock.time)
        }
        return LyricsCrawl.activeIndex(
            progress: LyricsCrawl.progress(time: clock.time,
                                           duration: media.nowPlaying.duration),
            lineCount: lines.count)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 24) {
                        Color.clear.frame(height: geo.size.height * 0.46)
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                            lineView(i, line).id(i)
                        }
                        Color.clear.frame(height: geo.size.height * 0.46)
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
            .font(.system(size: isActive ? 36 : 20,
                          weight: isActive ? .bold : .medium,
                          design: .rounded))
            .foregroundColor(textColor.opacity(isActive ? 1 : max(0.12, 0.48 - Double(d) * 0.11)))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .scaleEffect(isActive ? 1 : 0.97, anchor: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
    }
}

/// Full-window crawl surface shown when the video pill is opened on a track
/// with no music video — a black screen would be worse than lyrics flowing up.
struct ClipCrawlScreen: View {
    @ObservedObject var vm: NativeShellViewModel
    @EnvironmentObject private var media: MediaController

    var body: some View {
        ZStack {
            backdrop
            // The crawl auto-scrolls with playback, so it needs no interaction —
            // making it hit-transparent lets clicks fall through to the backdrop
            // (which exits), so the user can never get stuck here.
            content.allowsHitTesting(false)
            topBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .onExitCommand { vm.exitClipCrawl() }
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
        // Safety net: tapping the empty backdrop always exits, even if the
        // close button is hard to spot (e.g. on the "no lyrics" screen).
        .contentShape(Rectangle())
        .onTapGesture { vm.exitClipCrawl() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.clipSurface {
        case .loading:
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(L10n.t("lyrics.clipLoading"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
        case .crawl:
            crawlContent
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var crawlContent: some View {
        if let l = vm.lyrics {
            LyricsCrawlView(lyrics: l, textColor: .white.opacity(0.92))
                .padding(.horizontal, 60)
                .padding(.top, 40)
        } else if vm.lyricsLoading {
            ProgressView().tint(.white)
        } else {
            Text(vm.lyricsError ?? L10n.t("lyrics.notFound"))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 14) {
                Button(action: { vm.exitClipCrawl() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(L10n.t("common.close"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help(L10n.t("lyrics.close.help"))

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
