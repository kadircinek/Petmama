import Foundation
import MamaCore
import Supabase

// Moderasyon (Faz 3.1): `moderation_*` RPC'leri (docs/backend-contract.md → Moderasyon).
// Moderatörlük sunucuda her çağrıda yeniden doğrulanır; istemci yalnızca satırı gösterip gizler.

extension SupabaseBackend: ModeratorRepository {
    public func openCaseCount() async throws -> Int {
        try await perform {
            guard signedInUserId != nil else { return 0 }
            return SupabaseDecoding.openCaseCount(from: try await rpc("moderation_open_count"))
        }
    }

    public func moderationQueue(closed: Bool, limit: Int) async throws -> [ModerationCase] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("moderation_queue", ["p_closed": .bool(closed), "max_rows": .integer(limit)])
            return try SupabaseDecoding.moderationCases(from: data)
        }
    }

    public func moderationCase(target: ReportTarget, id: UUID) async throws -> ModerationCaseDetail? {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("moderation_target_reports", [
                "p_target_type": .string(target.rawValue),
                "p_target_id": Param.uuid(id),
            ])
            return try SupabaseDecoding.moderationCaseDetail(from: data)
        }
    }

    public func decide(target: ReportTarget, id: UUID, decision: ModerationDecision, note: String?) async throws -> ModerationOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("moderation_decide", Self.decideParams(target: target, id: id, decision: decision, note: note))
            return try SupabaseDecoding.moderationOutcome(from: data)
        }
    }

    public func suspend(userId: UUID, length: SuspensionLength, note: String?) async throws -> SuspendOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("moderation_suspend_user", Self.suspendParams(userId: userId, length: length, note: note))
            return try SupabaseDecoding.suspendOutcome(from: data)
        }
    }

    public func unsuspend(userId: UUID) async throws -> ModerationOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("moderation_unsuspend_user", ["p_user_id": Param.uuid(userId)])
            return try SupabaseDecoding.moderationOutcome(from: data, rpc: "moderation_unsuspend_user")
        }
    }

    // MARK: - Parametreler

    static func decideParams(target: ReportTarget, id: UUID, decision: ModerationDecision, note: String?) -> JSONObject {
        [
            "p_target_type": .string(target.rawValue),
            "p_target_id": Param.uuid(id),
            "p_action": .string(decision.rawValue),
            "p_note": Param.text(note),
        ]
    }

    static func suspendParams(userId: UUID, length: SuspensionLength, note: String?) -> JSONObject {
        [
            "p_user_id": Param.uuid(userId),
            "p_days": length.days.map(AnyJSON.integer) ?? .null,
            "p_note": Param.text(note),
        ]
    }

    /// Oturumdaki kullanıcının kendi uzaklaştırma bitişi (`my_suspension`); yoksa `nil`.
    func ownSuspension() async throws -> Date? {
        SupabaseDecoding.mySuspension(from: try await rpc("my_suspension"))
    }
}
