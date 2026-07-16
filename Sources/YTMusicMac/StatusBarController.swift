import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSMenuDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var trackItem: NSMenuItem?
    private var playPauseItem: NSMenuItem?
    private var notifyToggleItem: NSMenuItem?
    private var sleepItem: NSMenuItem?
    private var memoryItem: NSMenuItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YouTube Music")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        }
        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item

        MediaController.shared.$nowPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] np in self?.refresh(with: np) }
            .store(in: &cancellables)

        Preferences.shared.$notifyOnTrackChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.notifyToggleItem?.state = on ? .on : .off }
            .store(in: &cancellables)

        SleepTimer.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshSleepLabel() }
            .store(in: &cancellables)
    }

    /// Throw the menu away and build a new one in the current language.
    /// NSMenuItem titles are baked in at build time, so translating them in
    /// place isn't possible.
    func rebuildMenu() {
        guard let statusItem else { return }
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
        // The Combine sinks that normally seed these fired once at install
        // and won't fire again just because the language changed.
        refresh(with: MediaController.shared.nowPlaying)
        refreshSleepLabel()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let track = NSMenuItem(title: L10n.t("status.notPlaying"), action: nil, keyEquivalent: "")
        track.isEnabled = false
        menu.addItem(track)
        trackItem = track

        menu.addItem(.separator())

        let pp = NSMenuItem(title: L10n.t("transport.play"), action: #selector(StatusActions.playPause), keyEquivalent: "")
        pp.target = StatusActions.shared
        menu.addItem(pp)
        playPauseItem = pp

        let next = NSMenuItem(title: L10n.t("transport.next"), action: #selector(StatusActions.next), keyEquivalent: "")
        next.target = StatusActions.shared
        menu.addItem(next)

        let prev = NSMenuItem(title: L10n.t("transport.prev"), action: #selector(StatusActions.prev), keyEquivalent: "")
        prev.target = StatusActions.shared
        menu.addItem(prev)

        menu.addItem(.separator())

        let main = NSMenuItem(title: L10n.t("status.showMainWindow"), action: #selector(StatusActions.showMain), keyEquivalent: "")
        main.target = StatusActions.shared
        menu.addItem(main)

        let mini = NSMenuItem(title: L10n.t("status.showMiniPlayer"), action: #selector(StatusActions.showMini), keyEquivalent: "")
        mini.target = StatusActions.shared
        menu.addItem(mini)

        menu.addItem(.separator())

        let notify = NSMenuItem(title: L10n.t("status.notifyOnTrackChange"), action: #selector(StatusActions.toggleNotify), keyEquivalent: "")
        notify.target = StatusActions.shared
        // Seeded here rather than relying on the Combine sink, which only
        // fires on install — a rebuilt menu would otherwise lose the checkmark.
        notify.state = Preferences.shared.notifyOnTrackChange ? .on : .off
        menu.addItem(notify)
        notifyToggleItem = notify

        let sleep = NSMenuItem(title: L10n.t("sleep.title"), action: nil, keyEquivalent: "")
        sleep.submenu = buildSleepSubmenu()
        menu.addItem(sleep)
        sleepItem = sleep

        menu.addItem(.separator())

        let memory = NSMenuItem(title: L10n.t("status.memory", "…"), action: nil, keyEquivalent: "")
        memory.isEnabled = false
        menu.addItem(memory)
        memoryItem = memory

        menu.addItem(.separator())

        menu.addItem(AppDelegate.settingsMenuItem())

        let quit = NSMenuItem(title: L10n.t("menu.app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    // MARK: - NSMenuDelegate

    /// Refresh the memory line just before the menu draws. Avoids burning
    /// a timer in the background just to keep that one line live.
    func menuWillOpen(_ menu: NSMenu) {
        memoryItem?.title = L10n.t("status.memory", MemoryDiagnostic.summary())
    }

    private func buildSleepSubmenu() -> NSMenu {
        let m = NSMenu()
        let options: [(String, SleepTimer.Mode)] = [
            (L10n.plural("sleep.minutes", 5),  .duration(5 * 60)),
            (L10n.plural("sleep.minutes", 15), .duration(15 * 60)),
            (L10n.plural("sleep.minutes", 30), .duration(30 * 60)),
            (L10n.plural("sleep.hours", 1),    .duration(60 * 60)),
            (L10n.t("sleep.endOfTrack"),       .endOfTrack),
        ]
        for (label, mode) in options {
            let it = NSMenuItem(title: label, action: #selector(StatusActions.startSleep(_:)), keyEquivalent: "")
            it.target = StatusActions.shared
            it.representedObject = mode
            m.addItem(it)
        }
        m.addItem(.separator())
        let cancel = NSMenuItem(title: L10n.t("common.cancel"), action: #selector(StatusActions.cancelSleep), keyEquivalent: "")
        cancel.target = StatusActions.shared
        m.addItem(cancel)
        return m
    }

    private func refreshSleepLabel() {
        guard let sleepItem = sleepItem else { return }
        if let r = SleepTimer.shared.remaining, SleepTimer.shared.isActive {
            let mm = Int(r) / 60, ss = Int(r) % 60
            sleepItem.title = L10n.t("sleep.countdown", "\(mm):" + String(format: "%02d", ss))
        } else if case .endOfTrack? = SleepTimer.shared.mode {
            sleepItem.title = L10n.t("sleep.activeEndOfTrack")
        } else {
            sleepItem.title = L10n.t("sleep.title")
        }
    }

    private func refresh(with np: NowPlaying) {
        guard let button = statusItem?.button else { return }

        if np.hasTrack {
            let menuTitle = np.title.count > 40 ? String(np.title.prefix(40)) + "…" : np.title
            let menuArtist = np.artist.count > 30 ? String(np.artist.prefix(30)) + "…" : np.artist
            trackItem?.title = "\(menuTitle) — \(menuArtist)"
            button.title = " " + Self.compact("\(np.title) — \(np.artist)", max: 45)
            button.toolTip = "\(np.title) — \(np.artist)"
        } else {
            trackItem?.title = L10n.t("status.notPlaying")
            button.title = ""
            button.toolTip = "YouTube Music"
        }
        playPauseItem?.title = L10n.t(np.isPlaying ? "transport.pause" : "transport.play")
    }

    /// Trims runs of whitespace then truncates with an ellipsis. We're
    /// stingier than the dropdown menu because horizontal menu-bar space
    /// is shared with every other app.
    private static func compact(_ s: String, max: Int) -> String {
        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if collapsed.count <= max { return collapsed }
        return String(collapsed.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Cocoa selector targets need an NSObject; using a tiny shared instance.
final class StatusActions: NSObject {
    static let shared = StatusActions()

    @objc func playPause() { MediaController.shared.run("playpause") }
    @objc func next()      { MediaController.shared.run("next") }
    @objc func prev()      { MediaController.shared.run("prev") }
    @objc func togglePlayerPage() { MediaController.shared.run("togglePlayer") }
    @objc func like()    { MediaController.shared.run("like") }
    @objc func shuffle() { MediaController.shared.run("shuffle") }
    @objc func repeatMode() { MediaController.shared.run("repeat") }
    @objc func seekForward()  { MediaController.shared.run("seek", value: PlaybackClock.shared.time + 10) }
    @objc func seekBackward() { MediaController.shared.run("seek", value: max(0, PlaybackClock.shared.time - 10)) }

    @objc func showMain() {
        DispatchQueue.main.async {
            MainWindowController.shared.show()
        }
    }

    @objc func showMini() {
        MiniPlayerWindowController.shared.show()
    }

    @objc func toggleNotify() {
        Preferences.shared.notifyOnTrackChange.toggle()
    }

    @objc func startSleep(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? SleepTimer.Mode {
            SleepTimer.shared.start(mode)
        }
    }

    @objc func cancelSleep() {
        SleepTimer.shared.cancel()
    }
}

enum WindowID: String {
    case main = "main"
    case mini = "mini"
}
