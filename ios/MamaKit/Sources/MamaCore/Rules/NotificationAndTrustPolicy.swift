import Foundation

/// Push kuralları (FR-C4). Sunucu (push-dispatch) uygular; istemci ayarlar ekranında aynı kuralları gösterir.
public enum NotificationPolicy {
    public static let defaultQuietStartHour = 22
    public static let defaultQuietEndHour = 7
    public static let maxNeedFoodPushesPerDay = 3
    public static let needFoodRadiusMeters: Double = 1000
    public static let timeZone = TimeZone(identifier: "Europe/Istanbul")!

    /// Sessiz saat mi? Gece yarısını aşan aralıkları (22→07) destekler.
    public static func isQuietHour(
        _ date: Date,
        startHour: Int = defaultQuietStartHour,
        endHour: Int = defaultQuietEndHour,
        timeZone: TimeZone = timeZone
    ) -> Bool {
        guard startHour != endHour else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        return hour >= startHour || hour < endHour
    }

    public static func canSendNeedFoodPush(sentToday: Int, at date: Date, preferences: NotificationPreferences) -> Bool {
        preferences.needFoodNearby
            && sentToday < maxNeedFoodPushesPerDay
            && !isQuietHour(date, startHour: preferences.quietStartHour, endHour: preferences.quietEndHour)
    }
}

/// Güven puanı ve limitler (PRD 9.3, FR-P4).
public enum TrustPolicy {
    public static let initialTrustScore = 10
    /// Bunun altındaki hesapların yeni noktaları moderasyon onayına düşer.
    public static let moderationThreshold = 5
    public static let verifiedFeederCheckIns = 20
    public static let verifiedFeederWindowDays = 30
    public static let dailySpotLimitNew = 5
    public static let dailySpotLimitVerified = 30

    public static func dailySpotLimit(isVerifiedFeeder: Bool) -> Int {
        isVerifiedFeeder ? dailySpotLimitVerified : dailySpotLimitNew
    }

    public static func requiresModeration(trustScore: Int) -> Bool {
        trustScore < moderationThreshold
    }

    public static func qualifiesAsVerifiedFeeder(verifiedCheckInsLast30Days: Int) -> Bool {
        verifiedCheckInsLast30Days >= verifiedFeederCheckIns
    }

    /// Konumu doğrulanmış check-in +1, fotoğraflısı +1 ek.
    public static func scoreDelta(forCheckInWithPhoto hasPhoto: Bool) -> Int {
        hasPhoto ? 2 : 1
    }

    /// Doğrulanmış besleyici rozetine kalan check-in sayısı (profilde ilerleme göstermek için).
    public static func remainingForVerification(verifiedCheckInsLast30Days: Int) -> Int {
        max(0, verifiedFeederCheckIns - verifiedCheckInsLast30Days)
    }
}

/// Basit metin filtresi (PRD 9.2). Sunucu da aynı kontrolü yapar; bu yalnızca anında geri bildirim içindir.
public enum ContentFilter {
    private static let blockedStems: [String] = [
        "amk", "aq", "orospu", "piç", "siktir", "sikerim", "yarrak", "göt", "pezevenk", "kahpe",
        "fuck", "shit", "bitch", "cunt",
    ]

    public static func containsProfanity(_ text: String) -> Bool {
        let normalized = text.lowercased(with: Locale(identifier: "tr_TR"))
        let words = normalized
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        return words.contains { word in
            blockedStems.contains { stem in stem.count <= 3 ? word == stem : word.hasPrefix(stem) }
        }
    }
}
