import XCTest
import MamaCore
import FeatureSocial

@MainActor
final class SocialConsentAndMeetupTests: XCTestCase {
    func testConsentNeedsBothBoxes() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = SocialConsentViewModel(services: env.services)
        XCTAssertFalse(model.canSubmit)
        model.adultConfirmed = true
        XCTAssertFalse(model.canSubmit)
        let early = await model.submit()
        XCTAssertFalse(early)
        model.termsAccepted = true
        XCTAssertTrue(model.canSubmit)
        let done = await model.submit()
        XCTAssertTrue(done)
        let profile = try await env.backend.socialProfile()
        XCTAssertEqual(profile?.hasConsented, true)
    }

    func testMeetupsNeedConsentButStillList() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = MeetupsViewModel(services: env.services)
        await model.load(near: .modaKadikoy)
        XCTAssertTrue(model.needsConsent)
        XCTAssertFalse(model.meetups.isEmpty)
        _ = try await env.backend.giveSocialConsent()
        await model.load(near: .modaKadikoy)
        XCTAssertFalse(model.needsConsent)
    }

    func testShortTitleIsRejectedLocallyWithoutBackendCall() async throws {
        let env = try await makeSocialEnvironment()
        let model = CreateMeetupViewModel(services: env.services)
        model.title = "Ab"
        model.placeName = "Moda Parkı"
        XCTAssertEqual(model.validationIssue, SocialMessages.message(for: .titleLength))
        let before = try await env.backend.meetups(near: .modaKadikoy, radiusMeters: 10_000).count
        let outcome = await model.submit()
        XCTAssertNil(outcome)
        let after = try await env.backend.meetups(near: .modaKadikoy, radiusMeters: 10_000).count
        XCTAssertEqual(before, after)
    }

    func testMeetupPointNearDeviceAsksForConfirmation() async throws {
        let env = try await makeSocialEnvironment()
        let model = CreateMeetupViewModel(services: env.services, coordinate: .modaKadikoy)
        XCTAssertTrue(model.isNearDevice(.modaKadikoy))
        XCTAssertTrue(model.isNearDevice(GeoMath.offset(.modaKadikoy, north: 40, east: 0)))
        XCTAssertFalse(model.isNearDevice(GeoMath.offset(.modaKadikoy, north: 80, east: 0)))
        XCTAssertFalse(model.isNearDevice(nil))
    }

    func testValidMeetupIsCreated() async throws {
        let env = try await makeSocialEnvironment()
        let model = CreateMeetupViewModel(services: env.services)
        model.title = "Pazar mama turu"
        model.placeName = "Moda Parkı"
        model.capacityEnabled = true
        model.capacity = 6
        XCTAssertNil(model.validationIssue)
        let outcome = await model.submit()
        guard case .created(let meetupId, _) = outcome else { return XCTFail("created bekleniyordu: \(String(describing: outcome))") }
        let created = try await env.backend.meetup(id: meetupId, near: nil)
        XCTAssertEqual(created?.capacity, 6)
    }

    func testJoiningFullMeetupShowsMessage() async throws {
        let full = DemoData.id(8, 2)
        let env = try await makeSocialEnvironment { seed in
            guard let index = seed.meetups.firstIndex(where: { $0.meetup.id == full }) else { return }
            seed.meetups[index].meetup.capacity = 1
        }
        let model = MeetupDetailViewModel(services: env.services, meetupId: full)
        await model.load(near: .modaKadikoy)
        XCTAssertTrue(model.isFull)
        let outcome = await model.join()
        XCTAssertEqual(outcome, .full)
        XCTAssertEqual(model.message, "Bu buluşma doldu.")
        XCTAssertFalse(model.canChat)
    }

    func testJoinOpenMeetupOpensChatAndLeaveWorks() async throws {
        let open = DemoData.id(8, 2)
        let env = try await makeSocialEnvironment()
        let model = MeetupDetailViewModel(services: env.services, meetupId: open)
        await model.load(near: .modaKadikoy)
        XCTAssertFalse(model.canChat)
        let outcome = await model.join()
        guard case .joined = outcome else { return XCTFail("joined bekleniyordu") }
        XCTAssertTrue(model.canChat)
        XCTAssertNil(model.message)
        XCTAssertTrue(model.participants.contains { $0.id == DemoData.meId })
        let left = await model.leave()
        XCTAssertTrue(left)
        XCTAssertFalse(model.canChat)
    }

    func testFailureMessagesAreWarmTurkish() {
        XCTAssertEqual(SocialMessages.message(for: JoinMeetupOutcome.consentRequired), "Önce sosyal onayı vermelisin.")
        XCTAssertNil(SocialMessages.message(for: JoinMeetupOutcome.joined(conversationId: UUID())))
        XCTAssertNotNil(SocialMessages.message(for: SendRequestOutcome.cooldown))
        XCTAssertNotNil(SocialMessages.message(for: SocialProfileOutcome.locationRequired))
        XCTAssertNotNil(SocialMessages.message(for: SendMessageOutcome.rateLimited))
    }
}

