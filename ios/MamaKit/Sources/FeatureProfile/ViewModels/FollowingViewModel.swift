import Foundation
import Observation
import MamaCore

/// Takip ettiklerim (ekran 21): Tümü / Yakında / Son.
@MainActor
@Observable
public final class FollowingViewModel {
    public enum Segment: String, CaseIterable, Sendable, Hashable {
        case all, nearby, recent

        public var title: String {
            switch self {
            case .all: return "Tümü"
            case .nearby: return "Yakında"
            case .recent: return "Son"
            }
        }
    }

    /// Takip edilen hayvan + son görüldüğü nokta (mesafe ve başlık için).
    public struct AnimalItem: Identifiable, Hashable, Sendable {
        public let animal: Animal
        public let lastSeenSpot: Spot?

        public var id: UUID { animal.id }
        public var distanceMeters: Double? { lastSeenSpot?.distanceMeters }
    }

    /// "Yakında" sekmesinin yarıçapı.
    public static let nearbyRadiusMeters: Double = 1000

    public var segment: Segment = .all
    public private(set) var spots: [Spot] = []
    public private(set) var animals: [AnimalItem] = []
    public private(set) var origin: Coordinate?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var now: Date { services.now() }

    public func load(near coordinate: Coordinate?) async {
        isLoading = true
        defer { isLoading = false }
        origin = coordinate
        do {
            let followedSpots = try await services.profiles.followedSpots()
            let followedAnimals = try await services.profiles.followedAnimals()
            spots = followedSpots.map { $0.withDistance(from: coordinate) }

            var known = Dictionary(spots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var items: [AnimalItem] = []
            for animal in followedAnimals {
                var lastSeen: Spot?
                if let spotId = animal.lastSeenSpotId {
                    if let cached = known[spotId] {
                        lastSeen = cached
                    } else if let fetched = try? await services.spots.spot(id: spotId) {
                        let located = fetched.withDistance(from: coordinate)
                        known[spotId] = located
                        lastSeen = located
                    }
                }
                items.append(AnimalItem(animal: animal, lastSeenSpot: lastSeen))
            }
            animals = items
            hasLoaded = true
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    /// Konum değişince yeniden sorgulamadan mesafeleri günceller.
    public func updateOrigin(_ coordinate: Coordinate?) {
        guard coordinate != origin else { return }
        origin = coordinate
        spots = spots.map { $0.withDistance(from: coordinate) }
        animals = animals.map { AnimalItem(animal: $0.animal, lastSeenSpot: $0.lastSeenSpot?.withDistance(from: coordinate)) }
    }

    // MARK: - Görünen liste

    public var visibleSpots: [Spot] {
        switch segment {
        case .all:
            return spots.sorted { lhs, rhs in
                let l = lhs.distanceMeters ?? .infinity
                let r = rhs.distanceMeters ?? .infinity
                return l != r ? l < r : lhs.title < rhs.title
            }
        case .nearby:
            return spots
                .filter { ($0.distanceMeters ?? .infinity) <= Self.nearbyRadiusMeters }
                .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        case .recent:
            return spots.sorted { lhs, rhs in
                let l = lhs.lastFedAt ?? .distantPast
                let r = rhs.lastFedAt ?? .distantPast
                return l != r ? l > r : lhs.title < rhs.title
            }
        }
    }

    public var visibleAnimals: [AnimalItem] {
        switch segment {
        case .all:
            return animals
        case .nearby:
            return animals
                .filter { ($0.distanceMeters ?? .infinity) <= Self.nearbyRadiusMeters }
                .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        case .recent:
            return animals.sorted { ($0.animal.lastSeenAt ?? .distantPast) > ($1.animal.lastSeenAt ?? .distantPast) }
        }
    }

    /// Hiçbir şey takip edilmiyor.
    public var isEmpty: Bool { spots.isEmpty && animals.isEmpty }

    /// Seçili sekmede gösterilecek bir şey yok.
    public var isSegmentEmpty: Bool { visibleSpots.isEmpty && visibleAnimals.isEmpty }

    /// "Yakında" sekmesi konum olmadan çalışmaz.
    public var needsLocationForSegment: Bool { segment == .nearby && origin == nil }

    // MARK: - Takibi bırak

    public func unfollow(spot: Spot) async {
        await unfollow(target: .spot, id: spot.id) {
            self.spots.removeAll { $0.id == spot.id }
        }
    }

    public func unfollow(animal: Animal) async {
        await unfollow(target: .animal, id: animal.id) {
            self.animals.removeAll { $0.id == animal.id }
        }
    }

    private func unfollow(target: FollowTarget, id: UUID, onSuccess: () -> Void) async {
        do {
            try await services.profiles.setFollowing(false, target: target, id: id)
            onSuccess()
        } catch {
            self.error = MamaError.classify(error)
        }
    }
}
