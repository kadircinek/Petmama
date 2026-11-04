import XCTest
import MamaCore
@testable import FeatureNeeds

private actor FakeVetSearch: VetClinicSearching {
    var clinicsToReturn: [VetClinic]
    var shouldFail = false
    private(set) var lastCenter: Coordinate?

    init(clinics: [VetClinic], shouldFail: Bool = false) {
        self.clinicsToReturn = clinics
        self.shouldFail = shouldFail
    }

    func clinics(near center: Coordinate, radiusMeters: Double) async throws -> [VetClinic] {
        lastCenter = center
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return clinicsToReturn
    }
}

@MainActor
final class NeedVetHelpViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeServices() -> AppServices {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { fixed })
        return AppServices.inMemory(backend, now: { fixed })
    }

    private func clinic(_ name: String, metersNorth: Double) -> VetClinic {
        VetClinic(name: name, phone: "0216 555 00 00", coordinate: GeoMath.offset(.modaKadikoy, north: metersNorth, east: 0))
    }

    func testClinicsSortedByDistanceAndLimited() async {
        let far = (0..<10).map { clinic("Klinik \($0)", metersNorth: Double(1000 + $0 * 100)) }
        let search = FakeVetSearch(clinics: far + [clinic("En yakın", metersNorth: 120)])
        let model = VetHelpViewModel(needId: nil, services: makeServices(), searcher: search)

        await model.load(near: .modaKadikoy)

        XCTAssertEqual(model.clinics.count, VetHelpViewModel.maxClinics)
        XCTAssertEqual(model.clinics.first?.name, "En yakın")
        XCTAssertEqual(model.clinics.first?.distanceMeters ?? 0, 120, accuracy: 1)
        let distances = model.clinics.compactMap(\.distanceMeters)
        XCTAssertEqual(distances, distances.sorted())
        XCTAssertTrue(model.hasSearched)
        XCTAssertFalse(model.searchFailed)
    }

    func testSearchCenterFallsBackToNeedThenModa() async throws {
        let search = FakeVetSearch(clinics: [])
        let model = VetHelpViewModel(needId: DemoData.id(5, 1), services: makeServices(), searcher: search)
        await model.load(near: nil)
        let needCoordinate = try XCTUnwrap(model.need?.coordinate)
        let center = await search.lastCenter
        XCTAssertEqual(center, needCoordinate)

        let noNeed = VetHelpViewModel(needId: nil, services: makeServices(), searcher: search)
        XCTAssertEqual(noNeed.searchCenter(user: nil), .modaKadikoy)
        let user = GeoMath.offset(.modaKadikoy, north: 500, east: 0)
        XCTAssertEqual(noNeed.searchCenter(user: user), user)
    }

    func testSearchFailureIsReported() async {
        let search = FakeVetSearch(clinics: [clinic("A", metersNorth: 10)], shouldFail: true)
        let model = VetHelpViewModel(needId: nil, services: makeServices(), searcher: search)
        await model.load(near: .modaKadikoy)
        XCTAssertTrue(model.searchFailed)
        XCTAssertTrue(model.clinics.isEmpty)
    }

    func testTelURLSanitizesPhone() async {
        XCTAssertEqual(VetHelpViewModel.telURL("+90 (216) 555 01 02")?.absoluteString, "tel:+902165550102")
        XCTAssertEqual(VetHelpViewModel.telURL("153")?.absoluteString, "tel:153")
        XCTAssertNil(VetHelpViewModel.telURL(nil))
        XCTAssertNil(VetHelpViewModel.telURL("yok"))
    }

    func testMapsSearchFallbackURL() async {
        let url = VetHelpViewModel.mapsSearchURL(near: .modaKadikoy)
        XCTAssertEqual(url?.host, "maps.apple.com")
        XCTAssertTrue(url?.absoluteString.contains("q=veteriner") ?? false)
    }

    func testNoMedicalAdviceDisclaimer() async {
        XCTAssertTrue(VetHelpViewModel.disclaimer.contains("tıbbi tavsiye vermez"))
        XCTAssertTrue(VetHelpViewModel.municipalLine.contains("153"))
        XCTAssertTrue(VetHelpViewModel.emergencyLine.contains("112"))
    }
}
