import SwiftUI
import AppKit

@main
struct YTMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All real windows are NSWindow-managed. Settings is a placeholder
        // to satisfy SwiftUI's "App needs at least one Scene" requirement.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Held onto so the monitor stays alive for the app's lifetime.
    /// Apple's docs say to keep the returned token — otherwise the
    /// runtime is free to release it and stop delivering events.
    private var mouseNavLocalMonitor: Any?
    private var mouseNavGlobalMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        MediaController.shared.setup()
        StatusBarController.shared.install()
        GlobalHotkeys.shared.install()
        IdleReloader.shared.start()
        installMouseNavMonitor()
        buildMainMenu()
        MainWindowController.shared.show()
    }

    /// Hook up mouse side-buttons to Native Mode's back / forward history.
    /// We register BOTH a local monitor (events dispatched to our app)
    /// AND a global monitor (events that go elsewhere — needed when the
    /// hidden WebView's NSResponder chain swallows mouse 4/5 before
    /// SwiftUI sees it). Both monitors map button 3 → back, button 4 → fwd.
    private func installMouseNavMonitor() {
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]

        mouseNavLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .otherMouseDown, self.handleSideButton(event) {
                return nil   // swallow so the WebView underneath doesn't navigate too
            }
            return event
        }

        mouseNavGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self else { return }
            if event.type == .otherMouseDown { _ = self.handleSideButton(event) }
        }
    }

    /// True if we acted on this event so the local monitor can swallow it.
    @discardableResult
    private func handleSideButton(_ event: NSEvent) -> Bool {
        guard Preferences.shared.nativeUIMode else { return false }
        let btn = event.buttonNumber
        // Standard macOS convention: button 3 = back, button 4 = forward.
        // Some drivers (rare) use 4/5 instead — we treat button 5 as fwd
        // and keep button 4 as either depending on whether we saw a 3 first.
        switch btn {
        case 3:
            Task { @MainActor in NativeShellViewModel.shared.goBack() }
            return true
        case 4:
            Task { @MainActor in NativeShellViewModel.shared.goForward() }
            return true
        case 5:
            Task { @MainActor in NativeShellViewModel.shared.goForward() }
            return true
        default:
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return false
    }

    /// Builds the app's main menu from scratch. We don't use SwiftUI's
    /// `.commands` modifier because we don't have a SwiftUI window-bearing
    /// scene anymore.
    private func buildMainMenu() {
        let main = NSMenu()

        // ----- App menu -----
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "YouTube Music")
        appMenu.addItem(withTitle: "About YouTube Music",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(settingsMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide YouTube Music",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit YouTube Music",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // ----- Edit menu (needed for cut/copy/paste in WKWebView text fields) -----
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // ----- Controls menu -----
        let ctrlItem = NSMenuItem()
        let ctrl = NSMenu(title: "Controls")
        ctrl.addItem(item("Play / Pause", #selector(StatusActions.playPause), target: StatusActions.shared, key: " "))
        ctrl.addItem(item("Next Track", #selector(StatusActions.next), target: StatusActions.shared,
                          key: String(UnicodeScalar(NSRightArrowFunctionKey)!)))
        ctrl.addItem(item("Previous Track", #selector(StatusActions.prev), target: StatusActions.shared,
                          key: String(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        ctrl.addItem(.separator())
        ctrl.addItem(item("Toggle Fullscreen Player", #selector(StatusActions.togglePlayerPage),
                          target: StatusActions.shared, key: "f", mods: [.command]))
        ctrl.addItem(.separator())
        ctrl.addItem(item("Focus Search", #selector(AppActions.focusSearch), target: AppActions.shared,
                          key: "k", mods: [.command]))
        ctrl.addItem(item("Toggle Queue Panel", #selector(AppActions.toggleQueue), target: AppActions.shared,
                          key: "e", mods: [.command]))
        ctrl.addItem(.separator())
        // Cmd+Left / Cmd+Right — Safari's other standard for back/forward,
        // and the only one that survives non-US keyboard layouts (on a
        // Turkish-Q `[` maps to `Ğ` and `]` to `Ü`, which is why the
        // bracket shortcuts looked nonsense).
        ctrl.addItem(item("Back", #selector(AppActions.goBack), target: AppActions.shared,
                          key: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                          mods: [.command]))
        ctrl.addItem(item("Forward", #selector(AppActions.goForward), target: AppActions.shared,
                          key: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                          mods: [.command]))
        ctrl.addItem(item("Reload", #selector(AppActions.reload), target: AppActions.shared,
                          key: "r", mods: [.command]))
        ctrl.addItem(.separator())
        ctrl.addItem(item("Sign Out & Clear Data", #selector(AppActions.clearData), target: AppActions.shared,
                          key: "\u{8}", mods: [.command, .shift])) // ⌫
        ctrlItem.submenu = ctrl
        main.addItem(ctrlItem)

        // ----- Window menu -----
        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(.separator())
        win.addItem(item("Main Window", #selector(StatusActions.showMain), target: StatusActions.shared,
                         key: "0", mods: [.command]))
        win.addItem(item("Mini Player", #selector(StatusActions.showMini), target: StatusActions.shared,
                         key: "m", mods: [.command, .shift]))
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
    }

    /// Builds the Settings menu item. We target our own SettingsWindowController
    /// because SwiftUI's system selectors don't reliably hook in when we own
    /// the main menu manually.
    static func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…",
                              action: #selector(AppActions.openSettings),
                              keyEquivalent: ",")
        item.target = AppActions.shared
        return item
    }

    private func settingsMenuItem() -> NSMenuItem { Self.settingsMenuItem() }

    private func item(_ title: String,
                      _ action: Selector,
                      target: AnyObject,
                      key: String,
                      mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = target
        return item
    }
}

/// Selector targets for menu items that don't belong on StatusActions.
final class AppActions: NSObject {
    static let shared = AppActions()
    @objc func focusSearch() {
        // In Native Mode the WebView is hidden, so focusing YT's own search
        // box accomplishes nothing the user can see. Route to the SwiftUI
        // overlay instead. Outside Native Mode keep the legacy behaviour.
        if Preferences.shared.nativeUIMode {
            Task { @MainActor in NativeShellViewModel.shared.toggleSearch() }
        } else {
            WebViewHolder.shared.focusSearch()
        }
    }
    @objc func reload() { WebViewHolder.shared.reload() }
    @objc func clearData() { WebViewHolder.shared.clearAllData() }
    @objc func openSettings() { SettingsWindowController.shared.show() }
    @objc func toggleQueue() {
        Task { @MainActor in NativeShellViewModel.shared.toggleQueue() }
    }
    @objc func goBack() {
        Task { @MainActor in NativeShellViewModel.shared.goBack() }
    }
    @objc func goForward() {
        Task { @MainActor in NativeShellViewModel.shared.goForward() }
    }
}
