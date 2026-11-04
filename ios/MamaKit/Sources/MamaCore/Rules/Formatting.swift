import Foundation

/// Kısa, platformdan bağımsız biçimlendirme. Türkçe varsayılan, İngilizce ikinci dil (D12).
public enum MamaFormat {
    public enum Language: Sendable {
        case turkish, english

        public static var current: Language {
            let code = Locale.preferredLanguages.first?.prefix(2) ?? "tr"
            return code == "en" ? .english : .turkish
        }
    }

    /// "85 m", "1,2 km" / "1.2 km"
    public static func distance(_ meters: Double, language: Language = .current) -> String {
        guard meters.isFinite else { return "—" }
        if meters < 1000 {
            let rounded = meters < 100 ? (meters / 5).rounded() * 5 : (meters / 10).rounded() * 10
            return "\(Int(max(rounded, 1))) m"
        }
        let km = meters / 1000
        let text = km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
        return (language == .turkish ? text.replacingOccurrences(of: ".", with: ",") : text) + " km"
    }

    /// "az önce", "5 dk önce", "3 sa önce", "2 gün önce"
    public static func relative(_ date: Date?, now: Date = Date(), language: Language = .current) -> String {
        guard let date else { return language == .turkish ? "bilinmiyor" : "unknown" }
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        let hours = Int(seconds / 3600)
        let days = Int(seconds / 86_400)
        switch language {
        case .turkish:
            if minutes < 1 { return "az önce" }
            if minutes < 60 { return "\(minutes) dk önce" }
            if hours < 24 { return "\(hours) sa önce" }
            return "\(days) gün önce"
        case .english:
            if minutes < 1 { return "just now" }
            if minutes < 60 { return "\(minutes)m ago" }
            if hours < 24 { return "\(hours)h ago" }
            return "\(days)d ago"
        }
    }

    /// Selamlama: "Günaydın", "İyi günler", "İyi akşamlar", "İyi geceler".
    public static func greeting(at date: Date = Date(), timeZone: TimeZone = .current, language: Language = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        switch (language, hour) {
        case (.turkish, 5..<12): return "Günaydın"
        case (.turkish, 12..<18): return "İyi günler"
        case (.turkish, 18..<23): return "İyi akşamlar"
        case (.turkish, _): return "İyi geceler"
        case (.english, 5..<12): return "Good morning"
        case (.english, 12..<18): return "Good afternoon"
        case (.english, 18..<23): return "Good evening"
        case (.english, _): return "Good night"
        }
    }

    /// "5 USD", "12,50 USD"
    public static func usd(_ amount: Decimal, language: Language = .current) -> String {
        money(amount, code: "USD", language: language)
    }

    /// "≈ 210 TL"
    public static func approxTry(_ amount: Decimal, language: Language = .current) -> String {
        "≈ " + money(amount, code: "TL", language: language)
    }

    private static func money(_ amount: Decimal, code: String, language: Language) -> String {
        let number = NSDecimalNumber(decimal: amount).doubleValue
        let hasFraction = number.rounded() != number
        var text = hasFraction ? String(format: "%.2f", number) : String(format: "%.0f", number)
        if language == .turkish { text = text.replacingOccurrences(of: ".", with: ",") }
        return "\(text) \(code)"
    }

    /// "1.234 kg" / "1,234 kg" — binlik ayırıcılı tam sayı.
    public static func kilograms(_ kg: Double, language: Language = .current) -> String {
        let value = Int(kg.rounded())
        let digits = String(value)
        var grouped = ""
        for (index, char) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(language == .turkish ? "." : ",") }
            grouped.append(char)
        }
        return String(grouped.reversed()) + " kg"
    }
}
