import XCTest
import MamaCore
@testable import FeatureCommunity

@MainActor
final class CommunitySpotOptionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeBackend() -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { fixed })
    }

    private func makeServices(_ backend: InMemoryBackend) -> AppServices {
        let fixed = now
        return AppServices.inMemory(backend, now: { fixed })
    }

    func testGuardedSpotsComeBeforeNearbyWithoutDuplicates() async {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.ayseId)
        let model = CreatePostViewModel(kind: .coverRequest, spotId: nil, services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let guarded = model.spotOptions.filter { $0.source == .guarded }
        XCTAssertEqual(Set(guarded.map(\.id)), [DemoData.id(2, 1), DemoData.id(2, 2), DemoData.id(2, 14)])
        XCTAssertEqual(Array(model.spotOptions.prefix(guarded.count)), guarded, "koruyucusu olunan noktalar en üstte")
        let guardedDistances = guarded.compactMap(\.distanceMeters)
        XCTAssertEqual(guardedDistances.count, guarded.count)
        XCTAssertEqual(guardedDistances, guardedDistances.sorted())

        let nearby = model.spotOptions.filter { $0.source == .nearby }
        XCTAssertFalse(nearby.isEmpty)
        XCTAssertLessThanOrEqual(nearby.count, CreatePostViewModel.maxNearbyOptions)
        XCTAssertTrue(nearby.allSatisfy { ($0.distanceMeters ?? .infinity) <= Double(CreatePostViewModel.nearbyRadiusMeters) })
        XCTAssertEqual(Set(model.spotOptions.map(\.id)).count, model.spotOptions.count)
        XCTAssertTrue(model.hasLoadedSpots)
        XCTAssertFalse(model.isLoadingSpots)
    }

    func testViewerWithoutGuardedSpotsSeesNearbyOnly() async {
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        XCTAssertFalse(model.spotOptions.isEmpty)
        XCTAssertTrue(model.spotOptions.allSatisfy { $0.source == .nearby })
        let distances = model.spotOptions.compactMap(\.distanceMeters)
        XCTAssertEqual(distances, distances.sorted())
    }

    func testWithoutLocationOnlyGuardedSpotsAreOffered() async {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.emreId)
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(backend))
        await model.load(near: nil)
        XCTAssertEqual(model.spotOptions.map(\.id), [DemoData.id(2, 5)])
        XCTAssertEqual(model.spotOptions.first?.source, .guarded)
        XCTAssertNil(model.spotOptions.first?.distanceMeters)
    }

    func testPresetSpotIsFirstAndSelected() async {
        // 16 numaralı nokta Moda merkezine 500 m'den uzak olabilir; yine de listede ve seçili gelir.
        let presetId = DemoData.id(2, 16)
        let model = CreatePostViewModel(kind: .coverRequest, spotId: presetId, services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.spotOptions.first?.id, presetId)
        XCTAssertEqual(model.spotOptions.first?.source, .preset)
        XCTAssertEqual(model.selectedSpot?.id, presetId)
        XCTAssertEqual(model.spotOptions.filter { $0.id == presetId }.count, 1)
    }

    func testVanishedPresetSpotIsDeselected() async {
        let model = CreatePostViewModel(kind: .coverRequest, spotId: UUID(), services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        XCTAssertNil(model.selectedSpotId)
        XCTAssertNil(model.selectedSpot)
        XCTAssertEqual(model.validationError(near: .modaKadikoy), .bodyEmpty)
    }
}

final class CommunityFormatTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return CommunityFormat.istanbulCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    func testTurkishCoverRange() {
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 14), to: date(2026, 11, 15), language: .turkish), "14–15 Kasım")
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 14), to: date(2026, 11, 14), language: .turkish), "14 Kasım")
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 30), to: date(2026, 12, 2), language: .turkish), "30 Kasım – 2 Aralık")
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 12, 30), to: date(2027, 1, 2), language: .turkish), "30 Aralık 2026 – 2 Ocak 2027")
    }

    func testEnglishCoverRange() {
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 14), to: date(2026, 11, 15), language: .english), "Nov 14–15")
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 14), to: date(2026, 11, 14), language: .english), "Nov 14")
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 30), to: date(2026, 12, 2), language: .english), "Nov 30 – Dec 2")
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 12, 30), to: date(2027, 1, 2), language: .english), "Dec 30, 2026 – Jan 2, 2027")
    }

    func testCoverRangeUsesIstanbulDays() {
        // 14 Kasım 23:30 İstanbul = 20:30 UTC; 15 Kasım 00:30 İstanbul = 14 Kasım 21:30 UTC.
        let lateEvening = date(2026, 11, 14, hour: 23).addingTimeInterval(30 * 60)
        let afterMidnight = date(2026, 11, 15, hour: 0).addingTimeInterval(30 * 60)
        XCTAssertEqual(CommunityFormat.coverRange(from: lateEvening, to: afterMidnight, language: .turkish), "14–15 Kasım")
    }

    func testCoverRangeEdgeCases() {
        XCTAssertNil(CommunityFormat.coverRange(from: nil, to: nil, language: .turkish))
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 14), to: nil, language: .turkish), "14 Kasım")
        XCTAssertEqual(CommunityFormat.coverRange(from: nil, to: date(2026, 11, 15), language: .turkish), "15 Kasım")
        // Ters verilse de küçükten büyüğe yazılır.
        XCTAssertEqual(CommunityFormat.coverRange(from: date(2026, 11, 15), to: date(2026, 11, 14), language: .turkish), "14–15 Kasım")
    }

    func testDeleteMessagesDifferBySubject() {
        XCTAssertNotEqual(CommunityDeleteResult.deleted.message(for: .post), CommunityDeleteResult.deleted.message(for: .comment))
        XCTAssertNotEqual(CommunityDeleteResult.notAllowed.message(for: .post), CommunityDeleteResult.notAllowed.message(for: .comment))
        XCTAssertEqual(CommunityDeleteResult.failed(.offline).message(for: .comment), MamaError.offline.userMessage)
        XCTAssertEqual(CommunityDeleteResult.deleted.toastStyle, .success)
        XCTAssertEqual(CommunityDeleteResult.failed(.offline).toastStyle, .warning)
    }

    func testOptimisticPawNeverGoesNegative() {
        var post = CommunityPost(kind: .note, body: "x", authorId: UUID(), authorName: "A", pawCount: 0, viewerPawed: true)
        post.applyOptimisticPawToggle()
        XCTAssertFalse(post.viewerPawed)
        XCTAssertEqual(post.pawCount, 0)
        post.applyOptimisticPawToggle()
        XCTAssertTrue(post.viewerPawed)
        XCTAssertEqual(post.pawCount, 1)
        post.apply(PawToggleResult(pawed: false, pawCount: 7))
        XCTAssertFalse(post.viewerPawed)
        XCTAssertEqual(post.pawCount, 7)
    }
}
