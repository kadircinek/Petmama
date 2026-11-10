import Foundation
import MamaCore

/// Mahalle ekranlarının platformdan bağımsız biçimlendirmesi. Günler sunucudaki gibi İstanbul'a göre sayılır.
public enum CommunityFormat {
    /// Europe/Istanbul takvimi ("Yerime bakar mısın?" tarihleri ve günlük limitler bu güne göre).
    public static var istanbulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        return calendar
    }

    private static let turkishMonths = [
        "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
    ]
    private static let englishMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "14 Kasım", "14–15 Kasım", "30 Kasım – 2 Aralık", "30 Aralık 2026 – 2 Ocak 2027".
    /// İki tarih de yoksa `nil`; yalnızca biri varsa tek gün gibi yazılır.
    public static func coverRange(from: Date?, to: Date?, language: MamaFormat.Language = .current) -> String? {
        guard let first = from ?? to, let second = to ?? from else { return nil }
        let calendar = istanbulCalendar
        let start = calendar.dateComponents([.year, .month, .day], from: min(first, second))
        let end = calendar.dateComponents([.year, .month, .day], from: max(first, second))
        guard let startYear = start.year, let startMonth = start.month, let startDay = start.day,
              let endYear = end.year, let endMonth = end.month, let endDay = end.day else { return nil }

        let startName = monthName(startMonth, language: language)
        let endName = monthName(endMonth, language: language)
        switch language {
        case .turkish:
            if startYear != endYear {
                return "\(startDay) \(startName) \(startYear) – \(endDay) \(endName) \(endYear)"
            }
            if startMonth != endMonth { return "\(startDay) \(startName) – \(endDay) \(endName)" }
            if startDay != endDay { return "\(startDay)–\(endDay) \(endName)" }
            return "\(startDay) \(startName)"
        case .english:
            if startYear != endYear {
                return "\(startName) \(startDay), \(startYear) – \(endName) \(endDay), \(endYear)"
            }
            if startMonth != endMonth { return "\(startName) \(startDay) – \(endName) \(endDay)" }
            if startDay != endDay { return "\(startName) \(startDay)–\(endDay)" }
            return "\(startName) \(startDay)"
        }
    }

    private static func monthName(_ month: Int, language: MamaFormat.Language) -> String {
        let names = language == .turkish ? turkishMonths : englishMonths
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)"
    }
}

extension CommunityPost {
    /// Sunucu yanıtını beklemeden pati durumunu çevirir (başarısız olursa eski değer geri yazılır).
    mutating func applyOptimisticPawToggle() {
        viewerPawed.toggle()
        pawCount = max(0, pawCount + (viewerPawed ? 1 : -1))
    }

    mutating func apply(_ result: PawToggleResult) {
        viewerPawed = result.pawed
        pawCount = result.pawCount
    }
}
