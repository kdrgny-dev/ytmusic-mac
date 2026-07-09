import Foundation
import MediaPlayer
import AppKit
import Combine
import UserNotifications

/// Playback position lives on its OWN observable, separate from `NowPlaying`,
/// so the ~per-second time tick doesn't invalidate every view bound to
/// `MediaController` (an `@Published` fires object-level `objectWillChange`,
/// which would re-run e.g. the big playlist's filter+sort every tick). Only
/// the scrubber observes this clock.
final class PlaybackClock: ObservableObject {
    static let shared = PlaybackClock()
    @Published var time: Double = 0
}

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var artworkURL: String = ""
    var videoId: String = ""
    var duration: Double = 0
    var isPlaying: Bool = false
    var volume: Double = 1
    var liked: Bool = false
    var disliked: Bool = false
    var shuffle: Bool = false
    var repeatMode: String = "NONE" // NONE | ALL | ONE
    var hasVideo: Bool = false      // a music-video counterpart is available

    var hasTrack: Bool { !title.isEmpty }
    var trackKey: String { "\(title)|\(artist)" }
}

final class MediaController: ObservableObject {
    static let shared = MediaController()

    @Published private(set) var nowPlaying = NowPlaying()
    @Published private(set) var artwork: NSImage?

    /// Single source of truth for "notify on track change" is Preferences;
    /// expose a passthrough here to keep existing call sites happy.
    var notifyOnTrackChange: Bool { Preferences.shared.notifyOnTrackChange }

