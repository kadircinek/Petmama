#if canImport(UIKit)
import CoreLocation
import MamaCore

/// CoreLocation tabanlı `LocationDriver`. Yalnızca "Uygulamayı kullanırken" izni (PRD 7.1).
@MainActor
final class CoreLocationDriver: NSObject, LocationDriver {
    var onUpdate: ((Coordinate) -> Void)?

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var locationWaiters: [CheckedContinuation<Coordinate?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Sokak ölçeğinde gereksiz güncellemeleri önle.
        manager.distanceFilter = 15
    }

    var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> Coordinate? {
        guard authorization == .authorized else { return nil }
        if let location = manager.location, abs(location.timestamp.timeIntervalSinceNow) < 15 {
            return Coordinate(location.coordinate)
        }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
    }

    func startUpdating() {
        guard authorization == .authorized else { return }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private func resolveLocationWaiters(with coordinate: Coordinate?) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: coordinate) }
    }
}

extension CoreLocationDriver: CLLocationManagerDelegate {
    // CLLocationManager delegate'i oluşturulduğu (ana) iş parçacığında çağırır.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let status = self.authorization
            guard status != .notDetermined else { return }
            let waiters = self.authorizationWaiters
            self.authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: status) }
            if status == .authorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(last.coordinate)
        MainActor.assumeIsolated {
            self.onUpdate?(coordinate)
            self.resolveLocationWaiters(with: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.resolveLocationWaiters(with: self.manager.location.map { Coordinate($0.coordinate) })
        }
    }
}
#endif
