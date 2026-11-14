import XCTest
@testable import MamaCore

/// Sunucu kurallarının (supabase/tests/91–95) `InMemoryBackend` aynası.
final class SocialBackendTests: XCTestCase {
    /// Elle ilerletilen saat: senaryolu demo davranışı (`demoResponseDelay`) zamana bağlı.
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
    }

    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var clock: TestClock!
    var backend: InMemoryBackend!

    override func setUp() {
        super.setUp()
        let clock = TestClock(start)
        self.clock = clock
        backend = InMemoryBackend(seed: DemoData.make(now: start), signedIn: true, now: { clock.now })
    }

    let me = DemoData.meId

    func consentAndShow(at coordinate: Coordinate = .modaKadikoy) async throws {
        _ = try await backend.giveSocialConsent()
        let outcome = try await backend.updateSocialProfile(isVisible: true, about: "Moda'da besliyorum", interests: [.cats], at: coordinate)
        XCTAssertEqual(outcome, .saved)
    }

    func draft(
        title: String = "Moda Parkı mama turu",
        description: String = "",
        startsIn: TimeInterval = 2 * 3600,
        duration: Int = 120,
        place: String = "Moda Parkı girişi",
        spotId: UUID? = nil,
        capacity: Int? = nil
    ) -> MeetupDraft {
        MeetupDraft(title: title, description: description, startsAt: start.addingTimeInterval(startsIn), durationMinutes: duration,
                    placeName: place, coordinate: .modaKadikoy, spotId: spotId, capacity: capacity)
    }

    // MARK: - SocialPolicy

    func testNearDeviceThreshold() {
        let home = Coordinate.modaKadikoy
        XCTAssertEqual(SocialPolicy.nearDeviceMeters, 50)
        XCTAssertTrue(SocialPolicy.isNearDevice(point: home, device: home))
        XCTAssertTrue(SocialPolicy.isNearDevice(point: GeoMath.offset(home, north: 49, east: 0), device: home))
        XCTAssertFalse(SocialPolicy.isNearDevice(point: GeoMath.offset(home, north: 51, east: 0), device: home))
    }

    func testDistanceBands() {
        XCTAssertEqual(SocialPolicy.band(meters: 0), .under1km)
        XCTAssertEqual(SocialPolicy.band(meters: 999), .under1km)
        XCTAssertEqual(SocialPolicy.band(meters: 1000), .from1to3km)
        XCTAssertEqual(SocialPolicy.band(meters: 2999), .from1to3km)
        XCTAssertEqual(SocialPolicy.band(meters: 3000), .from3to10km)
        XCTAssertEqual(SocialPolicy.band(meters: 10_000), .from3to10km)
        XCTAssertNil(SocialPolicy.band(meters: 10_001))
    }

    func testRoundedCell() {
        XCTAssertEqual(SocialPolicy.roundedCell(Coordinate(latitude: 40.98765, longitude: 29.02512)),
                       Coordinate(latitude: 40.99, longitude: 29.03))
    }

    func testNotificationPreferencesDecodeWithoutSocialUpdates() throws {
        let legacy = try JSONEncoder().encode(NotificationPreferences(communityUpdates: false))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        object["socialUpdates"] = nil
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.socialUpdates)
        XCTAssertFalse(decoded.communityUpdates)
    }

    // MARK: - Onay

    func testWritesRequireConsent() async throws {
        let profile = try await backend.socialProfile()
        XCTAssertNil(profile)
        let create = try await backend.createMeetup(draft())
        XCTAssertEqual(create, .consentRequired)
        let join = try await backend.joinMeetup(id: DemoData.id(8, 1))
        XCTAssertEqual(join, .consentRequired)
        let request = try await backend.sendConnectionRequest(to: DemoData.ayseId, note: nil)
        XCTAssertEqual(request, .consentRequired)
        let update = try await backend.updateSocialProfile(isVisible: true, about: "", interests: [], at: .modaKadikoy)
        XCTAssertEqual(update, .consentRequired)
        let lovers = try await backend.animalLovers(interest: nil)
        XCTAssertTrue(lovers.isEmpty)
        let incoming = try await backend.incomingConnectionRequests()
        XCTAssertTrue(incoming.isEmpty, "onay yoksa okuma boş")
        // Buluşma listesi onay istemez.
        let meetups = try await backend.meetups(near: .modaKadikoy, radiusMeters: 10_000)
        XCTAssertEqual(meetups.count, 2)
        XCTAssertEqual(meetups.first { $0.id == DemoData.id(8, 1) }?.participantCount, 3)

        let consented = try await backend.giveSocialConsent()
        XCTAssertTrue(consented.hasConsented)
        XCTAssertFalse(consented.isVisible)
        let located = try await backend.updateSocialProfile(isVisible: true, about: "", interests: [], at: nil)
        XCTAssertEqual(located, .locationRequired)
        let long = try await backend.updateSocialProfile(isVisible: false, about: String(repeating: "a", count: SocialPolicy.maxAbout + 1), interests: [], at: nil)
        XCTAssertEqual(long, .aboutTooLong)
    }

    // MARK: - Buluşma doğrulaması

    func testCreateMeetupValidationBoundaries() async throws {
        _ = try await backend.giveSocialConsent()
        let cases: [(MeetupDraft, MeetupInvalidReason)] = [
            (draft(title: "ab"), .titleLength),
            (draft(title: String(repeating: "a", count: 81)), .titleLength),
            (draft(description: String(repeating: "a", count: 601)), .descriptionTooLong),
            (draft(place: "  "), .placeNameLength),
            (draft(place: String(repeating: "a", count: 81)), .placeNameLength),
            (draft(startsIn: 3599), .startTooSoon),
            (draft(startsIn: 60 * 86_400 + 1), .startTooLate),
            (draft(duration: 29), .durationRange),
            (draft(duration: 481), .durationRange),
            (draft(capacity: 1), .capacityRange),
            (draft(capacity: 51), .capacityRange),
            (draft(spotId: UUID()), .spotNotFound),
        ]
        for (input, reason) in cases {
            let outcome = try await backend.createMeetup(input)
            XCTAssertEqual(outcome, .invalid(reason), "\(reason)")
            XCTAssertEqual(SocialPolicy.validate(input, now: start), reason == .spotNotFound ? nil : reason)
        }

        // Sınır değerleri geçerli; günde en fazla 3.
        for valid in [draft(startsIn: 3600, duration: 30, capacity: 2),
                      draft(startsIn: 60 * 86_400, duration: 480, capacity: 50),
                      draft(spotId: DemoData.id(2, 1))] {
            guard case .created = try await backend.createMeetup(valid) else { return XCTFail("\(valid)") }
        }
        let fourth = try await backend.createMeetup(draft())
        XCTAssertEqual(fourth, .limitReached(SocialPolicy.dailyMeetups))
    }

    // MARK: - Katılım

    func testJoinCapacityRemovedCancelledEnded() async throws {
        _ = try await backend.giveSocialConsent()
        guard case .created(let meetupId, let conversationId) = try await backend.createMeetup(draft(capacity: 2)) else {
            return XCTFail("oluşturulamadı")
        }
        let mine = try await backend.meetup(id: meetupId, near: nil)
        XCTAssertEqual(mine?.viewerRole, .organizer)
        XCTAssertEqual(mine?.participantCount, 1)
        let leave = try await backend.leaveMeetup(id: meetupId)
        XCTAssertFalse(leave, "düzenleyen ayrılamaz")

        await backend.setCurrentUser(DemoData.ayseId)
        let joined = try await backend.joinMeetup(id: meetupId)
        XCTAssertEqual(joined, .joined(conversationId: conversationId))
        let again = try await backend.joinMeetup(id: meetupId)
        XCTAssertEqual(again, .joined(conversationId: conversationId), "idempotent")

        await backend.setCurrentUser(DemoData.emreId)
        let full = try await backend.joinMeetup(id: meetupId)
        XCTAssertEqual(full, .full)
        let hidden = try await backend.meetupParticipants(meetupId: meetupId)
        XCTAssertTrue(hidden.isEmpty, "katılımcı listesi yalnızca katılanlara")

        await backend.setCurrentUser(me)
        let participants = try await backend.meetupParticipants(meetupId: meetupId)
        XCTAssertEqual(participants.map(\.id), [me, DemoData.ayseId])
        XCTAssertEqual(participants.first?.isOrganizer, true)
        let removed = try await backend.removeParticipant(meetupId: meetupId, userId: DemoData.ayseId)
        XCTAssertTrue(removed)

        await backend.setCurrentUser(DemoData.ayseId)
        let rejoin = try await backend.joinMeetup(id: meetupId)
        XCTAssertEqual(rejoin, .removed)
        let removedView = try await backend.meetup(id: meetupId, near: nil)
        XCTAssertEqual(removedView?.viewerRole, .removed)
        XCTAssertNil(removedView?.conversationId)
        let ayseConversations = try await backend.conversations()
        XCTAssertFalse(ayseConversations.contains { $0.id == conversationId }, "çıkarılan sohbetten düşer")

        await backend.setCurrentUser(me)
        let cancelled = try await backend.cancelMeetup(id: meetupId)
        XCTAssertTrue(cancelled)
        let chat = try await backend.conversations().first { $0.id == conversationId }
        XCTAssertEqual(chat?.isReadOnly, true)
        let send = try await backend.sendMessage(conversationId: conversationId, body: "Merhaba")
        XCTAssertEqual(send, .readOnly)

        await backend.setCurrentUser(DemoData.zeynepId)
        let joinCancelled = try await backend.joinMeetup(id: meetupId)
        XCTAssertEqual(joinCancelled, .cancelled)
        let nearby = try await backend.meetups(near: .modaKadikoy, radiusMeters: 10_000)
        XCTAssertFalse(nearby.contains { $0.id == meetupId }, "iptal listede yok")

        // Seed buluşması bitince: katılım `ended`, sohbet 24 saat sonra salt okunur.
        let seeded = try await backend.meetup(id: DemoData.id(8, 1), near: nil)
        let ends = try XCTUnwrap(seeded?.endsAt)
        clock.advance(ends.timeIntervalSince(clock.now) + 1)
        let ended = try await backend.joinMeetup(id: DemoData.id(8, 1))
        XCTAssertEqual(ended, .ended)
        let seededChat = try XCTUnwrap(seeded?.conversationId, "Zeynep seed buluşmasına katılmış")
        var summary = try await backend.conversations().first { $0.id == seededChat }
        XCTAssertEqual(summary?.isReadOnly, false)
        clock.advance(SocialPolicy.readOnlyAfterEnd)
        summary = try await backend.conversations().first { $0.id == seededChat }
        XCTAssertEqual(summary?.isReadOnly, true)
    }

    // MARK: - Hayvanseverler

    func testBandsFromViewerCellAndScriptedAcceptance() async throws {
        try await consentAndShow()
        let lovers = try await backend.animalLovers(interest: nil)
        XCTAssertEqual(lovers.map(\.id), [DemoData.ayseId, DemoData.emreId, DemoData.zeynepId])
        XCTAssertEqual(lovers.map(\.distanceBand), [.under1km, .from1to3km, .from3to10km])
        XCTAssertEqual(lovers.first?.sharedInterestCount, 1)
        let cats = try await backend.animalLovers(interest: .dogs)
        XCTAssertTrue(cats.allSatisfy { $0.interests.contains(.dogs) })

        guard case .sent(let requestId) = try await backend.sendConnectionRequest(to: DemoData.ayseId, note: "Moda Parkı'nda beraber besleyelim mi?") else {
            return XCTFail("gönderilemedi")
        }
        let duplicate = try await backend.sendConnectionRequest(to: DemoData.ayseId, note: nil)
        XCTAssertEqual(duplicate, .alreadyPending)
        var ayse = try await backend.animalLovers(interest: nil).first { $0.id == DemoData.ayseId }
        XCTAssertEqual(ayse?.connection, .outgoingPending(requestId: requestId))

        clock.advance(InMemoryBackend.demoResponseDelay - 0.5)
        ayse = try await backend.animalLovers(interest: nil).first { $0.id == DemoData.ayseId }
        XCTAssertEqual(ayse?.connection, .outgoingPending(requestId: requestId))

        clock.advance(0.5)
        ayse = try await backend.animalLovers(interest: nil).first { $0.id == DemoData.ayseId }
        guard case .connected(let conversationId) = ayse?.connection else { return XCTFail("kabul edilmedi") }
        let chats = try await backend.conversations()
        let direct = try XCTUnwrap(chats.first { $0.id == conversationId })
        XCTAssertEqual(direct.kind, .direct)
        XCTAssertEqual(direct.title, "Ayşe")
        XCTAssertEqual(direct.otherUserId, DemoData.ayseId)
        XCTAssertFalse(direct.isReadOnly)
        let connected = try await backend.sendConnectionRequest(to: DemoData.ayseId, note: nil)
        XCTAssertEqual(connected, .alreadyConnected)
    }

    func testFarViewerSeesNoOne() async throws {
        try await consentAndShow(at: GeoMath.offset(.modaKadikoy, north: 30_000, east: 0))
        let lovers = try await backend.animalLovers(interest: nil)
        XCTAssertTrue(lovers.isEmpty, "10 km dışı dönmez")
    }

    func testMutualRequestAutoAccepts() async throws {
        try await consentAndShow()
        let incoming = try await backend.incomingConnectionRequests()
        let fromZeynep = try XCTUnwrap(incoming.first { $0.userId == DemoData.zeynepId })
        let zeynep = try await backend.animalLovers(interest: nil).first { $0.id == DemoData.zeynepId }
        XCTAssertEqual(zeynep?.connection, .incomingPending(requestId: fromZeynep.id))

        let outcome = try await backend.sendConnectionRequest(to: DemoData.zeynepId, note: nil)
        guard case .autoAccepted(let conversationId) = outcome else { return XCTFail("\(outcome)") }
        let remaining = try await backend.incomingConnectionRequests()
        XCTAssertTrue(remaining.isEmpty)
        let chats = try await backend.conversations()
        XCTAssertTrue(chats.contains { $0.id == conversationId && $0.kind == .direct })
    }

    func testDeclineCooldownWithdrawAndRemove() async throws {
        // Emre görünür olsun ve istek atsın; ben reddedeyim → Emre 30 gün bekler.
        try await consentAndShow()
        await backend.setCurrentUser(DemoData.emreId)
        guard case .sent(let requestId) = try await backend.sendConnectionRequest(to: me, note: nil) else { return XCTFail() }
        await backend.setCurrentUser(me)
        let declined = try await backend.respondToConnection(requestId: requestId, accept: false)
        XCTAssertNil(declined)
        await backend.setCurrentUser(DemoData.emreId)
        let cooldown = try await backend.sendConnectionRequest(to: me, note: nil)
        XCTAssertEqual(cooldown, .cooldown)
        let pendingView = try await backend.animalLovers(interest: nil).first { $0.id == me }
        XCTAssertEqual(pendingView?.connection, .outgoingPending(requestId: requestId), "reddedilen kendi isteğini bekliyor görür")

        // Ben ona istek atabilirim (benim reddettiğim satır yok sayılır); Emre kabul eder, sonra bağlantıyı kaldırırım.
        await backend.setCurrentUser(me)
        let tooLong = try await backend.sendConnectionRequest(to: DemoData.emreId, note: String(repeating: "a", count: SocialPolicy.maxNote + 1))
        XCTAssertEqual(tooLong, .noteTooLong)
        guard case .sent(let mine) = try await backend.sendConnectionRequest(to: DemoData.emreId, note: nil) else { return XCTFail() }
        try await backend.withdrawConnectionRequest(id: mine)
        let afterWithdraw = try await backend.animalLovers(interest: nil).first { $0.id == DemoData.emreId }
        XCTAssertEqual(afterWithdraw?.connection, ConnectionState.none)
        guard case .sent(let again) = try await backend.sendConnectionRequest(to: DemoData.emreId, note: nil) else { return XCTFail() }
        await backend.setCurrentUser(DemoData.emreId)
        let conversationId = try await backend.respondToConnection(requestId: again, accept: true)
        XCTAssertNotNil(conversationId)

        await backend.setCurrentUser(me)
        try await backend.removeConnection(userId: DemoData.emreId)
        let chats = try await backend.conversations()
        XCTAssertFalse(chats.contains { $0.id == conversationId }, "kaldırılan bağlantının sohbeti gizlenir")
        let messages = try await backend.messages(conversationId: conversationId!, before: nil, limit: 50)
        XCTAssertTrue(messages.isEmpty)
    }

    // MARK: - Sohbet

    func connectWithAyse() async throws -> UUID {
        try await consentAndShow()
        _ = try await backend.sendConnectionRequest(to: DemoData.ayseId, note: nil)
        clock.advance(InMemoryBackend.demoResponseDelay)
        let ayse = try await backend.animalLovers(interest: nil).first { $0.id == DemoData.ayseId }
        guard case .connected(let conversationId) = ayse?.connection else {
            XCTFail("bağlanmadı")
            return UUID()
        }
        return conversationId
    }

    func testBlockHidesDirectConversation() async throws {
        let conversationId = try await connectWithAyse()
        try await backend.block(userId: DemoData.ayseId)
        let chats = try await backend.conversations()
        XCTAssertFalse(chats.contains { $0.id == conversationId })
        let lovers = try await backend.animalLovers(interest: nil)
        XCTAssertFalse(lovers.contains { $0.id == DemoData.ayseId })
        let send = try await backend.sendMessage(conversationId: conversationId, body: "Merhaba")
        XCTAssertEqual(send, .readOnly)

        // Engel iki yönlü: Ayşe de beni göremez.
        await backend.setCurrentUser(DemoData.ayseId)
        let ayseChats = try await backend.conversations()
        XCTAssertFalse(ayseChats.contains { $0.id == conversationId })
    }

    /// Katılımcı düzenleyeni engellerse buluşmadan `leave_meetup` gibi çıkar: buluşma ona gizlendiği için
    /// "Ayrıl" düğmesini göremez; grup sohbeti listeden düşer.
    func testParticipantBlockingOrganizerLeavesMeetup() async throws {
        _ = try await backend.giveSocialConsent()
        let meetupId = DemoData.id(8, 1)  // Ayşe düzenliyor
        guard case .joined(let conversationId) = try await backend.joinMeetup(id: meetupId) else { return XCTFail() }

        try await backend.block(userId: DemoData.ayseId)
        let chats = try await backend.conversations()
        XCTAssertFalse(chats.contains { $0.id == conversationId }, "grup sohbeti listeden düşer")
        let send = try await backend.sendMessage(conversationId: conversationId, body: "Merhaba")
        XCTAssertEqual(send, .notMember)

        await backend.setCurrentUser(DemoData.ayseId)
        let participants = try await backend.meetupParticipants(meetupId: meetupId)
        XCTAssertFalse(participants.contains { $0.id == me }, "engelleyen katılımcı listede yok")
        let detail = try await backend.meetup(id: meetupId, near: nil)
        XCTAssertEqual(detail?.participantCount, 3, "Ayşe + Emre + Zeynep")
    }

    /// Uzunluklar Postgres `char_length` gibi kod noktasıyla sayılır (ZWJ'li emoji tek grafem, üç kod noktası).
    func testLengthLimitsCountUnicodeScalars() async throws {
        _ = try await backend.giveSocialConsent()
        let blackCat = "\u{1F408}\u{200D}\u{2B1B}"  // 🐈‍⬛: 1 grafem, 3 kod noktası
        XCTAssertEqual(blackCat.count, 1)
        let over = String(repeating: blackCat, count: 27)              // 81 kod noktası
        let atLimit = String(repeating: blackCat, count: 26) + "ab"    // 80 kod noktası
        XCTAssertEqual(SocialPolicy.validate(draft(title: over), now: start), .titleLength)
        XCTAssertNil(SocialPolicy.validate(draft(title: atLimit), now: start))
        XCTAssertEqual(SocialPolicy.prefix(atLimit + blackCat, maxLength: 80), atLimit, "grafem bölünmez")
        XCTAssertEqual(SocialPolicy.prefix("ab" + blackCat, maxLength: 4), "ab")
        let rejected = try await backend.createMeetup(draft(title: over))
        XCTAssertEqual(rejected, .invalid(.titleLength))
        guard case .created = try await backend.createMeetup(draft(title: atLimit)) else { return XCTFail("sınırda geçerli") }

        try await consentAndShow()
        let note = String(repeating: blackCat, count: 67)  // 201 kod noktası
        let tooLong = try await backend.sendConnectionRequest(to: DemoData.ayseId, note: note)
        XCTAssertEqual(tooLong, .noteTooLong)
    }

    func testCannedReplyArrivesAfterDelay() async throws {
        let conversationId = try await connectWithAyse()
        let empty = try await backend.sendMessage(conversationId: conversationId, body: "  ")
        XCTAssertEqual(empty, .bodyEmpty)
        let long = try await backend.sendMessage(conversationId: conversationId, body: String(repeating: "a", count: SocialPolicy.maxMessage + 1))
        XCTAssertEqual(long, .bodyTooLong)

        let sent = try await backend.sendMessage(conversationId: conversationId, body: " Merhaba, bu hafta mama turuna çıkıyor musun? ")
        guard case .sent(let message) = sent else { return XCTFail("\(sent)") }
        XCTAssertEqual(message.body, "Merhaba, bu hafta mama turuna çıkıyor musun?")
        XCTAssertEqual(message.authorId, me)

        var messages = try await backend.messages(conversationId: conversationId, before: nil, limit: 50)
        XCTAssertEqual(messages.map(\.id), [message.id])

        clock.advance(InMemoryBackend.demoResponseDelay)
        messages = try await backend.messages(conversationId: conversationId, before: nil, limit: 50)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.authorId, DemoData.ayseId)
        XCTAssertEqual(messages.last?.body, DemoData.cannedReplies[0])
        XCTAssertEqual(messages.last?.createdAt, message.createdAt.addingTimeInterval(3))

        var summary = try await backend.conversations().first { $0.id == conversationId }
        XCTAssertEqual(summary?.unreadCount, 1)
        XCTAssertEqual(summary?.lastBody, DemoData.cannedReplies[0])
        try await backend.markConversationRead(id: conversationId)
        summary = try await backend.conversations().first { $0.id == conversationId }
        XCTAssertEqual(summary?.unreadCount, 0)

        let older = try await backend.messages(conversationId: conversationId, before: messages.last!.createdAt, limit: 50)
        XCTAssertEqual(older.map(\.id), [message.id])
    }

    /// `count` sinyal gelirse true; `timeout` içinde gelmezse false (asılı kalmaz). Akış göndermeden önce dinlenir.
    func expectSignals(_ stream: AsyncStream<Void>, count: Int, within timeout: Duration = .seconds(2)) -> Task<Bool, Never> {
        let consumer = Task {
            var received = 0
            for await _ in stream {
                received += 1
                if received >= count { return true }
            }
            return false
        }
        Task {
            try? await Task.sleep(for: timeout)
            consumer.cancel()
        }
        return consumer
    }

    func testChatUpdatesYieldOnNewMessage() async throws {
        let conversationId = try await connectWithAyse()
        let signals = expectSignals(backend.updates(conversationId: conversationId), count: 1)
        _ = try await backend.sendMessage(conversationId: conversationId, body: "Merhaba")
        let received = await signals.value
        XCTAssertTrue(received, "kendi mesajında sinyal gelmedi")
    }

    func testChatUpdatesSignalAgainWhenCannedReplyIsDue() async throws {
        let conversationId = try await connectWithAyse()
        await backend.setReplySignalDelay(.milliseconds(50))
        let signals = expectSignals(backend.updates(conversationId: conversationId), count: 2)
        _ = try await backend.sendMessage(conversationId: conversationId, body: "Merhaba")
        let received = await signals.value
        XCTAssertTrue(received, "hazır cevap için gecikmeli ikinci sinyal gelmedi")
    }

    func testNotMemberCannotSend() async throws {
        _ = try await backend.giveSocialConsent()
        let seeded = try await backend.meetup(id: DemoData.id(8, 1), near: .modaKadikoy)
        XCTAssertEqual(seeded?.viewerRole, MeetupViewerRole.none)
        XCTAssertNil(seeded?.conversationId)
        let outcome = try await backend.sendMessage(conversationId: DemoData.id(9, 1), body: "Merhaba")
        XCTAssertEqual(outcome, .notMember)

        guard case .joined(let conversationId) = try await backend.joinMeetup(id: DemoData.id(8, 1)) else { return XCTFail() }
        XCTAssertEqual(conversationId, DemoData.id(9, 1))
        let history = try await backend.messages(conversationId: conversationId, before: nil, limit: 50)
        XCTAssertFalse(history.isEmpty, "katılınca önceki mesajlar görünür")
        let summary = try await backend.conversations().first { $0.id == conversationId }
        XCTAssertEqual(summary?.unreadCount, 0, "katılımdan önceki mesajlar okunmamış sayılmaz")
        XCTAssertEqual(summary?.kind, .meetup)
    }

    /// Review Focus 5: karşı taraf hesabını silerse bire bir sohbet kalır, 'Silinmiş kullanıcı' + salt okunur.
    func testOtherUserDeletedAccountLeavesReadOnlyConversation() async throws {
        let conversationId = try await connectWithAyse()
        _ = try await backend.sendMessage(conversationId: conversationId, body: "Merhaba")

        await backend.setCurrentUser(DemoData.ayseId)
        try await backend.deleteAccount()

        await backend.setCurrentUser(me)
        let chats = try await backend.conversations()
        let summary = try XCTUnwrap(chats.first { $0.id == conversationId })
        XCTAssertEqual(summary.title, "Silinmiş kullanıcı")
        XCTAssertTrue(summary.isReadOnly)
        XCTAssertNil(summary.otherUserId)
        let messages = try await backend.messages(conversationId: conversationId, before: nil, limit: 50)
        XCTAssertEqual(messages.map(\.body), ["Merhaba"], "silinen kişinin mesajları gider, benimkiler kalır")
        let send = try await backend.sendMessage(conversationId: conversationId, body: "Orada mısın?")
        XCTAssertEqual(send, .readOnly)

        // Ayşe'nin düzenlediği seed buluşması da gider.
        let meetups = try await backend.meetups(near: .modaKadikoy, radiusMeters: 10_000)
        XCTAssertFalse(meetups.contains { $0.organizerId == DemoData.ayseId })
    }
}
