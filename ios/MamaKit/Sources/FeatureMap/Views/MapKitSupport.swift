#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

extension GeoBounds {
    init(_ region: MKCoordinateRegion) {
        self.init(
            center: Coordinate(region.center),
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
    }

    var mkRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clCoordinate,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

enum MapCameraDefaults {
    /// Sokak seviyesi (~1:2000, FR-H1): bina ve sokak adları okunur.
    static let streetDistance: CLLocationDistance = 700

    static func street(_ coordinate: Coordinate) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: coordinate.clCoordinate, distance: streetDistance))
    }

    /// Kamera ilk değişimi bildirmeden önceki yaklaşık görünür bölge (kümeleme eşiğinin altında kalır).
    static func approximateBounds(around coordinate: Coordinate) -> GeoBounds {
        GeoBounds(center: coordinate, radiusMeters: 220)
    }
}

extension SpotFilter.Sort {
    var label: String {
        switch self {
        case .nearest: return String(localized: "En yakın")
        case .longestUnfed: return String(localized: "En uzun süredir beslenmeyen")
        case .urgent: return String(localized: "Acil")
        }
    }

    var systemImage: String {
        switch self {
        case .nearest: return "location.fill"
        case .longestUnfed: return "clock.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
}
#endif
