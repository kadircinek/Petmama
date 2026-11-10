import Foundation

// Maskot ikonları (D18): kedi ve köpek yüzleri, tüy rengi × ifade.
// Çizimler `scripts/generate_mascots.py` ile üretilir; görünümler MamaDesign'dadır.
// Eşleme mantığı burada durur ki Linux'ta test edilebilsin.

/// Maskotun ifadesi. Nokta durumunu renk ve metne ek olarak yüz ifadesiyle de anlatır.
public enum MascotMood: String, CaseIterable, Sendable, Hashable {
    /// Mama kondu: gülen gözler.
    case happy
    case neutral
    /// Mama bekliyor: iri, bekleyen gözler. (Ton: suçlayıcı değil, sevimli.)
    case hungry

    public init(status: SpotStatus) {
        switch status {
        case .fedRecent: self = .happy
        case .needsFood: self = .hungry
        case .fedStale, .unknown: self = .neutral
        }
    }
}

/// Haritada ve boş durumlarda kullanılan genel maskot.
public enum MascotSpecies: String, CaseIterable, Sendable, Hashable {
    case cat, dog
    /// Kedi ve köpek birlikte.
    case duo

    public init(_ species: SpotSpecies) {
        switch species {
        case .cat: self = .cat
        case .dog: self = .dog
        case .both: self = .duo
        }
    }

    public init(_ species: AnimalSpecies) {
        self = species == .cat ? .cat : .dog
    }

    public func assetName(mood: MascotMood) -> String {
        switch self {
        case .cat: return MascotCoat.catOrange.assetName(mood: mood)
        case .dog: return MascotCoat.dogCream.assetName(mood: mood)
        case .duo: return "mascot-duo-\(mood.rawValue)"
        }
    }
}

/// Hayvanın tüy rengine göre maskot.
public enum MascotCoat: String, CaseIterable, Sendable, Hashable {
    case catOrange = "cat-orange"
    case catGray = "cat-gray"
    case catWhite = "cat-white"
    case catBlack = "cat-black"
    case catCalico = "cat-calico"
    case dogCream = "dog-cream"
    case dogBrown = "dog-brown"
    case dogBlack = "dog-black"
    case dogSpotted = "dog-spotted"

    public static let cats: [MascotCoat] = [.catOrange, .catGray, .catWhite, .catBlack, .catCalico]
    public static let dogs: [MascotCoat] = [.dogCream, .dogBrown, .dogBlack, .dogSpotted]

    public func assetName(mood: MascotMood) -> String {
        "mascot-\(rawValue)-\(mood.rawValue)"
    }

    /// Serbest metin renk/desen tarifinden ("Sarman", "Gri tekir", "Açık kahve") maskot seçer.
    /// Tanınmayan tarifte `seed`'e göre kararlı bir seçim yapar: aynı hayvan hep aynı maskotla görünür.
    public static func matching(species: AnimalSpecies, colorPattern: String?, seed: UUID) -> MascotCoat {
        // Türkçe ve İngilizce küçük harfe çevirme birlikte: "BEYAZ" → "beyaz", "WHITE" → "white".
        let raw = colorPattern ?? ""
        let text = raw.lowercased(with: Locale(identifier: "tr_TR")) + " " + raw.lowercased()
        let rules: [(keywords: [String], coat: MascotCoat)]
        let fallback: [MascotCoat]
        switch species {
        case .cat:
            rules = [
                (["calico", "üç renk", "uc renk", "alaca", "tricolor"], .catCalico),
                (["sarman", "sarı", "turuncu", "orange", "ginger", "kızıl"], .catOrange),
                (["tekir", "gri", "duman", "gray", "grey", "tabby", "mavi"], .catGray),
                (["siyah", "kara", "black", "smokin"], .catBlack),
                (["beyaz", "white", "krem"], .catWhite),
            ]
            fallback = cats
        case .dog:
            rules = [
                (["benek", "alaca", "spotted", "lekeli"], .dogSpotted),
                (["krem", "sarı", "açık", "golden", "bal rengi", "cream"], .dogCream),
                (["kahve", "brown", "kızıl", "tarçın"], .dogBrown),
                (["siyah", "kara", "black"], .dogBlack),
                (["beyaz", "white"], .dogSpotted),
            ]
            fallback = dogs
        }
        if !raw.isEmpty, let match = rules.first(where: { rule in rule.keywords.contains { text.contains($0) } }) {
            return match.coat
        }
        let index = Int(LocationFuzzer.fnv1a64(seed.uuidString) % UInt64(fallback.count))
        return fallback[index]
    }
}

extension Animal {
    public var mascotCoat: MascotCoat {
        MascotCoat.matching(species: species, colorPattern: colorPattern, seed: id)
    }
}
