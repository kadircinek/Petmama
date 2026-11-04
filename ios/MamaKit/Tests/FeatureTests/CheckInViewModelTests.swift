import Foundation
import XCTest
import MamaCore
@testable import FeatureSpots

@MainActor
final class CheckInViewModelTests: XCTestCase {
    private func makeModel(spot index: Int, kind: CheckInKind = .fed, services: AppServices? = nil) async -> CheckInViewModel {
        let model = CheckInViewModel(spotId: DemoData.id(2, index), kind: kind, services: services ?? MapSpotsFixture.services().services)
        await model.load()
        return model
    }

    func testTooFarPrecheckBlocksSubmitWithFriendlyMessage() async {
        let model = await makeModel(spot: 1)
        let user = GeoMath.destination(from: MapSpotsFixture.coordinate(ofSpot: 1), meters: 180, bearingDegrees: 90)
        model.updateLocation(user)

        XCTAssertTrue(model.isTooFar)
        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(model.precheckMessage, "Noktaya biraz daha yaklaşman gerekiyor: 180 m uzaktasın, en fazla 100 m.")
        XCTAssertEqual(model.precheckTone, .warning)

        let result = await model.submit(user: user)
        guard case .tooFar(let distance, let maxDistance) = result else {
            return XCTFail("tooFar bekleniyordu, gelen: \(result)")
        }
        XCTAssertEqual(distance, 180, accuracy: 1)
        XCTAssertEqual(maxDistance, 100)
        XCTAssertFalse(result.dismissesSheet)
        XCTAssertEqual(model.result, result)
    }

    func testRequestAllowsUpTo300m() async {
        let model = await makeModel(spot: 1, kind: .needFood)
        let user = GeoMath.destination(from: MapSpotsFixture.coordinate(ofSpot: 1), meters: 180, bearingDegrees: 90)
        model.updateLocation(user)

        XCTAssertTrue(model.isRequestFlow)
        XCTAssertEqual(model.availableKinds, CheckInKind.requestKinds)
        XCTAssertFalse(model.allowsPhoto)
        XCTAssertTrue(model.canSubmit)

        model.kind = .broken
        let result = await model.submit(user: user)
        XCTAssertEqual(result, .success(kind: .broken, closedNeedCount: 0))
        XCTAssertEqual(result.message, "Teşekkürler! Yakındaki gönüllülere haber verdik.")
    }

    func testFedSuccessClosesOpenRequest() async {
        let model = await makeModel(spot: 6)
        let user = MapSpotsFixture.coordinate(ofSpot: 6)
        model.updateLocation(user)
        model.toggleAmount(.full)

        XCTAssertEqual(model.precheckTone, .ok)
        let result = await model.submit(user: user)
        XCTAssertEqual(result, .success(kind: .fed, closedNeedCount: 1))
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.dismissesSheet)
        XCTAssertEqual(result.toastStyle, .success)
        XCTAssertEqual(result.message, "Teşekkürler! Mama bekleyen noktayı sen kapattın.")
    }

    func testPlainFedSuccessAndRateLimit() async {
        let model = await makeModel(spot: 1)
        let user = MapSpotsFixture.coordinate(ofSpot: 1)

        let first = await model.submit(user: user)
        XCTAssertEqual(first, .success(kind: .fed, closedNeedCount: 0))
        XCTAssertEqual(first.message, "Teşekkürler! Mama koyduğun kaydedildi.")

        let second = await model.submit(user: user)
        XCTAssertEqual(second, .rateLimited)
        XCTAssertFalse(second.dismissesSheet)
    }

    func testOfflineCheckInIsQueued() async {
        let backend = MapSpotsFixture.backend()
        let services = MapSpotsFixture.offlineServices(backend: backend, offlineSpots: false, offlineCheckIns: true)
        let model = await makeModel(spot: 2, services: services)

        let result = await model.submit(user: MapSpotsFixture.coordinate(ofSpot: 2))
        let pending = await services.checkInQueue.pendingCount()
        XCTAssertEqual(result, .queuedOffline)
        XCTAssertTrue(result.dismissesSheet)
        XCTAssertEqual(result.toastStyle, .info)
        XCTAssertEqual(result.message, "Bağlantı yok, check-in'in sırada; bağlantı gelince gönderilecek.")
        XCTAssertEqual(pending, 1)
    }

    func testMissingLocationDoesNotSubmit() async {
        let model = await makeModel(spot: 1)
        XCTAssertEqual(model.precheckTone, .warning)
        XCTAssertFalse(model.canSubmit)
        let result = await model.submit(user: nil)
        XCTAssertEqual(result, .locationUnavailable)
    }

    func testSignedOutFailsWithSignInMessage() async {
        let services = MapSpotsFixture.services(signedIn: false).services
        let model = await makeModel(spot: 1, services: services)
        // Giriş yapmayan için konum bulanık: istemci karar veremez, sunucu doğrular.
        let result = await model.submit(user: MapSpotsFixture.coordinate(ofSpot: 1))
        XCTAssertEqual(result, .failed(.notSignedIn))
        XCTAssertEqual(result.message, MamaError.notSignedIn.userMessage)
    }

    func testInactiveSpotOutcomeMapping() async {
        let result = CheckInResult(.spotInactive, kind: .fed)
        XCTAssertEqual(result, .spotInactive)
        XCTAssertFalse(result.dismissesSheet)
        let water = CheckInResult(.success(CheckInReceipt(checkInId: UUID(), distanceMeters: 5, closedNeedCount: 0, spotStatus: .fedRecent)), kind: .water)
        XCTAssertEqual(water.message, "Teşekkürler! Su koyduğun kaydedildi.")
    }
}
