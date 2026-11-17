import Foundation
import MamaCore

// Moderasyon (Faz 3.1): `moderation_*` RPC satırları ve jsonb sonuçları → domain.
// Sunucu karşılığı: supabase/migrations/20261117000026_moderation.sql.

/// Uzaklaştırma bitişi: `'infinity'` → `Date.distantFuture` (süresiz).
func suspensionDate(_ text: String?) -> Date? {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    if text.lowercased() == "infinity" { return .distantFuture }
    return PostgresDate.parse(text)
}

private func decodeReasons(_ raw: [String]?) -> [ReportReason] {
    (raw ?? []).compactMap(ReportReason.init(rawValue:))
}

/// `moderation_queue` satırı.
struct ModerationCaseRowDTO: Decodable {
    var targetType: String
    var targetId: UUID
    var title: String?
    var body: String?
    var photoUrl: String?
    var ownerId: UUID?
    var ownerName: String?
    var reportCount: Int?
    var reasons: [String]?
    var firstReportedAt: String?
    var lastReportedAt: String?
    var contentState: String?
    var decision: String?
    var decidedAt: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "target_type"
        case targetId = "target_id"
        case title, body
        case photoUrl = "photo_url"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case reportCount = "report_count"
        case reasons
        case firstReportedAt = "first_reported_at"
        case lastReportedAt = "last_reported_at"
        case contentState = "content_state"
        case decision
        case decidedAt = "decided_at"
    }

    /// Bilinmeyen hedef türü (daha yeni sunucu) düşer.
    func toDomain() -> ModerationCase? {
        guard let target = ReportTarget(rawValue: targetType) else { return nil }
        let first = firstReportedAt.flatMap(PostgresDate.parse) ?? Date(timeIntervalSince1970: 0)
        return ModerationCase(
            target: target,
            targetId: targetId,
            title: title,
            body: body,
            photoURL: photoUrl?.nonEmptyURL,
            ownerId: ownerId,
            ownerName: ownerName,
            reportCount: reportCount ?? 0,
            reasons: decodeReasons(reasons),
            firstReportedAt: first,
            lastReportedAt: lastReportedAt.flatMap(PostgresDate.parse) ?? first,
            contentState: contentState.flatMap(ModerationContentState.init(rawValue:)) ?? .live,
            decision: decision.flatMap(ModerationDecision.init(rawValue:)),
            decidedAt: decidedAt.flatMap(PostgresDate.parse)
        )
    }
}

/// `moderation_target_reports` jsonb gövdesi.
struct ModerationDetailDTO: Decodable {
    struct CaseDTO: Decodable {
        var targetType: String
        var targetId: UUID
        var title: String?
        var body: String?
        var photoUrl: String?
        var ownerId: UUID?
        var ownerName: String?
        var contentState: String?
        var decision: String?
        var decidedAt: String?
        var restorable: Bool?

        enum CodingKeys: String, CodingKey {
            case targetType = "target_type"
            case targetId = "target_id"
            case title, body
            case photoUrl = "photo_url"
            case ownerId = "owner_id"
            case ownerName = "owner_name"
            case contentState = "content_state"
            case decision
            case decidedAt = "decided_at"
            case restorable
        }
    }

    struct ReportDTO: Decodable {
        var id: UUID
        var reason: String
        var details: String?
        var createdAt: String?
        var reporterId: UUID?
        var reporterName: String?
        var status: String?

        enum CodingKeys: String, CodingKey {
            case id, reason, details, status
            case createdAt = "created_at"
            case reporterId = "reporter_id"
            case reporterName = "reporter_name"
        }

        func toDomain() -> ModerationReportEntry? {
            guard let reason = ReportReason(rawValue: reason) else { return nil }
            return ModerationReportEntry(
                id: id,
                reason: reason,
                details: details,
                createdAt: createdAt.flatMap(PostgresDate.parse) ?? Date(timeIntervalSince1970: 0),
                reporterId: reporterId,
                reporterName: reporterName,
                status: status.flatMap(ModerationReportStatus.init(rawValue:)) ?? .open
            )
        }
    }

    struct OwnerDTO: Decodable {
        var userId: UUID
        var displayName: String?
        var avatarUrl: String?
        var isModerator: Bool?
        var removedCount90d: Int?
        var suspensionCount90d: Int?
        var suspendedUntil: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case displayName = "display_name"
            case avatarUrl = "avatar_url"
            case isModerator = "is_moderator"
            case removedCount90d = "removed_count_90d"
            case suspensionCount90d = "suspension_count_90d"
            case suspendedUntil = "suspended_until"
        }

