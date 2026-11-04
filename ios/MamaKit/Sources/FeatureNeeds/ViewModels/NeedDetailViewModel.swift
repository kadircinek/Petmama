import Foundation
import Observation
import MamaCore

/// Durum zaman çizelgesindeki bir adım: açıldı → üstlenildi → çözüldü (FR-I2).
public struct NeedTimelineStep: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case opened, claimed, resolved }

    public let kind: Kind
    public var title: String
    public var detail: String?
    public var date: Date?
    public var isDone: Bool

    public var id: Kind { kind }
}

/// İhtiyaç detayı.
@MainActor
@Observable
public final class NeedDetailViewModel {
    public private(set) var need: Need?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isWorking = false
    public var error: MamaError?

    public let needId: UUID
    @ObservationIgnored private let services: AppServices

    public init(needId: UUID, services: AppServices) {
        self.needId = needId
        self.services = services
    }

    public var now: Date { services.now() }

    public func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            need = try await services.needs.need(id: needId)
            error = need == nil ? .notFound : nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    // MARK: - Eylemler

    public var canClaim: Bool { need?.status == .open }

    /// Açan, üstlenen veya doğrulanmış besleyici "Çözüldü" görür. Son kararı sunucu verir.
    public func canResolve(userId: UUID?, isVerifiedFeeder: Bool) -> Bool {
        guard let need, need.status != .resolved, let userId else { return false }
        return need.createdBy == userId || need.claimedBy == userId || isVerifiedFeeder
    }

    /// Acil veteriner bilgisi bağlantısı (FR-I4).
    public var showsVetHelp: Bool { need?.type == .vet }

    public func claim() async -> NeedClaimResult {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = NeedClaimResult(try await services.needs.claim(needId: needId))
            await load()
            return result
        } catch {
            return .failed(MamaError.classify(error))
        }
    }

    public func resolve() async -> NeedResolveResult {
        isWorking = true
        defer { isWorking = false }
        do {
            let allowed = try await services.needs.resolve(needId: needId)
            guard allowed else { return .notAllowed }
            await load()
            return .resolved
        } catch {
            return .failed(MamaError.classify(error))
        }
    }

    // MARK: - Zaman çizelgesi

    public var timeline: [NeedTimelineStep] {
        guard let need else { return [] }
        let wasClaimed = need.claimedBy != nil || need.claimedAt != nil || need.status == .claimed
        let claimDetail: String
        if let name = need.claimedByName {
            claimDetail = "\(name) ilgileniyor"
        } else if wasClaimed {
            claimDetail = "Bir gönüllü ilgileniyor"
        } else if need.status == .resolved {
            claimDetail = "Üstlenilmeden çözüldü"
        } else {
            claimDetail = "Henüz kimse üstlenmedi"
        }
        return [
            NeedTimelineStep(kind: .opened, title: "İhtiyaç açıldı", detail: nil, date: need.createdAt, isDone: true),
            NeedTimelineStep(kind: .claimed, title: "Üstlenildi", detail: claimDetail, date: need.claimedAt, isDone: wasClaimed),
            NeedTimelineStep(
                kind: .resolved,
                title: "Çözüldü",
                detail: need.status == .resolved ? nil : "Henüz çözülmedi",
                date: need.resolvedAt,
                isDone: need.status == .resolved
            ),
        ]
    }
}
