import AppKit
import SwiftUI

/// Manual settings window. We don't use SwiftUI's `Settings` scene because
/// the `showSettingsWindow:` / `showPreferencesWindow:` selectors don't get
/// hooked up reliably when we install our own `NSApp.mainMenu`.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func build() {
        let hosting = NSHostingController(rootView: SettingsView())
        let w = NSWindow(contentViewController: hosting)
        w.title = L10n.t("settings.windowTitle")
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.identifier = NSUserInterfaceItemIdentifier("settings")
        window = w
    }
}
