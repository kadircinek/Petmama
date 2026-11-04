import XCTest
import MamaCore
import FeatureProfile

private let reportNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class ReportViewModelTests: XCTestCase {
    private func makeEnvironment(signedIn: Bool = true) -> (InMemoryBackend, AppServices) {
        let now = reportNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: signedIn, now: { now })
        return (backend, AppServices.inMemory(backend, now: { now }))
    }

    func testReasonIsRequired() async {
        let (backend, services) = makeEnvironment()
        let model = ReportViewModel(target: .spot, targetId: DemoData.id(2, 1), services: services)
        XCTAssertFalse(model.canSubmit)
        let submitted = await model.submit()
        XCTAssertFalse(submitted)
        XCTAssertNotNil(model.errorMessage)
        let reports = await backend.allReports()
        XCTAssertTrue(reports.isEmpty)
    }

    func testSpotReportIsStoredWithTrimmedDetails() async {
        let (backend, services) = makeEnvironment()
        let spotId = DemoData.id(2, 3)
        let model = ReportViewModel(target: .spot, targetId: spotId, services: services)
        XCTAssertEqual(model.question, "Bu noktayı neden bildiriyorsun?")
        XCTAssertFalse(model.offersBlock)
        model.reason = .wrongLocation
        model.details = "  Nokta 50 m ileride, köşede.  "
        let submitted = await model.submit()
        XCTAssertTrue(submitted)
        XCTAssertTrue(model.didSubmit)
        XCTAssertEqual(model.completionMessage, "Teşekkürler. Raporunu 24 saat içinde inceleyeceğiz.")
        let reports = await backend.allReports()
        XCTAssertEqual(reports, [ReportDraft(target: .spot, targetId: spotId, reason: .wrongLocation, details: "Nokta 50 m ileride, köşede.")])
    }

    func testEmptyDetailsAreSentAsNil() async {
        let (backend, services) = makeEnvironment()
        let model = ReportViewModel(target: .photo, targetId: DemoData.id(3, 1), services: services)
        model.reason = .inappropriate
        model.details = "   "
        _ = await model.submit()
        let reports = await backend.allReports()
        XCTAssertEqual(reports.first?.details, nil)
        XCTAssertEqual(reports.first?.target, .photo)
    }

    func testAnimalHarmShowsEmergencyWarning() async {
        let (_, services) = makeEnvironment()
        let model = ReportViewModel(target: .animal, targetId: DemoData.id(4, 1), services: services)
        XCTAssertFalse(model.showsAnimalHarmWarning)
        model.reason = .animalHarm
        XCTAssertTrue(model.showsAnimalHarmWarning)
        XCTAssertTrue(ReportViewModel.animalHarmWarning.contains("112"))
    }

    func testUserReportCanAlsoBlock() async throws {
        let (backend, services) = makeEnvironment()
        let model = ReportViewModel(target: .user, targetId: DemoData.emreId, services: services)
        XCTAssertTrue(model.offersBlock)
        model.reason = .harassment
        model.alsoBlock = true
        let submitted = await model.submit()
        XCTAssertTrue(submitted)
        XCTAssertTrue(model.didBlock)
        XCTAssertTrue(model.completionMessage.contains("engelledin"))
        let blocked = try await services.moderation.blockedUserIds()
        XCTAssertEqual(blocked, [DemoData.emreId])
        let reports = await backend.allReports()
        XCTAssertEqual(reports.map(\.target), [.user])
    }

    func testBlockToggleIgnoredForNonUserTargets() async throws {
        let (_, services) = makeEnvironment()
        let model = ReportViewModel(target: .need, targetId: DemoData.id(5, 1), services: services)
        model.reason = .spam
        model.alsoBlock = true
        _ = await model.submit()
        XCTAssertFalse(model.didBlock)
        let blocked = try await services.moderation.blockedUserIds()
        XCTAssertTrue(blocked.isEmpty)
    }

    func testDetailsLengthLimit() async {
        let (backend, services) = makeEnvironment()
        let model = ReportViewModel(target: .spot, targetId: DemoData.id(2, 1), services: services)
        model.reason = .other
        model.details = String(repeating: "a", count: ReportViewModel.maximumDetailsLength + 1)
        XCTAssertTrue(model.isDetailsTooLong)
        XCTAssertFalse(model.canSubmit)
        let submitted = await model.submit()
        XCTAssertFalse(submitted)
        let reports = await backend.allReports()
        XCTAssertTrue(reports.isEmpty)
    }

    func testReportRequiresSignIn() async {
        let (_, services) = makeEnvironment(signedIn: false)
        let model = ReportViewModel(target: .spot, targetId: DemoData.id(2, 1), services: services)
        model.reason = .spam
        let submitted = await model.submit()
        XCTAssertFalse(submitted)
        XCTAssertEqual(model.errorMessage, MamaError.notSignedIn.userMessage)
        XCTAssertFalse(model.didSubmit)
    }
}
