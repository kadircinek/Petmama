import Foundation
import Observation

public enum LocationAuthorization: Sendable, Hashable {
    case notDetermined, denied, authorized
}

/// Platforma özel konum sağlayıcı (CoreLocation implementasyonu `AppFeature` içinde).
/// Yalnızca "Uygulamayı kullanırken" izni istenir; arka plan konumu yok (PRD 7.1).
@MainActor
public protocol LocationDriver: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
    func currentLocation() async -> Coordinate?
    /// Konum değiştikçe çağrılır.
    var onUpdate: ((Coordinate) -> Void)? { get set }
    func startUpdating()
    func stopUpdating()
}

@MainActor
@Observable
public final class LocationStore {
    public private(set) var coordinate: Coordinate?
    public private(set) var authorization: LocationAuthorization

    @ObservationIgnored private let driver: any LocationDriver

    public init(driver: any LocationDriver) {
        self.driver = driver
        self.authorization = driver.authorization
        driver.onUpdate = { [weak self] coordinate in
            self?.coordinate = coordinate
        }
    }

    public var isAuthorized: Bool { authorization == .authorized }

    @discardableResult
    public func requestAuthorization() async -> LocationAuthorization {
        authorization = await driver.requestAuthorization()
        if authorization == .authorized { driver.startUpdating() }
        return authorization
    }

    /// Bir kez konum alır (check-in anında taze konum için).
    @discardableResult
    public func refresh() async -> Coordinate? {
        authorization = driver.authorization
        guard authorization == .authorized else { return coordinate }
        if let fresh = await driver.currentLocation() {
            coordinate = fresh
        }
        return coordinate
    }

    public func start() {
        authorization = driver.authorization
        if authorization == .authorized { driver.startUpdating() }
    }

    public func stop() {
        driver.stopUpdating()
    }
}

/// Testler, önizlemeler ve demo modu için sabit konum.
@MainActor
public final class StaticLocationDriver: LocationDriver {
    public var authorization: LocationAuthorization
    public var location: Coordinate?
    public var onUpdate: ((Coordinate) -> Void)?

    public init(location: Coordinate? = .modaKadikoy, authorization: LocationAuthorization = .authorized) {
        self.location = location
        self.authorization = authorization
    }

    public func requestAuthorization() async -> LocationAuthorization {
        if authorization == .notDetermined { authorization = .authorized }
        return authorization
    }

    public func currentLocation() async -> Coordinate? {
        authorization == .authorized ? location : nil
    }

    public func startUpdating() {
        if authorization == .authorized, let location { onUpdate?(location) }
    }

    public func stopUpdating() {}

    public func move(to coordinate: Coordinate) {
        location = coordinate
        onUpdate?(coordinate)
    }
}
