import Foundation
import Observation
import MamaCore

/// Bağış sekmesi (ekran 18, PRD 8.1–8.2). Lansmanda bağış derneğin kendi sayfasında, harici Safari'de alınır (D2).
/// Uygulama içinde ödeme, IAP veya Apple Pay yoktur.
@MainActor
@Observable
public final class DonateViewModel {
    public static let quantityRange = 1...10
    public static let refCodeKey = "mama.donation.refCode"
    public static let refCodeLength = 8
    /// Karışmasın diye 0/O ve 1/I yok.
    static let refCodeAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public private(set) var overview: DonationOverview?
    public var selectedPackageId: String
    /// Adet seçici (1–10). Hesaplarda `clampedQuantity` kullanılır.
    public var quantity: Int = 1
    public private(set) var isOpening = false

    /// Cihaza özel anonim referans kodu; kişisel veri içermez (PRD 8.2).
    public let refCode: String
    public let config: DonationConfig
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.config = services.config.donation
        self.refCode = Self.refCode(in: defaults)
        self.selectedPackageId = services.config.donation.packages.first?.id ?? DonationPackage.cat.id
    }

    // MARK: - Referans kodu

    /// Kayıtlı kodu döner; yoksa veya bozuksa yenisini üretip saklar.
    public static func refCode(in defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: refCodeKey), isValidRefCode(stored) {
            return stored
        }
        var generator = SystemRandomNumberGenerator()
        let code = String((0..<refCodeLength).compactMap { _ in refCodeAlphabet.randomElement(using: &generator) })
        defaults.set(code, forKey: refCodeKey)
        return code
    }

    static func isValidRefCode(_ code: String) -> Bool {
        code.count == refCodeLength && code.allSatisfy(refCodeAlphabet.contains)
    }

    // MARK: - Paketler

    public var packages: [DonationPackage] { config.packages }
    public var isConfigured: Bool { config.isConfigured }

    public var selectedPackage: DonationPackage? {
        packages.first { $0.id == selectedPackageId } ?? packages.first
    }

    public var clampedQuantity: Int {
        min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
    }

    public func select(_ package: DonationPackage) {
        selectedPackageId = package.id
    }

    public func title(for package: DonationPackage) -> String {
        package.species == .cat ? "Kedi maması paketi" : "Köpek maması paketi"
    }

    /// "5 USD"
    public func priceText(for package: DonationPackage, quantity: Int = 1) -> String {
        MamaFormat.usd(package.priceUSD * Decimal(max(1, quantity)), language: .turkish)
    }

    /// "≈ 208 TL" — kur yoksa `nil` (yalnızca USD gösterilir).
    public func tryText(for package: DonationPackage, quantity: Int = 1) -> String? {
        config.tryAmount(for: package, quantity: quantity).map { MamaFormat.approxTry($0, language: .turkish) }
    }

    /// "yaklaşık 2 kg kuru mama ≈ 40 kedinin bir öğünü"
    public func impactText(for package: DonationPackage, quantity: Int = 1) -> String {
        let qty = Double(max(1, quantity))
        let kg = Self.kilogramText(package.approxKg * qty)
        let meals = package.approxMeals * max(1, quantity)
        let animal = package.species == .cat ? "kedinin" : "köpeğin"
        return "yaklaşık \(kg) kg kuru mama ≈ \(meals) \(animal) bir öğünü"
    }

    /// 2 → "2", 2.5 → "2,5"
    static func kilogramText(_ kg: Double) -> String {
        let rounded = (kg * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// "Toplam 15 USD (≈ 623 TL)"
    public var totalText: String? {
        guard let package = selectedPackage else { return nil }
        let usd = priceText(for: package, quantity: clampedQuantity)
        if let tl = tryText(for: package, quantity: clampedQuantity) { return "Toplam \(usd) (\(tl))" }
        return "Toplam \(usd)"
    }

    // MARK: - Şeffaflık ve sayaç

    public var transparencyText: String {
        if isConfigured {
            return "Bağışın doğrudan \(config.partnerName) derneğine gider. Mama Haritası para toplamaz; bağış derneğin kendi sayfasında alınır."
        }
        return "Bağışlar doğrudan ortak derneğe gidecek. Mama Haritası para toplamaz; bağış derneğin kendi sayfasında alınır."
    }

    public static let notConfiguredText = "Ortak dernek yakında açıklanacak"

    /// "Bu ay 412 kg mama dağıtıldı"
    public var monthlyCounterText: String? {
        overview.map { "Bu ay \(MamaFormat.kilograms($0.kgDistributed, language: .turkish)) mama dağıtıldı" }
    }

    public var donorCountText: String? {
        guard let count = overview?.donorCount, count > 0 else { return nil }
        return "\(count) bağışçı katkı verdi"
    }

    public func load() async {
        overview = try? await services.donations.overview()
    }

    // MARK: - Bağış linki

    /// `utm` + paket + adet + anonim referans kodu (PRD 8.2). Ortak dernek yoksa `nil`.
    public var donationURL: URL? {
        guard let package = selectedPackage else { return nil }
        return config.link(for: package, quantity: clampedQuantity, refCode: refCode)
    }

    /// Linki hazırlar ve yalnızca "bağış sayfasına gidildi" olayını kaydeder. Açmak görünümün işi (`openURL`).
    /// Kayıt başarısız olsa da bağış engellenmez.
    public func prepareDonation() async -> URL? {
        guard !isOpening, let url = donationURL else { return nil }
        isOpening = true
        defer { isOpening = false }
        try? await services.donations.logDonationClick(refCode: refCode)
        return url
    }
}
