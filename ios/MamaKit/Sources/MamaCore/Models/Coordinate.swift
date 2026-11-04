import Foundation

/// Platformdan bağımsız WGS84 koordinatı. MapKit/CoreLocation'a UI katmanında çevrilir.
public struct Coordinate: Hashable, Codable, Sendable, CustomStringConvertible {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    public var description: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    /// Pilot ilçe merkezi: Moda, Kadıköy (D3).
    public static let modaKadikoy = Coordinate(latitude: 40.9862, longitude: 29.0254)
}

/// Enlem/boylam sınır kutusu. Harita görünür bölgesi sorguları için.
public struct GeoBounds: Hashable, Codable, Sendable {
    public var minLatitude: Double
    public var minLongitude: Double
    public var maxLatitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double) {
        self.minLatitude = min(minLatitude, maxLatitude)
        self.maxLatitude = max(minLatitude, maxLatitude)
        self.minLongitude = min(minLongitude, maxLongitude)
        self.maxLongitude = max(minLongitude, maxLongitude)
    }

    /// Merkez ve derece cinsinden açıklık (MapKit `MKCoordinateSpan` ile aynı anlam).
    public init(center: Coordinate, latitudeDelta: Double, longitudeDelta: Double) {
        self.init(
            minLatitude: center.latitude - latitudeDelta / 2,
            minLongitude: center.longitude - longitudeDelta / 2,
            maxLatitude: center.latitude + latitudeDelta / 2,
            maxLongitude: center.longitude + longitudeDelta / 2
        )
    }

    /// Merkez etrafında yaklaşık `radiusMeters` yarıçaplı kutu.
    public init(center: Coordinate, radiusMeters: Double) {
        let latDelta = radiusMeters / GeoMath.metersPerDegreeLatitude
        let lngDelta = radiusMeters / GeoMath.metersPerDegreeLongitude(atLatitude: center.latitude)
        self.init(
            minLatitude: center.latitude - latDelta,
            minLongitude: center.longitude - lngDelta,
            maxLatitude: center.latitude + latDelta,
            maxLongitude: center.longitude + lngDelta
        )
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }

    public var latitudeDelta: Double { maxLatitude - minLatitude }
    public var longitudeDelta: Double { maxLongitude - minLongitude }

    public func contains(_ c: Coordinate) -> Bool {
        (minLatitude...maxLatitude).contains(c.latitude) && (minLongitude...maxLongitude).contains(c.longitude)
    }

    /// `other` tamamen bu kutunun içinde mi? (Önbellekten yanıt verilebilir mi kontrolü.)
    public func contains(_ other: GeoBounds) -> Bool {
        minLatitude <= other.minLatitude && maxLatitude >= other.maxLatitude
            && minLongitude <= other.minLongitude && maxLongitude >= other.maxLongitude
    }

    /// Her yönde oransal büyütülmüş kutu (ör. 1.5 → %50 tampon). Kaydırmada tekrar sorguyu azaltır.
    public func expanded(by factor: Double) -> GeoBounds {
        GeoBounds(center: center, latitudeDelta: latitudeDelta * factor, longitudeDelta: longitudeDelta * factor)
    }
}