@MainActor
final class SocialLoversTests: XCTestCase {
    func testInvisibleUserSeesNoLoversAndProfileSaysSo() async throws {
        let env = try await makeSocialEnvironment()
        let model = AnimalLoversViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertTrue(model.lovers.isEmpty)
        XCTAssertEqual(model.profile?.isVisible, false)
        XCTAssertFalse(model.isVisible)
    }

    func testVisibleUserSeesLoversAndLocationRefreshMovesBands() async throws {
        let env = try await makeSocialEnvironment()
        let edit = SocialProfileEditViewModel(services: env.services)
        await edit.load()
        edit.isVisible = true
        edit.about = "Moda'da kedilere bakıyorum."
        edit.toggle(.cats)
        let saved = await edit.save(at: .modaKadikoy)
        XCTAssertEqual(saved, .saved)

        let model = AnimalLoversViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertFalse(model.lovers.isEmpty)
        let before = model.lovers.first { $0.id == DemoData.ayseId }?.distanceBand
        XCTAssertEqual(before, .under1km)

        // ~2 km kuzeye taşındı: hücre değişir, konum tazelenir, bantlar yeniden hesaplanır.
        let moved = GeoMath.offset(.modaKadikoy, north: 2000, east: 0)
        await model.load(at: moved)
        XCTAssertEqual(model.lovers.first { $0.id == DemoData.emreId }?.distanceBand, .under1km)

        await model.setInterestFilter(.birds)
        XCTAssertEqual(model.interestFilter, .birds)
        XCTAssertTrue(model.lovers.allSatisfy { $0.interests.contains(.birds) })
    }

    func testDemoRequestIsAcceptedAfterDelayWithOneReload() async throws {
        let env = try await makeSocialEnvironment()
        let edit = SocialProfileEditViewModel(services: env.services)
        await edit.load()
        edit.isVisible = true
        _ = await edit.save(at: .modaKadikoy)

        let clock = env.clock
        let slept = SleepRecorder()
        let model = AnimalLoversViewModel(services: env.services, sleep: { seconds in
            await slept.record(seconds)
            clock.advance(seconds)
        })
        await model.load(at: .modaKadikoy)
        let outcome = await model.sendRequest(to: DemoData.ayseId, note: "Merhaba!")
        guard case .sent = outcome else { return XCTFail("sent bekleniyordu") }
        let seconds = await slept.values
        XCTAssertEqual(seconds, [InMemoryBackend.demoResponseDelay])
        guard case .connected = model.lovers.first(where: { $0.id == DemoData.ayseId })?.connection else {
            return XCTFail("Senaryolu kullanıcı isteği kabul etmiş görünmeli")
        }
    }

