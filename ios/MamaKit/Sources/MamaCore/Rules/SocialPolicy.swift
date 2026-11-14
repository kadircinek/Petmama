import Foundation

/// Tanışma kuralları (spec Global Constraints). Sunucudaki sabitlerle birebir aynı tutulmalı.
public enum SocialPolicy {
    // Buluşma
    public static let titleLength = 3...80
    public static let maxDescription = 600
    public static let placeNameLength = 1...80
    /// Başlangıç en erken şimdiden 1 saat sonra.
    public static let minLeadTime: TimeInterval = 3600
    /// Başlangıç en geç 60 gün sonra.
    public static let maxLeadDays = 60
    public static let durationMinutes = 30...480
    public static let defaultDurationMinutes = 120
    public static let capacity = 2...50
    /// Kullanıcı başına günde (İstanbul günü) en fazla buluşma.
    public static let dailyMeetups = 3

    // Hayvanseverler
    public static let maxAbout = 300
    public static let maxNote = 200
    public static let dailyRequests = 10
    /// Reddedilen istekten sonra aynı kişiye yeniden istek için bekleme.
    public static let cooldownDays = 30

    // Sohbet
    public static let maxMessage = 1000
    /// Sohbet başına dakikada mesaj.
    public static let perMinute = 20
    /// Kullanıcı başına günde mesaj.
    public static let perDay = 500
    /// Buluşma sohbeti bitişten bu kadar sonra salt okunur.
    public static let readOnlyAfterEnd: TimeInterval = 86_400

    /// Buluşma listesi ve Hayvanseverler yarıçapı.
    public static let radiusMeters = 10_000

    /// Mesafe bandı; `radiusMeters` dışı `nil` (listede gösterilmez).
    public static func band(meters: Double) -> DistanceBand? {
        guard meters >= 0 else { return nil }
        if meters < 1000 { return .under1km }
        if meters < 3000 { return .from1to3km }
        if meters <= Double(radiusMeters) { return .from3to10km }
        return nil
    }

    /// Kaba konum: 2 ondalığa yuvarlanır (≈1,1 km), sunucudaki `round(lat, 2)` ile aynı.
    public static func roundedCell(_ c: Coordinate) -> Coordinate {
        Coordinate(latitude: (c.latitude * 100).rounded() / 100, longitude: (c.longitude * 100).rounded() / 100)
    }

    /// İstemci tarafı ön doğrulama, sunucudaki sırayla (nokta görünürlüğü yalnızca sunucuda denetlenir).
    public static func validate(_ draft: MeetupDraft, now: Date) -> MeetupInvalidReason? {
        if !titleLength.contains(trimmed(draft.title).count) { return .titleLength }
        if trimmed(draft.description).count > maxDescription { return .descriptionTooLong }
        if !placeNameLength.contains(trimmed(draft.placeName).count) { return .placeNameLength }
        if draft.startsAt < now.addingTimeInterval(minLeadTime) { return .startTooSoon }
        if draft.startsAt > now.addingTimeInterval(TimeInterval(maxLeadDays) * 86_400) { return .startTooLate }
        if !durationMinutes.contains(draft.durationMinutes) { return .durationRange }
        if let value = draft.capacity, !capacity.contains(value) { return .capacityRange }
        return nil
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension DistanceBand {
    /// Yakından uzağa sıralama.
    var rank: Int {
        switch self {
        case .under1km: return 0
        case .from1to3km: return 1
        case .from3to10km: return 2
        }
    }
}
