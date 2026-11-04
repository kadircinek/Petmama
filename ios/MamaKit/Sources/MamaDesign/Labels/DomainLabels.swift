#if canImport(UIKit)
import SwiftUI
import MamaCore

// Domain enum'ları için kullanıcıya görünen etiketler, SF Symbols ve renkler.
// Ton: sıcak, suçlayıcı olmayan dil — "Aç kaldı" yerine "Mama bekliyor" (PRD 6.4).
// Metinler String Catalog'dan (Localizable.xcstrings, ana bundle) çevrilir.

extension SpotStatus {
    public var label: String {
        switch self {
        case .fedRecent: return String(localized: "Mama kondu")
        case .fedStale: return String(localized: "12+ saat önce")
        case .unknown: return String(localized: "Bilinmiyor")
        case .needsFood: return String(localized: "Mama bekliyor")
        }
    }

    public var systemImage: String {
        switch self {
        case .fedRecent: return "checkmark.circle.fill"
        case .fedStale: return "clock.fill"
        case .unknown: return "questionmark.circle.fill"
        case .needsFood: return "exclamationmark.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .fedRecent: return MamaColor.statusFed
        case .fedStale: return MamaColor.statusStale
        case .unknown: return MamaColor.statusUnknown
        case .needsFood: return MamaColor.statusNeeds
        }
    }

    /// Lejant ve erişilebilirlik için uzun açıklama.
    public var explanation: String {
        switch self {
        case .fedRecent: return String(localized: "Son 12 saatte mama kondu")
        case .fedStale: return String(localized: "12–24 saat önce mama kondu")
        case .unknown: return String(localized: "24 saattir haber yok")
        case .needsFood: return String(localized: "Biri mama gerekli dedi")
        }
    }
}

extension SpotType {
    public var label: String {
        switch self {
        case .food: return String(localized: "Mama noktası")
        case .water: return String(localized: "Su kabı")
        case .shelter: return String(localized: "Kulübe / barınak")
        case .mixed: return String(localized: "Karışık")
        }
    }

    public var systemImage: String {
        switch self {
        case .food: return "pawprint.fill"
        case .water: return "drop.fill"
        case .shelter: return "house.fill"
        case .mixed: return "square.grid.2x2.fill"
        }
    }
}

extension SpotSpecies {
    public var label: String {
        switch self {
        case .cat: return String(localized: "Kedi")
        case .dog: return String(localized: "Köpek")
        case .both: return String(localized: "Kedi ve köpek")
        }
    }

    public var systemImage: String {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .both: return "pawprint.fill"
        }
    }
}

extension AnimalSpecies {
    public var label: String {
        switch self {
        case .cat: return String(localized: "Kedi")
        case .dog: return String(localized: "Köpek")
        }
    }

    public var systemImage: String {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        }
    }
}

extension SpotVisibility {
    public var label: String {
        switch self {
        case .public: return String(localized: "Herkese açık")
        case .fuzzed: return String(localized: "Yaklaşık konum")
        case .private: return String(localized: "Özel")
        }
    }

    public var explanation: String {
        switch self {
        case .public: return String(localized: "Giriş yapan herkes tam konumu görür; giriş yapmayanlar yaklaşık konumu görür.")
        case .fuzzed: return String(localized: "Herkes 50–100 m bulanık konumu görür; tam konumu yalnızca koruyucular ve doğrulanmış besleyiciler görür.")
        case .private: return String(localized: "Giriş yapmayanlara hiç görünmez; tam konumu yalnızca koruyucular ve doğrulanmış besleyiciler görür.")
        }
    }

    public var systemImage: String {
        switch self {
        case .public: return "globe"
        case .fuzzed: return "circle.dashed"
        case .private: return "lock.fill"
        }
    }
}

extension CheckInKind {
    public var label: String {
        switch self {
        case .fed: return String(localized: "Mama koydum")
        case .water: return String(localized: "Su koydum")
        case .needFood: return String(localized: "Mama bitti")
        case .needWater: return String(localized: "Su bitti")
        case .broken: return String(localized: "Kap kirli veya kırık")
        }
    }

    public var systemImage: String {
        switch self {
        case .fed: return "pawprint.fill"
        case .water: return "drop.fill"
        case .needFood: return "fork.knife"
        case .needWater: return "drop.triangle.fill"
        case .broken: return "exclamationmark.triangle.fill"
        }
    }
}

extension FoodAmount {
    public var label: String {
        switch self {
        case .low: return String(localized: "Az")
        case .medium: return String(localized: "Orta")
        case .full: return String(localized: "Dolu kap")
        }
    }
}

extension NeedType {
    public var label: String {
        switch self {
        case .vet: return String(localized: "Veteriner")
        case .neuter: return String(localized: "Kısırlaştırma")
        case .vaccine: return String(localized: "Aşı")
        case .meds: return String(localized: "İlaç / pire-kene")
        case .shelter: return String(localized: "Kış barınağı")
        case .water: return String(localized: "Su kabı")
        case .adoption: return String(localized: "Sahiplendirme")
        case .lostFound: return String(localized: "Kayıp / bulunan")
        }
    }

