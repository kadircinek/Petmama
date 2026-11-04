import XCTest
import MamaCore
@testable import FeatureNeeds

@MainActor
final class NeedsListViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeServices(signedIn: Bool = true) -> AppServices {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
        return AppServices.inMemory(backend, now: { fixed })
    }

    func testUrgentFirstThenDistanceWithoutResolved() async {
        let model = NeedsListViewModel(services: makeServices())
        await model.load(near: .modaKadikoy)
        let visible = model.visibleNeeds

        XCTAssertEqual(visible.first?.id, DemoData.id(5, 1), "açık acil veteriner ihtiyacı en üstte")
        XCTAssertFalse(visible.contains { $0.status == .resolved })
        let openNormal = visible.filter { $0.status == .open && $0.urgency == .normal }
        let distances = openNormal.compactMap(\.distanceMeters)
        XCTAssertEqual(distances.count, openNormal.count)
        XCTAssertEqual(distances, distances.sorted())
        let lastOpenIndex = visible.lastIndex { $0.status == .open } ?? -1
        let firstClaimedIndex = visible.firstIndex { $0.status == .claimed } ?? Int.max
        XCTAssertLessThan(lastOpenIndex, firstClaimedIndex, "üstlenilenler açıkların altında")
    }

    func testTypeFilter() async {
        let model = NeedsListViewModel(services: makeServices())
        await model.load(near: .modaKadikoy)

        model.toggleType(.vet)
        XCTAssertEqual(model.visibleNeeds.map(\.id), [DemoData.id(5, 1)])
        XCTAssertTrue(model.hasActiveFilter)

        model.toggleType(.water)
        XCTAssertEqual(Set(model.visibleNeeds.map(\.type)), [.vet, .water])

        model.toggleType(.vet)
        XCTAssertEqual(model.visibleNeeds.map(\.type), [.water])

        model.clearTypes()
        XCTAssertFalse(model.hasActiveFilter)
        XCTAssertEqual(model.visibleNeeds.count, 5)
    }

    func testFilterWithNoMatchesIsEmpty() async {
        let model = NeedsListViewModel(services: makeServices())
        await model.load(near: .modaKadikoy)
        model.toggleType(.adoption)
        XCTAssertTrue(model.isEmpty)
    }

    func testIncludeResolvedShowsResolvedLast() async {
        let model = NeedsListViewModel(services: makeServices())
        model.includeResolved = true
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.visibleNeeds.last?.id, DemoData.id(5, 6))
        XCTAssertEqual(model.visibleNeeds.last?.status, .resolved)
    }

    func testFallsBackToModaWithoutLocation() async {
        let model = NeedsListViewModel(services: makeServices())
        await model.load(near: nil)
        XCTAssertFalse(model.visibleNeeds.isEmpty)
        XCTAssertNil(model.error)
    }

    func testFarAwayLocationShowsEmptyState() async {
        let model = NeedsListViewModel(services: makeServices())
        await model.load(near: GeoMath.offset(.modaKadikoy, north: 20_000, east: 0))
        XCTAssertTrue(model.isEmpty)
    }

    func testClaimOpenNeed() async {
        let model = NeedsListViewModel(services: makeServices())
        await model.load(near: .modaKadikoy)
        let result = await model.claim(DemoData.id(5, 1), near: .modaKadikoy)

        XCTAssertEqual(result, .claimed)
        let claimed = model.needs.first { $0.id == DemoData.id(5, 1) }
        XCTAssertEqual(claimed?.status, .claimed)
        XCTAssertEqual(claimed?.claimedBy, DemoData.meId)
        XCTAssertNil(model.claimingId)
    }

    func testClaimAlreadyClaimedByAnotherVolunteer() async {
        let model = NeedsListViewModel(services: makeServices())
        let result = await model.claim(DemoData.id(5, 4), near: nil)
        XCTAssertEqual(result, .alreadyClaimed)
        XCTAssertEqual(result.message, "Başka bir gönüllü ilgileniyor")
        XCTAssertEqual(result.toastStyle, .info)
    }

    func testClaimResolvedNeed() async {
        let model = NeedsListViewModel(services: makeServices())
        let result = await model.claim(DemoData.id(5, 6), near: nil)
        XCTAssertEqual(result, .resolved)
    }

    func testClaimSignedOutFails() async {
        let model = NeedsListViewModel(services: makeServices(signedIn: false))
        let result = await model.claim(DemoData.id(5, 1), near: nil)
        XCTAssertEqual(result, .failed(.notSignedIn))
    }

    func testClaimOutcomeMapping() async {
        XCTAssertEqual(NeedClaimResult(.ok), .claimed)
        XCTAssertEqual(NeedClaimResult(.alreadyClaimed), .alreadyClaimed)
        XCTAssertEqual(NeedClaimResult(.resolved), .resolved)
    }
}
