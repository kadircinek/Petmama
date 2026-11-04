import Foundation
import Observation
import MamaCore

/// Raporla (PRD 9.1–9.2, App Store 1.2): neden, isteğe bağlı açıklama, kullanıcı için engelleme.
@MainActor
@Observable
public final class ReportViewModel {
    public let target: ReportTarget
    public let targetId: UUID

    public var reason: ReportReason?
    public var details = ""
    /// Yalnızca kullanıcı raporunda: "Bu kullanıcıyı engelle".
    public var alsoBlock = false
    public private(set) var isSubmitting = false
    public private(set) var didSubmit = false
    public private(set) var didBlock = false
    public private(set) var blockFailed = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let services: AppServices

    public static let reasons = ReportReason.allCases
    public static let maximumDetailsLength = 500
    public static let thankYouMessage = "Teşekkürler. Raporunu 24 saat içinde inceleyeceğiz."
    public static let animalHarmWarning =
        "Zehirleme veya hayvana zarar şüphesinde lütfen 112'yi ara; bölgedeki koruyuculara da haber verdik."

    public init(target: ReportTarget, targetId: UUID, services: AppServices) {
        self.target = target
        self.targetId = targetId
        self.services = services
    }

    public var showsAnimalHarmWarning: Bool { reason == .animalHarm }
    public var offersBlock: Bool { target == .user }
    public var isDetailsTooLong: Bool { details.count > Self.maximumDetailsLength }
    public var canSubmit: Bool { reason != nil && !isSubmitting && !isDetailsTooLong }

    /// "Bu noktayı neden bildiriyorsun?"
    public var question: String {
        switch target {
        case .spot: return "Bu noktayı neden bildiriyorsun?"
        case .animal: return "Bu hayvan profilini neden bildiriyorsun?"
        case .need: return "Bu ihtiyacı neden bildiriyorsun?"
        case .checkin: return "Bu kaydı neden bildiriyorsun?"
        case .photo: return "Bu fotoğrafı neden bildiriyorsun?"
        case .user: return "Bu kullanıcıyı neden bildiriyorsun?"
        }
    }

    /// Gönderim sonrası toast metni.
    public var completionMessage: String {
        if didBlock { return Self.thankYouMessage + " Bu kullanıcıyı engelledin." }
        if blockFailed { return Self.thankYouMessage + " Engelleme şu an tamamlanamadı." }
        return Self.thankYouMessage
    }

    @discardableResult
    public func submit() async -> Bool {
        errorMessage = nil
        guard let reason else {
            errorMessage = "Lütfen bir neden seç."
            return false
        }
        guard !isDetailsTooLong else {
            errorMessage = "Açıklama en fazla \(Self.maximumDetailsLength) karakter olabilir."
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await services.moderation.report(
                ReportDraft(target: target, targetId: targetId, reason: reason, details: text.isEmpty ? nil : text)
            )
        } catch {
            errorMessage = MamaError.classify(error).userMessage
            return false
        }
        didSubmit = true
        if offersBlock && alsoBlock {
            do {
                try await services.moderation.block(userId: targetId)
                didBlock = true
            } catch {
                blockFailed = true
            }
        }
        return true
    }
}
