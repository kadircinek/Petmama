import Foundation

public enum ReportTarget: String, Codable, CaseIterable, Sendable, Hashable {
    case spot, animal, need, checkin, photo, user
}

public enum ReportReason: String, Codable, CaseIterable, Sendable, Hashable {
    case inappropriate
    case spam
    case wrongLocation = "wrong_location"
    /// "Şüpheli durum": zehirleme şüphesi veya hayvana zarar (PRD 9.1).
    case animalHarm = "animal_harm"
    case harassment
    case other
}

public struct ReportDraft: Hashable, Codable, Sendable {
    public var target: ReportTarget
    public var targetId: UUID
    public var reason: ReportReason
    public var details: String?

    public init(target: ReportTarget, targetId: UUID, reason: ReportReason, details: String? = nil) {
        self.target = target
        self.targetId = targetId
        self.reason = reason
        self.details = details
    }
}