    func testPendingRequestCanBeWithdrawn() async throws {
        let env = try await makeSocialEnvironment()
        let edit = SocialProfileEditViewModel(services: env.services)
        await edit.load()
        edit.isVisible = true
        _ = await edit.save(at: .modaKadikoy)
        // Saat ilerlemez: senaryolu kabul gelmeden istek beklemede kalır.
        let model = AnimalLoversViewModel(services: env.services, sleep: { _ in })
        await model.load(at: .modaKadikoy)
        guard case .sent = await model.sendRequest(to: DemoData.ayseId, note: nil) else { return XCTFail("sent bekleniyordu") }
        guard case .outgoingPending(let requestId) = model.lovers.first(where: { $0.id == DemoData.ayseId })?.connection else {
            return XCTFail("beklemede görünmeli")
        }
        let withdrawn = await model.withdraw(requestId: requestId)
        XCTAssertTrue(withdrawn)
        XCTAssertEqual(model.lovers.first { $0.id == DemoData.ayseId }?.connection, ConnectionState.none)
        XCTAssertNil(model.error)
    }

    func testIncomingRequestCanBeAccepted() async throws {
        let env = try await makeSocialEnvironment()
        let edit = SocialProfileEditViewModel(services: env.services)
        await edit.load()
        edit.isVisible = true
        _ = await edit.save(at: .modaKadikoy)
        let model = AnimalLoversViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertEqual(model.incoming.count, 1)
        let conversationId = await model.respond(model.incoming[0], accept: true)
        XCTAssertNotNil(conversationId)
        XCTAssertTrue(model.incoming.isEmpty)
    }

    func testNotVisibleSenderGetsMessage() async throws {
        let env = try await makeSocialEnvironment()
        let model = AnimalLoversViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let outcome = await model.sendRequest(to: DemoData.ayseId)
        XCTAssertEqual(outcome, .notVisible)
        XCTAssertEqual(model.message, SocialMessages.message(for: SendRequestOutcome.notVisible))
    }

    func testProfileEditWithoutLocationReportsRequirement() async throws {
        let env = try await makeSocialEnvironment()
        let edit = SocialProfileEditViewModel(services: env.services)
        await edit.load()
        edit.isVisible = true
        let outcome = await edit.save(at: nil)
        XCTAssertEqual(outcome, .locationRequired)
        XCTAssertNotNil(edit.message)
    }
}

private actor SleepRecorder {
    private(set) var values: [TimeInterval] = []
    func record(_ value: TimeInterval) { values.append(value) }
}

@MainActor
final class SocialChatTests: XCTestCase {
    /// Demo kullanıcısı görünür; Ayşe'ye istek atıp kabulünü bekler, bire bir sohbetin kimliğini döndürür.
    private func directConversation(_ env: SocialEnvironment) async throws -> UUID {
        _ = try await env.backend.updateSocialProfile(isVisible: true, about: "", interests: [], at: .modaKadikoy)
        guard case .sent = try await env.backend.sendConnectionRequest(to: DemoData.ayseId, note: nil) else {
            throw XCTSkip("istek gönderilemedi")
        }
        env.clock.advance(InMemoryBackend.demoResponseDelay)
        let list = try await env.backend.conversations()
        return try XCTUnwrap(list.first { $0.kind == .direct }?.id)
    }

    func testConversationsListAndUnread() async throws {
        let env = try await makeSocialEnvironment()
        let model = ConversationsViewModel(services: env.services)
        await model.load()
        XCTAssertTrue(model.isEmpty)
        _ = try await env.backend.joinMeetup(id: DemoData.id(8, 1))
        await model.load()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertEqual(model.totalUnread, 0) // katılmadan önceki mesajlar okunmamış sayılmaz
    }

