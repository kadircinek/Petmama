#if canImport(UIKit)
import SwiftUI
import UIKit
import UserNotifications
import MamaCore

/// Uygulama temsilcisi: servis kurulumu, APNs jetonu, bildirime dokunma.
///
///     @main struct MamaHaritasiApp: App {
///         @UIApplicationDelegateAdaptor(MamaAppDelegate.self) private var delegate
///         var body: some Scene { WindowGroup { AppRootView(model: delegate.model) } }
///     }
@MainActor
public final class MamaAppDelegate: NSObject, UIApplicationDelegate {
    public lazy var model: AppModel = {
        let configuration = AppConfiguration.from(infoDictionary: Bundle.main.infoDictionary ?? [:])
        return AppModel(services: ServiceFactory.make(configuration), locationDriver: CoreLocationDriver())
    }()

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Kullanıcı daha önce izin verdiyse jetonu tazele (izin isteği onboarding'de).
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = PushPayload.hexToken(deviceToken)
        Task { await model.didReceiveDeviceToken(token) }
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simülatörde ve izin yokken beklenen durum; uygulama içi bildirimler çalışmaya devam eder.
    }
}

extension MamaAppDelegate: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        // userInfo Sendable değil; yalnızca gereken kimlikleri ana aktöre taşı.
        let spotId = userInfo["spot_id"] as? String
        let needId = userInfo["need_id"] as? String
        await MainActor.run {
            var payload: [AnyHashable: Any] = [:]
            if let spotId { payload["spot_id"] = spotId }
            if let needId { payload["need_id"] = needId }
            self.model.openFromPush(payload)
        }
    }
}
#endif
