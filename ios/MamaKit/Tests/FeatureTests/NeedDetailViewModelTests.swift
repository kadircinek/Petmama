import XCTest
import MamaCore
@testable import FeatureNeeds

@MainActor
final class NeedDetailViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeServices(signedIn: Bool = true) -> (AppServices, InMemoryBackend) {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
        return (AppServices.inMemory(backend, now: { fixed }), backend)
    }

    func testLoadsNeedWithLinkedAnimalAndSpot() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 1), services: services)
        await model.load()
        XCTAssertEqual(model.need?.animalName, "Zeytin")
        XCTAssertEqual(model.need?.spotTitle, "Şair Nefi Sokak çınar")
        XCTAssertTrue(model.canClaim)
        XCTAssertTrue(model.showsVetHelp)
    }

    func testVetHelpOnlyForVetNeeds() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 2), services: services)
        await model.load()
        XCTAssertFalse(model.showsVetHelp)
    }

    func testMissingNeedReportsNotFound() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: UUID(), services: services)
        await model.load()
        XCTAssertNil(model.need)
        XCTAssertEqual(model.error, .notFound)
    }

    func testTimelineForClaimedNeed() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 4), services: services)
        await model.load()
        let steps = model.timeline(viewerId: DemoData.meId)
        XCTAssertEqual(steps.map(\.kind), [.opened, .claimed, .resolved])
        XCTAssertEqual(steps.map(\.isDone), [true, true, false])
        XCTAssertEqual(steps[1].detail, "Ayşe ilgileniyor")
        XCTAssertEqual(steps[1].date, now.addingTimeInterval(-6 * 3600))
        XCTAssertFalse(model.canClaim)
    }

    func testCanResolvePermissions() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 1), services: services) // Zeynep açtı
        await model.load()
        XCTAssertFalse(model.canResolve(userId: DemoData.meId, isVerifiedFeeder: false))
        XCTAssertTrue(model.canResolve(userId: DemoData.zeynepId, isVerifiedFeeder: false), "açan kapatabilir")
        XCTAssertTrue(model.canResolve(userId: DemoData.meId, isVerifiedFeeder: true), "doğrulanmış besleyici kapatabilir")
        XCTAssertFalse(model.canResolve(userId: nil, isVerifiedFeeder: true), "giriş yoksa gösterilmez")

        let claimed = NeedDetailViewModel(needId: DemoData.id(5, 4), services: services) // Ayşe üstlendi
        await claimed.load()
        XCTAssertTrue(claimed.canResolve(userId: DemoData.ayseId, isVerifiedFeeder: false), "üstlenen kapatabilir")

        let resolved = NeedDetailViewModel(needId: DemoData.id(5, 6), services: services)
        await resolved.load()
        XCTAssertFalse(resolved.canResolve(userId: DemoData.ayseId, isVerifiedFeeder: true), "çözülmüş tekrar kapatılmaz")
    }

    func testServerRejectsResolveForUnrelatedUser() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 2), services: services)
        await model.load()
        let result = await model.resolve()
        XCTAssertEqual(result, .notAllowed)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertEqual(model.need?.status, .open)
    }

    func testClaimThenResolve() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 1), services: services)
        await model.load()

        let claim = await model.claim()
        XCTAssertEqual(claim, .claimed)
        XCTAssertEqual(model.need?.status, .claimed)
        XCTAssertTrue(model.canResolve(userId: DemoData.meId, isVerifiedFeeder: false))
        XCTAssertEqual(model.timeline(viewerId: DemoData.meId)[1].detail, "Sen ilgileniyorsun")
        XCTAssertEqual(model.timeline(viewerId: nil)[1].detail, "Sen ilgileniyor", "başkası adı görür")

        let resolve = await model.resolve()
        XCTAssertEqual(resolve, .resolved)
        XCTAssertEqual(model.need?.status, .resolved)
        let finalSteps = model.timeline(viewerId: DemoData.meId)
        XCTAssertEqual(finalSteps.map(\.isDone), [true, true, true])
        XCTAssertEqual(finalSteps[2].date, now)
    }

    func testClaimAlreadyClaimed() async {
        let (services, _) = makeServices()
        let model = NeedDetailViewModel(needId: DemoData.id(5, 4), services: services)
        await model.load()
        let result = await model.claim()
        XCTAssertEqual(result, .alreadyClaimed)
    }

    func testResolveSignedOutFails() async {
        let (services, _) = makeServices(signedIn: false)
        let model = NeedDetailViewModel(needId: DemoData.id(5, 1), services: services)
        await model.load()
        let result = await model.resolve()
        XCTAssertEqual(result, .failed(.notSignedIn))
    }
}
