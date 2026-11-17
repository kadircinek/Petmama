import XCTest
import MamaCore
import FeatureModeration
import FeatureProfile
import FeatureSpots
import FeatureSocial

private let moderationNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class ModerationViewModelTests: XCTestCase {
    private func makeEnvironment() -> (InMemoryBackend, AppServices) {
        let now = moderationNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { now })
        return (backend, AppServices.inMemory(backend, now: { now }))
    }

    // MARK: - Kuyruk

    func testQueueLoadsOpenCasesAndSwitchesToClosed() async throws {
        let (_, services) = makeEnvironment()
        let model = ModerationQueueViewModel(services: services)
        XCTAssertEqual(model.tab, .open)
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.cases.map(\.target), [.post, .chatMessage, .user])
        XCTAssertEqual(model.openCount, 3)
        XCTAssertFalse(model.isEmpty)

        _ = try await services.moderator.decide(target: .post, id: DemoData.moderationPostId, decision: .remove, note: nil)
        await model.select(.closed)
        XCTAssertEqual(model.tab, .closed)
        XCTAssertEqual(model.cases.map(\.targetId), [DemoData.moderationPostId])
        XCTAssertEqual(model.cases.first?.decision, .remove)

        await model.select(.open)
        XCTAssertEqual(model.cases.count, 2)
        XCTAssertEqual(model.openCount, 2)
    }

    func testQueueEmptyStateAndNonModerator() async {
        let (backend, services) = makeEnvironment()
        await backend.setModerator(false, for: DemoData.meId)
        let model = ModerationQueueViewModel(services: services)
        await model.load()
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.emptyTitle, "Bekleyen rapor yok")
        await model.select(.closed)
        XCTAssertEqual(model.emptyTitle, "Son 30 günde kapanan rapor yok")
    }

    func testCaseSummaryTexts() async {
        let item = ModerationCase(target: .post, targetId: UUID(), body: "x", reportCount: 2, reasons: [.spam],
                                  firstReportedAt: moderationNow, lastReportedAt: moderationNow, contentState: .pending)
        XCTAssertEqual(ModerationFormat.reportCount(item.reportCount), "2 rapor")
        XCTAssertEqual(ModerationFormat.stateLabel(.live), "Yayında")
        XCTAssertEqual(ModerationFormat.stateLabel(.pending), "İncelemede")
        XCTAssertEqual(ModerationFormat.stateLabel(.removed), "Kaldırıldı")
        XCTAssertEqual(ModerationFormat.stateLabel(.gone), "Silinmiş")
        XCTAssertEqual(ModerationFormat.decisionLabel(.approve), "Uygun bulundu")
        XCTAssertEqual(ModerationFormat.decisionLabel(.remove), "Kaldırıldı")
        XCTAssertEqual(ModerationFormat.lengthLabel(.week), "7 gün")
        XCTAssertEqual(ModerationFormat.lengthLabel(.month), "30 gün")
        XCTAssertEqual(ModerationFormat.lengthLabel(.indefinite), "Süresiz")
    }

    // MARK: - Detay ve kararlar

    func testCaseDetailLoadsReportsAndOwnerHistory() async {
        let (_, services) = makeEnvironment()
        let model = ModerationCaseViewModel(target: .post, targetId: DemoData.moderationPostId, services: services)
        await model.load()
        XCTAssertEqual(model.detail?.reports.count, 2)
        XCTAssertEqual(model.detail?.owner?.displayName, "Zeynep")
        XCTAssertTrue(model.canDecide)
        XCTAssertTrue(model.canSuspend)
        XCTAssertFalse(model.isOwnerSuspended)
        XCTAssertFalse(model.isNotFound)
    }

    func testRemoveWithNoteClosesCaseAndShowsMessage() async throws {
        let (backend, services) = makeEnvironment()
        let model = ModerationCaseViewModel(target: .post, targetId: DemoData.moderationPostId, services: services)
        await model.load()
        model.note = "  Tekrarlayan ilan  "
        let done = await model.decide(.remove)
        XCTAssertTrue(done)
        XCTAssertEqual(model.message, "İçerik kaldırıldı. 2 rapor kapandı.")
        XCTAssertFalse(model.canDecide, "karar verilen vaka kapanır")
        XCTAssertEqual(model.detail?.moderationCase.decision, .remove)
        XCTAssertEqual(model.note, "", "not temizlenir")
        let actions = await backend.allModerationActions()
        XCTAssertEqual(actions.last?.note, "Tekrarlayan ilan")
    }

    func testApproveMessageAndLongNoteBlocksSubmission() async {
        let (_, services) = makeEnvironment()
        let model = ModerationCaseViewModel(target: .chatMessage, targetId: DemoData.id(10, 3), services: services)
        await model.load()
        model.note = String(repeating: "a", count: ModerationPolicy.maxNoteLength + 1)
        XCTAssertTrue(model.isNoteTooLong)
        let blocked = await model.decide(.approve)
        XCTAssertFalse(blocked)
        XCTAssertTrue(model.canDecide)
        model.note = ""
        let done = await model.decide(.approve)
        XCTAssertTrue(done)
        XCTAssertEqual(model.message, "Uygun bulundu, içerik yayında kalıyor. 1 rapor kapandı.")
    }

    func testSuspendAndUnsuspendOwner() async throws {
        let (backend, services) = makeEnvironment()
        let model = ModerationCaseViewModel(target: .user, targetId: DemoData.emreId, services: services)
        await model.load()
        XCTAssertTrue(model.canSuspend)
        let suspended = await model.suspend(.week)
        XCTAssertTrue(suspended)
        XCTAssertTrue(model.isOwnerSuspended)
        XCTAssertTrue(model.message?.contains("tarihine kadar uzaklaştırıldı") ?? false, model.message ?? "")
        XCTAssertEqual(model.detail?.owner?.suspensionCount90d, 1)

        let lifted = await model.unsuspend()
        XCTAssertTrue(lifted)
        XCTAssertFalse(model.isOwnerSuspended)
        XCTAssertEqual(model.message, "Uzaklaştırma kaldırıldı.")

        _ = await model.suspend(.indefinite)
        XCTAssertEqual(model.message, "Emre süresiz uzaklaştırıldı.")
        let profile = await backend.rawUser(DemoData.emreId)
        XCTAssertEqual(profile?.suspendedUntil, .distantFuture)
    }

    func testCannotSuspendModeratorOwnerOrSelf() async {
        let (backend, services) = makeEnvironment()
        await backend.setModerator(true, for: DemoData.zeynepId)
        let model = ModerationCaseViewModel(target: .post, targetId: DemoData.moderationPostId, services: services)
        await model.load()
        XCTAssertFalse(model.canSuspend, "moderatör uzaklaştırılamaz")
        let outcome = await model.suspend(.week)
        XCTAssertFalse(outcome)
    }

    func testUnknownCaseIsNotFound() async {
        let (_, services) = makeEnvironment()
        let model = ModerationCaseViewModel(target: .post, targetId: UUID(), services: services)
        await model.load()
        XCTAssertTrue(model.isNotFound)
        XCTAssertNil(model.detail)
    }

    func testNonModeratorGetsPermissionError() async {
        let (backend, services) = makeEnvironment()
        await backend.setModerator(false, for: DemoData.meId)
        let model = ModerationCaseViewModel(target: .post, targetId: DemoData.moderationPostId, services: services)
        await model.load()
        XCTAssertEqual(model.error, .permissionDenied)
        let decided = await model.decide(.remove)
        XCTAssertFalse(decided)
    }

    // MARK: - Profil satırı

    func testProfileShowsModerationBadgeOnlyForModerators() async throws {
        let (backend, services) = makeEnvironment()
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        await session.restore()
        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        XCTAssertEqual(session.profile?.isModerator, true)
        XCTAssertEqual(model.moderationBadgeText, "3")
        XCTAssertTrue(model.showsModeration(session.profile))

        await backend.setModerator(false, for: DemoData.meId)
        await model.load(session: session)
        XCTAssertFalse(model.showsModeration(session.profile))
        XCTAssertNil(model.moderationBadgeText)
    }

    func testProfileShowsSuspensionNoticeToSuspendedUser() async throws {
        let (backend, services) = makeEnvironment()
        _ = try await services.moderator.suspend(userId: DemoData.emreId, length: .month, note: nil)
        await backend.setCurrentUser(DemoData.emreId)
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        await session.restore()
        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        let until = moderationNow.addingTimeInterval(30 * 86_400)
        XCTAssertEqual(session.profile?.suspendedUntil, until)
        XCTAssertEqual(model.suspensionNotice(session.profile), MamaError.suspended(until: until).userMessage)
        XCTAssertFalse(model.showsModeration(session.profile))
        XCTAssertNil(model.suspensionNotice(UserProfile(displayName: "Biri")))
    }

    // MARK: - Uzaklaştırılan kullanıcının yazma hataları

    func testSuspendedUserSeesSuspensionOnCheckInAndChat() async throws {
        let (backend, services) = makeEnvironment()
        _ = try await services.moderator.suspend(userId: DemoData.zeynepId, length: .week, note: nil)
        await backend.setCurrentUser(DemoData.zeynepId)
        let expected = MamaError.suspended(until: moderationNow.addingTimeInterval(7 * 86_400)).userMessage

        let checkIn = CheckInViewModel(spotId: DemoData.id(2, 1), kind: .fed, services: services)
        await checkIn.load()
        let result = await checkIn.submit(user: Coordinate(latitude: 40.98455, longitude: 29.02560))
        XCTAssertEqual(result, .failed(.suspended(until: moderationNow.addingTimeInterval(7 * 86_400))))
        XCTAssertEqual(result.message, expected)
        let queued = await services.checkInQueue.pendingCount()
        XCTAssertEqual(queued, 0, "uzaklaştırma hatası çevrimdışı kuyruğa alınmaz")

        let chat = ChatViewModel(services: services, conversationId: DemoData.id(9, 1))
        chat.draft = "Merhaba"
        await chat.send()
        XCTAssertEqual(chat.error?.userMessage, expected)
    }
}
