import XCTest
@testable import AppFeature
@testable import MamaCore

final class AppConfigurationTests: XCTestCase {
    func testEmptyOrUnresolvedValuesFallBackToDemo() {
        let config = AppConfiguration.from(infoDictionary: [
            "MAMA_SUPABASE_URL": "$(MAMA_SUPABASE_URL)",
            "MAMA_SUPABASE_ANON_KEY": "",
        ])
        XCTAssertFalse(config.usesSupabase)
        XCTAssertTrue(config.app.isDemo)
        XCTAssertTrue(config.app.donation.isConfigured, "demo modunda örnek bağış linki")
    }

    func testSupabaseAndDonationConfiguration() {
        let config = AppConfiguration.from(infoDictionary: [
            "MAMA_SUPABASE_URL": "https://abc.supabase.co",
            "MAMA_SUPABASE_ANON_KEY": "sb_publishable_123",
            "MAMA_PARTNER_NAME": "Örnek Dernek",
            "MAMA_DONATION_URL": "https://ornek.org/bagis",
            "MAMA_USD_TRY_RATE": "41.75",
            "MAMA_SUPPORT_EMAIL": "iletisim@ornek.org",
        ])
        XCTAssertTrue(config.usesSupabase)
        XCTAssertFalse(config.app.isDemo)
        XCTAssertEqual(config.app.donation.partnerName, "Örnek Dernek")
        XCTAssertEqual(config.app.donation.donationURL?.host, "ornek.org")
        XCTAssertEqual(config.app.donation.usdToTry, Decimal(string: "41.75"))
        XCTAssertEqual(config.app.supportEmail, "iletisim@ornek.org")
    }

    func testAPNsEnvironmentFromEntitlement() {
        XCTAssertEqual(AppConfiguration.from(infoDictionary: ["MAMA_APNS_ENV": "development"]).app.apnsEnvironment, .sandbox)
        XCTAssertEqual(AppConfiguration.from(infoDictionary: ["MAMA_APNS_ENV": "production"]).app.apnsEnvironment, .production)
        XCTAssertEqual(AppConfiguration.from(infoDictionary: [:]).app.apnsEnvironment, .production,
                       "bilinmiyorsa sunucu varsayılanı")
    }

    func testProductionWithoutPartnerKeepsDonationDisabled() {
        let config = AppConfiguration.from(infoDictionary: [
            "MAMA_SUPABASE_URL": "https://abc.supabase.co",
            "MAMA_SUPABASE_ANON_KEY": "key",
        ])
        XCTAssertFalse(config.app.donation.isConfigured)
    }

