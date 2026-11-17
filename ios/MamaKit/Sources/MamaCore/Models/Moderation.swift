import Foundation

public enum ReportTarget: String, Codable, CaseIterable, Sendable, Hashable {
    case spot, animal, need, checkin, photo, user
    /// Mahalle paylaşımı ve yorumu.
    case post, comment
    /// Buluşma ve sohbet mesajı (Tanışma).
    case meetup
    case chatMessage = "chat_message"
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

// MARK: - Moderasyon ekranı (Faz 3.1, docs/backend-contract.md → Moderasyon)

/// Moderatörün rapor edilen içerik için kararı.
public enum ModerationDecision: String, Codable, CaseIterable, Sendable, Hashable {
    /// Uygun, yayında kalsın: içerik onaylanır (otomatik gizlendiyse geri açılır), açık raporlar reddedilir.
    case approve
    /// İçerik herkesten gizlenir (ya da iptal edilir / silinir), açık raporlar işleme alınır.
    case remove
}

/// Uzaklaştırma süresi. Uzaklaştırılan kullanıcı okur ama yazamaz.
public enum SuspensionLength: String, CaseIterable, Sendable, Hashable {
    case week, month, indefinite

    /// `nil` = süresiz.
    public var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .indefinite: return nil
        }
    }
}

/// Raporlanan içeriğin şu anki durumu.
public enum ModerationContentState: String, Codable, Sendable, Hashable {
    /// Yayında.
    case live
    /// İncelemede (otomatik gizlendi ya da düşük güven puanıyla bekliyor).
    case pending
    /// Moderatör kaldırdı.
    case removed
    /// İçerik artık yok (sahibi sildi).
    case gone
}

public enum ModerationReportStatus: String, Codable, Sendable, Hashable {
    case open
    /// Moderatör içeriği kaldırdı.
    case actioned
    /// Moderatör içeriği uygun buldu.
    case dismissed
}

/// Kuyruktaki bir satır: aynı hedefe gelen raporlar tek satırda.
public struct ModerationCase: Identifiable, Hashable, Sendable {
    public var target: ReportTarget
    public var targetId: UUID
    /// Başlık (nokta/hayvan adı, buluşma başlığı, kullanıcı adı…); ihtiyaç ve paylaşımda tür anahtarı.
    public var title: String?
    /// Kısa metin (en fazla 300 karakter). Sohbet mesajında yalnızca raporlanan mesaj.
    public var body: String?
    public var photoURL: URL?
    public var ownerId: UUID?
    public var ownerName: String?
    /// Açık sekmede açık rapor sayısı, Kapananlar'da tüm raporlar.
    public var reportCount: Int
    public var reasons: [ReportReason]
    public var firstReportedAt: Date
    public var lastReportedAt: Date
    public var contentState: ModerationContentState
    /// Kapananlar'da verilen karar.
    public var decision: ModerationDecision?
    public var decidedAt: Date?

    public var id: String { "\(target.rawValue)-\(targetId.uuidString)" }

    public init(
        target: ReportTarget,
        targetId: UUID,
        title: String? = nil,
        body: String? = nil,
        photoURL: URL? = nil,
        ownerId: UUID? = nil,
        ownerName: String? = nil,
        reportCount: Int,
        reasons: [ReportReason],
        firstReportedAt: Date,
        lastReportedAt: Date,
        contentState: ModerationContentState,
        decision: ModerationDecision? = nil,
        decidedAt: Date? = nil
    ) {
        self.target = target
        self.targetId = targetId
        self.title = title
        self.body = body
        self.photoURL = photoURL
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.reportCount = reportCount
        self.reasons = reasons
        self.firstReportedAt = firstReportedAt
        self.lastReportedAt = lastReportedAt
        self.contentState = contentState
        self.decision = decision
        self.decidedAt = decidedAt
    }

    /// Henüz karar verilmemiş (Açık sekmesi).
    public var isOpen: Bool { decision == nil }
}

/// Detaydaki tek rapor.
public struct ModerationReportEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var reason: ReportReason
    public var details: String?
    public var createdAt: Date
    public var reporterId: UUID?
    /// Hesabını silen raporlayanda `nil`.
    public var reporterName: String?
    public var status: ModerationReportStatus

    public init(id: UUID, reason: ReportReason, details: String?, createdAt: Date, reporterId: UUID?, reporterName: String?, status: ModerationReportStatus) {
        self.id = id
        self.reason = reason
        self.details = details
        self.createdAt = createdAt
        self.reporterId = reporterId
        self.reporterName = reporterName
        self.status = status
    }
}

/// İçerik sahibinin son 90 gündeki geçmişi.
public struct ModerationOwnerHistory: Hashable, Sendable {
    public var userId: UUID
    public var displayName: String?
    public var isModerator: Bool
    public var removedCount90d: Int
    public var suspensionCount90d: Int
    /// Şu an uzaklaştırılmışsa bitiş; süresiz `Date.distantFuture`.
    public var suspendedUntil: Date?

    public init(userId: UUID, displayName: String?, isModerator: Bool = false, removedCount90d: Int, suspensionCount90d: Int, suspendedUntil: Date?) {
        self.userId = userId
        self.displayName = displayName
        self.isModerator = isModerator
        self.removedCount90d = removedCount90d
        self.suspensionCount90d = suspensionCount90d
        self.suspendedUntil = suspendedUntil
    }
}

public struct ModerationCaseDetail: Hashable, Sendable {
    public var moderationCase: ModerationCase
    /// Yeniden eskiye; açık ve kapanmış raporlar.
    public var reports: [ModerationReportEntry]
    /// İçerik sahibi bilinmiyorsa (hesabını silmiş) `nil`.
    public var owner: ModerationOwnerHistory?

    public init(moderationCase: ModerationCase, reports: [ModerationReportEntry], owner: ModerationOwnerHistory?) {
        self.moderationCase = moderationCase
        self.reports = reports
        self.owner = owner
    }
}

public enum ModerationOutcome: Hashable, Sendable {
    case done(closedReports: Int)
    case notAllowed
    case notFound
    case invalid(reason: String)
}

public enum SuspendOutcome: Hashable, Sendable {
    /// Süresiz uzaklaştırmada `Date.distantFuture`.
    case suspended(until: Date)
    case notAllowed
    case notFound
    case invalid(reason: String)
}

public enum ModerationPolicy {
    public static let maxNoteLength = 500
    public static let previewLength = 300
    /// Kapananlar sekmesi bu kadar günü gösterir.
    public static let closedWindowDays = 30
    /// Sahip geçmişi penceresi.
    public static let historyWindowDays = 90

    /// Süresiz uzaklaştırma (`'infinity'` / `Date.distantFuture`).
    public static func isIndefinite(_ until: Date) -> Bool {
        until >= Date(timeIntervalSince1970: 32_503_680_000) // 3000-01-01
    }

    public static func isSuspended(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return until > now
    }

    /// Boşlukları kırpılmış not; boşsa `nil`.
    public static func normalizedNote(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
