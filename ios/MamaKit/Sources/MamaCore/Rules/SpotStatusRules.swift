import Foundation

/// Nokta durumunun zamanla eskimesi (FR-H3, FR-N5, PRD 7.5). Sunucudaki `compute_spot_status` ile aynı kurallar.
public enum SpotStatusRules {
    public static let freshWindow: TimeInterval = 12 * 3600
    public static let staleWindow: TimeInterval = 24 * 3600

    public static func status(lastFedAt: Date?, hasOpenFoodRequest: Bool, now: Date) -> SpotStatus {
        if hasOpenFoodRequest { return .needsFood }
        guard let lastFedAt else { return .unknown }
        let elapsed = now.timeIntervalSince(lastFedAt)
        if elapsed < freshWindow { return .fedRecent }
        if elapsed < staleWindow { return .fedStale }
        return .unknown
    }

    /// "En uzun süredir beslenmeyen" sıralaması için: hiç beslenmemiş en başta.
    public static func hoursSinceFed(_ lastFedAt: Date?, now: Date) -> Double {
        guard let lastFedAt else { return .infinity }
        return max(0, now.timeIntervalSince(lastFedAt) / 3600)
    }
}

/// Check-in mesafe kuralları (FR-C2, FR-C3).
public enum CheckInPolicy {
    public static let feedMaxDistance: Double = 100
    public static let requestMaxDistance: Double = 300

    public enum Precheck: Equatable, Sendable {
        case allowed(distanceMeters: Double)
        case tooFar(distanceMeters: Double, maxDistanceMeters: Double)
        /// Nokta konumu bulanık olduğu için istemci karar veremez; sunucu doğrular.
        case deferToServer
        case locationUnavailable
    }

    /// Sunucuya gitmeden önce dostça uyarı göstermek için ön kontrol. Asıl karar sunucuda.
    public static func precheck(kind: CheckInKind, user: Coordinate?, spot: Spot) -> Precheck {
        guard let user else { return .locationUnavailable }
        guard spot.isLocationExact else { return .deferToServer }
        let distance = GeoMath.distance(user, spot.coordinate)
        let maxDistance = kind.maxDistanceMeters
        return distance <= maxDistance
            ? .allowed(distanceMeters: distance)
            : .tooFar(distanceMeters: distance, maxDistanceMeters: maxDistance)
    }

    /// Ana sayfadaki tek dokunuşla "Mama koydum" için 100 m içindeki en yakın aktif nokta (PRD 6.4).
    public static func quickFeedCandidate(user: Coordinate?, spots: [Spot]) -> (spot: Spot, distance: Double)? {
        guard let user else { return nil }
        let eligible = spots.filter { $0.isActive && $0.isLocationExact }
        guard let nearest = GeoMath.nearest(to: user, in: eligible, coordinate: \.coordinate),
              nearest.distance <= feedMaxDistance else { return nil }
        return (nearest.item, nearest.distance)
    }
}

/// Mükerrer nokta önleme (FR-N3).
public enum DuplicateSpotPolicy {
    public static let radiusMeters: Double = 15

    public static func candidates(near coordinate: Coordinate, among spots: [Spot]) -> [DuplicateCandidate] {
        spots
            .filter(\.isActive)
            .map { DuplicateCandidate(id: $0.id, title: $0.title, distanceMeters: GeoMath.distance(coordinate, $0.coordinate)) }
            .filter { $0.distanceMeters <= radiusMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }
}

/// "Bu nokta artık yok" bildirimi (FR-N6).
public enum InactiveSpotPolicy {
    public static let distinctReportsToDeactivate = 3

    public static func shouldDeactivate(distinctReporterCount: Int) -> Bool {
        distinctReporterCount >= distinctReportsToDeactivate
    }
}
