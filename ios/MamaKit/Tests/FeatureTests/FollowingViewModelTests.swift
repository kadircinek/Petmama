import XCTest
import MamaCore
import FeatureProfile

private let followingNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class FollowingViewModelTests: XCTestCase {
    // Mühürdar parkı (15) referans: İskele arkası (6) ≈ 300 m, Yeldeğirmeni (8) ≈ 1,2 km.
    private let muhurdar = DemoData.id(2, 15)
    private let iskele = DemoData.id(2, 6)
    private let yeldegirmeni = DemoData.id(2, 8)
    private let pamuk = DemoData.id(4, 1)
    private let kont = DemoData.id(4, 6)

    private func makeEnvironment() async throws -> (InMemoryBackend, AppServices, Coordinate) {
        let now = followingNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { now })
        let services = AppServices.inMemory(backend, now: { now })
        for id in [muhurdar, iskele, yeldegirmeni] {
            try await services.profiles.setFollowing(true, target: .spot, id: id)
        }
        for id in [pamuk, kont] {
            try await services.profiles.setFollowing(true, target: .animal, id: id)
        }
        let raw = await backend.rawSpot(muhurdar)
        let origin = try XCTUnwrap(raw).coordinate
        return (backend, services, origin)
    }

    func testEmptyWhenNothingFollowed() async {
        let now = followingNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { now })
        let model = FollowingViewModel(services: AppServices.inMemory(backend, now: { now }))
        await model.load(near: .modaKadikoy)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.isSegmentEmpty)
    }

    func testAllSegmentSortsByDistanceAndResolvesAnimalSpots() async throws {
        let (_, services, origin) = try await makeEnvironment()
        let model = FollowingViewModel(services: services)
        await model.load(near: origin)
        XCTAssertEqual(model.segment, .all)
        XCTAssertEqual(model.visibleSpots.map(\.id), [muhurdar, iskele, yeldegirmeni])
        XCTAssertEqual(model.visibleSpots.first?.distanceMeters ?? -1, 0, accuracy: 1)
        XCTAssertEqual(model.visibleAnimals.map(\.animal.name), ["Kont", "Pamuk"])
        let pamukItem = try XCTUnwrap(model.visibleAnimals.first { $0.id == pamuk })
        XCTAssertEqual(pamukItem.lastSeenSpot?.title, "Moda Parkı girişi")
        XCTAssertNotNil(pamukItem.distanceMeters)
    }

    func testNearbySegmentKeepsOnlyWithinOneKilometre() async throws {
        let (_, services, origin) = try await makeEnvironment()
        let model = FollowingViewModel(services: services)
        await model.load(near: origin)
        model.segment = .nearby
        XCTAssertEqual(model.visibleSpots.map(\.id), [muhurdar, iskele])
        XCTAssertTrue(model.visibleSpots.allSatisfy { ($0.distanceMeters ?? .infinity) <= 1000 })
        XCTAssertEqual(model.visibleAnimals.map(\.animal.name), ["Pamuk", "Kont"], "yakından uzağa")
        XCTAssertFalse(model.needsLocationForSegment)
    }

    func testRecentSegmentPutsRecentlyFedFirst() async throws {
        let (_, services, origin) = try await makeEnvironment()
        let model = FollowingViewModel(services: services)
        await model.load(near: origin)
        model.segment = .recent
        // Yeldeğirmeni 1 sa, Mühürdar 16 sa önce; İskele arkası hiç beslenmedi.
        XCTAssertEqual(model.visibleSpots.map(\.id), [yeldegirmeni, muhurdar, iskele])
        XCTAssertEqual(model.visibleAnimals.map(\.animal.name), ["Pamuk", "Kont"])
    }

    func testNearbyNeedsLocation() async throws {
        let (_, services, _) = try await makeEnvironment()
        let model = FollowingViewModel(services: services)
        await model.load(near: nil)
        model.segment = .nearby
        XCTAssertTrue(model.needsLocationForSegment)
        XCTAssertTrue(model.isSegmentEmpty)
        XCTAssertFalse(model.isEmpty)

        model.updateOrigin(.modaKadikoy)
        XCTAssertFalse(model.needsLocationForSegment)
        XCTAssertFalse(model.visibleSpots.isEmpty)
    }

    func testUnfollowRemovesFromListAndBackend() async throws {
        let (_, services, origin) = try await makeEnvironment()
        let model = FollowingViewModel(services: services)
        await model.load(near: origin)
        let spot = try XCTUnwrap(model.spots.first { $0.id == yeldegirmeni })
        await model.unfollow(spot: spot)
        let animal = try XCTUnwrap(model.animals.first { $0.id == kont }).animal
        await model.unfollow(animal: animal)

        XCTAssertFalse(model.spots.contains { $0.id == yeldegirmeni })
        XCTAssertFalse(model.animals.contains { $0.id == kont })
        let followed = try await services.profiles.followedSpotIds()
        XCTAssertEqual(followed, [muhurdar, iskele])
        let animals = try await services.profiles.followedAnimals()
        XCTAssertEqual(animals.map(\.id), [pamuk])
        XCTAssertNil(model.error)
    }
}
