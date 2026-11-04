import Foundation
import XCTest
import MamaCore
@testable import FeatureSpots

@MainActor
final class QuickFeedViewModelTests: XCTestCase {
    func testPicksNearestExactSpotWithin100m() async {
        let model = QuickFeedViewModel(services: MapSpotsFixture.services().services)
        await model.locate(user: .modaKadikoy)

        guard case .candidate(let spot, let distance) = model.state else {
            return XCTFail("Aday bekleniyordu, gelen: \(model.state)")
        }
        XCTAssertEqual(spot.id, DemoData.id(2, 20), "Kilise bahçesi önü ≈ 84 m")
        XCTAssertEqual(distance, 84, accuracy: 3)
        XCTAssertLessThanOrEqual(distance, CheckInPolicy.feedMaxDistance)
    }

    func testSubmitFedCheckIn() async {
        let model = QuickFeedViewModel(services: MapSpotsFixture.services().services)
        await model.locate(user: MapSpotsFixture.coordinate(ofSpot: 1))
        XCTAssertEqual(model.candidate?.id, DemoData.id(2, 1))

        let result = await model.submit()
        XCTAssertEqual(result, .success(kind: .fed, closedNeedCount: 0))
        XCTAssertEqual(model.result, result)
    }

    func testNoneNearbyListsNearestFew() async {
        let model = QuickFeedViewModel(services: MapSpotsFixture.services().services)
        let user = GeoMath.destination(from: MapSpotsFixture.coordinate(ofSpot: 8), meters: 240, bearingDegrees: 0)
        await model.locate(user: user)

        guard case .noneNearby(let spots) = model.state else {
            return XCTFail("Yakında nokta olmamalı, gelen: \(model.state)")
        }
        XCTAssertEqual(spots.first?.id, DemoData.id(2, 8))
        XCTAssertLessThanOrEqual(spots.count, QuickFeedViewModel.fallbackCount)
        let result = await model.submit()
        XCTAssertEqual(result, .locationUnavailable)
    }

    func testFarAwayHasNoSpots() async {
        let model = QuickFeedViewModel(services: MapSpotsFixture.services().services)
        await model.locate(user: Coordinate(latitude: 41.2, longitude: 29.6))
        XCTAssertEqual(model.state, .noneNearby([]))
    }

    func testNoLocationAsksForPermission() async {
        let model = QuickFeedViewModel(services: MapSpotsFixture.services().services)
        await model.locate(user: nil)
        XCTAssertEqual(model.state, .needsLocation)
    }

    func testOfflineUsesCachedSpotsAndQueuesCheckIn() async {
        let backend = MapSpotsFixture.backend()
        let cache = InMemorySpotCache()
        let user = MapSpotsFixture.coordinate(ofSpot: 1)
        await cache.store([MapSpotsFixture.spot(1), MapSpotsFixture.spot(2)], for: GeoBounds(center: user, radiusMeters: 1000))
        let services = MapSpotsFixture.offlineServices(backend: backend, cache: cache, offlineSpots: true, offlineCheckIns: true)
        let model = QuickFeedViewModel(services: services)

        await model.locate(user: user)
        XCTAssertEqual(model.candidate?.id, DemoData.id(2, 1))
        let result = await model.submit()
        XCTAssertEqual(result, .queuedOffline)
    }
}
