#if canImport(UIKit)
import MapKit
import MamaCore
import MamaDesign

/// `MKLocalSearch` ile "veteriner" araması (FR-I4). ViewModel yalnızca `VetClinicSearching` görür.
struct MapKitVetClinicSearch: VetClinicSearching {
    func clinics(near center: Coordinate, radiusMeters: Double) async throws -> [VetClinic] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "veteriner"
        request.region = MKCoordinateRegion(
            center: center.clCoordinate,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            VetClinic(
                name: item.name ?? String(localized: "Veteriner kliniği"),
                address: item.placemark.title,
                phone: item.phoneNumber,
                coordinate: Coordinate(item.placemark.coordinate)
            )
        }
    }
}

extension VetClinic {
    /// Haritalar'da yürüyüş yol tarifi.
    @MainActor
    func openWalkingDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
        item.name = name
        item.phoneNumber = phone
        _ = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
#endif
