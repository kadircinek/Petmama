import XCTest
import MamaCore
@testable import FeatureDonate

@MainActor
final class DonateViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeServices(config: AppConfig? = nil) -> (AppServices, InMemoryBackend) {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { fixed })
        return (AppServices.inMemory(backend, config: config, now: { fixed }), backend)
    }

    private func freshDefaults() -> UserDefaults {
        // Test başına ayrı, boş bir depo.
        UserDefaults(suiteName: UUID().uuidString) ?? .standard
    }

    private func query(_ url: URL?) -> [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    func testDonationLinkContainsPackageQuantityAndRef() async throws {
        let (services, _) = makeServices()
        let model = DonateViewModel(services: services, defaults: freshDefaults())
        let dog = try XCTUnwrap(model.packages.first { $0.species == .dog })
        model.select(dog)
        model.quantity = 3

        let params = query(model.donationURL)
        XCTAssertEqual(model.donationURL?.host, "example.org")
        XCTAssertEqual(params["package"], "dog_7")
        XCTAssertEqual(params["qty"], "3")
        XCTAssertEqual(params["ref"], model.refCode)
        XCTAssertEqual(params["utm_source"], "mamaharitasi")
        XCTAssertEqual(params["utm_medium"], "ios")
    }

    func testPrepareDonationLogsClickOnce() async {
        let (services, backend) = makeServices()
        let model = DonateViewModel(services: services, defaults: freshDefaults())

        let url = await model.prepareDonation()

        XCTAssertNotNil(url)
        XCTAssertEqual(query(url)["package"], "cat_5")
        let clicks = await backend.allDonationClicks()
        XCTAssertEqual(clicks, [model.refCode])
        XCTAssertFalse(model.isOpening)
    }

    func testRefCodeStableAcrossInstancesAndAnonymous() async {
        let (services, _) = makeServices()
        let defaults = freshDefaults()
        let first = DonateViewModel(services: services, defaults: defaults)
        let second = DonateViewModel(services: services, defaults: defaults)

        XCTAssertEqual(first.refCode, second.refCode)
        XCTAssertEqual(first.refCode.count, 8)
        XCTAssertTrue(first.refCode.allSatisfy { $0.isUppercase || $0.isNumber })
        XCTAssertEqual(defaults.string(forKey: DonateViewModel.refCodeKey), first.refCode)

        let other = DonateViewModel(services: services, defaults: freshDefaults())
        XCTAssertNotEqual(other.refCode, first.refCode, "farklı cihaz farklı kod")
    }

    func testCorruptStoredRefCodeIsReplaced() async {
        let defaults = freshDefaults()
        defaults.set("x", forKey: DonateViewModel.refCodeKey)
        let code = DonateViewModel.refCode(in: defaults)
        XCTAssertEqual(code.count, 8)
        XCTAssertEqual(defaults.string(forKey: DonateViewModel.refCodeKey), code)
    }

    func testUnconfiguredPartnerDisablesDonation() async {
        let (services, backend) = makeServices(config: AppConfig(isDemo: true, donation: .placeholder))
        let model = DonateViewModel(services: services, defaults: freshDefaults())

        XCTAssertFalse(model.isConfigured)
        XCTAssertNil(model.donationURL)
        let url = await model.prepareDonation()
        XCTAssertNil(url)
        let clicks = await backend.allDonationClicks()
        XCTAssertTrue(clicks.isEmpty, "dernek yokken tıklama kaydedilmez")
        XCTAssertFalse(model.transparencyText.contains("belirlenecek"))
        XCTAssertEqual(DonateViewModel.notConfiguredText, "Ortak dernek yakında açıklanacak")
    }

    func testTransparencyTextNamesPartner() async {
        let (services, _) = makeServices()
        let model = DonateViewModel(services: services, defaults: freshDefaults())
        XCTAssertEqual(
            model.transparencyText,
            "Bağışın doğrudan Ortak dernek (demo) derneğine gider. Mama Haritası para toplamaz; bağış derneğin kendi sayfasında alınır."
        )
    }

    func testPriceTryAndImpactTexts() async throws {
        let (services, _) = makeServices() // demo kuru: 41,5
        let model = DonateViewModel(services: services, defaults: freshDefaults())
        let cat = try XCTUnwrap(model.packages.first { $0.species == .cat })
        let dog = try XCTUnwrap(model.packages.first { $0.species == .dog })

        XCTAssertEqual(model.title(for: cat), "Kedi maması paketi")
        XCTAssertEqual(model.priceText(for: cat), "5 USD")
        XCTAssertEqual(model.tryText(for: cat), "≈ 208 TL")
        XCTAssertEqual(model.impactText(for: cat), "yaklaşık 2 kg kuru mama ≈ 40 kedinin bir öğünü")
        XCTAssertEqual(model.impactText(for: dog), "yaklaşık 2,5 kg kuru mama ≈ 10 köpeğin bir öğünü")
        XCTAssertEqual(model.impactText(for: dog, quantity: 2), "yaklaşık 5 kg kuru mama ≈ 20 köpeğin bir öğünü")

        model.quantity = 3
        XCTAssertEqual(model.totalText, "Toplam 15 USD (≈ 623 TL)")
    }

    func testWithoutExchangeRateOnlyUsdShown() async {
        let donation = DonationConfig(partnerName: "Dernek", donationURL: URL(string: "https://example.org/bagis"), usdToTry: nil)
        let (services, _) = makeServices(config: AppConfig(isDemo: true, donation: donation))
        let model = DonateViewModel(services: services, defaults: freshDefaults())
        XCTAssertNil(model.tryText(for: .cat))
        XCTAssertEqual(model.totalText, "Toplam 5 USD")
    }

    func testQuantityIsClamped() async {
        let (services, _) = makeServices()
        let model = DonateViewModel(services: services, defaults: freshDefaults())
        model.quantity = 25
        XCTAssertEqual(model.clampedQuantity, 10)
        XCTAssertEqual(query(model.donationURL)["qty"], "10")
        model.quantity = 0
        XCTAssertEqual(model.clampedQuantity, 1)
    }

    func testMonthlyCounter() async {
        let (services, _) = makeServices()
        let model = DonateViewModel(services: services, defaults: freshDefaults())
        XCTAssertNil(model.monthlyCounterText)
        await model.load()
        XCTAssertEqual(model.monthlyCounterText, "Bu ay 412 kg mama dağıtıldı")
        XCTAssertEqual(model.donorCountText, "37 bağışçı katkı verdi")
    }
}
