import Foundation
import MamaCore

/// Buluşma metinleri. Saat dilimi sabit `Europe/Istanbul`; cihaz saat diliminden bağımsızdır.
public enum MeetupFormat {
    private static let weekdays = ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"]
    private static let months = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        calendar.locale = Locale(identifier: "tr_TR")
        return calendar
    }

    /// "Bugün 10:00", "Yarın 18:30", aksi halde "Cmt 16 Kas 10:00".
    public static func when(_ m: Meetup, now: Date) -> String {
        let calendar = calendar
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: m.startsAt)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if calendar.isDate(m.startsAt, inSameDayAs: now) { return "Bugün \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(m.startsAt, inSameDayAs: tomorrow) {
            return "Yarın \(time)"
        }
        let weekday = weekdays[((c.weekday ?? 1) - 1) % 7]
        let month = months[((c.month ?? 1) - 1) % 12]
        return "\(weekday) \(c.day ?? 1) \(month) \(time)"
    }

    public static func bandLabel(_ b: DistanceBand) -> String {
        switch b {
        case .under1km: return "1 km'den yakın"
        case .from1to3km: return "1–3 km"
        case .from3to10km: return "3–10 km"
        }
    }
}
