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
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor.clear
        w.isOpaque = false
        w.hasShadow = true
        w.setContentSize(NSSize(width: 260, height: 320))
        w.minSize = NSSize(width: 220, height: 270)
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
        ZStack {
            backdrop
            VStack(spacing: 10) {
                artworkWithOverlay
                title
                transport
            }
            .padding(.horizontal, 14)
            .padding(.top, 28)   // leave room for traffic lights
            .padding(.bottom, 14)
        }
    }

    // MARK: - sections

    private var backdrop: some View {
        ZStack {
            if let img = media.artwork {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 60, opaque: true)
                    .opacity(0.55)
            } else {
                Color(white: 0.08)
            }
            Color.black.opacity(0.35)
        }
        .ignoresSafeArea()
    }

    /// Square artwork that grows with the window width, with a small
    /// like/dislike overlay in the top-right corner.
    private var artworkWithOverlay: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = media.artwork {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white.opacity(0.35))
                            )
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

                HStack(spacing: 4) {
                    overlayButton(systemName: media.nowPlaying.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                  active: media.nowPlaying.liked,
                                  tint: .pink) { media.run("like") }
                    overlayButton(systemName: media.nowPlaying.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                                  active: media.nowPlaying.disliked,
                                  tint: .blue) { media.run("dislike") }
                }
                .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var title: some View {
        VStack(spacing: 2) {
            Text(media.nowPlaying.hasTrack ? media.nowPlaying.title : "Not Playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(media.nowPlaying.artist)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
    }

    private var transport: some View {
        HStack(spacing: 18) {
            controlButton("backward.fill") { media.run("prev") }
            controlButton(media.nowPlaying.isPlaying ? "pause.fill" : "play.fill", large: true) { media.run("playpause") }
            controlButton("forward.fill") { media.run("next") }
        }
    }

    // MARK: - components

    private func controlButton(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 22 : 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: large ? 44 : 32, height: large ? 44 : 32)
                .background(Color.white.opacity(large ? 0.18 : 0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func overlayButton(systemName: String,
                               active: Bool,
                               tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? tint : .white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
