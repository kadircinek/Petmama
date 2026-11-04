#if canImport(Network)
import Foundation
import Network
import Observation

/// Bağlantı geri geldiğinde çevrimdışı check-in kuyruğunu boşaltmak için (FR-H8).
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "mama.connectivity")
    @ObservationIgnored var onReconnect: (() -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reconnected = online && !self.isOnline
                self.isOnline = online
                if reconnected { self.onReconnect?() }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
#endif
