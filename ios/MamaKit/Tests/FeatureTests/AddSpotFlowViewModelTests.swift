import Foundation
import XCTest
import MamaCore
@testable import FeatureSpots

@MainActor
final class AddSpotFlowViewModelTests: XCTestCase {
    func testDuplicateThenForceCreates() async {
        let (services, backend) = MapSpotsFixture.services()
        let near = GeoMath.offset(MapSpotsFixture.coordinate(ofSpot: 1), north: 5, east: 0)
        let model = AddSpotFlowViewModel(initialCoordinate: near, services: services)
        model.title = "Parkın girişi, çınarın yanı"

        let first = await model.submit()
        guard case .duplicate(let candidates) = first else {
            return XCTFail("Mükerrer uyarısı bekleniyordu, gelen: \(first)")
        }
        XCTAssertEqual(candidates.first?.id, DemoData.id(2, 1))
        XCTAssertEqual(model.duplicates, candidates)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.message(for: first), "Bu nokta zaten var mı?")

        let forced = await model.submit(force: true)
        guard case .created(let id, let pending) = forced else {
            return XCTFail("Oluşturma bekleniyordu, gelen: \(forced)")
        }
        XCTAssertFalse(pending)
        XCTAssertTrue(model.duplicates.isEmpty)
        XCTAssertEqual(model.message(for: forced), "Teşekkürler! Noktan haritaya eklendi.")
        let stored = await backend.rawSpot(id)
        XCTAssertEqual(stored?.title, "Parkın girişi, çınarın yanı")
        XCTAssertEqual(stored?.createdBy, DemoData.meId)
    }

    func testStepsAndDraftFields() async {
        let (services, backend) = MapSpotsFixture.services()
        let model = AddSpotFlowViewModel(initialCoordinate: nil, services: services)
        XCTAssertEqual(model.step, .location)
        model.back()
        XCTAssertEqual(model.step, .location)

        model.next()
        XCTAssertEqual(model.step, .details)
        model.type = .water
        model.species = .both
        model.title = "  "
        model.next()
        XCTAssertEqual(model.step, .extras)
        XCTAssertTrue(model.isLastStep)
        XCTAssertFalse(model.canGoNext)
        model.next()
        XCTAssertEqual(model.step, .extras)

        model.note = "Mavi kap, ağacın dibinde"
        model.visibility = .fuzzed
        let far = Coordinate(latitude: 40.9700, longitude: 29.0500)
        model.moveCoordinate(to: far)
        let result = await model.submit()
        guard case .created(let id, _) = result else {
            return XCTFail("Oluşturma bekleniyordu, gelen: \(result)")
        }
        let stored = await backend.rawSpot(id)
        XCTAssertEqual(stored?.type, .water)
        XCTAssertEqual(stored?.species, .both)
        XCTAssertEqual(stored?.visibility, .fuzzed)
        XCTAssertEqual(stored?.note, "Mavi kap, ağacın dibinde")
        XCTAssertEqual(stored?.coordinate, far)
    }

    func testAdoptsUserLocationOnlyWithoutExplicitStart() async {
        let services = MapSpotsFixture.services().services
        let user = MapSpotsFixture.coordinate(ofSpot: 3)

        let fromLongPress = AddSpotFlowViewModel(initialCoordinate: MapSpotsFixture.coordinate(ofSpot: 5), services: services)
        XCTAssertFalse(fromLongPress.adoptUserLocation(user))
        XCTAssertEqual(fromLongPress.coordinate, MapSpotsFixture.coordinate(ofSpot: 5))

        let fromMenu = AddSpotFlowViewModel(initialCoordinate: nil, services: services)
        XCTAssertEqual(fromMenu.coordinate, .modaKadikoy)
        XCTAssertTrue(fromMenu.adoptUserLocation(user))
        XCTAssertEqual(fromMenu.coordinate, user)
        XCTAssertFalse(fromMenu.adoptUserLocation(.modaKadikoy), "Bir kez benimsenir")
    }

    func testInitialCameraReportDoesNotBlockUserLocation() async {
        let services = MapSpotsFixture.services().services
        let model = AddSpotFlowViewModel(initialCoordinate: nil, services: services)
        // Harita açılınca kamera mevcut merkezi (≈ aynı nokta) bildirir.
        model.moveCoordinate(to: GeoMath.offset(.modaKadikoy, north: 1, east: 1))
        XCTAssertTrue(model.adoptUserLocation(MapSpotsFixture.coordinate(ofSpot: 3)))

        let panned = AddSpotFlowViewModel(initialCoordinate: nil, services: services)
        panned.moveCoordinate(to: GeoMath.offset(.modaKadikoy, north: 40, east: 0))
        XCTAssertFalse(panned.adoptUserLocation(MapSpotsFixture.coordinate(ofSpot: 3)), "Kullanıcı kaydırdıysa konumu ezilmez")
    }

    func testProfanityIsRejectedBeforeServer() async {
        let model = AddSpotFlowViewModel(initialCoordinate: Coordinate(latitude: 40.97, longitude: 29.05), services: MapSpotsFixture.services().services)
        model.step = .details
        model.title = "siktir"
        XCTAssertNotNil(model.titleWarning)
        XCTAssertFalse(model.canGoNext)
        XCTAssertFalse(model.canSubmit)

        let result = await model.submit()
        XCTAssertEqual(result, .rejectedContent)
        XCTAssertEqual(model.errorMessage, MamaError.rejectedContent.userMessage)
    }

    func testDailyLimitReached() async {
        let services = MapSpotsFixture.services().services
        var lastResult: AddSpotFlowViewModel.SubmitResult?
        for index in 0..<(TrustPolicy.dailySpotLimitNew + 1) {
            let coordinate = Coordinate(latitude: 40.96 - Double(index) * 0.001, longitude: 29.06)
            let model = AddSpotFlowViewModel(initialCoordinate: coordinate, services: services)
            lastResult = await model.submit()
        }
        XCTAssertEqual(lastResult, .limitReached(TrustPolicy.dailySpotLimitNew))
    }

    func testOfflineCreateFails() async {
        let services = MapSpotsFixture.offlineServices(backend: MapSpotsFixture.backend())
        let model = AddSpotFlowViewModel(initialCoordinate: .modaKadikoy, services: services)
        let result = await model.submit()
        XCTAssertEqual(result, .failed(.offline))
        XCTAssertEqual(model.errorMessage, MamaError.offline.userMessage)
    }

    func testHasProgressPreventsAccidentalDismiss() async {
        let model = AddSpotFlowViewModel(initialCoordinate: nil, services: MapSpotsFixture.services().services)
        XCTAssertFalse(model.hasProgress)
        model.setPhoto(Data([0xFF, 0xD8]))
        XCTAssertTrue(model.hasProgress)
        model.setPhoto(nil)
        XCTAssertFalse(model.hasProgress)
    }
}
