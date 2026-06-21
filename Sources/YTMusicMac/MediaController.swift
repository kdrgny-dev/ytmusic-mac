import Foundation
import MediaPlayer
import AppKit
import Combine
import UserNotifications

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var artworkURL: String = ""
    var videoId: String = ""
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying: Bool = false
    var volume: Double = 1
    var liked: Bool = false
    var disliked: Bool = false

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

    private var artworkCache: [String: NSImage] = [:]
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
        if cmd == "next", Preferences.shared.nativeUIMode {
            if MainActor.assumeIsolated({
                NativeShellViewModel.shared.consumeOwnQueueNext()
            }) {
                return
            }
        }
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript("window.__ytmCmd && window.__ytmCmd('\(cmd)')", completionHandler: nil)
        }
    }

    /// Run a command that takes a numeric argument (seek, volume).
    func run(_ cmd: String, value: Double) {
        DispatchQueue.main.async {
            WebViewHolder.shared.webView?.evaluateJavaScript("window.__ytmCmd && window.__ytmCmd('\(cmd)', \(value))", completionHandler: nil)
        }
    }

    func updateNowPlaying(info: [String: Any]) {
        let title = info["title"] as? String ?? ""
        let artist = info["artist"] as? String ?? ""
        let playing = info["playing"] as? Bool ?? false
        let dur = info["duration"] as? Double ?? 0
        let cur = info["currentTime"] as? Double ?? 0
        let artURL = info["artwork"] as? String ?? ""

        let newState = NowPlaying(
            title: title,
            artist: artist,
            artworkURL: artURL,
            videoId: info["videoId"] as? String ?? "",
            duration: dur,
            currentTime: cur,
            isPlaying: playing,
            volume: info["volume"] as? Double ?? 1,
            liked: info["liked"] as? Bool ?? false,
            disliked: info["disliked"] as? Bool ?? false
        )

        let trackChanged = newState.hasTrack && newState.trackKey != nowPlaying.trackKey

        DispatchQueue.main.async {
            self.nowPlaying = newState
        }

        publishNowPlaying(newState)

        if !artURL.isEmpty {
            if let cached = artworkCache[artURL] {
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

    private func publishNowPlaying(_ s: NowPlaying) {
        var np: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist,
            MPMediaItemPropertyPlaybackDuration: s.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: s.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: s.isPlaying ? 1.0 : 0.0
        ]
        if let img = artworkCache[s.artworkURL] {
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
            self.artworkCache[urlString] = image
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
