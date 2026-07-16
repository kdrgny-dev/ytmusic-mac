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
        UpdateChecker.shared.startPeriodicChecks()
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

    func applicationWillTerminate(_ notification: Notification) {
        MediaController.shared.flushHistory()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return false
    }

    // MARK: - Dock menu (right-click the Dock icon)

    /// AppKit rebuilds this every time the Dock menu is shown, so we can read
    /// the live playback state to pick the Play/Pause label and show the
    /// current track. Items are appended ABOVE AppKit's standard entries
    /// (Show All Windows / Hide / Quit).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let np = MediaController.shared.nowPlaying

        if np.hasTrack {
            let header = NSMenuItem(title: np.artist.isEmpty ? np.title : "\(np.title) — \(np.artist)",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        let playPause = NSMenuItem(title: L10n.t(np.isPlaying ? "transport.pause" : "transport.play"),
                                   action: #selector(dockPlayPause), keyEquivalent: "")
        playPause.target = self
        menu.addItem(playPause)

        let next = NSMenuItem(title: L10n.t("transport.next"), action: #selector(dockNext), keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let prev = NSMenuItem(title: L10n.t("transport.prev"), action: #selector(dockPrev), keyEquivalent: "")
        prev.target = self
        menu.addItem(prev)

        if np.hasTrack {
            menu.addItem(.separator())
            let like = NSMenuItem(title: L10n.t(np.liked ? "transport.unlike" : "transport.like"),
                                  action: #selector(dockLike), keyEquivalent: "")
            like.target = self
            menu.addItem(like)
        }

        return menu
    }

    @objc private func dockPlayPause() { MediaController.shared.run("playpause") }
    @objc private func dockNext()      { MediaController.shared.run("next") }
    @objc private func dockPrev()      { MediaController.shared.run("prev") }
    @objc private func dockLike()      { MediaController.shared.run("like") }

    /// Rebuilds the whole main menu in the current language. NSMenuItem titles
    /// are resolved once at build time and never re-read, so a language change
    /// has to throw the menu away and construct a new one.
    func rebuildMainMenu() { buildMainMenu() }

    /// Builds the app's main menu from scratch. We don't use SwiftUI's
    /// `.commands` modifier because we don't have a SwiftUI window-bearing
    /// scene anymore.
    private func buildMainMenu() {
        let main = NSMenu()

        // ----- App menu -----
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "YouTube Music")
        appMenu.addItem(withTitle: L10n.t("menu.app.about"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let update = NSMenuItem(title: L10n.t("menu.app.checkUpdates"),
                                action: #selector(AppActions.checkForUpdates),
                                keyEquivalent: "")
        update.target = AppActions.shared
        appMenu.addItem(update)
        appMenu.addItem(.separator())
        appMenu.addItem(settingsMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.app.hide"),
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L10n.t("menu.app.hideOthers"),
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L10n.t("menu.app.showAll"),
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.app.quit"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // ----- Edit menu (needed for cut/copy/paste in WKWebView text fields) -----
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.t("menu.edit.title"))
        editMenu.addItem(withTitle: L10n.t("menu.edit.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: L10n.t("menu.edit.redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("menu.edit.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("menu.edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("menu.edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("menu.edit.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // ----- Controls menu -----
        let ctrlItem = NSMenuItem()
        let ctrl = NSMenu(title: L10n.t("menu.controls.title"))
        ctrl.addItem(item(L10n.t("menu.controls.playPause"), #selector(StatusActions.playPause), target: StatusActions.shared, key: " "))
        ctrl.addItem(item(L10n.t("menu.controls.next"), #selector(StatusActions.next), target: StatusActions.shared,
                          key: String(UnicodeScalar(NSRightArrowFunctionKey)!)))
        ctrl.addItem(item(L10n.t("menu.controls.prev"), #selector(StatusActions.prev), target: StatusActions.shared,
                          key: String(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        ctrl.addItem(item(L10n.t("menu.controls.seekForward"), #selector(StatusActions.seekForward), target: StatusActions.shared,
                          key: String(UnicodeScalar(NSRightArrowFunctionKey)!), mods: [.option]))
        ctrl.addItem(item(L10n.t("menu.controls.seekBackward"), #selector(StatusActions.seekBackward), target: StatusActions.shared,
                          key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), mods: [.option]))
        ctrl.addItem(.separator())
        ctrl.addItem(item(L10n.t("menu.controls.like"), #selector(StatusActions.like), target: StatusActions.shared,
                          key: "l", mods: [.command]))
        ctrl.addItem(item(L10n.t("menu.controls.shuffle"), #selector(StatusActions.shuffle), target: StatusActions.shared,
                          key: "s", mods: [.command, .control]))
        ctrl.addItem(item(L10n.t("menu.controls.repeat"), #selector(StatusActions.repeatMode), target: StatusActions.shared,
                          key: "r", mods: [.command, .control]))
        ctrl.addItem(.separator())
        ctrl.addItem(item(L10n.t("menu.controls.nowPlaying"), #selector(AppActions.toggleNowPlaying),
                          target: AppActions.shared, key: "f", mods: [.command]))
        ctrl.addItem(.separator())
        ctrl.addItem(item(L10n.t("menu.controls.focusSearch"), #selector(AppActions.focusSearch), target: AppActions.shared,
                          key: "k", mods: [.command]))
        ctrl.addItem(item(L10n.t("menu.controls.toggleQueue"), #selector(AppActions.toggleQueue), target: AppActions.shared,
                          key: "e", mods: [.command]))
        ctrl.addItem(item(L10n.t("menu.controls.toggleLyrics"), #selector(AppActions.toggleLyrics), target: AppActions.shared,
                          key: "y", mods: [.command]))
        ctrl.addItem(.separator())
        // Cmd+Left / Cmd+Right — Safari's other standard for back/forward,
        // and the only one that survives non-US keyboard layouts (on a
        // Turkish-Q `[` maps to `Ğ` and `]` to `Ü`, which is why the
        // bracket shortcuts looked nonsense).
        ctrl.addItem(item(L10n.t("menu.controls.back"), #selector(AppActions.goBack), target: AppActions.shared,
                          key: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                          mods: [.command]))
        ctrl.addItem(item(L10n.t("menu.controls.forward"), #selector(AppActions.goForward), target: AppActions.shared,
                          key: String(UnicodeScalar(NSRightArrowFunctionKey)!),
                          mods: [.command]))
        ctrl.addItem(item(L10n.t("menu.controls.reload"), #selector(AppActions.reload), target: AppActions.shared,
                          key: "r", mods: [.command]))
        ctrl.addItem(.separator())
        ctrl.addItem(item(L10n.t("menu.controls.clearData"), #selector(AppActions.clearData), target: AppActions.shared,
                          key: "\u{8}", mods: [.command, .shift])) // ⌫
        ctrlItem.submenu = ctrl
        main.addItem(ctrlItem)

        // ----- Window menu -----
        let winItem = NSMenuItem()
        let win = NSMenu(title: L10n.t("menu.window.title"))
        win.addItem(withTitle: L10n.t("menu.window.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: L10n.t("menu.window.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(.separator())
        win.addItem(item(L10n.t("menu.window.main"), #selector(StatusActions.showMain), target: StatusActions.shared,
                         key: "0", mods: [.command]))
        win.addItem(item(L10n.t("menu.window.mini"), #selector(StatusActions.showMini), target: StatusActions.shared,
                         key: "m", mods: [.command, .shift]))
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
    }

    /// Builds the Settings menu item. We target our own SettingsWindowController
    /// because SwiftUI's system selectors don't reliably hook in when we own
    /// the main menu manually.
    static func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.t("menu.app.settings"),
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

    /// Manual check from the app menu. Unlike the periodic one this always
    /// says something, so "nothing happened" can't be mistaken for a failure.
    @objc func checkForUpdates() {
        Task { @MainActor in
            let found = await UpdateChecker.shared.check()
            let alert = NSAlert()
            if let found {
                alert.messageText = L10n.t("update.available", found.version)
                alert.informativeText = found.notes ?? ""
                alert.addButton(withTitle: L10n.t("update.download"))
                alert.addButton(withTitle: L10n.t("update.later"))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(found.downloadURL)
                }
            } else {
                alert.messageText = L10n.t("update.upToDate")
                alert.informativeText = L10n.t("update.installedVersion", UpdateChecker.shared.currentVersion)
                alert.addButton(withTitle: L10n.t("update.ok"))
                alert.runModal()
            }
        }
    }
    @objc func focusSearch() {
        // In Native Mode the WebView is hidden, so focusing YT's own search
        // box accomplishes nothing the user can see. Route to the SwiftUI
        // overlay instead. Outside Native Mode keep the legacy behaviour.
        if Preferences.shared.nativeUIMode {
            Task { @MainActor in NativeShellViewModel.shared.goSearch() }
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
    @objc func toggleLyrics() {
        Task { @MainActor in NativeShellViewModel.shared.toggleLyrics() }
    }
    @objc func toggleNowPlaying() {
        Task { @MainActor in NativeShellViewModel.shared.toggleNowPlaying() }
    }
    @objc func goBack() {
        Task { @MainActor in NativeShellViewModel.shared.goBack() }
    }
    @objc func goForward() {
        Task { @MainActor in NativeShellViewModel.shared.goForward() }
    }
}
