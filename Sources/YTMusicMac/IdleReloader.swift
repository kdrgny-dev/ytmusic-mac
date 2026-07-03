import Foundation
import Combine

/// Auto-reloads the WebView when playback has been paused for a long time.
///
/// Why: WKWebView running music.youtube.com accumulates DOM, image cache,
/// and Polymer view state over a long listening session. A soft reload
/// clears all of that without dropping cookies (HTTPCookieStorage persists)
/// — so login stays, accumulated memory goes away.
///
/// Trigger: nowPlaying.isPlaying flips to false and stays false for the
/// idle threshold (default 30 min). If the user comes back and plays
/// something before the timer fires, we cancel.
@MainActor
final class IdleReloader {
    static let shared = IdleReloader()

    /// User configurable in Preferences; defaults to 30 minutes.
    var idleThreshold: TimeInterval = 30 * 60

    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var wasPlaying = false

    func start() {
        MediaController.shared.$nowPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] np in self?.handlePlayState(np.isPlaying) }
            .store(in: &cancellables)
    }

    private func handlePlayState(_ playing: Bool) {
        guard Preferences.shared.autoReloadOnIdle else {
            timer?.invalidate(); timer = nil
            wasPlaying = playing
            return
        }
        if playing {
            // Cancel any pending reload — user is back.
            timer?.invalidate()
            timer = nil
        } else if wasPlaying || timer == nil {
            // Just paused (or app launched paused) — schedule reload.
            scheduleReload()
        }
        wasPlaying = playing
    }

    private func scheduleReload() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.fire() }
        }
    }

    private func fire() {
        guard !MediaController.shared.nowPlaying.isPlaying else { return }
        // Suppress autoplay so the reload doesn't spontaneously resume the
        // current /watch track in the background.
        WebViewHolder.shared.reloadSuppressingAutoplay()
        timer = nil
    }
}
