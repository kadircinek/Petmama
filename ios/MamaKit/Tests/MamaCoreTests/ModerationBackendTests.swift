import XCTest
@testable import MamaCore

/// Moderasyon (Faz 3.1): bellek içi backend sunucudaki kuralları (supabase/tests/97_moderation.sql) aynalar.
final class ModerationBackendTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeBackend() -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { fixed })
    }

    // MARK: - Demo seed ve yetki

    func testDemoUserIsModeratorWithThreeSeededCases() async throws {
        let backend = makeBackend()
        let me = try await backend.profile(id: DemoData.meId)
        XCTAssertEqual(me?.isModerator, true)
        let count = try await backend.openCaseCount()
        XCTAssertEqual(count, 3)
        let queue = try await backend.moderationQueue(closed: false, limit: 50)
        XCTAssertEqual(queue.map(\.target), [.post, .chatMessage, .user])
        XCTAssertEqual(queue.first?.reportCount, 2)
        XCTAssertEqual(Set(queue.first?.reasons ?? []), [.spam, .inappropriate])
        XCTAssertEqual(queue.first?.contentState, .live)
        XCTAssertEqual(queue.first?.ownerName, "Zeynep")
        XCTAssertNil(queue.first?.decision)
    }

    func testNonModeratorSeesNothingAndCannotDecide() async throws {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.emreId)
        let count = try await backend.openCaseCount()
        XCTAssertEqual(count, 0)
        let queue = try await backend.moderationQueue(closed: false, limit: 50)
        XCTAssertTrue(queue.isEmpty)
        do {
            _ = try await backend.moderationCase(target: .post, id: DemoData.moderationPostId)
            XCTFail("yetki hatası bekleniyordu")
        } catch let error as MamaError {
            XCTAssertEqual(error, .permissionDenied)
        }
        let decide = try await backend.decide(target: .post, id: DemoData.moderationPostId, decision: .remove, note: nil)
        XCTAssertEqual(decide, .notAllowed)
        let suspend = try await backend.suspend(userId: DemoData.zeynepId, length: .week, note: nil)
        XCTAssertEqual(suspend, .notAllowed)
        let unsuspend = try await backend.unsuspend(userId: DemoData.zeynepId)
        XCTAssertEqual(unsuspend, .notAllowed)
    }

    func testReportsGroupByTargetAndChatPreviewShowsOnlyThatMessage() async throws {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.ayseId)
        try await backend.report(ReportDraft(target: .post, targetId: DemoData.moderationPostId, reason: .other, details: "Üçüncü"))
        await backend.setCurrentUser(DemoData.meId)
        let queue = try await backend.moderationQueue(closed: false, limit: 50)
        XCTAssertEqual(queue.count, 3, "aynı hedefe gelen raporlar tek satır")
        XCTAssertEqual(queue.first?.reportCount, 3)

        let chat = try XCTUnwrap(queue.first { $0.target == .chatMessage })
        XCTAssertEqual(chat.body, "Ben de kısırlaştırılmamış kedilerin listesini getiririm.")
        let detailValue = try await backend.moderationCase(target: .chatMessage, id: chat.targetId)
        let detail = try XCTUnwrap(detailValue)
        XCTAssertEqual(detail.reports.count, 1)
        XCTAssertEqual(detail.moderationCase.body, chat.body)
        XCTAssertEqual(detail.reports.first?.reporterName, "Emre")
        XCTAssertEqual(detail.reports.first?.status, .open)
        XCTAssertEqual(detail.owner?.userId, DemoData.zeynepId)
        XCTAssertEqual(detail.owner?.removedCount90d, 0)

        let limited = try await backend.moderationQueue(closed: false, limit: 1)
        XCTAssertEqual(limited.count, 1)
        let unknown = try await backend.moderationCase(target: .post, id: UUID())
        XCTAssertNil(unknown)
    }

    // MARK: - Kararlar

    func testRemovePostHidesItFromEveryoneAndClosesReports() async throws {
        let backend = makeBackend()
        let outcome = try await backend.decide(target: .post, id: DemoData.moderationPostId, decision: .remove, note: "  Reklam ")
        XCTAssertEqual(outcome, .done(closedReports: 2))

        await backend.setCurrentUser(DemoData.zeynepId)
        let forAuthor = try await backend.post(id: DemoData.moderationPostId, near: nil)
        XCTAssertNil(forAuthor, "kaldırılan paylaşım yazarına da görünmez")
        await backend.setCurrentUser(DemoData.emreId)
        let forOthers = try await backend.post(id: DemoData.moderationPostId, near: nil)
        XCTAssertNil(forOthers)

        await backend.setCurrentUser(DemoData.meId)
        let open = try await backend.moderationQueue(closed: false, limit: 50)
        XCTAssertFalse(open.contains { $0.targetId == DemoData.moderationPostId })
        let closed = try await backend.moderationQueue(closed: true, limit: 50)
        let row = try XCTUnwrap(closed.first { $0.targetId == DemoData.moderationPostId })
        XCTAssertEqual(row.decision, .remove)
        XCTAssertEqual(row.contentState, .removed)
        XCTAssertEqual(row.decidedAt, now)
        let count = try await backend.openCaseCount()
        XCTAssertEqual(count, 2)

        let detailValue = try await backend.moderationCase(target: .post, id: DemoData.moderationPostId)
        let detail = try XCTUnwrap(detailValue)
        XCTAssertEqual(detail.reports.map(\.status), [.actioned, .actioned])
        XCTAssertEqual(detail.owner?.removedCount90d, 1)
        let actions = await backend.allModerationActions()
        XCTAssertEqual(actions.last?.note, "Reklam")
        XCTAssertEqual(actions.last?.moderatorId, DemoData.meId)
    }

    func testApproveRestoresAutoHiddenContentAndDismissesReports() async throws {
        let backend = makeBackend()
        let postId = DemoData.id(6, 3)
        for reporter in [DemoData.ayseId, DemoData.zeynepId, DemoData.meId] {
            await backend.setCurrentUser(reporter)
            try await backend.report(ReportDraft(target: .post, targetId: postId, reason: .spam))
        }
        let hidden = await backend.rawPost(postId)
        XCTAssertEqual(hidden?.isPendingModeration, true, "3 raporla otomatik gizlenir")
        let queue = try await backend.moderationQueue(closed: false, limit: 50)
        XCTAssertEqual(queue.first { $0.targetId == postId }?.contentState, .pending)

        let outcome = try await backend.decide(target: .post, id: postId, decision: .approve, note: nil)
        XCTAssertEqual(outcome, .done(closedReports: 3))
        let restored = await backend.rawPost(postId)
        XCTAssertEqual(restored?.isPendingModeration, false)
        let detailValue = try await backend.moderationCase(target: .post, id: postId)
        let detail = try XCTUnwrap(detailValue)
        XCTAssertTrue(detail.reports.allSatisfy { $0.status == .dismissed })
        XCTAssertEqual(detail.moderationCase.decision, .approve)
        XCTAssertEqual(detail.moderationCase.contentState, .live)
    }

    func testRemoveSemanticsPerTargetType() async throws {
        let backend = makeBackend()
        let needId = DemoData.id(5, 3)
        let animalId = DemoData.id(4, 6)
        let spotId = DemoData.id(2, 9)
        let meetupId = DemoData.id(8, 2)
        let messageId = DemoData.id(10, 3)
        await backend.setCurrentUser(DemoData.ayseId)
        for (target, id) in [(ReportTarget.need, needId), (.animal, animalId), (.spot, spotId), (.meetup, meetupId)] {
            try await backend.report(ReportDraft(target: target, targetId: id, reason: .inappropriate))
        }
        await backend.setCurrentUser(DemoData.meId)
        for (target, id) in [(ReportTarget.need, needId), (.animal, animalId), (.spot, spotId), (.meetup, meetupId),
                             (.chatMessage, messageId), (.user, DemoData.emreId)] {
            let outcome = try await backend.decide(target: target, id: id, decision: .remove, note: nil)
            XCTAssertEqual(outcome, .done(closedReports: 1), "\(target)")
        }
        let need = try await backend.need(id: needId)
        XCTAssertNil(need, "ihtiyaç silinir")
        let animal = try await backend.animal(id: animalId)
        XCTAssertNil(animal, "hayvan silinir")
        await backend.setCurrentUser(DemoData.emreId)
        let spot = try await backend.spot(id: spotId)
        XCTAssertNil(spot, "nokta herkesten gizlenir")
        let meetup = try await backend.meetup(id: meetupId, near: nil)
        XCTAssertEqual(meetup?.status, .cancelled, "buluşma iptal edilir")
        await backend.setCurrentUser(DemoData.zeynepId)
        _ = try await backend.giveSocialConsent()
        let messages = try await backend.messages(conversationId: DemoData.id(9, 1), before: nil, limit: 50)
        XCTAssertFalse(messages.contains { $0.id == messageId }, "kaldırılan mesaj yazarına da görünmez")
        let emre = try await backend.profile(id: DemoData.emreId)
        XCTAssertNotNil(emre, "kullanıcı raporunda yalnızca raporlar kapanır")
        XCTAssertNil(emre?.suspendedUntil)

        await backend.setCurrentUser(DemoData.meId)
        let closed = try await backend.moderationQueue(closed: true, limit: 50)
        XCTAssertEqual(closed.first { $0.targetId == needId }?.contentState, .removed)
        XCTAssertEqual(closed.first { $0.targetId == DemoData.emreId }?.contentState, .live)
    }

    func testDecideValidation() async throws {
        let backend = makeBackend()
        let long = String(repeating: "n", count: 501)
        let tooLong = try await backend.decide(target: .post, id: DemoData.moderationPostId, decision: .remove, note: long)
        XCTAssertEqual(tooLong, .invalid(reason: "note_too_long"))
        let unknown = try await backend.decide(target: .post, id: UUID(), decision: .remove, note: nil)
        XCTAssertEqual(unknown, .notFound)
        let count = try await backend.openCaseCount()
        XCTAssertEqual(count, 3)
    }

    // MARK: - Uzaklaştırma

    func testSuspensionBlocksWritesButNotReads() async throws {
        let backend = makeBackend()
        let selfOutcome = try await backend.suspend(userId: DemoData.meId, length: .week, note: nil)
        XCTAssertEqual(selfOutcome, .notAllowed, "kendini uzaklaştıramaz")
        let unknown = try await backend.suspend(userId: UUID(), length: .week, note: nil)
        XCTAssertEqual(unknown, .notFound)
        let outcome = try await backend.suspend(userId: DemoData.emreId, length: .week, note: "Taciz")
        let until = now.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(outcome, .suspended(until: until))

        await backend.setCurrentUser(DemoData.emreId)
        let expected = MamaError.suspended(until: until)
        await assertThrows(expected) { try await backend.checkIn(CheckInDraft(spotId: DemoData.id(2, 1), kind: .fed, userCoordinate: .modaKadikoy)) }
        await assertThrows(expected) {
            try await backend.createPost(CommunityPostDraft(kind: .note, body: "Merhaba", coordinate: .modaKadikoy))
        }
        await assertThrows(expected) { try await backend.addComment(postId: DemoData.id(6, 2), body: "Yorum") }
        await assertThrows(expected) { try await backend.togglePaw(postId: DemoData.id(6, 2)) }
        await assertThrows(expected) { try await backend.sendMessage(conversationId: DemoData.id(9, 1), body: "Selam") }
        await assertThrows(expected) { try await backend.joinMeetup(id: DemoData.id(8, 1)) }
        await assertThrows(expected) { try await backend.sendConnectionRequest(to: DemoData.ayseId, note: nil) }
        await assertThrows(expected) { try await backend.startFeedingTour(spotId: DemoData.id(2, 1), durationMinutes: 60) }
        await assertThrows(expected) { try await backend.setFollowing(true, target: .spot, id: DemoData.id(2, 1)) }
        await assertThrows(expected) { try await backend.setGuardian(spotId: DemoData.id(2, 1), schedule: [.monday]) }
        await assertThrows(expected) { try await backend.createAnimal(AnimalDraft(species: .cat, name: "Yeni")) }
        await assertThrows(expected) {
            try await backend.createSpot(SpotDraft(coordinate: .modaKadikoy, type: .food, species: .cat, title: "Yeni"))
        }

        // okumalar ve izin verilen yazmalar açık
        let feed = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 20)
        XCTAssertFalse(feed.isEmpty)
        let spots = try await backend.spots(near: .modaKadikoy, radiusMeters: 1000)
        XCTAssertFalse(spots.isEmpty)
        let conversations = try await backend.conversations()
        XCTAssertFalse(conversations.isEmpty)
        try await backend.block(userId: DemoData.ayseId)
        _ = try await backend.updateProfile(displayName: "Emre", neighborhood: "Moda", avatarURL: nil)
        await assertThrows(expected) { try await backend.updateProfile(displayName: "Emre K.", neighborhood: nil, avatarURL: nil) }
        await assertThrows(expected) {
            try await backend.updateProfile(displayName: "Emre", neighborhood: nil, avatarURL: URL(string: "https://x.test/a.jpg"))
        }
        // güvenlik eylemleri: raporlamak ve isteği reddetmek açık; kabul etmek kapalı
        try await backend.report(ReportDraft(target: .user, targetId: DemoData.ayseId, reason: .harassment))
        try await backend.updatePreferences(.default)
        try await backend.setFollowing(false, target: .spot, id: DemoData.id(2, 1))
        try await backend.setGuardian(spotId: DemoData.id(2, 5), schedule: nil)

        // kendi durumunu görür; başkası göremez
        let own = try await backend.profile(id: DemoData.emreId)
        XCTAssertEqual(own?.suspendedUntil, until)
        await backend.setCurrentUser(DemoData.ayseId)
        let seenByOthers = try await backend.profile(id: DemoData.emreId)
        XCTAssertNil(seenByOthers?.suspendedUntil)

        // sahip geçmişi ve kaldırma
        await backend.setCurrentUser(DemoData.meId)
        let detailValue = try await backend.moderationCase(target: .user, id: DemoData.emreId)
        let detail = try XCTUnwrap(detailValue)
        XCTAssertEqual(detail.owner?.suspensionCount90d, 1)
        XCTAssertEqual(detail.owner?.suspendedUntil, until)
        let lifted = try await backend.unsuspend(userId: DemoData.emreId)
        XCTAssertEqual(lifted, .done(closedReports: 0))
        await backend.setCurrentUser(DemoData.emreId)
        let paw = try await backend.togglePaw(postId: DemoData.id(6, 2))
        XCTAssertNotNil(paw, "uzaklaştırma kalkınca yazabilir")
    }

    func testIndefiniteSuspensionAndModeratorsCannotBeSuspended() async throws {
        let backend = makeBackend()
        await backend.setModerator(true, for: DemoData.ayseId)
        let moderator = try await backend.suspend(userId: DemoData.ayseId, length: .month, note: nil)
        XCTAssertEqual(moderator, .notAllowed)
        let outcome = try await backend.suspend(userId: DemoData.zeynepId, length: .indefinite, note: nil)
        XCTAssertEqual(outcome, .suspended(until: .distantFuture))
        await backend.setCurrentUser(DemoData.zeynepId)
        await assertThrows(MamaError.suspendedIndefinitely) { try await backend.togglePaw(postId: DemoData.id(6, 2)) }
        await backend.setCurrentUser(DemoData.meId)
        let longNote = try await backend.suspend(userId: DemoData.emreId, length: .week, note: String(repeating: "x", count: 501))
        XCTAssertEqual(longNote, .invalid(reason: "note_too_long"))
    }

    func testSuspensionExpires() async throws {
        let clock = Clock(now)
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { clock.now })
        _ = try await backend.suspend(userId: DemoData.emreId, length: .week, note: nil)
        await backend.setCurrentUser(DemoData.emreId)
        await assertThrows(MamaError.suspended(until: now.addingTimeInterval(7 * 86_400))) {
            try await backend.togglePaw(postId: DemoData.id(6, 2))
        }
        clock.advance(7 * 86_400 + 1)
        let paw = try await backend.togglePaw(postId: DemoData.id(6, 2))
        XCTAssertNotNil(paw)
        let own = try await backend.profile(id: DemoData.emreId)
        XCTAssertNil(own?.suspendedUntil, "süresi dolan uzaklaştırma görünmez")
    }

    // MARK: - Mesaj

    func testSuspendedMessageIsWarmAndDated() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 15))!
        XCTAssertEqual(MamaFormat.day(date, language: .turkish), "24 Kasım 2026")
        XCTAssertEqual(MamaFormat.day(date, language: .english), "November 24, 2026")
        let dated = MamaError.suspended(until: date).userMessage
        XCTAssertTrue(dated.hasPrefix("Hesabın"), dated)
        XCTAssertTrue(dated.contains("tarihine kadar askıya alındı"), dated)
        let indefinite = MamaError.suspendedIndefinitely.userMessage
        XCTAssertTrue(indefinite.contains("süresiz"), indefinite)
        XCTAssertEqual(MamaError.suspension(until: .distantFuture), .suspendedIndefinitely)
        let unknown = MamaError.suspended(until: nil).userMessage
        XCTAssertFalse(unknown.contains("süresiz"), "bitiş bilinmiyorsa süresiz denmez")
        XCTAssertTrue(unknown.contains("askıya alındı"), unknown)
        XCTAssertEqual(MamaError.suspension(until: date), .suspended(until: date))
        XCTAssertFalse(MamaError.suspended(until: nil).isConnectivity, "çevrimdışı kuyruğa alınmaz")
    }

    func testSuspendedUserCanDeclineAndHideButNotAcceptOrEdit() async throws {
        let backend = makeBackend()
        // seed: Zeynep → Sen bekleyen istek; ikinci istek Emre'den
        _ = try await backend.giveSocialConsent()
        let profile = try await backend.updateSocialProfile(isVisible: true, about: "Merhaba", interests: [.cats], at: .modaKadikoy)
        XCTAssertEqual(profile, .saved)
        await backend.setCurrentUser(DemoData.emreId)
        _ = try await backend.giveSocialConsent()
        _ = try await backend.sendConnectionRequest(to: DemoData.meId, note: nil)
        await backend.setCurrentUser(DemoData.meId)
        let requests = try await backend.incomingConnectionRequests()
        XCTAssertEqual(requests.count, 2)
        await backend.setModerator(false, for: DemoData.meId)
        await backend.setSuspendedUntil(now.addingTimeInterval(86_400), for: DemoData.meId)
        let expected = MamaError.suspended(until: now.addingTimeInterval(86_400))

        let declined = try await backend.respondToConnection(requestId: requests[0].id, accept: false)
        XCTAssertNil(declined)
        await assertThrows(expected) { try await backend.respondToConnection(requestId: requests[1].id, accept: true) }
        await assertThrows(expected) {
            try await backend.updateSocialProfile(isVisible: true, about: "Merhaba", interests: [.cats], at: nil)
        }
        await assertThrows(expected) {
            try await backend.updateSocialProfile(isVisible: false, about: "Yeni metin", interests: [.cats], at: nil)
        }
        let hidden = try await backend.updateSocialProfile(isVisible: false, about: "Merhaba", interests: [.cats], at: nil)
        XCTAssertEqual(hidden, .saved)
        let social = try await backend.socialProfile()
        XCTAssertEqual(social?.isVisible, false)
        XCTAssertEqual(social?.about, "Merhaba")
    }

    func testRemovedMeetupNeedAnimalCannotBeApproved() async throws {
        let backend = makeBackend()
        let needId = DemoData.id(5, 3)
        await backend.setCurrentUser(DemoData.ayseId)
        try await backend.report(ReportDraft(target: .need, targetId: needId, reason: .spam))
        await backend.setCurrentUser(DemoData.meId)
        let before = try await backend.moderationCase(target: .need, id: needId)
        XCTAssertEqual(before?.moderationCase.isRestorable, true)
        _ = try await backend.decide(target: .need, id: needId, decision: .remove, note: nil)
        let approve = try await backend.decide(target: .need, id: needId, decision: .approve, note: nil)
        XCTAssertEqual(approve, .invalid(reason: "not_restorable"))
        let after = try await backend.moderationCase(target: .need, id: needId)
        XCTAssertEqual(after?.moderationCase.isRestorable, false)
        XCTAssertEqual(after?.moderationCase.contentState, .removed)
        // post kaldırması geri alınabilir
        let post = try await backend.moderationCase(target: .post, id: DemoData.moderationPostId)
        XCTAssertEqual(post?.moderationCase.isRestorable, true)
        XCTAssertEqual(post?.owner?.avatarURL, nil)
    }

    func testSuspensionLengthDays() {
        XCTAssertEqual(SuspensionLength.week.days, 7)
        XCTAssertEqual(SuspensionLength.month.days, 30)
        XCTAssertNil(SuspensionLength.indefinite.days)
    }

    // MARK: - Yardımcılar

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(_ start: Date) { current = start }
        var now: Date { lock.lock(); defer { lock.unlock() }; return current }
        func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
    }

    func assertThrows<T>(_ expected: MamaError, file: StaticString = #filePath, line: UInt = #line,
                         _ work: () async throws -> T) async {
        do {
            _ = try await work()
            XCTFail("\(expected) bekleniyordu", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? MamaError, expected, file: file, line: line)
        }
    }
}