    func testSendAppendsMessageAndScriptedReplyAppearsOnRefresh() async throws {
        let env = try await makeSocialEnvironment()
        let conversationId = try await directConversation(env)
        let model = ChatViewModel(services: env.services, conversationId: conversationId)
        await model.start()
        defer { model.stop() }
        XCTAssertFalse(model.isReadOnly)
        // Başlık menüsü (engelle / bağlantıyı kaldır) için sohbet özeti.
        XCTAssertEqual(model.summary?.kind, .direct)
        XCTAssertEqual(model.summary?.otherUserId, DemoData.ayseId)
        model.draft = "Merhaba!"
        await model.send()
        XCTAssertEqual(model.messages.map(\.body), ["Merhaba!"])
        XCTAssertEqual(model.draft, "")

        env.clock.advance(InMemoryBackend.demoResponseDelay)
        await model.start()
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages.last?.authorId, DemoData.ayseId)
    }

    func testRestartDropsMessagesOfBlockedMember() async throws {
        let env = try await makeSocialEnvironment()
        _ = try await env.backend.joinMeetup(id: DemoData.id(8, 1))
        let model = ChatViewModel(services: env.services, conversationId: DemoData.id(9, 1))
        await model.start()
        defer { model.stop() }
        XCTAssertTrue(model.messages.contains { $0.authorId == DemoData.emreId })
        try await env.services.moderation.block(userId: DemoData.emreId)
        await model.restart()
        XCTAssertFalse(model.messages.isEmpty)
        XCTAssertFalse(model.messages.contains { $0.authorId == DemoData.emreId })
    }

    func testLiveSignalRefreshesMessages() async throws {
        let env = try await makeSocialEnvironment()
        await env.backend.setReplySignalDelay(.milliseconds(50))
        let conversationId = try await directConversation(env)
        let model = ChatViewModel(services: env.services, conversationId: conversationId)
        await model.start()
        defer { model.stop() }
        model.draft = "Selam"
        await model.send()
        env.clock.advance(InMemoryBackend.demoResponseDelay)
        for _ in 0..<100 where model.messages.count < 2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.messages.count, 2)
    }

    /// Açık sohbet, karşı taraf engelleyince bir sonraki yenilemede gizlenir: mesajlar temizlenir, gönderilemez.
    func testOpenChatNoticesBlockOnRefresh() async throws {
        let env = try await makeSocialEnvironment()
        let conversationId = try await directConversation(env)
        let model = ChatViewModel(services: env.services, conversationId: conversationId)
        await model.start()
        defer { model.stop() }
        model.draft = "Merhaba!"
        await model.send()
        XCTAssertFalse(model.isHidden)
        XCTAssertEqual(model.messages.count, 1)

        await env.backend.setCurrentUser(DemoData.ayseId)
        try await env.backend.block(userId: DemoData.meId)
        await env.backend.setCurrentUser(DemoData.meId)
        await model.refresh()
        XCTAssertTrue(model.isHidden)
        XCTAssertTrue(model.isReadOnly)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNil(model.summary, "başlık menüsü (engelle / kaldır) artık gösterilmez")
        model.draft = "Orada mısın?"
        XCTAssertFalse(model.canSend)
    }

    /// Buluşma iptal edilince açık grup sohbeti bir sonraki yenilemede salt okunur olur (gizlenmez).
    func testOpenMeetupChatBecomesReadOnlyWhenCancelled() async throws {
        let env = try await makeSocialEnvironment()
        guard case .joined(let conversationId) = try await env.backend.joinMeetup(id: DemoData.id(8, 1)) else { return XCTFail() }
        let model = ChatViewModel(services: env.services, conversationId: conversationId)
        await model.start()
        defer { model.stop() }
        XCTAssertFalse(model.isReadOnly)

        await env.backend.setCurrentUser(DemoData.ayseId)
        _ = try await env.backend.cancelMeetup(id: DemoData.id(8, 1))
        await env.backend.setCurrentUser(DemoData.meId)
        await model.refresh()
        XCTAssertTrue(model.isReadOnly)
        XCTAssertFalse(model.isHidden)
        XCTAssertFalse(model.messages.isEmpty)
    }

    /// Karşı taraf hesabını silerse sunucu başlığı ('Silinmiş kullanıcı') yerine yerelleştirilmiş metin gösterilir.
    func testDeletedUserTitleIsLocalized() async throws {
        let deleted = ConversationSummary(id: UUID(), kind: .direct, title: "Silinmiş kullanıcı", otherUserId: nil, isReadOnly: true)
        XCTAssertEqual(deleted.displayTitle, String(localized: "Silinmiş kullanıcı"))
        let named = ConversationSummary(id: UUID(), kind: .direct, title: "Ayşe", otherUserId: DemoData.ayseId)
        XCTAssertEqual(named.displayTitle, "Ayşe")
        let group = ConversationSummary(id: UUID(), kind: .meetup, title: "Moda Parkı mama turu")
        XCTAssertEqual(group.displayTitle, "Moda Parkı mama turu")

        let env = try await makeSocialEnvironment()
        let conversationId = try await directConversation(env)
        await env.backend.setCurrentUser(DemoData.ayseId)
        try await env.backend.deleteAccount()
        await env.backend.setCurrentUser(DemoData.meId)
        let model = ChatViewModel(services: env.services, conversationId: conversationId)
        await model.start()
        defer { model.stop() }
        XCTAssertEqual(model.title, String(localized: "Silinmiş kullanıcı"))
        XCTAssertTrue(model.isReadOnly)
        XCTAssertFalse(model.isHidden)
    }

    func testReadOnlyConversationNeverSends() async throws {
        let env = try await makeSocialEnvironment()
        let draft = MeetupDraft(title: "Kısa buluşma", startsAt: env.clock.now.addingTimeInterval(7200), durationMinutes: 60,
                                placeName: "Moda Parkı", coordinate: .modaKadikoy)
        guard case .created(_, let conversationId) = try await env.backend.createMeetup(draft) else {
            return XCTFail("buluşma oluşmalı")
        }
        // Bitişten (başlangıç + 1 saat) 24 saatten fazla sonra salt okunur.
        env.clock.advance(7200 + 3600 + 86_400 + 60)
        let model = ChatViewModel(services: env.services, conversationId: conversationId)
        await model.start()
        defer { model.stop() }
        XCTAssertTrue(model.isReadOnly)
        model.draft = "Merhaba"
        XCTAssertFalse(model.canSend)
        await model.send()
        XCTAssertEqual(model.draft, "Merhaba")
        XCTAssertTrue(model.messages.isEmpty)
    }
}

