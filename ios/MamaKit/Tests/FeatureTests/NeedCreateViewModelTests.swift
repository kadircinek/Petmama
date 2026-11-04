import XCTest
import MamaCore
@testable import FeatureNeeds

@MainActor
final class NeedCreateViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let validText = "Su kabı kırılmış, yenisi lazım."

    private func makeServices(signedIn: Bool = true) -> AppServices {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
        return AppServices.inMemory(backend, now: { fixed })
    }

    func testTypeIsRequiredFirst() async {
        let model = CreateNeedViewModel(spotId: DemoData.id(2, 3), animalId: nil, services: makeServices())
        model.descriptionText = validText
        XCTAssertEqual(model.validationIssue, .missingType)
    }

    func testSpotRequiredWithoutAnimal() async throws {
        let services = makeServices()
        let model = CreateNeedViewModel(spotId: nil, animalId: nil, services: services)
        model.type = .water
        model.descriptionText = validText
        XCTAssertTrue(model.isSpotRequired)
        XCTAssertTrue(model.showsSpotPicker)
        XCTAssertEqual(model.validationIssue, .missingTarget)

        let before = try await services.needs.needs(near: .modaKadikoy, radiusMeters: 50_000, includeResolved: true).count
        let id = await model.submit()
        XCTAssertNil(id)
        XCTAssertTrue(model.attemptedSubmit)
        let after = try await services.needs.needs(near: .modaKadikoy, radiusMeters: 50_000, includeResolved: true).count
        XCTAssertEqual(before, after)
    }

    func testAnimalSatisfiesTarget() async {
        let model = CreateNeedViewModel(spotId: nil, animalId: DemoData.id(4, 2), services: makeServices())
        model.type = .neuter
        model.descriptionText = validText
        XCTAssertFalse(model.isSpotRequired)
        XCTAssertTrue(model.showsSpotPicker)
        XCTAssertNil(model.validationIssue)
    }

    func testDescriptionTooShortIsTrimmed() async {
        let model = CreateNeedViewModel(spotId: DemoData.id(2, 3), animalId: nil, services: makeServices())
        model.type = .water
        model.descriptionText = "   Kap yok      "
        XCTAssertEqual(model.validationIssue, .descriptionTooShort)
        model.descriptionText = "Kap yok, lütfen"
        XCTAssertNil(model.validationIssue)
    }

    func testProfanityIsRejectedBeforeServer() async {
        let model = CreateNeedViewModel(spotId: DemoData.id(2, 3), animalId: nil, services: makeServices())
        model.type = .water
        model.descriptionText = "Kap yine kırılmış amk, yenisi lazım"
        XCTAssertEqual(model.validationIssue, .profanity)
        XCTAssertEqual(model.validationIssue?.message, MamaError.rejectedContent.userMessage)
        let id = await model.submit()
        XCTAssertNil(id)
    }

    func testSubmitCreatesNeedOnSelectedSpot() async throws {
        let services = makeServices()
        let model = CreateNeedViewModel(spotId: nil, animalId: nil, services: services)
        await model.load(near: .modaKadikoy)
        XCTAssertFalse(model.nearbySpots.isEmpty)
        XCTAssertTrue(model.nearbySpots.allSatisfy { ($0.distanceMeters ?? .infinity) <= 500 })

        let spotId = model.nearbySpots[0].id
        model.toggleSpot(spotId)
        model.type = .water
        model.descriptionText = "  \(validText)  "
        model.addPhoto(Data([1, 2, 3]))

        let created = await model.submit()
        let id = try XCTUnwrap(created)
        let fetched = try await services.needs.need(id: id)
        let need = try XCTUnwrap(fetched)
        XCTAssertEqual(need.spotId, spotId)
        XCTAssertEqual(need.type, .water)
        XCTAssertEqual(need.urgency, .normal)
        XCTAssertEqual(need.description, validText)
        XCTAssertEqual(need.photoURLs.count, 1)
        XCTAssertEqual(need.createdBy, DemoData.meId)
        XCTAssertFalse(model.shouldOpenVetHelp)
    }

    func testUrgentVetOpensVetHelp() async throws {
        let services = makeServices()
        let model = CreateNeedViewModel(spotId: nil, animalId: DemoData.id(4, 4), services: services)
        model.type = .vet
        model.urgency = .normal
        XCTAssertFalse(model.shouldOpenVetHelp)
        model.urgency = .urgent
        XCTAssertTrue(model.shouldOpenVetHelp)

        model.descriptionText = "Ön patisini basamıyor, topallıyor."
        let created = await model.submit()
        let id = try XCTUnwrap(created)
        let fetched = try await services.needs.need(id: id)
        XCTAssertEqual(fetched?.animalId, DemoData.id(4, 4))
        XCTAssertEqual(fetched?.urgency, .urgent)
    }

    func testPresetSpotAndAnimalAreLoaded() async {
        let model = CreateNeedViewModel(spotId: DemoData.id(2, 1), animalId: DemoData.id(4, 1), services: makeServices())
        await model.load(near: .modaKadikoy)
        XCTAssertFalse(model.showsSpotPicker)
        XCTAssertEqual(model.presetSpot?.title, "Moda Parkı girişi")
        XCTAssertEqual(model.animal?.name, "Pamuk")
        XCTAssertTrue(model.nearbySpots.isEmpty)
    }

    func testPhotosLimitedToThree() async {
        let model = CreateNeedViewModel(spotId: nil, animalId: nil, services: makeServices())
        for byte in 1...5 { model.addPhoto(Data([UInt8(byte)])) }
        XCTAssertEqual(model.photos.count, 3)
        model.removePhoto(model.photos[1].id)
        XCTAssertEqual(model.photos.count, 2)
        XCTAssertTrue(model.canAddPhoto)
    }

    func testSubmitSignedOutSurfacesError() async {
        let model = CreateNeedViewModel(spotId: DemoData.id(2, 3), animalId: nil, services: makeServices(signedIn: false))
        model.type = .water
        model.descriptionText = validText
        let id = await model.submit()
        XCTAssertNil(id)
        XCTAssertEqual(model.error, .notSignedIn)
    }
}
