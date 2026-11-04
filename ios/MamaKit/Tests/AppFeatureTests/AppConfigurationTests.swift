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
        XCTAssertEqual(both?.tab, .needs)
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
}