final class MeetupFormatTests: XCTestCase {
    private func istanbul(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func meetup(at date: Date) -> Meetup {
        Meetup(title: "x", startsAt: date, endsAt: date.addingTimeInterval(7200), placeName: "y",
               coordinate: .modaKadikoy, organizerId: UUID(), organizerName: "z")
    }

    func testTodayTomorrowAndLaterFormats() {
        let now = istanbul(2026, 11, 14, 9)
        XCTAssertEqual(MeetupFormat.when(meetup(at: istanbul(2026, 11, 14, 10)), now: now), "Bugün 10:00")
        XCTAssertEqual(MeetupFormat.when(meetup(at: istanbul(2026, 11, 15, 18, 30)), now: now), "Yarın 18:30")
        XCTAssertEqual(MeetupFormat.when(meetup(at: istanbul(2026, 11, 21, 10)), now: now), "Cmt 21 Kas 10:00")
    }

    /// Review Focus 4: işlem saat dilimi İstanbul dışında olsa da İstanbul saati yazılır.
    func testFormatIgnoresProcessTimeZone() {
        let oldTZ = getenv("TZ").map { String(cString: $0) }
        let oldDefault = NSTimeZone.default
        setenv("TZ", "America/New_York", 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        defer {
            if let oldTZ { setenv("TZ", oldTZ, 1) } else { unsetenv("TZ") }
            tzset()
            NSTimeZone.resetSystemTimeZone()
            NSTimeZone.default = oldDefault
        }
        XCTAssertEqual(TimeZone.current.identifier, "America/New_York")
        let now = istanbul(2026, 11, 14, 9)
        XCTAssertEqual(MeetupFormat.when(meetup(at: istanbul(2026, 11, 14, 10)), now: now), "Bugün 10:00")
        XCTAssertEqual(MeetupFormat.when(meetup(at: istanbul(2026, 11, 21, 10)), now: now), "Cmt 21 Kas 10:00")
        XCTAssertEqual(MeetupFormat.when(meetup(at: istanbul(2026, 11, 15, 0, 30)), now: now), "Yarın 00:30")
    }

    func testBandLabels() {
        XCTAssertEqual(MeetupFormat.bandLabel(.under1km), "1 km'den yakın")
        XCTAssertEqual(MeetupFormat.bandLabel(.from1to3km), "1–3 km")
        XCTAssertEqual(MeetupFormat.bandLabel(.from3to10km), "3–10 km")
    }
}