        func toDomain() -> ModerationOwnerHistory {
            ModerationOwnerHistory(
                userId: userId,
                displayName: displayName,
                avatarURL: avatarUrl?.nonEmptyURL,
                isModerator: isModerator ?? false,
                removedCount90d: removedCount90d ?? 0,
                suspensionCount90d: suspensionCount90d ?? 0,
                suspendedUntil: suspensionDate(suspendedUntil)
            )
        }
    }

    var status: String
    var `case`: CaseDTO?
    var reports: LossyArray<ReportDTO>?
    var owner: OwnerDTO?

    func toDomain() throws -> ModerationCaseDetail? {
        switch status {
        case "ok": break
        case "not_found": return nil
        default: throw StatusError.unexpected(rpc: "moderation_target_reports", status: status)
        }
        guard let row = self.case, let target = ReportTarget(rawValue: row.targetType) else {
            throw MamaError.server("moderation_target_reports: eksik hedef")
        }
        let entries = (reports?.elements ?? []).compactMap { $0.toDomain() }
        let open = entries.filter { $0.status == .open }
        let counted = open.isEmpty ? entries : open
        let dates = counted.map(\.createdAt)
        var orderedReasons: [ReportReason] = []
        for entry in counted where !orderedReasons.contains(entry.reason) { orderedReasons.append(entry.reason) }
        let summary = ModerationCase(
            target: target,
            targetId: row.targetId,
            title: row.title,
            body: row.body,
            photoURL: row.photoUrl?.nonEmptyURL,
            ownerId: row.ownerId,
            ownerName: row.ownerName,
            reportCount: counted.count,
            reasons: orderedReasons,
            firstReportedAt: dates.min() ?? Date(timeIntervalSince1970: 0),
            lastReportedAt: dates.max() ?? Date(timeIntervalSince1970: 0),
            contentState: row.contentState.flatMap(ModerationContentState.init(rawValue:)) ?? .live,
            decision: open.isEmpty ? row.decision.flatMap(ModerationDecision.init(rawValue:)) : nil,
            decidedAt: open.isEmpty ? row.decidedAt.flatMap(PostgresDate.parse) : nil,
            isRestorable: row.restorable ?? true
        )
        return ModerationCaseDetail(moderationCase: summary, reports: entries, owner: owner?.toDomain())
    }
}

/// `moderation_decide` / `moderation_suspend_user` / `moderation_unsuspend_user` jsonb sonucu.
struct ModerationResultDTO: Decodable {
    var status: String
    var reason: String?
    var closedReports: Int?
    var suspendedUntil: String?

    enum CodingKeys: String, CodingKey {
        case status, reason
        case closedReports = "closed_reports"
        case suspendedUntil = "suspended_until"
    }

    func moderationOutcome(rpc: String) throws -> ModerationOutcome {
        switch status {
        case "ok": return .done(closedReports: closedReports ?? 0)
        case "not_allowed": return .notAllowed
        case "not_found": return .notFound
        case "invalid": return .invalid(reason: reason ?? "unknown")
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func suspendOutcome() throws -> SuspendOutcome {
        switch status {
        case "ok":
            guard let until = suspensionDate(suspendedUntil) else {
                throw MamaError.server("moderation_suspend_user: bitiş yok")
            }
            return .suspended(until: until)
        case "not_allowed": return .notAllowed
        case "not_found": return .notFound
        case "invalid": return .invalid(reason: reason ?? "unknown")
        default: throw StatusError.unexpected(rpc: "moderation_suspend_user", status: status)
        }
    }
}

extension SupabaseDecoding {
    static func moderationCases(from data: Data) throws -> [ModerationCase] {
        try SupabaseJSON.rows(ModerationCaseRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func moderationCaseDetail(from data: Data) throws -> ModerationCaseDetail? {
        try SupabaseJSON.object(ModerationDetailDTO.self, from: data).toDomain()
    }

    static func moderationOutcome(from data: Data, rpc: String = "moderation_decide") throws -> ModerationOutcome {
        try SupabaseJSON.object(ModerationResultDTO.self, from: data).moderationOutcome(rpc: rpc)
    }

    static func suspendOutcome(from data: Data) throws -> SuspendOutcome {
        try SupabaseJSON.object(ModerationResultDTO.self, from: data).suspendOutcome()
    }

    /// `my_suspension()`: `null` | `"infinity"` | timestamptz.
    static func mySuspension(from data: Data) -> Date? {
        if SupabaseJSON.isEmptyBody(data) { return nil }
        let text = (try? JSONDecoder().decode(String.self, from: data))
            ?? String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        return suspensionDate(text)
    }

    /// `moderation_open_count()`: skaler int.
    static func openCaseCount(from data: Data) -> Int {
        if SupabaseJSON.isEmptyBody(data) { return 0 }
        if let value = try? JSONDecoder().decode(Int.self, from: data) { return value }
        return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