    func testPushPayloadRouting() {
        let need = UUID()
        let spot = UUID()
        let both = PushPayload.route(from: ["need_id": need.uuidString, "spot_id": spot.uuidString])
        XCTAssertEqual(both?.route, .need(need))
        XCTAssertEqual(both?.tab, .community)
        let post = UUID()
        let postTarget = PushPayload.route(from: ["post_id": post.uuidString, "spot_id": spot.uuidString])
        XCTAssertEqual(postTarget?.route, .post(post))
        XCTAssertEqual(postTarget?.tab, .community)
        XCTAssertEqual(PushPayload.route(from: ["spot_id": spot.uuidString])?.route, .spot(spot))
        XCTAssertNil(PushPayload.route(from: ["spot_id": "bozuk"]))
        XCTAssertEqual(PushPayload.hexToken(Data([0x0a, 0xff, 0x01])), "0aff01")
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func testOpenFromPushSwitchesTabAndPushesRoute() async {
        let model = AppModel(services: .demo(), locationDriver: StaticLocationDriver())
        let id = UUID()
        model.openFromPush(["spot_id": id.uuidString])
        XCTAssertEqual(model.router.selectedTab, .map)
        XCTAssertEqual(model.router.path(for: .map), [.spot(id)])
    }

    func testDeviceTokenRegisteredAfterSignIn() async {
        let model = AppModel(services: .demo(), locationDriver: StaticLocationDriver())
        await model.didReceiveDeviceToken("abc")
        _ = await model.session.signIn(email: "demo@mamaharitasi.app", password: "demo1234")
        await model.signedInStateChanged()
        // Kayıt hatasız tamamlanmalı; bir sonraki çağrı no-op.
        await model.signedInStateChanged()
        XCTAssertTrue(model.session.isSignedIn)
    }

    // MARK: - Oturum değişimi: cihaz token'ı ve çevrimdışı kuyruk

    private static let token = "a1b2c3d4e5f60718"

    private func makeModel(pending: [CheckInDraft] = [], apnsEnvironment: APNsEnvironment = .production) -> (AppModel, SpyNotifications) {
        var services = AppServices.demo()
        services.config.apnsEnvironment = apnsEnvironment
        let spy = SpyNotifications(base: services.notifications)
        services.notifications = spy
        let queue = OfflineCheckInQueue(store: InMemoryPendingCheckInStore(pending), repository: services.checkIns)
        services.checkIns = queue
        services.checkInQueue = queue
        return (AppModel(services: services, locationDriver: StaticLocationDriver()), spy)
    }

    private func signIn(_ model: AppModel) async {
        _ = await model.session.signIn(email: "demo@mamaharitasi.app", password: "demo1234")
        await model.signedInStateChanged()
    }

    func testSignOutUnregistersDeviceTokenBeforeEndingSession() async {
        let (model, spy) = makeModel()
        await model.didReceiveDeviceToken(Self.token)
        await signIn(model)

        await model.session.signOut()

        let unregistered = await spy.unregistered
        XCTAssertEqual(unregistered, [Self.token])
        let signedInWhileUnregistering = await spy.unregisterSawSignedInUser
        XCTAssertEqual(signedInWhileUnregistering, [true], "token oturum hâlâ açıkken silinmeli (RLS)")
    }

    func testDeviceTokenRegisteredAgainForNextAccount() async {
        let (model, spy) = makeModel()
        await model.didReceiveDeviceToken(Self.token)
        await signIn(model)
        await model.session.signOut()
        await model.signedInStateChanged()

        _ = await model.session.signUp(email: "ikinci@ornek.org", password: "sifre1234", displayName: "İkinci")
        await model.signedInStateChanged()

        let registered = await spy.registered
        XCTAssertEqual(registered, [Self.token, Self.token], "yeni hesap uygulama yeniden açılmadan bildirim almalı")
    }

    func testDeviceTokenRegisteredWithBuildsAPNsEnvironment() async {
        let (model, spy) = makeModel(apnsEnvironment: .sandbox)
        await model.didReceiveDeviceToken(Self.token)
        await signIn(model)
        let environments = await spy.registeredEnvironments
        XCTAssertEqual(environments, [.sandbox])
    }

    func testSignOutClearsOfflineQueue() async {
        let draft = CheckInDraft(spotId: UUID(), kind: .fed, userCoordinate: .modaKadikoy)
        let (model, _) = makeModel(pending: [draft])
        await signIn(model)

        await model.session.signOut()

        let pending = await model.services.checkInQueue.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    func testDeleteAccountClearsOfflineQueue() async {
        let draft = CheckInDraft(spotId: UUID(), kind: .fed, userCoordinate: .modaKadikoy)
        let (model, _) = makeModel(pending: [draft])
        await signIn(model)

        let deleted = await model.session.deleteAccount()

        XCTAssertTrue(deleted)
        let pending = await model.services.checkInQueue.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    // MARK: - E-posta bağlantıları (deep link)

    func testExpiredAuthLinkShowsErrorToast() async {
        let (model, _) = makeModel()
        let handled = await model.handleOpenURL(URL(string: "mamaharitasi://auth-callback#error=access_denied&error_code=otp_expired")!)
        XCTAssertTrue(handled)
        XCTAssertEqual(model.router.toast?.message, AuthLink.expiredMessage)
        XCTAssertEqual(model.router.toast?.style, .warning)
    }

    func testForeignURLIsIgnored() async {
        let (model, _) = makeModel()
        let handled = await model.handleOpenURL(URL(string: "https://ornek.org")!)
        XCTAssertFalse(handled)
        XCTAssertNil(model.router.toast)
    }

    func testSignInSetsQueueOwner() async {
        let (model, _) = makeModel()
        await signIn(model)
        let owner = await model.services.checkInQueue.owner
        XCTAssertEqual(owner, model.session.userId)
    }
}

/// Bildirim deposunu sarar; token kayıt/silme çağrılarını kaydeder.
actor SpyNotifications: NotificationRepository {
    let base: any NotificationRepository
    private(set) var registered: [String] = []
    private(set) var registeredEnvironments: [APNsEnvironment] = []
    private(set) var unregistered: [String] = []
    private(set) var unregisterSawSignedInUser: [Bool] = []

    init(base: any NotificationRepository) { self.base = base }

    func notifications() async throws -> [AppNotification] { try await base.notifications() }
    func markRead(ids: [UUID]) async throws { try await base.markRead(ids: ids) }
    func preferences() async throws -> NotificationPreferences { try await base.preferences() }
    func updatePreferences(_ preferences: NotificationPreferences) async throws { try await base.updatePreferences(preferences) }
    func updateNotifyCenter(_ coordinate: Coordinate) async throws { try await base.updateNotifyCenter(coordinate) }

    func registerDeviceToken(_ token: String, environment: APNsEnvironment) async throws {
        try await base.registerDeviceToken(token, environment: environment)
        registered.append(token)
        registeredEnvironments.append(environment)
    }

    func unregisterDeviceToken(_ token: String) async throws {
        // Demo backend oturum yoksa `requireUser` ile hata atar: başarı = oturum açıktı.
        do {
            try await base.unregisterDeviceToken(token)
            unregisterSawSignedInUser.append(true)
        } catch {
            unregisterSawSignedInUser.append(false)
        }
        unregistered.append(token)
    }
}
