import Foundation
import Observation
import MamaCore

/// Uygulama ömrü boyunca yaşayan store'ları ve servisleri bir arada tutar.
@MainActor
@Observable
public final class AppModel {
    public let services: AppServices
    public let session: SessionStore
    public let router: AppRouter
    public let location: LocationStore

    @ObservationIgnored private var lastNotifyCenter: Coordinate?
    @ObservationIgnored private var pendingDeviceToken: String?

    public init(services: AppServices, locationDriver: any LocationDriver) {
        self.services = services
        self.session = SessionStore(auth: services.auth, profiles: services.profiles)
        self.router = AppRouter()
        self.location = LocationStore(driver: locationDriver)
    }

    public func start() async {
        await session.restore()
        location.start()
        await flushOfflineQueue()
        await registerPendingDeviceToken()
    }

    /// Bağlantı gelince ve uygulama öne gelince (FR-H8).
    public func flushOfflineQueue() async {
        let outcomes = await services.checkInQueue.flush(now: services.now())
        let sent = outcomes.filter { if case .success = $0 { return true } else { return false } }.count
        if sent > 0 {
            router.showToast(sent == 1
                ? "Bekleyen check-in'in gönderildi."
                : "Bekleyen \(sent) check-in gönderildi.")
        }
    }

    public func didReceiveDeviceToken(_ token: String) async {
        pendingDeviceToken = token
        await registerPendingDeviceToken()
    }

    public func signedInStateChanged() async {
        await registerPendingDeviceToken()
    }

    private func registerPendingDeviceToken() async {
        guard session.isSignedIn, let token = pendingDeviceToken else { return }
        if (try? await services.notifications.registerDeviceToken(token)) != nil {
            pendingDeviceToken = nil
        }
    }

    /// Yakındaki "mama gerekli" bildirimleri için son kaba konum (D8). 300 m'den az hareketi göndermez.
    public func updateNotifyCenterIfNeeded(_ coordinate: Coordinate?) async {
        guard session.isSignedIn, let coordinate else { return }
        if let last = lastNotifyCenter, GeoMath.distance(last, coordinate) < 300 { return }
        let prefs = (try? await services.notifications.preferences()) ?? .default
        guard prefs.needFoodNearby else { return }
        if (try? await services.notifications.updateNotifyCenter(coordinate)) != nil {
            lastNotifyCenter = coordinate
        }
    }

    public func openFromPush(_ userInfo: [AnyHashable: Any]) {
        guard let target = PushPayload.route(from: userInfo) else { return }
        router.open(target.route, in: target.tab)
    }
}
