import AppKit
import Combine
import SwiftUI

final class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var trackItem: NSMenuItem?
    private var playPauseItem: NSMenuItem?
    private var notifyToggleItem: NSMenuItem?
    private var sleepItem: NSMenuItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YouTube Music")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        }
        item.menu = buildMenu()
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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let track = NSMenuItem(title: "Not Playing", action: nil, keyEquivalent: "")
        track.isEnabled = false
        menu.addItem(track)
        trackItem = track

        menu.addItem(.separator())

        let pp = NSMenuItem(title: "Play", action: #selector(StatusActions.playPause), keyEquivalent: "")
        pp.target = StatusActions.shared
        menu.addItem(pp)
        playPauseItem = pp

        let next = NSMenuItem(title: "Next", action: #selector(StatusActions.next), keyEquivalent: "")
        next.target = StatusActions.shared
        menu.addItem(next)

        let prev = NSMenuItem(title: "Previous", action: #selector(StatusActions.prev), keyEquivalent: "")
        prev.target = StatusActions.shared
        menu.addItem(prev)

        menu.addItem(.separator())

        let main = NSMenuItem(title: "Show Main Window", action: #selector(StatusActions.showMain), keyEquivalent: "")
        main.target = StatusActions.shared
        menu.addItem(main)

        let mini = NSMenuItem(title: "Show Mini Player", action: #selector(StatusActions.showMini), keyEquivalent: "")
        mini.target = StatusActions.shared
        menu.addItem(mini)

        menu.addItem(.separator())

        let notify = NSMenuItem(title: "Notify on Track Change", action: #selector(StatusActions.toggleNotify), keyEquivalent: "")
        notify.target = StatusActions.shared
        menu.addItem(notify)
        notifyToggleItem = notify

        let sleep = NSMenuItem(title: "Sleep Timer", action: nil, keyEquivalent: "")
        sleep.submenu = buildSleepSubmenu()
        menu.addItem(sleep)
        sleepItem = sleep

        menu.addItem(.separator())

        menu.addItem(AppDelegate.settingsMenuItem())

        let quit = NSMenuItem(title: "Quit YouTube Music", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private func buildSleepSubmenu() -> NSMenu {
        let m = NSMenu()
        let options: [(String, SleepTimer.Mode)] = [
            ("5 minutes",  .duration(5 * 60)),
            ("15 minutes", .duration(15 * 60)),
            ("30 minutes", .duration(30 * 60)),
            ("1 hour",     .duration(60 * 60)),
            ("End of current track", .endOfTrack),
        ]
        for (label, mode) in options {
            let it = NSMenuItem(title: label, action: #selector(StatusActions.startSleep(_:)), keyEquivalent: "")
            it.target = StatusActions.shared
            it.representedObject = mode
            m.addItem(it)
        }
        m.addItem(.separator())
        let cancel = NSMenuItem(title: "Cancel", action: #selector(StatusActions.cancelSleep), keyEquivalent: "")
        cancel.target = StatusActions.shared
        m.addItem(cancel)
        return m
    }

    private func refreshSleepLabel() {
        guard let sleepItem = sleepItem else { return }
        if let r = SleepTimer.shared.remaining, SleepTimer.shared.isActive {
            let mm = Int(r) / 60, ss = Int(r) % 60
            sleepItem.title = "Sleep Timer — \(mm):" + String(format: "%02d", ss)
        } else if case .endOfTrack? = SleepTimer.shared.mode {
            sleepItem.title = "Sleep Timer — end of track"
        } else {
            sleepItem.title = "Sleep Timer"
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
            trackItem?.title = "Not Playing"
            button.title = ""
            button.toolTip = "YouTube Music"
        }
        playPauseItem?.title = np.isPlaying ? "Pause" : "Play"
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
