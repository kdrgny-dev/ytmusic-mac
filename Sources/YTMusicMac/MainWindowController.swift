import AppKit
import Combine
import SwiftUI
import WebKit

/// Single-instance controller for the app's main window. Manages an NSWindow
/// directly (not SwiftUI WindowGroup) so we have full control over close
/// (hide-don't-destroy) and reopen (always the same window, never a duplicate).
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private let frameAutosaveName = "YTMusicMacMainWindow"
    private var nativeOverlay: NSHostingView<AnyView>?
    private var prefsCancellable: AnyCancellable?
    /// Tracked so a shell rebuild can restore the z-order instead of dropping
    /// the SwiftUI overlay back on top of a playing music video.
    private var clipMode = false

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// NSWindow subclass that intercepts back/forward navigation events
    /// before they reach the responder chain. Three paths because there's
    /// no single source of truth across mice + keyboards + drivers:
    ///   - mouse side-buttons (raw NSEvent.otherMouseDown, buttons 3/4/5)
    ///   - command + arrow / command + [ / command + ] keystrokes
    ///   - layout-tolerant via charactersIgnoringModifiers AND keyCode
    /// sendEvent runs for every event INTO the window, before any responder
    /// chain dispatch, so this catches them even when the hidden WebView
    /// would otherwise grab them first.
    private final class MouseInterceptingWindow: NSWindow {
        override func sendEvent(_ event: NSEvent) {
            if Preferences.shared.nativeUIMode {
                if handleNavEvent(event) { return }
            }
            super.sendEvent(event)
        }

        private func handleNavEvent(_ event: NSEvent) -> Bool {
            switch event.type {
            case .otherMouseDown:
                switch event.buttonNumber {
                case 3:
                    NativeShellViewModel.shared.goBack()
                    return true
                case 4, 5:
                    NativeShellViewModel.shared.goForward()
                    return true
                default: return false
                }
            case .keyDown where event.modifierFlags.contains(.command):
                // keyCode is layout-independent (the physical key on the
                // keyboard). 123 = left arrow, 124 = right arrow,
                // 33 = `[` on US (becomes Ğ on Turkish-Q),
                // 30 = `]` on US (becomes Ü on Turkish-Q).
                switch event.keyCode {
                case 123, 33:   // ⌘ + ←  or  ⌘ + [
                    NativeShellViewModel.shared.goBack()
                    return true
                case 124, 30:   // ⌘ + →  or  ⌘ + ]
                    NativeShellViewModel.shared.goForward()
                    return true
                default: return false
                }
            case .keyDown where !event.modifierFlags.contains(.command):
                // Transport shortcuts — but never steal keys while the user
                // is typing in a text field (search, rename, create dialog).
                // The native shell's fields are SwiftUI TextFields, whose
                // first responder is NOT an NSText, so checking that alone
                // let space/arrows leak out of the search box (space would
                // toggle playback, arrows would seek instead of moving the
                // caret). NSTextInputContext.current is non-nil whenever ANY
                // text input client — AppKit field editor OR SwiftUI TextField
                // — is active in the responder chain, so it catches both.
                if firstResponder is NSText || NSTextInputContext.current != nil { return false }
                switch event.keyCode {
                case 49:  // space → play/pause
                    MediaController.shared.run("playpause")
                    return true
                case 123: // ← seek back 5s
                    seek(by: -5); return true
                case 124: // → seek forward 5s
                    seek(by: 5); return true
                default: return false
                }
            default: return false
            }
        }

        private func seek(by delta: Double) {
            let cur = PlaybackClock.shared.time
            MediaController.shared.run("seek", value: max(0, cur + delta))
        }
    }

    private func build() {
        // Plain titled window — NO fullSizeContentView, because YT Music's
        // popup dialogs (edit playlist cover, etc.) need the top of the
        // content area to be unobstructed by the title bar/traffic lights.
        let w = MouseInterceptingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.identifier = NSUserInterfaceItemIdentifier(WindowID.main.rawValue)
        w.title = "YouTube Music"
        w.minSize = NSSize(width: 800, height: 500)
        w.isReleasedWhenClosed = false
        w.delegate = self
        // Match YT Music's --yt-spec-base-background (#030303) so resize and
        // launch don't flash white before the page paints.
        w.backgroundColor = NSColor(red: 0.012, green: 0.012, blue: 0.012, alpha: 1)
        // Restore last frame if available; only center on first launch.
        let restored = w.setFrameAutosaveName(frameAutosaveName)
        if !restored { w.center() }

        // Wrapper container holds the WebView AND (when Native Mode is on)
        // the SwiftUI overlay. WKWebView is a remote-process view, so we
        // can't safely add NSHostingView as ITS subview — siblings under a
        // plain NSView container work fine.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.012, green: 0.012, blue: 0.012, alpha: 1).cgColor

        let webView = WebViewHolder.shared.obtain()
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        w.contentView = container
        window = w

        // Subscribe AFTER window is set so applyNativeMode can actually
        // find the container. .sink fires immediately with the current
        // value, which seeds initial state.
        prefsCancellable = Preferences.shared.$nativeUIMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.applyNativeMode(on) }
    }

    /// Add or remove the SwiftUI shell as a sibling subview alongside the
    /// WebView. Same container, same size, on top in z-order.
    private func applyNativeMode(_ on: Bool) {
        guard let container = window?.contentView else { return }
        if on {
            if nativeOverlay == nil {
                let root = AnyView(
                    NativeShellView()
                        .environmentObject(MediaController.shared)
                )
                let host = NSHostingView(rootView: root)
                host.frame = container.bounds
                host.autoresizingMask = [.width, .height]
                container.addSubview(host, positioned: .above, relativeTo: nil)
                nativeOverlay = host
            }
        } else {
            nativeOverlay?.removeFromSuperview()
            nativeOverlay = nil
        }
    }

    /// Rebuild the SwiftUI shell from scratch. Needed when the language
    /// changes: the shell's views resolve strings at body-eval time but
    /// observe `NativeShellViewModel`, not `Preferences`, so a language flip
    /// alone redraws nothing. Safe to tear down because every piece of shell
    /// state — open section, queue, panels, history stacks — lives on the
    /// view model singleton, not in the view tree.
    func rebuildNativeShell() {
        guard nativeOverlay != nil else { return }
        applyNativeMode(false)
        applyNativeMode(true)
        if clipMode { setClipMode(true) }
    }

    /// Clip mode: bring the WebView (now showing the full-window music video)
    /// ABOVE the SwiftUI shell, or send it back behind. Purely a z-order swap
    /// of the two existing sibling subviews — fully reversible.
    func setClipMode(_ on: Bool) {
        clipMode = on
        guard let container = window?.contentView,
              let webView = WebViewHolder.shared.webView,
              let host = nativeOverlay else { return }
        if on {
            container.addSubview(webView, positioned: .above, relativeTo: host)
        } else {
            container.addSubview(host, positioned: .above, relativeTo: webView)
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