    public var systemImage: String {
        switch self {
        case .vet: return "cross.case.fill"
        case .neuter: return "scissors"
        case .vaccine: return "syringe.fill"
        case .meds: return "pills.fill"
        case .shelter: return "house.fill"
        case .water: return "drop.fill"
        case .adoption: return "heart.fill"
        case .lostFound: return "magnifyingglass"
        }
    }

    public var tileColor: Color {
        switch self {
        case .vet, .meds: return MamaColor.tilePeach
        case .neuter, .vaccine: return MamaColor.tileLavender
        case .shelter, .water: return MamaColor.tileBlue
        case .adoption, .lostFound: return MamaColor.tileMint
        }
    }
}

extension NeedUrgency {
    public var label: String {
        switch self {
        case .normal: return String(localized: "Normal")
        case .urgent: return String(localized: "Acil")
        }
    }
}

extension NeedStatus {
    public var label: String {
        switch self {
        case .open: return String(localized: "Açık")
        case .claimed: return String(localized: "Üstlenildi")
        case .resolved: return String(localized: "Çözüldü")
        }
    }

    public var systemImage: String {
        switch self {
        case .open: return "circle"
        case .claimed: return "hand.raised.fill"
        case .resolved: return "checkmark.circle.fill"
        }
    }
}

extension AnimalSex {
    public var label: String {
        switch self {
        case .female: return String(localized: "Dişi")
        case .male: return String(localized: "Erkek")
        case .unknown: return String(localized: "Bilinmiyor")
        }
    }
}

extension AgeEstimate {
    public var label: String {
        switch self {
        case .baby: return String(localized: "Yavru")
        case .young: return String(localized: "Genç")
        case .adult: return String(localized: "Yetişkin")
        case .senior: return String(localized: "Yaşlı")
        case .unknown: return String(localized: "Yaş bilinmiyor")
        }
    }
}

extension TemperamentTag {
    public var label: String {
        switch self {
        case .friendly: return String(localized: "Uysal")
        case .shy: return String(localized: "Çekingen")
        case .mayBeAggressive: return String(localized: "Agresif olabilir")
        case .goodWithKids: return String(localized: "Çocuklarla iyi")
        case .energetic: return String(localized: "Enerjik")
        case .calm: return String(localized: "Sakin")
        }
    }

    public var systemImage: String {
        switch self {
        case .friendly: return "hand.thumbsup.fill"
        case .shy: return "eye.slash.fill"
        case .mayBeAggressive: return "exclamationmark.triangle.fill"
        case .goodWithKids: return "figure.and.child.holdinghands"
        case .energetic: return "bolt.fill"
        case .calm: return "leaf.fill"
        }
    }

    public var tileColor: Color {
        switch self {
        case .friendly, .goodWithKids: return MamaColor.tileMint
        case .shy, .calm: return MamaColor.tileBlue
        case .energetic: return MamaColor.tileLavender
        case .mayBeAggressive: return MamaColor.tilePeach
        }
    }
}

extension AnimalWarning {
    public var label: String {
        switch self {
        case .doNotApproach: return String(localized: "Yaklaşmayın")
        case .skittish: return String(localized: "Ürkek")
        case .mayBite: return String(localized: "Isırabilir")
        }
    }
}

extension ReportReason {
    public var label: String {
        switch self {
        case .inappropriate: return String(localized: "Uygunsuz içerik")
        case .spam: return String(localized: "Spam veya sahte")
        case .wrongLocation: return String(localized: "Yanlış konum")
        case .animalHarm: return String(localized: "Şüpheli durum / hayvana zarar")
        case .harassment: return String(localized: "Taciz veya hakaret")
        case .other: return String(localized: "Diğer")
        }
    }
}

extension NotificationKind {
    public var systemImage: String {
        switch self {
        case .needFoodNearby: return "fork.knife"
        case .followedSpotChanged: return "mappin.and.ellipse"
        case .guardianSpotUnfed: return "clock.fill"
        case .needResolved: return "checkmark.circle.fill"
        case .thanksFed: return "heart.fill"
        case .donationDelivered: return "gift.fill"
        }
    }

    public var tint: Color {
        switch self {
        case .needFoodNearby, .guardianSpotUnfed: return MamaColor.statusNeeds
        case .followedSpotChanged: return MamaColor.textSecondary
        case .needResolved, .thanksFed, .donationDelivered: return MamaColor.statusFed
        }
    }
}

extension Weekday {
    public var localizedShortName: String {
        switch self {
        case .monday: return String(localized: "Pzt")
        case .tuesday: return String(localized: "Sal")
        case .wednesday: return String(localized: "Çar")
        case .thursday: return String(localized: "Per")
        case .friday: return String(localized: "Cum")
        case .saturday: return String(localized: "Cmt")
        case .sunday: return String(localized: "Paz")
        }
    }
}
#endif
