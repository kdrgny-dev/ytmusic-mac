import Foundation
import Network
import Combine

/// Live network reachability. Without this the app can only infer "offline"
/// from a failed request, which means a page that happens to have cached
/// content looks perfectly healthy while nothing else in the app works.
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ytmusicmac.connection")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
