import XCTest
import MamaCore
@testable import FeatureAnimals

@MainActor
final class AnimalAddViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeServices(signedIn: Bool = true) -> AppServices {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
        return AppServices.inMemory(backend, now: { fixed })
    }

    func testSubmitCreatesAnimalAttachedToPreselectedSpot() async throws {
        let services = makeServices()
        let spotId = DemoData.id(2, 3)
        let model = AddAnimalViewModel(spotId: spotId, services: services)
        model.species = .cat
        model.name = "  Boncuk "
        model.colorPattern = "Tekir"
        model.sex = .female
        model.ageEstimate = .young
        model.neutered = .yes
        model.earTag = true
        model.toggleTemperament(.shy)
        model.toggleTemperament(.friendly)
        model.warning = .skittish

        let created = await model.submit()
        let animal = try XCTUnwrap(created)

        XCTAssertEqual(animal.name, "Boncuk")
        XCTAssertEqual(animal.isNeutered, true)
        XCTAssertTrue(animal.earTag)
        XCTAssertEqual(animal.temperamentTags, [.friendly, .shy])
        XCTAssertEqual(animal.warning, .skittish)
        XCTAssertNil(animal.about, "boş metin nil gönderilmeli")
        XCTAssertEqual(animal.lastSeenSpotId, spotId)
        let atSpot = try await services.animals.animals(atSpot: spotId)
        XCTAssertTrue(atSpot.contains { $0.id == animal.id })
    }

    func testPreselectedSpotIsLoaded() async {
        let model = AddAnimalViewModel(spotId: DemoData.id(2, 1), services: makeServices())
        await model.loadSpots(near: .modaKadikoy)
        XCTAssertEqual(model.preselectedSpot?.title, "Moda Parkı girişi")
        XCTAssertTrue(model.nearbySpots.isEmpty)
        XCTAssertEqual(model.selectedSpotId, DemoData.id(2, 1))
    }

    func testNearbySpotsWithin300mWhenNoSpotGiven() async {
        let model = AddAnimalViewModel(spotId: nil, services: makeServices())
        await model.loadSpots(near: .modaKadikoy)
        XCTAssertFalse(model.nearbySpots.isEmpty)
        XCTAssertTrue(model.nearbySpots.allSatisfy { ($0.distanceMeters ?? .infinity) <= 300 })
        XCTAssertNil(model.selectedSpotId)

        let first = model.nearbySpots[0].id
        model.toggleSpot(first)
        XCTAssertEqual(model.selectedSpotId, first)
        model.toggleSpot(first)
        XCTAssertNil(model.selectedSpotId, "aynı noktaya tekrar dokunmak seçimi kaldırır")
    }

    func testAnimalWithoutSpotIsAllowed() async {
        let model = AddAnimalViewModel(spotId: nil, services: makeServices())
        let animal = await model.submit()
        XCTAssertNotNil(animal)
        XCTAssertNil(animal?.lastSeenSpotId)
    }

    func testProfanityBlocksSubmit() async {
        let model = AddAnimalViewModel(spotId: nil, services: makeServices())
        model.name = "siktir"
        XCTAssertNotNil(model.validationMessage)
        XCTAssertFalse(model.canSubmit)
        let animal = await model.submit()
        XCTAssertNil(animal)
        XCTAssertEqual(model.error, .invalidInput(MamaError.rejectedContent.userMessage))
    }

    func testPhotosLimitedToThreeAndUploaded() async throws {
        let model = AddAnimalViewModel(spotId: nil, services: makeServices())
        for byte in 1...4 { model.addPhoto(Data([UInt8(byte)])) }
        XCTAssertEqual(model.photos.count, AddAnimalViewModel.maxPhotos)
        XCTAssertFalse(model.canAddPhoto)
        model.removePhoto(model.photos[0].id)
        XCTAssertEqual(model.photos.count, 2)

        let created = await model.submit()
        let animal = try XCTUnwrap(created)
        XCTAssertEqual(animal.photoURLs.count, 2)
    }

    func testSubmitRequiresSignIn() async {
        let model = AddAnimalViewModel(spotId: nil, services: makeServices(signedIn: false))
        let animal = await model.submit()
        XCTAssertNil(animal)
        XCTAssertEqual(model.error, .notSignedIn)
    }
}
