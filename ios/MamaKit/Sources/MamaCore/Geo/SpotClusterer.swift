import Foundation

/// Haritadaki bir küme veya tekil nokta (FR-H2).
public struct SpotCluster: Identifiable, Hashable, Sendable {
    public let id: String
    public var coordinate: Coordinate
    public var spots: [Spot]

    public var count: Int { spots.count }
    public var isSingle: Bool { spots.count == 1 }
    /// Küme rozetinde turuncu gösterilen "mama gerekli" sayısı.
    public var needsFoodCount: Int { spots.filter { $0.status == .needsFood }.count }
    public var hasUrgentNeed: Bool { spots.contains { $0.hasUrgentNeed } }

    public init(id: String, coordinate: Coordinate, spots: [Spot]) {
        self.id = id
        self.coordinate = coordinate
        self.spots = spots
    }
}

/// Izgara tabanlı istemci kümeleme (D5).
///
/// Görünür bölge `gridDivisions × gridDivisions` hücreye bölünür; aynı hücredeki noktalar tek kümede toplanır.
/// Bölge `clusteringThreshold`'dan daha dar ise (sokak ölçeği) kümeleme yapılmaz.
/// Hücreler dünya koordinatlarına sabitlendiği için kaydırma sırasında kümeler zıplamaz.
public struct SpotClusterer: Sendable {
    /// Bu enlem açıklığının altında (~450 m) tüm noktalar tek tek gösterilir.
    public var clusteringThreshold: Double
    public var gridDivisions: Int

    public init(clusteringThreshold: Double = 0.004, gridDivisions: Int = 7) {
        self.clusteringThreshold = clusteringThreshold
        self.gridDivisions = max(1, gridDivisions)
    }

    public func clusters(for spots: [Spot], in bounds: GeoBounds) -> [SpotCluster] {
        let visible = spots.filter { bounds.contains($0.coordinate) }
        guard bounds.latitudeDelta >= clusteringThreshold else {
            return visible.map { SpotCluster(id: $0.id.uuidString, coordinate: $0.coordinate, spots: [$0]) }
        }

        // Hücre boyutunu sabit adımlara yuvarla: küçük zoom değişimlerinde kümeler kararlı kalsın.
        let rawCell = bounds.latitudeDelta / Double(gridDivisions)
        let cell = pow(2, (log2(rawCell)).rounded(.up))
        let lngCell = cell * GeoMath.metersPerDegreeLatitude / GeoMath.metersPerDegreeLongitude(atLatitude: bounds.center.latitude)

        var buckets: [String: [Spot]] = [:]
        for spot in visible {
            let row = Int((spot.coordinate.latitude / cell).rounded(.down))
            let col = Int((spot.coordinate.longitude / lngCell).rounded(.down))
            buckets["\(row):\(col)", default: []].append(spot)
        }

        return buckets
            .map { key, members in
                let lat = members.map(\.coordinate.latitude).reduce(0, +) / Double(members.count)
                let lng = members.map(\.coordinate.longitude).reduce(0, +) / Double(members.count)
                let id = members.count == 1 ? members[0].id.uuidString : "cluster-\(key)"
                return SpotCluster(id: id, coordinate: Coordinate(latitude: lat, longitude: lng), spots: members)
            }
            .sorted { $0.id < $1.id }
    }
}
