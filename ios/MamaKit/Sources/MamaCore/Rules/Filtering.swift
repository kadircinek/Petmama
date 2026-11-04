import Foundation

/// Harita ve liste filtresi (FR-H5, ekran 11).
public struct SpotFilter: Hashable, Codable, Sendable {
    public enum Sort: String, Codable, CaseIterable, Sendable, Hashable {
        case nearest
        case longestUnfed
        case urgent
    }

    /// Boş küme = hepsi.
    public var species: Set<AnimalSpecies>
    public var statuses: Set<SpotStatus>
    public var spotTypes: Set<SpotType>
    /// İhtiyaçlar sekmesi ve segmentinde uygulanır.
    public var needTypes: Set<NeedType>
    /// 1…10 km.
    public var maxDistanceKm: Double
    public var onlyFollowed: Bool
    public var sort: Sort

    public init(
        species: Set<AnimalSpecies> = [],
        statuses: Set<SpotStatus> = [],
        spotTypes: Set<SpotType> = [],
        needTypes: Set<NeedType> = [],
        maxDistanceKm: Double = 3,
        onlyFollowed: Bool = false,
        sort: Sort = .nearest
    ) {
        self.species = species
        self.statuses = statuses
        self.spotTypes = spotTypes
        self.needTypes = needTypes
        self.maxDistanceKm = min(max(maxDistanceKm, 1), 10)
        self.onlyFollowed = onlyFollowed
        self.sort = sort
    }

    public static let `default` = SpotFilter()

    public var isDefault: Bool { self == .default }

    /// Filtre ekranındaki "x filtre aktif" rozeti için.
    public var activeCount: Int {
        var count = 0
        if !species.isEmpty { count += 1 }
        if !statuses.isEmpty { count += 1 }
        if !spotTypes.isEmpty { count += 1 }
        if !needTypes.isEmpty { count += 1 }
        if maxDistanceKm != SpotFilter.default.maxDistanceKm { count += 1 }
        if onlyFollowed { count += 1 }
        return count
    }

    public func matches(_ spot: Spot, followedIds: Set<UUID>, now: Date) -> Bool {
        guard spot.isActive else { return false }
        if !species.isEmpty, !species.contains(where: spot.species.matches) { return false }
        if !statuses.isEmpty, !statuses.contains(spot.currentStatus(now: now)) { return false }
        if !spotTypes.isEmpty, !spotTypes.contains(spot.type) { return false }
        if onlyFollowed, !followedIds.contains(spot.id) { return false }
        if let distance = spot.distanceMeters, distance > maxDistanceKm * 1000 { return false }
        return true
    }

    public func apply(to spots: [Spot], followedIds: Set<UUID> = [], now: Date = Date()) -> [Spot] {
        let filtered = spots.filter { matches($0, followedIds: followedIds, now: now) }
        switch sort {
        case .nearest:
            return filtered.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        case .longestUnfed:
            return filtered.sorted {
                let a = SpotStatusRules.hoursSinceFed($0.lastFedAt, now: now)
                let b = SpotStatusRules.hoursSinceFed($1.lastFedAt, now: now)
                if a != b { return a > b }
                return ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity)
            }
        case .urgent:
            return filtered.sorted { lhs, rhs in
                let l = Self.urgencyRank(lhs, now: now)
                let r = Self.urgencyRank(rhs, now: now)
                if l != r { return l < r }
                return (lhs.distanceMeters ?? .infinity) < (rhs.distanceMeters ?? .infinity)
            }
        }
    }

    private static func urgencyRank(_ spot: Spot, now: Date) -> Int {
        if spot.hasUrgentNeed { return 0 }
        switch spot.currentStatus(now: now) {
        case .needsFood: return 1
        case .unknown: return 2
        case .fedStale: return 3
        case .fedRecent: return 4
        }
    }

    public func apply(to needs: [Need]) -> [Need] {
        let filtered = needs.filter { need in
            (needTypes.isEmpty || needTypes.contains(need.type))
                && (need.distanceMeters.map { $0 <= maxDistanceKm * 1000 } ?? true)
        }
        return NeedSorting.sorted(filtered)
    }
}

/// İhtiyaçlar sekmesinde mesafe ve aciliyete göre sıralama (FR-I5).
public enum NeedSorting {
    public static func sorted(_ needs: [Need]) -> [Need] {
        needs.sorted { lhs, rhs in
            let l = rank(lhs)
            let r = rank(rhs)
            if l != r { return l < r }
            let ld = lhs.distanceMeters ?? .infinity
            let rd = rhs.distanceMeters ?? .infinity
            if ld != rd { return ld < rd }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// Açık acil → açık normal → üstlenilmiş → çözülmüş.
    static func rank(_ need: Need) -> Int {
        switch (need.status, need.urgency) {
        case (.open, .urgent): return 0
        case (.open, .normal): return 1
        case (.claimed, .urgent): return 2
        case (.claimed, .normal): return 3
        case (.resolved, _): return 4
        }
    }
}
