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
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.identifier = NSUserInterfaceItemIdentifier(WindowID.main.rawValue)
        w.title = "YouTube Music"
        w.minSize = NSSize(width: 800, height: 500)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setFrameAutosaveName(frameAutosaveName)
        w.center()

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
