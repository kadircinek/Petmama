import Foundation
import XCTest
import MamaCore
@testable import FeatureSpots

@MainActor
final class SpotDetailViewModelTests: XCTestCase {
    private func makeModel(spot index: Int = 1, signedIn: Bool = true) -> (SpotDetailViewModel, InMemoryBackend) {
        let (services, backend) = MapSpotsFixture.services(signedIn: signedIn)
        return (SpotDetailViewModel(spotId: DemoData.id(2, index), services: services), backend)
    }

    func testLoadFillsAllSections() async {
        let (model, _) = makeModel()
        await model.load(near: MapSpotsFixture.coordinate(ofSpot: 1), userId: DemoData.meId)

        XCTAssertEqual(model.spot?.title, "Moda Parkı girişi")
        XCTAssertEqual(model.status, .fedRecent)
        XCTAssertEqual(Set(model.animals.map(\.name)), ["Pamuk", "Tarçın"])
        XCTAssertEqual(model.timeline.count, 7)
        XCTAssertEqual(model.needs.map(\.id), [DemoData.id(5, 2)], "Çözülmüş aşı ihtiyacı gösterilmez")
        XCTAssertEqual(model.guardians.map(\.displayName), ["Ayşe"])
        XCTAssertFalse(model.isGuardian)
        XCTAssertFalse(model.isFollowing)
        XCTAssertLessThan(model.spot?.distanceMeters ?? .infinity, 1)
        let relative = MamaFormat.relative(MapSpotsFixture.spot(1).lastFedAt, now: MapSpotsFixture.now)
        XCTAssertEqual(model.lastFedText, "Son mama: \(relative)")
    }

    func testTimelineBarsEndTodayWithIstanbulWeekdays() async {
        let (model, _) = makeModel()
        await model.load(near: nil, userId: DemoData.meId)

        let bars = model.timelineBars
        XCTAssertEqual(bars.count, 7)
        XCTAssertEqual(bars.last?.isToday, true)
        XCTAssertEqual(bars.filter(\.isToday).count, 1)
        // 2026-11-04 bir Çarşamba.
        XCTAssertEqual(bars.last?.weekday, .wednesday)
        XCTAssertEqual(bars.last?.label, "Çar")
        XCTAssertEqual(bars.first?.weekday, .thursday)
        XCTAssertGreaterThan(model.maxTimelineCount, 0)
        XCTAssertEqual(model.weeklyFedCount, model.timeline.map(\.fedCount).reduce(0, +))
    }

    func testWeekdayMapping() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        let sunday = Date(timeIntervalSince1970: 1_793_516_400) // 2026-11-01 10:00 İstanbul
        let monday = sunday.addingTimeInterval(86_400)
        XCTAssertEqual(SpotDetailViewModel.weekday(of: sunday, calendar: calendar), .sunday)
        XCTAssertEqual(SpotDetailViewModel.weekday(of: monday, calendar: calendar), .monday)
    }

    func testFollowToggle() async {
        let (model, backend) = makeModel()
        await model.load(near: nil, userId: DemoData.meId)

        let feedback = await model.setFollowing(true)
        let followed = try? await backend.followedSpotIds()
        XCTAssertTrue(feedback.isSuccess)
        XCTAssertTrue(model.isFollowing)
        XCTAssertEqual(followed, [DemoData.id(2, 1)])

        _ = await model.setFollowing(false)
        XCTAssertFalse(model.isFollowing)
    }

    func testBecomeAndStopBeingGuardian() async {
        let (model, _) = makeModel()
        await model.load(near: nil, userId: DemoData.meId)

        let joined = await model.setGuardian(schedule: [.monday, .thursday], userId: DemoData.meId)
        XCTAssertTrue(joined.isSuccess)
        XCTAssertTrue(model.isGuardian)
        XCTAssertEqual(model.mySchedule, [.monday, .thursday])
        XCTAssertEqual(model.guardians.count, 2)

        _ = await model.setGuardian(schedule: nil, userId: DemoData.meId)
        XCTAssertFalse(model.isGuardian)
        XCTAssertEqual(model.guardians.count, 1)
    }

    func testReportGoneCountsDistinctReporters() async {
        let (model, backend) = makeModel(spot: 3)
        await model.load(near: nil, userId: DemoData.meId)

        let first = await model.reportGone()
        XCTAssertEqual(first.message, "Teşekkürler! Bildirimin alındı (1/3).")

        await backend.setCurrentUser(DemoData.ayseId)
        _ = await model.reportGone()
        await backend.setCurrentUser(DemoData.emreId)
        let third = await model.reportGone()
        XCTAssertEqual(third.message, "Teşekkürler! Nokta haritadan kaldırıldı.")
        XCTAssertEqual(model.spot?.isActive, false)
    }

    func testSignedOutActionsExplainSignIn() async {
        let (model, _) = makeModel(signedIn: false)
        await model.load(near: nil, userId: nil)

        XCTAssertEqual(model.spot?.isLocationExact, false, "Giriş yapmayan yaklaşık konumu görür")
        let feedback = await model.setFollowing(true)
        XCTAssertFalse(feedback.isSuccess)
        XCTAssertEqual(feedback.message, MamaError.notSignedIn.userMessage)
    }

    func testMissingSpotIsNotFound() async {
        let services = MapSpotsFixture.services().services
        let model = SpotDetailViewModel(spotId: UUID(), services: services)
        await model.load(near: nil, userId: nil)
        XCTAssertTrue(model.notFound)
    }

    func testOfflineLoadSurfacesError() async {
        let services = MapSpotsFixture.offlineServices(backend: MapSpotsFixture.backend())
        let model = SpotDetailViewModel(spotId: DemoData.id(2, 1), services: services)
        await model.load(near: nil, userId: nil)
        XCTAssertEqual(model.error, .offline)
        XCTAssertFalse(model.notFound)
    }
}
