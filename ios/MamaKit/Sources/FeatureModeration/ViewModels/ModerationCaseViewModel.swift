import Foundation
import Observation
import MamaCore

/// Tek vakanın detayı: önizleme, raporlar, içerik sahibinin geçmişi ve kararlar (onay diyaloğu ekranda).
/// Rota: `AppRoute.moderationCase(target:id:)`.
@MainActor
@Observable
public final class ModerationCaseViewModel {
    public let target: ReportTarget
    public let targetId: UUID
    public private(set) var detail: ModerationCaseDetail?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isBusy = false
    /// Hiç raporu olmayan (ya da artık bulunmayan) vaka.
    public private(set) var isNotFound = false
    /// Son eylemin sonucu.
    public private(set) var message: String?
    public var error: MamaError?
    /// İsteğe bağlı kısa not (karar kaydına yazılır, kullanıcıya gitmez).
    public var note = ""
    @ObservationIgnored private let services: AppServices

    public init(target: ReportTarget, targetId: UUID, services: AppServices) {
        self.target = target
        self.targetId = targetId
        self.services = services
    }

    public var isNoteTooLong: Bool { note.trimmingCharacters(in: .whitespacesAndNewlines).count > ModerationPolicy.maxNoteLength }

    /// Açık raporu olan vakada karar verilebilir.
    public var canDecide: Bool {
        guard let detail else { return false }
        return detail.reports.contains { $0.status == .open }
    }

    /// İçerik sahibi biliniyor, moderatör değil ve kişinin kendisi değil (sunucu yeniden denetler).
    public var canSuspend: Bool {
        guard let owner = detail?.owner else { return false }
        return !owner.isModerator && owner.userId != currentUserId
    }

    public var isOwnerSuspended: Bool {
        ModerationPolicy.isSuspended(until: detail?.owner?.suspendedUntil, now: services.now())
    }

    /// "24 Kasım 2026 tarihine kadar" / "Süresiz".
    public var ownerSuspensionText: String? {
        guard isOwnerSuspended, let until = detail?.owner?.suspendedUntil else { return nil }
        return ModerationFormat.suspensionText(until)
    }

    @ObservationIgnored private var currentUserId: UUID?

    public func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        currentUserId = await services.auth.currentUserId()
        await refresh()
    }

    @discardableResult
    public func decide(_ decision: ModerationDecision) async -> Bool {
        guard canDecide, !isNoteTooLong else { return false }
        return await act { [services, target, targetId, note] in
            let outcome = try await services.moderator.decide(target: target, id: targetId, decision: decision, note: note)
            switch outcome {
            case .done(let closed): return (true, ModerationFormat.decisionMessage(decision, closedReports: closed))
            default: return (false, ModerationFormat.failureMessage(outcome))
            }
        }
    }

    @discardableResult
    public func suspend(_ length: SuspensionLength) async -> Bool {
        guard let owner = detail?.owner, canSuspend, !isNoteTooLong else { return false }
        return await act { [services, note] in
            let outcome = try await services.moderator.suspend(userId: owner.userId, length: length, note: note)
            switch outcome {
            case .suspended(let until):
                return (true, ModerationFormat.suspendedMessage(name: owner.displayName, until: until))
            case .notAllowed: return (false, ModerationFormat.notAllowedMessage)
            case .notFound: return (false, ModerationFormat.notFoundMessage)
            case .invalid: return (false, ModerationFormat.invalidMessage)
            }
        }
    }

    @discardableResult
    public func unsuspend() async -> Bool {
        guard let owner = detail?.owner else { return false }
        return await act { [services] in
            let outcome = try await services.moderator.unsuspend(userId: owner.userId)
            switch outcome {
            case .done: return (true, ModerationFormat.unsuspendedMessage)
            default: return (false, ModerationFormat.failureMessage(outcome))
            }
        }
    }

    private func act(_ work: () async throws -> (Bool, String)) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        message = nil
        error = nil
        defer { isBusy = false }
        do {
            let (done, text) = try await work()
            message = text
            if done { note = "" }
            await refresh()
            return done
        } catch {
            self.error = MamaError.classify(error)
            return false
        }
    }

    private func refresh() async {
        do {
            detail = try await services.moderator.moderationCase(target: target, id: targetId)
            isNotFound = detail == nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }
}
