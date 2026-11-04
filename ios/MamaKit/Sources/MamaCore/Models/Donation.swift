import Foundation

/// Bağış paketi (PRD 8.1). Lansmanda ödeme uygulama dışında alınır (D2, Seçenek B).
public struct DonationPackage: Identifiable, Hashable, Codable, Sendable {
    /// Sunucu ve dernek tarafındaki paket kodu: `cat_5`, `dog_7`.
    public let id: String
    public var species: AnimalSpecies
    public var priceUSD: Decimal
    /// Toptan alım fiyatına göre her çeyrek güncellenir (PRD 8.1).
    public var approxKg: Double
    public var approxMeals: Int

    public init(id: String, species: AnimalSpecies, priceUSD: Decimal, approxKg: Double, approxMeals: Int) {
        self.id = id
        self.species = species
        self.priceUSD = priceUSD
        self.approxKg = approxKg
        self.approxMeals = approxMeals
    }

    public static let cat = DonationPackage(id: "cat_5", species: .cat, priceUSD: 5, approxKg: 2, approxMeals: 40)
    public static let dog = DonationPackage(id: "dog_7", species: .dog, priceUSD: 7, approxKg: 2.5, approxMeals: 10)
}

public struct DonationOverview: Hashable, Codable, Sendable {
    public var month: Date
    public var kgDistributed: Double
    public var donorCount: Int

    public init(month: Date, kgDistributed: Double, donorCount: Int) {
        self.month = month
        self.kgDistributed = kgDistributed
        self.donorCount = donorCount
    }
}

/// Ortak dernek ve bağış sayfası ayarları. Değerler Info.plist'ten gelir (D2).
public struct DonationConfig: Hashable, Sendable {
    public var partnerName: String
    public var donationURL: URL?
    /// TL karşılığı göstermek için günlük kur (PRD 8.1). Bilinmiyorsa yalnızca USD gösterilir.
    public var usdToTry: Decimal?
    public var packages: [DonationPackage]

    public init(
        partnerName: String,
        donationURL: URL?,
        usdToTry: Decimal? = nil,
        packages: [DonationPackage] = [.cat, .dog]
    ) {
        self.partnerName = partnerName
        self.donationURL = donationURL
        self.usdToTry = usdToTry
        self.packages = packages
    }

    /// Ortak dernek netleşmeden kullanılan yer tutucu. `donationURL` nil olduğundan buton devre dışı kalır.
    public static let placeholder = DonationConfig(partnerName: "Ortak dernek (belirlenecek)", donationURL: nil)

    public var isConfigured: Bool { donationURL != nil }

    /// Harici Safari'de açılacak bağış linki: `utm` parametreleri + anonim referans kodu (PRD 8.2).
    public func link(for package: DonationPackage, quantity: Int, refCode: String) -> URL? {
        guard let donationURL, var components = URLComponents(url: donationURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "utm_source", value: "mamaharitasi"),
            URLQueryItem(name: "utm_medium", value: "ios"),
            URLQueryItem(name: "utm_campaign", value: "bagis"),
            URLQueryItem(name: "package", value: package.id),
            URLQueryItem(name: "qty", value: String(max(1, quantity))),
            URLQueryItem(name: "ref", value: refCode),
        ])
        components.queryItems = items
        return components.url
    }

    /// TL karşılığı (yuvarlanmış), kur yoksa nil.
    public func tryAmount(for package: DonationPackage, quantity: Int) -> Decimal? {
        guard let usdToTry else { return nil }
        var value = package.priceUSD * Decimal(max(1, quantity)) * usdToTry
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded
    }
}
