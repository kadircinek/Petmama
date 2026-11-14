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
    /// APNs'ten gelen son token. Uygulama ömrü boyunca saklanır: hesap değişince yeni hesaba kaydedilir.
    @ObservationIgnored private var deviceToken: String?
    /// Token'ın sunucuda kayıtlı olduğu kullanıcı.
    @ObservationIgnored private var deviceTokenOwner: UUID?

    public init(services: AppServices, locationDriver: any LocationDriver) {
        self.services = services
        self.session = SessionStore(auth: services.auth, profiles: services.profiles)
        self.router = AppRouter()
        self.location = LocationStore(driver: locationDriver)
        session.willEndSession = { [weak self] in await self?.sessionWillEnd() }
        session.didEndSession = { [weak self] in await self?.sessionDidEnd() }
    }

    public func start() async {
        await session.restore()
        await services.checkInQueue.setOwner(session.userId)
        location.start()
        await flushOfflineQueue()
        await registerDeviceTokenIfNeeded()
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
        if token != deviceToken { deviceTokenOwner = nil }
        deviceToken = token
        await registerDeviceTokenIfNeeded()
    }

    public func signedInStateChanged() async {
        await services.checkInQueue.setOwner(session.userId)
        await registerDeviceTokenIfNeeded()
        if session.isSignedIn { await flushOfflineQueue() }
    }

    private func registerDeviceTokenIfNeeded() async {
        guard let userId = session.userId, let token = deviceToken, deviceTokenOwner != userId else { return }
        if (try? await services.notifications.registerDeviceToken(token, environment: services.config.apnsEnvironment)) != nil {
            deviceTokenOwner = userId
        }
    }

    /// Oturum hâlâ açıkken: bu cihaz artık çıkan hesabın bildirimlerini almasın.
    private func sessionWillEnd() async {
        if let token = deviceToken, deviceTokenOwner != nil {
            try? await services.notifications.unregisterDeviceToken(token)
        }
        deviceTokenOwner = nil
    }

    /// Çıkış ya da hesap silme sonrası: bekleyen check-in'ler bir sonraki hesaba geçmesin.
    private func sessionDidEnd() async {
        deviceTokenOwner = nil
        lastNotifyCenter = nil
        await services.checkInQueue.clear()
        await services.checkInQueue.setOwner(nil)
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

    /// `onOpenURL`: e-posta doğrulama / şifre sıfırlama bağlantıları. Tanımadığı adresi `false` ile bırakır.
    @discardableResult
    public func handleOpenURL(_ url: URL) async -> Bool {
        guard let kind = await session.handleAuthLink(url) else { return false }
        switch kind {
        case .emailConfirmed: router.showToast("E-postan doğrulandı. Hoş geldin!")
        case .passwordRecovery: break  // "Yeni şifre" ekranı `session.isRecoveringPassword` ile açılır.
        case .failed(let message): router.showToast(message, style: .warning)
        }
        await signedInStateChanged()
        return true
    }

    public func openFromPush(_ userInfo: [AnyHashable: Any]) {
        guard let target = PushPayload.route(from: userInfo) else { return }
        router.open(target.route, in: target.tab)
    }
}
