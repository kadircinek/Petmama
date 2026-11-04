import Foundation

public enum GeoMath {
    /// Ortalama dünya yarıçapı (IUGG), metre.
    public static let earthRadius: Double = 6_371_008.8
    public static let metersPerDegreeLatitude: Double = 111_320

    public static func metersPerDegreeLongitude(atLatitude latitude: Double) -> Double {
        max(1, metersPerDegreeLatitude * cos(latitude * .pi / 180))
    }

    /// Haversine mesafesi (metre). Sokak ölçeğinde PostGIS `ST_Distance(geography)` ile < %0,5 fark.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// `coordinate`'tan kuzeye `north`, doğuya `east` metre kaydırılmış nokta.
    public static func offset(_ coordinate: Coordinate, north: Double, east: Double) -> Coordinate {
        Coordinate(
            latitude: coordinate.latitude + north / metersPerDegreeLatitude,
            longitude: coordinate.longitude + east / metersPerDegreeLongitude(atLatitude: coordinate.latitude)
        )
    }

    /// `bearingDegrees` yönünde (0 = kuzey, saat yönünde) `meters` uzaklıktaki nokta.
    public static func destination(from coordinate: Coordinate, meters: Double, bearingDegrees: Double) -> Coordinate {
        let rad = bearingDegrees * .pi / 180
        return offset(coordinate, north: meters * cos(rad), east: meters * sin(rad))
    }

    /// `origin`'e en yakın öğe ve mesafesi.
    public static func nearest<T>(
        to origin: Coordinate,
        in items: [T],
        coordinate: (T) -> Coordinate
    ) -> (item: T, distance: Double)? {
        items
            .map { ($0, distance(origin, coordinate($0))) }
            .min { $0.1 < $1.1 }
            .map { (item: $0.0, distance: $0.1) }
    }
}

/// Deterministik konum bulanıklaştırma (PRD 9.1).
///
/// Asıl uygulama sunucudadır (`fuzz_point`); bu tip demo backend ve testler için aynı davranışı sağlar.
/// Aynı nokta her zaman aynı sahte konumda görünür; böylece tekrar sorgulayıp ortalama alarak gerçek konum bulunamaz.
public enum LocationFuzzer {
    public static let minimumOffsetMeters: Double = 50
    public static let maximumOffsetMeters: Double = 100

    public static func fuzz(_ coordinate: Coordinate, seed: UUID, salt: String = "demo-salt") -> Coordinate {
        let hash = fnv1a64(seed.uuidString + salt)
        let distanceFraction = Double(hash & 0xFFFF) / Double(0xFFFF)
        let bearingFraction = Double((hash >> 16) & 0xFFFF) / Double(0xFFFF)
        let meters = minimumOffsetMeters + (maximumOffsetMeters - minimumOffsetMeters) * distanceFraction
        return GeoMath.destination(from: coordinate, meters: meters, bearingDegrees: 360 * bearingFraction)
    }

    /// Süreçten bağımsız, kararlı 64-bit FNV-1a (Swift `Hasher` her çalıştırmada rastgele tohumlanır).
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
