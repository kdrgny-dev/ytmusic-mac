import AppKit
import SwiftUI
import Combine

/// Lazily-created floating window hosting the mini player. Resizable, no
/// title bar chrome, always-on-top toggle from Preferences.
final class MiniPlayerWindowController {
    static let shared = MiniPlayerWindowController()

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func show() {
        if let w = window {
            applyLevel(to: w)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: MiniPlayerView().environmentObject(MediaController.shared))
        let w = NSWindow(contentViewController: hosting)
        w.identifier = NSUserInterfaceItemIdentifier(WindowID.mini.rawValue)
        w.title = "Mini Player"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        // Fixed-size horizontal pill. .closable kept so Cmd+W still works;
        // .resizable dropped because size is locked. Traffic-light buttons
        // hidden below so the chrome doesn't eat into the 100px height.
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor.clear
        w.isOpaque = false
        w.hasShadow = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { kind in
            w.standardWindowButton(kind)?.isHidden = true
        }
        let size = NSSize(width: 650, height: 100)
        w.setContentSize(size)
        w.minSize = size
        w.maxSize = size
        w.setFrameAutosaveName("YTMusicMacMiniPlayer")
        w.center()
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        applyLevel(to: w)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        Preferences.shared.$miniPlayerAlwaysOnTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if let w = self?.window { self?.applyLevel(to: w) }
            }
            .store(in: &cancellables)
    }

    private func applyLevel(to w: NSWindow) {
        w.level = Preferences.shared.miniPlayerAlwaysOnTop ? .floating : .normal
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var media: MediaController

    var body: some View {
        HStack(spacing: 14) {
            cover
            info
            Spacer(minLength: 8)
            reactionsPill
            transportPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 650, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - sections

    private var cover: some View {
        Group {
            if let img = media.artwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.red
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(media.nowPlaying.hasTrack ? media.nowPlaying.title : "Song Title")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(media.nowPlaying.hasTrack ? media.nowPlaying.artist : "Artist")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reactionsPill: some View {
        HStack(spacing: 4) {
            pillButton(systemName: media.nowPlaying.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                       active: media.nowPlaying.liked,
                       tint: .pink) { media.run("like") }
            pillButton(systemName: media.nowPlaying.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                       active: media.nowPlaying.disliked,
                       tint: .white) { media.run("dislike") }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }

    private var transportPill: some View {
        HStack(spacing: 4) {
            pillButton(systemName: "backward.fill", active: false, tint: .white) { media.run("prev") }
            pillButton(systemName: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                       active: false, tint: .white, large: true) { media.run("playpause") }
            pillButton(systemName: "forward.fill", active: false, tint: .white) { media.run("next") }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }

    // MARK: - components

    private func pillButton(systemName: String,
                            active: Bool,
                            tint: Color,
                            large: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: large ? 14 : 12, weight: .semibold))
                .foregroundColor(active ? tint : .white)
                .frame(width: large ? 32 : 26, height: large ? 32 : 26)
                .background(
                    Circle().fill(large ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
