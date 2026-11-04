import Foundation
import Observation
import MamaCore

/// İhtiyaçlar sekmesi (ekran 17, FR-I1…I5).
@MainActor
@Observable
public final class NeedsListViewModel {
    public static let radiusMeters = 5000

    public private(set) var needs: [Need] = []
    /// Boş küme = tüm tipler.
    public private(set) var selectedTypes: Set<NeedType> = []
    public var includeResolved = false
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var claimingId: UUID?
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var now: Date { services.now() }

    /// Seçili tiplere göre süzülmüş; önce açık acil, sonra mesafe (FR-I5).
    public var visibleNeeds: [Need] {
        let filtered = needs.filter { need in
            (selectedTypes.isEmpty || selectedTypes.contains(need.type))
                && (includeResolved || need.status != .resolved)
        }
        return NeedSorting.sorted(filtered)
    }

    public var hasActiveFilter: Bool { !selectedTypes.isEmpty }

    public var isEmpty: Bool { hasLoaded && visibleNeeds.isEmpty }

    public func load(near coordinate: Coordinate?) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            needs = try await services.needs.needs(
                near: coordinate ?? .modaKadikoy,
                radiusMeters: Self.radiusMeters,
                includeResolved: includeResolved
            )
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func toggleType(_ type: NeedType) {
        if selectedTypes.contains(type) { selectedTypes.remove(type) } else { selectedTypes.insert(type) }
    }

    public func clearTypes() {
        selectedTypes = []
    }

    /// Oturum kontrolü görünümde yapılır (giriş yoksa giriş ekranı açılır).
    public func claim(_ needId: UUID, near coordinate: Coordinate?) async -> NeedClaimResult {
        claimingId = needId
        defer { claimingId = nil }
        let result: NeedClaimResult
        do {
            result = NeedClaimResult(try await services.needs.claim(needId: needId))
        } catch {
            return .failed(MamaError.classify(error))
        }
        await load(near: coordinate)
        return result
    }
}
