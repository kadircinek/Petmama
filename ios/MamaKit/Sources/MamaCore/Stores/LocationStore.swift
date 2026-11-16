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
    @ObservationIgnored private let refreshTimeout: Duration

    public init(driver: any LocationDriver, refreshTimeout: Duration = .seconds(8)) {
        self.driver = driver
        self.refreshTimeout = refreshTimeout
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

    /// Bir kez konum alır (check-in anında taze konum için). Sürücü cevap vermezse (ör. iOS, takip açıkken
    /// `requestLocation`'ı yanıtlamaz ve hareketsiz kullanıcıya yeni konum gelmez) `refreshTimeout` sonunda
    /// bilinen son konumla döner — asla sonsuza kadar beklemez.
    @discardableResult
    public func refresh() async -> Coordinate? {
        authorization = driver.authorization
        guard authorization == .authorized else { return coordinate }
        if let fresh = await currentLocationWithTimeout() {
            coordinate = fresh
        }
        return coordinate
    }

    private func currentLocationWithTimeout() async -> Coordinate? {
        let driver = driver
        let timeout = refreshTimeout
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let work = Task { @MainActor in once.resume(await driver.currentLocation()) }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(nil)
                work.cancel()
            }
        }
    }

    public func start() {
        authorization = driver.authorization
        if authorization == .authorized { driver.startUpdating() }
    }

    public func stop() {
        driver.stopUpdating()
    }
}

/// Devamlılığı yalnızca bir kez sürdürür (sürücü ile zaman aşımı yarışı için).
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Coordinate?, Never>?
    init(_ continuation: CheckedContinuation<Coordinate?, Never>) { self.continuation = continuation }
    func resume(_ value: Coordinate?) {
        continuation?.resume(returning: value)
        continuation = nil
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
