import XCTest
import MamaCore
@testable import FeatureAnimals

@MainActor
final class AnimalProfileViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let pamuk = DemoData.id(4, 1)
    private let tarcin = DemoData.id(4, 2)

    private func makeServices(signedIn: Bool = true) -> (AppServices, InMemoryBackend) {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
        return (AppServices.inMemory(backend, now: { fixed }), backend)
    }

    func testLoadsAnimalSpotsAndOpenNeeds() async {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: tarcin, services: services)
        await model.load()

        XCTAssertEqual(model.animal?.name, "Tarçın")
        XCTAssertEqual(model.spots.map(\.id), [DemoData.id(2, 1)])
        XCTAssertEqual(model.openNeeds.map(\.id), [DemoData.id(5, 2)])
        XCTAssertEqual(model.neuteredText, "Hayır")
        XCTAssertEqual(model.vaccinationText, "Bilinmiyor")
        XCTAssertEqual(model.lastSeenText, "5 sa önce · Moda Parkı girişi")
        XCTAssertNil(model.error)
    }

    func testOpenNeedsExcludeResolvedAndInfoTexts() async {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()

        XCTAssertTrue(model.openNeeds.isEmpty, "Pamuk'un aşı ihtiyacı çözülmüş; listelenmemeli")
        XCTAssertEqual(Set(model.spots.map(\.id)), [DemoData.id(2, 1), DemoData.id(2, 2)])
        XCTAssertEqual(model.neuteredText, "Evet · kulak küpesi var")
        XCTAssertEqual(model.vaccinationText, "Kuduz aşısı 2026")
    }

    func testMissingAnimalReportsNotFound() async {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: UUID(), services: services)
        await model.load()
        XCTAssertNil(model.animal)
        XCTAssertEqual(model.error, .notFound)
        XCTAssertTrue(model.hasLoaded)
    }

    func testMarkSeenChoosesNearestKnownSpotWithin300m() async throws {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()
        let beach = try XCTUnwrap(model.spots.first { $0.id == DemoData.id(2, 2) })
        // Sahil banklarına 20 m; park girişi de 300 m içinde ama daha uzak.
        let user = GeoMath.offset(beach.coordinate, north: -20, east: 0)

        let result = await model.markSeen(user: user)

        XCTAssertEqual(result, .marked(spotId: DemoData.id(2, 2), spotTitle: "Moda Sahili bankları"))
        XCTAssertEqual(model.animal?.lastSeenSpotId, DemoData.id(2, 2))
        XCTAssertEqual(model.animal?.lastSeenAt, now)
        XCTAssertTrue(result.message.contains("Moda Sahili bankları"))
    }

    func testMarkSeenFallsBackToLastSeenSpotWhenFarAway() async {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()
        let farAway = GeoMath.offset(.modaKadikoy, north: 3000, east: 0)

        let result = await model.markSeen(user: farAway)

        XCTAssertEqual(result, .marked(spotId: DemoData.id(2, 1), spotTitle: "Moda Parkı girişi"))
        XCTAssertEqual(model.animal?.lastSeenSpotId, DemoData.id(2, 1))
    }

    func testMarkSeenNeedsLocation() async {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()
        let result = await model.markSeen(user: nil)
        XCTAssertEqual(result, .needsLocation)
    }

    func testMarkSeenRequiresSignIn() async {
        let (services, _) = makeServices(signedIn: false)
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()
        let result = await model.markSeen(user: .modaKadikoy)
        XCTAssertEqual(result, .failed(.notSignedIn))
    }

    func testSeenSpotChoiceWithoutKnownSpots() async {
        let choice = AnimalProfileViewModel.seenSpotChoice(user: .modaKadikoy, spots: [], lastSeenSpotId: nil)
        XCTAssertNil(choice)
    }

    func testToggleFollowPersists() async throws {
        let (services, _) = makeServices()
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()
        XCTAssertFalse(model.isFollowing)

        await model.toggleFollow()
        XCTAssertTrue(model.isFollowing)
        let followed = try await services.profiles.followedAnimals()
        XCTAssertEqual(followed.map(\.id), [pamuk])

        let reloaded = AnimalProfileViewModel(animalId: pamuk, services: services)
        await reloaded.load()
        XCTAssertTrue(reloaded.isFollowing)

        await reloaded.toggleFollow()
        let afterUnfollow = try await services.profiles.followedAnimals()
        XCTAssertTrue(afterUnfollow.isEmpty)
    }

    func testToggleFollowRevertsOnError() async {
        let (services, _) = makeServices(signedIn: false)
        let model = AnimalProfileViewModel(animalId: pamuk, services: services)
        await model.load()
        await model.toggleFollow()
        XCTAssertFalse(model.isFollowing)
        XCTAssertEqual(model.error, .notSignedIn)
    }
}
