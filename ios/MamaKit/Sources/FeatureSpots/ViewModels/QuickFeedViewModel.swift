import Foundation
import Observation
import MamaCore

/// Tek dokunuşla "Mama koydum" (PRD 6.4): kullanıcının 100 m içindeki en yakın noktasını seçer ve onay ister.
/// Yakında nokta yoksa en yakın birkaç noktayı ve "Yeni nokta ekle"yi gösterir.
@MainActor
@Observable
public final class QuickFeedViewModel {
    public enum State: Equatable, Sendable {
        case locating
        case needsLocation
        case candidate(Spot, distanceMeters: Double)
        case noneNearby([Spot])
        case failed(MamaError)
    }

    /// Aday arama yarıçapı. Aday yine de `CheckInPolicy.feedMaxDistance` (100 m) içinde olmalı.
    public static let searchRadiusMeters = 150
    public static let fallbackRadiusMeters = 1000
    public static let fallbackCount = 3

    public internal(set) var state: State = .locating
    public internal(set) var isSubmitting = false
    public internal(set) var result: CheckInResult?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var userCoordinate: Coordinate?

    public init(services: AppServices) {
        self.services = services
    }

    public var now: Date { services.now() }

    public var candidate: Spot? {
        if case .candidate(let spot, _) = state { return spot }
        return nil
    }

    public func locate(user: Coordinate?) async {
        guard let user else {
            state = .needsLocation
            return
        }
        userCoordinate = user
        result = nil
        state = .locating
        do {
            let close = try await services.spots.spots(near: user, radiusMeters: Self.searchRadiusMeters)
            if let found = CheckInPolicy.quickFeedCandidate(user: user, spots: close) {
                state = .candidate(found.spot.withDistance(from: user), distanceMeters: found.distance)
                return
            }
            let wider = try await services.spots.spots(near: user, radiusMeters: Self.fallbackRadiusMeters)
            state = .noneNearby(Array(wider.prefix(Self.fallbackCount)))
        } catch {
            let classified = MamaError.classify(error)
            guard classified.isConnectivity else {
                state = .failed(classified)
                return
            }
            // Çevrimdışı: son görülen noktalardan seç; check-in kuyruğa alınır (FR-H8).
            let radius = Double(Self.fallbackRadiusMeters)
            let cached = await services.spotCache.cachedSpots(in: GeoBounds(center: user, radiusMeters: radius))
                .map { $0.withDistance(from: user) }
                .filter { $0.isActive && ($0.distanceMeters ?? .infinity) <= radius }
                .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
            if let found = CheckInPolicy.quickFeedCandidate(user: user, spots: cached) {
                state = .candidate(found.spot.withDistance(from: user), distanceMeters: found.distance)
            } else {
                state = .noneNearby(Array(cached.prefix(Self.fallbackCount)))
            }
        }
    }

    @discardableResult
    public func submit() async -> CheckInResult {
        guard case .candidate(let spot, _) = state, let user = userCoordinate else {
            let missing = CheckInResult.locationUnavailable
            result = missing
            return missing
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let draft = CheckInDraft(spotId: spot.id, kind: .fed, userCoordinate: user, createdAt: services.now())
        let outcome: CheckInResult
        do {
            outcome = CheckInResult(try await services.checkIns.checkIn(draft), kind: .fed)
        } catch {
            outcome = .failed(MamaError.classify(error))
        }
        result = outcome
        return outcome
    }
}
