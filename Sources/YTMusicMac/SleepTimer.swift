import Foundation
import Combine

/// Pauses playback after a fixed duration or at the end of the current track.
/// Exposed as an ObservableObject so menus can show the live countdown.
final class SleepTimer: ObservableObject {
    static let shared = SleepTimer()

    enum Mode { case duration(TimeInterval); case endOfTrack }

    @Published private(set) var endsAt: Date?
    @Published private(set) var mode: Mode?

    private var timer: Timer?
    private var trackObservation: AnyCancellable?
    private var initialTrackKey: String?

    var isActive: Bool { mode != nil }

    var remaining: TimeInterval? {
        guard let endsAt = endsAt else { return nil }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    func start(_ mode: Mode) {
        cancel()
        self.mode = mode
        switch mode {
        case .duration(let secs):
            endsAt = Date().addingTimeInterval(secs)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self, let r = self.remaining else { return }
                self.objectWillChange.send()
                if r <= 0.5 { self.fire() }
            }
        case .endOfTrack:
            initialTrackKey = MediaController.shared.nowPlaying.trackKey
            trackObservation = MediaController.shared.$nowPlaying
                .receive(on: DispatchQueue.main)
                .sink { [weak self] np in
                    guard let self = self else { return }
                    // Fire when the track key changes to something different.
                    if np.hasTrack && np.trackKey != self.initialTrackKey {
                        self.fire()
                    }
                }
        }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        trackObservation?.cancel(); trackObservation = nil
        endsAt = nil
        mode = nil
        initialTrackKey = nil
    }

    private func fire() {
        if MediaController.shared.nowPlaying.isPlaying {
            MediaController.shared.run("playpause")
        }
        cancel()
    }
}
