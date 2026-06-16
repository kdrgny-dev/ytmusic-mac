import AppKit
import WebKit

/// Single-instance controller for the app's main window. Manages an NSWindow
/// directly (not SwiftUI WindowGroup) so we have full control over close
/// (hide-don't-destroy) and reopen (always the same window, never a duplicate).
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private let frameAutosaveName = "YTMusicMacMainWindow"

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        // Plain titled window — NO fullSizeContentView, because YT Music's
        // popup dialogs (edit playlist cover, etc.) need the top of the
        // content area to be unobstructed by the title bar/traffic lights.
        let w = NSWindow(
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

        // Host the singleton WebView directly as the window's content view.
        let webView = WebViewHolder.shared.obtain()
        webView.removeFromSuperview()
        w.contentView = webView

        window = w
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
