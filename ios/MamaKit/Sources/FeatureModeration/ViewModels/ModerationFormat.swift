import Foundation
import MamaCore

/// Moderasyon ekranlarının Türkçe metinleri (ViewModel'ler Linux'ta derlenir ve test edilir).
public enum ModerationFormat {
    public static let notAllowedMessage = "Bu işlem için moderatör yetkin yok ya da bu kişi uzaklaştırılamaz."
    public static let notFoundMessage = "Bu rapor artık bulunamadı."
    public static let invalidMessage = "Not en fazla 500 karakter olabilir."
    public static let unsuspendedMessage = "Uzaklaştırma kaldırıldı."

    public static func reportCount(_ count: Int) -> String { "\(count) rapor" }

    public static func stateLabel(_ state: ModerationContentState) -> String {
        switch state {
        case .live: return "Yayında"
        case .pending: return "İncelemede"
        case .removed: return "Kaldırıldı"
        case .gone: return "Silinmiş"
        }
    }

    public static func decisionLabel(_ decision: ModerationDecision) -> String {
        switch decision {
        case .approve: return "Uygun bulundu"
        case .remove: return "Kaldırıldı"
        }
    }

    public static func lengthLabel(_ length: SuspensionLength) -> String {
        switch length {
        case .week: return "7 gün"
        case .month: return "30 gün"
        case .indefinite: return "Süresiz"
        }
    }

    public static func decisionMessage(_ decision: ModerationDecision, closedReports: Int) -> String {
        switch decision {
        case .approve: return "Uygun bulundu, içerik yayında kalıyor. \(reportCount(closedReports)) kapandı."
        case .remove: return "İçerik kaldırıldı. \(reportCount(closedReports)) kapandı."
        }
    }

    public static func failureMessage(_ outcome: ModerationOutcome) -> String {
        switch outcome {
        case .done: return ""
        case .notAllowed: return notAllowedMessage
        case .notFound: return notFoundMessage
        case .invalid: return invalidMessage
        }
    }

    /// "24 Kasım 2026 tarihine kadar" / "Süresiz".
    public static func suspensionText(_ until: Date) -> String {
        if ModerationPolicy.isIndefinite(until) { return "Süresiz" }
        return "\(MamaFormat.day(until)) tarihine kadar"
    }

    public static func suspendedMessage(name: String?, until: Date) -> String {
        let who = name ?? "Kullanıcı"
        if ModerationPolicy.isIndefinite(until) { return "\(who) süresiz uzaklaştırıldı." }
        return "\(who) \(MamaFormat.day(until)) tarihine kadar uzaklaştırıldı."
    }
}