    /// Artwork cache. Was a plain `[String: NSImage]` that only ever GREW —
    /// every track's cover stayed forever, so a long session leaked hundreds
    /// of MB. NSCache is bounded (auto-evicts under memory pressure) AND
    /// thread-safe, so it also removes the manual lock the dictionary needed.
    private let artworkCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 80
        c.totalCostLimit = 32 * 1024 * 1024 // ~32 MB of decoded covers
        return c
    }()
    private func cachedArtwork(_ url: String) -> NSImage? {
        artworkCache.object(forKey: url as NSString)
    }
    private func cacheArtwork(_ image: NSImage, for url: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        artworkCache.setObject(image, forKey: url as NSString, cost: cost)
    }
    private var lastArtworkURL: String = ""
    private var lastNotifiedTrackKey: String = ""

    func setup() {
        let cmd = MPRemoteCommandCenter.shared()
        cmd.playCommand.isEnabled = true
        cmd.pauseCommand.isEnabled = true
        cmd.togglePlayPauseCommand.isEnabled = true
        cmd.nextTrackCommand.isEnabled = true
        cmd.previousTrackCommand.isEnabled = true

        cmd.playCommand.addTarget { [weak self] _ in self?.run("playpause"); return .success }
        cmd.pauseCommand.addTarget { [weak self] _ in self?.run("playpause"); return .success }
        cmd.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run("playpause"); return .success }
        cmd.nextTrackCommand.addTarget { [weak self] _ in self?.run("next"); return .success }
        cmd.previousTrackCommand.addTarget { [weak self] _ in self?.run("prev"); return .success }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func run(_ cmd: String) {
        // When the user presses Next in Native Mode and ownQueue has
        // items, consume from OUR queue first instead of letting YT's
        // internal queue take over. This is what "Add to queue" promises:
        // the manually queued tracks play in the order the user picked.
        // MPRemoteCommandCenter does not guarantee the handler fires on the
        // main thread, so we must NOT touch the @MainActor view model here
        // directly — `assumeIsolated` would hard-trap off-main. Hop to main
        // first, then it's safe to consume ownQueue / drive the WebView.
        if cmd == "next", Preferences.shared.nativeUIMode {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if NativeShellViewModel.shared.consumeOwnQueueNext() { return }
                    WebViewHolder.shared.webView?.evaluateJavaScript("window.__ytmCmd && window.__ytmCmd('next')", completionHandler: nil)
                }
            }
            return
        }
        // In Native Mode the WebView is hidden, so clicking YT's own like
        // button is both fragile (the markup keeps moving) and invisible to
        // the user. Go straight to the InnerTube like endpoint instead and
        // paint the heart optimistically.
        if cmd == "like" || cmd == "dislike", Preferences.shared.nativeUIMode {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NativeShellViewModel.shared.toggleNowPlayingLike(dislike: cmd == "dislike")
                }
            }
            return
        }
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript("window.__ytmCmd && window.__ytmCmd('\(cmd)')", completionHandler: nil)
        }
    }

    /// Last-resort like: click YT's own button in the hidden page. Used when
    /// the InnerTube path can't run (no videoId, signed out) or refuses.
    func clickLikeInPage(dislike: Bool) {
        let cmd = dislike ? "dislike" : "like"
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript(
                "window.__ytmCmd && window.__ytmCmd('\(cmd)')", completionHandler: nil)
        }
    }

    /// Run a command that takes a numeric argument (seek, volume).
    func run(_ cmd: String, value: Double) {
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript("window.__ytmCmd && window.__ytmCmd('\(cmd)', \(value))", completionHandler: nil)
        }
    }

    /// Like state we set ourselves via InnerTube. The hidden WebView's DOM
    /// never learns about it, so its `like-status` attribute keeps reporting
    /// the old value and every bridge push would flip the heart back. Held
    /// per videoId and dropped as soon as a different track loads.
    private var likeOverride: (videoId: String, liked: Bool, disliked: Bool)?

    /// Stop pinning the heart and let the page's `like-status` be the truth
    /// again. Called when the API path failed and we handed off to a DOM click.
    func clearLikeOverride() {
        likeOverride = nil
    }

    /// Paint the heart now; `NativeShellViewModel` reverts this if the
    /// network call turns out to have failed.
    func setLikeState(videoId: String, liked: Bool, disliked: Bool) {
        likeOverride = (videoId, liked, disliked)
        DispatchQueue.main.async {
            guard self.nowPlaying.videoId == videoId else { return }
            var s = self.nowPlaying
            s.liked = liked
            s.disliked = disliked
            self.nowPlaying = s
        }
    }

    func updateNowPlaying(info: [String: Any]) {
        let title = info["title"] as? String ?? ""
        let artist = info["artist"] as? String ?? ""
        let playing = info["playing"] as? Bool ?? false
        let dur = info["duration"] as? Double ?? 0
        let cur = info["currentTime"] as? Double ?? 0
        let artURL = info["artwork"] as? String ?? ""

        var newState = NowPlaying(
            title: title,
            artist: artist,
            artworkURL: artURL,
            videoId: info["videoId"] as? String ?? "",
            duration: dur,
            isPlaying: playing,
            volume: info["volume"] as? Double ?? 1,
            liked: info["liked"] as? Bool ?? false,
            disliked: info["disliked"] as? Bool ?? false,
            shuffle: info["shuffle"] as? Bool ?? false,
            repeatMode: info["repeatMode"] as? String ?? "NONE",
            hasVideo: info["hasVideo"] as? Bool ?? false
        )

        if let ov = likeOverride {
            if ov.videoId == newState.videoId {
                newState.liked = ov.liked
                newState.disliked = ov.disliked
            } else if !newState.videoId.isEmpty {
                likeOverride = nil
            }
        }

        let trackChanged = newState.hasTrack && newState.trackKey != nowPlaying.trackKey

        DispatchQueue.main.async {
            // Only republish `nowPlaying` when something OTHER than the clock
            // actually changed — the 4s safety poll used to reassign an equal
            // struct every tick and re-render list views for nothing.
            if self.nowPlaying != newState { self.nowPlaying = newState }
            PlaybackClock.shared.time = cur
        }

        publishNowPlaying(newState, currentTime: cur)

        if !artURL.isEmpty {
            if let cached = cachedArtwork(artURL) {
                DispatchQueue.main.async {
                    if self.artwork !== cached { self.artwork = cached }
                }
                attachArtwork(cached, to: newState)
            } else if artURL != lastArtworkURL {
                lastArtworkURL = artURL
                loadArtwork(urlString: artURL) { [weak self] image in
                    guard let self = self, let image = image else { return }
                    self.artwork = image
                    self.attachArtwork(image, to: newState)
                    if trackChanged && self.notifyOnTrackChange {
                        self.postTrackNotification(newState, image: image)
                    }
                }
            }
        }

        if trackChanged && notifyOnTrackChange && lastNotifiedTrackKey != newState.trackKey {
            lastNotifiedTrackKey = newState.trackKey
            // Notification with artwork is fired from loadArtwork completion above;
            // also post a text-only one immediately in case artwork load is slow.
            postTrackNotification(newState, image: nil)
        }
    }

    private func publishNowPlaying(_ s: NowPlaying, currentTime: Double) {
        var np: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPMediaItemPropertyPlaybackDuration: s.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: s.isPlaying ? 1.0 : 0.0
        ]
        if let img = cachedArtwork(s.artworkURL) {
            np[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = np
        center.playbackState = s.isPlaying ? .playing : .paused
    }

    private func attachArtwork(_ image: NSImage, to s: NowPlaying) {
        var np = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        np[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = np
    }

    private func loadArtwork(urlString: String, completion: @escaping (NSImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.cacheArtwork(image, for: urlString)
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    private func postTrackNotification(_ s: NowPlaying, image: NSImage?) {
        let content = UNMutableNotificationContent()
        content.title = s.title
        content.body = s.artist
        content.sound = nil

        if let image = image, let attachment = makeNotificationAttachment(image) {
            content.attachments = [attachment]
        }

        let req = UNNotificationRequest(identifier: "track-\(s.trackKey)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func makeNotificationAttachment(_ image: NSImage) -> UNNotificationAttachment? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ytm-art-\(UUID().uuidString).png")
        do {
            try png.write(to: tmp)
            return try UNNotificationAttachment(identifier: "art", url: tmp, options: nil)
        } catch {
            return nil
        }
    }
}
