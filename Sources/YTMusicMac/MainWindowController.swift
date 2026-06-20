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

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// NSWindow subclass that intercepts mouse side-buttons before they
    /// reach the responder chain. Going through sendEvent is the only way
    /// to reliably catch button 3 / 4 — NSEvent.addLocalMonitorForEvents
    /// doesn't fire when the hidden WebView's NSResponder grabs the event
    /// first. macOS guarantees sendEvent is called for every event on its
    /// way INTO the window, so this catches them no matter what.
    private final class MouseInterceptingWindow: NSWindow {
        override func sendEvent(_ event: NSEvent) {
            if event.type == .otherMouseDown,
               Preferences.shared.nativeUIMode {
                switch event.buttonNumber {
                case 3:
                    NativeShellViewModel.shared.goBack()
                    return
                case 4, 5:
                    NativeShellViewModel.shared.goForward()
                    return
                default: break
                }
            }
            super.sendEvent(event)
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

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
