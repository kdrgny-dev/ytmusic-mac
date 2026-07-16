import AppKit

/// Re-renders everything that caches a translated string, so switching
/// language takes effect without a restart.
///
/// SwiftUI views that observe `Preferences.shared` redraw on their own (the
/// Settings window does). Two things don't, and this exists for them:
///   - the native shell, whose views observe `NativeShellViewModel`, not prefs
///   - every AppKit menu, which holds `NSMenuItem.title` strings that were
///     resolved once at build time and never re-read
enum LanguageBridge {
    @MainActor
    static func apply() {
        L10n.reload()
        // Shell state (open page, queue, panels) lives on the VM singleton,
        // so tearing the hosting view down and back up is not destructive.
        MainWindowController.shared.rebuildNativeShell()
        (NSApp.delegate as? AppDelegate)?.rebuildMainMenu()
        StatusBarController.shared.rebuildMenu()
        // Language is also InnerTube's `hl`, so YT's own shelf and genre
        // titles are now stale in the previous language.
        NativeShellViewModel.shared.reloadLocalizedContent()
    }
}
