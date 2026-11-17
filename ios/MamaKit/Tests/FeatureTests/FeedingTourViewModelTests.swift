import XCTest
import MamaCore
import FeatureSocial

/// Mahalle › Akış üstü ("Şu an turda" + hayvanseverler şeridi) ve "Mama turuna çıkıyorum" (spec 2026-11-16).
@MainActor
final class NeighborhoodSocialViewModelTests: XCTestCase {
    func showMe(_ env: SocialEnvironment) async throws {
        let outcome = try await env.backend.updateSocialProfile(isVisible: true, about: "", interests: [.cats], at: .modaKadikoy)
        XCTAssertEqual(outcome, .saved)
    }

    func testWithoutConsentShowsToursAndConsentInvitation() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = NeighborhoodSocialViewModel(services: env.services)
        XCTAssertEqual(model.stripState, .loading)
        await model.load(at: .modaKadikoy)
        XCTAssertEqual(model.stripState, .needsConsent)
        XCTAssertTrue(model.lovers.isEmpty)
        XCTAssertEqual(model.tours.map(\.id), [DemoData.ayseTourId], "turlar onaysız da görünür; normal buluşmalar değil")
    }

    func testConsentedButInvisibleShowsVisibilityInvitation() async throws {
        let env = try await makeSocialEnvironment()
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertEqual(model.stripState, .needsVisibility)
        XCTAssertTrue(model.lovers.isEmpty)
    }

    func testVisibleViewerSeesStripWithBadges() async throws {
        let env = try await makeSocialEnvironment()
        try await showMe(env)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertEqual(model.stripState, .lovers)
        XCTAssertEqual(model.lovers.first?.id, DemoData.ayseId, "turda olan en önde")
        XCTAssertTrue(model.lovers.first?.isOnTour ?? false)
        XCTAssertEqual(model.lovers.first { $0.id == DemoData.emreId }?.fedToday, true)
        XCTAssertLessThanOrEqual(model.lovers.count, NeighborhoodSocialViewModel.stripLimit)
    }

    func testTourCardTimingAndRoles() async throws {
        let env = try await makeSocialEnvironment()
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        XCTAssertEqual(model.remainingMinutes(tour), 70, "90 dk tur, 20 dk önce başladı")
        XCTAssertEqual(tour.participantCount, 2)
        XCTAssertFalse(model.isMember(tour))
        env.clock.advance(69 * 60 + 30)
        XCTAssertEqual(model.remainingMinutes(tour), 1, "yukarı yuvarlanır")
        env.clock.advance(60)
        XCTAssertEqual(model.remainingMinutes(tour), 0)
        await model.load(at: .modaKadikoy)
        XCTAssertTrue(model.tours.isEmpty, "süresi dolan tur kartı kalkar")
    }

    func testVisibleToursPruneEndedAtRenderTime() async throws {
        let env = try await makeSocialEnvironment()
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        XCTAssertEqual(model.visibleTours(at: env.clock.now).map(\.id), [tour.id])
        // Yeniden yüklemeden: saat ilerleyince biten tur kartı çizimde düşer.
        XCTAssertEqual(model.visibleTours(at: tour.endsAt.addingTimeInterval(-1)).map(\.id), [tour.id])
        XCTAssertTrue(model.visibleTours(at: tour.endsAt).isEmpty)
        XCTAssertFalse(model.hasMoreTours(at: env.clock.now))
    }

    func testTourCardsCappedAtThree() async throws {
        let env = try await makeSocialEnvironment()
        for (user, spot) in [(DemoData.emreId, DemoData.id(2, 5)), (DemoData.zeynepId, DemoData.id(2, 1)), (DemoData.meId, DemoData.id(2, 10))] {
            await env.backend.setCurrentUser(user)
            guard case .started = try await env.backend.startFeedingTour(spotId: spot, durationMinutes: 60) else {
                return XCTFail("tur başlamadı")
            }
        }
        await env.backend.setCurrentUser(DemoData.meId)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertEqual(model.tours.count, 4)
        XCTAssertEqual(model.visibleTours(at: env.clock.now).count, NeighborhoodSocialViewModel.maxTourCards)
        XCTAssertEqual(NeighborhoodSocialViewModel.maxTourCards, 3)
        XCTAssertTrue(model.hasMoreTours(at: env.clock.now))
        XCTAssertEqual(model.visibleTours(at: env.clock.now).first?.viewerRole, .organizer, "kendi turum kesilmez")
    }

    func testProfileLoadFailureHidesStripInsteadOfInviting() async throws {
        let env = try await makeSocialEnvironment()
        await env.backend.setCurrentUser(nil)   // okumalar notSignedIn ile hata verir
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.stripState, .unavailable, "hata varken onay daveti gösterilmez")
    }

    func testPersonActionMessageIsSeparateFromTourMessage() async throws {
        let env = try await makeSocialEnvironment()
        let outcome = try await env.backend.updateSocialProfile(isVisible: true, about: "", interests: [], at: .modaKadikoy)
        XCTAssertEqual(outcome, .saved)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        _ = await model.sendRequest(to: DemoData.emreId, note: nil)
        XCTAssertEqual(model.personMessage, SocialMessages.message(for: SendRequestOutcome.sent(requestId: UUID())))
        XCTAssertNil(model.message, "kişi kartının mesajı Mahalle bandında tekrar görünmez")
    }

    func testBusyActionTracksWhichButton() async throws {
        let env = try await makeSocialEnvironment()
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        XCTAssertNil(model.busyAction)
        let tour = try XCTUnwrap(model.tours.first)
        _ = await model.messageTour(tour)
        XCTAssertNil(model.busyAction, "işlem bitince temizlenir")
    }

    func testJoinThenMessageOpensConversation() async throws {
        let env = try await makeSocialEnvironment()
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)

        let outcome = await model.join(tour)
        guard case .joined(let conversationId) = outcome else { return XCTFail("katılamadı: \(String(describing: outcome))") }
        let joined = try XCTUnwrap(model.tours.first)
        XCTAssertTrue(model.isMember(joined))
        XCTAssertEqual(joined.participantCount, 3)
        let again = await model.messageTour(joined)
        XCTAssertEqual(again, conversationId, "üye için Sohbete git")
    }

    func testMessageJoinsFirst() async throws {
        let env = try await makeSocialEnvironment()
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        let conversationId = await model.messageTour(tour)
        XCTAssertNotNil(conversationId)
        XCTAssertTrue(model.isMember(try XCTUnwrap(model.tours.first)))
        let chats = try await env.backend.conversations()
        XCTAssertTrue(chats.contains { $0.id == conversationId })
    }

    func testMessageWithoutConsentReportsConsentRequired() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        let conversationId = await model.messageTour(tour)
        XCTAssertNil(conversationId)
        XCTAssertNil(model.message, "onay ekranı açılır; ayrıca uyarı metni gösterilmez")
        XCTAssertTrue(model.lastActionNeedsConsent)
    }

    /// Onay verildikten sonra yarım kalan "Mesaj at" kendiliğinden tamamlanır (kullanıcı ikinci kez dokunmaz).
    func testPendingMessageResumesAfterConsent() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        let first = await model.messageTour(tour)
        XCTAssertNil(first)

        _ = try await env.backend.giveSocialConsent()
        await model.load(at: .modaKadikoy)
        let resumed = await model.resumeAfterConsent()

        guard case .openConversation(let conversationId)? = resumed else { return XCTFail("sohbet açılmalıydı: \(String(describing: resumed))") }
        let listed = try await env.backend.conversations().map(\.id)
        XCTAssertTrue(listed.contains(conversationId))
        XCTAssertNil(model.message)
        let again = await model.resumeAfterConsent()
        XCTAssertNil(again, "bekleyen işlem bir kez çalışır")
    }

    func testPendingJoinResumesAfterConsent() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        _ = await model.join(tour)

        _ = try await env.backend.giveSocialConsent()
        await model.load(at: .modaKadikoy)
        let resumed = await model.resumeAfterConsent()

        XCTAssertEqual(resumed, .joined)
        XCTAssertEqual(model.tours.first?.viewerRole, .participant)
    }

    /// Onay ekranı vazgeçilerek kapatılırsa bekleyen işlem düşer; sonradan kendiliğinden çalışmaz.
    func testPendingActionDroppedWhenConsentNotGiven() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let tour = try XCTUnwrap(model.tours.first)
        _ = await model.join(tour)

        await model.load(at: .modaKadikoy)
        let resumed = await model.resumeAfterConsent()
        XCTAssertNil(resumed)

        _ = try await env.backend.giveSocialConsent()
        await model.load(at: .modaKadikoy)
        let later = await model.resumeAfterConsent()
        XCTAssertNil(later)
        XCTAssertEqual(model.tours.first?.viewerRole, MeetupViewerRole.none)
    }

    func testOrganizerEndsTour() async throws {
        let env = try await makeSocialEnvironment()
        guard case .started(let tourId, _) = try await env.backend.startFeedingTour(spotId: DemoData.id(2, 1), durationMinutes: 60) else {
            return XCTFail("tur başlamadı")
        }
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let mine = try XCTUnwrap(model.tours.first { $0.id == tourId })
        XCTAssertEqual(mine.viewerRole, .organizer)
        XCTAssertTrue(model.isMember(mine))
        XCTAssertEqual(model.tours.first?.id, tourId, "kendi turum en önde")
        let ended = await model.endTour(mine)
        XCTAssertTrue(ended)
        XCTAssertFalse(model.tours.contains { $0.id == tourId })
    }

    func testRequestFromStripUpdatesLover() async throws {
        let env = try await makeSocialEnvironment()
        try await showMe(env)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        let outcome = await model.sendRequest(to: DemoData.emreId, note: nil)
        guard case .sent(let requestId) = outcome else { return XCTFail("istek gitmedi") }
        XCTAssertEqual(model.lover(id: DemoData.emreId)?.connection, .outgoingPending(requestId: requestId))
        let withdrawn = await model.withdraw(requestId: requestId)
        XCTAssertTrue(withdrawn)
        XCTAssertEqual(model.lover(id: DemoData.emreId)?.connection, ConnectionState.none)
    }

    func testRespondFromStripOpensChat() async throws {
        let env = try await makeSocialEnvironment()
        try await showMe(env)
        let model = NeighborhoodSocialViewModel(services: env.services)
        await model.load(at: .modaKadikoy)
        guard case .incomingPending(let requestId) = model.lover(id: DemoData.zeynepId)?.connection else {
            return XCTFail("Zeynep'in isteği bekliyor olmalı")
        }
        let conversationId = await model.respond(requestId: requestId, accept: true)
        XCTAssertNotNil(conversationId)
        guard case .connected = model.lover(id: DemoData.zeynepId)?.connection else { return XCTFail("bağlanmadı") }
    }
}

@MainActor
final class StartTourViewModelTests: XCTestCase {
    func testDefaultsAndNearestPublicSpots() async throws {
        let env = try await makeSocialEnvironment()
        let model = StartTourViewModel(services: env.services)
        XCTAssertEqual(model.durationMinutes, SocialPolicy.defaultTourDuration)
        XCTAssertEqual(StartTourViewModel.durationOptions, [60, 90, 120])
        await model.load(near: .modaKadikoy, preselected: nil)
        XCTAssertFalse(model.spots.isEmpty)
        XCTAssertLessThanOrEqual(model.spots.count, StartTourViewModel.maxSpots)
        XCTAssertTrue(model.spots.allSatisfy { $0.visibility == .public })
        let distances = model.spots.compactMap(\.distanceMeters)
        XCTAssertEqual(distances, distances.sorted(), "yakından uzağa")
        XCTAssertEqual(model.selectedSpotId, model.spots.first?.id, "en yakın seçili gelir")
        XCTAssertTrue(model.canSubmit)
    }

    func testPreselectedSpotComesFirst() async throws {
        let env = try await makeSocialEnvironment()
        let model = StartTourViewModel(services: env.services)
        let far = DemoData.id(2, 12)   // Kuşdili Çayırı, listenin sonlarında
        await model.load(near: .modaKadikoy, preselected: far)
        XCTAssertEqual(model.selectedSpotId, far)
        XCTAssertEqual(model.spots.first?.id, far)
        XCTAssertEqual(model.spots.filter { $0.id == far }.count, 1)
    }

    func testNonPublicPreselectionIsIgnored() async throws {
        let env = try await makeSocialEnvironment()
        let model = StartTourViewModel(services: env.services)
        await model.load(near: .modaKadikoy, preselected: DemoData.id(2, 13))   // bulanık nokta
        XCTAssertNotEqual(model.selectedSpotId, DemoData.id(2, 13))
        XCTAssertFalse(model.spots.contains { $0.id == DemoData.id(2, 13) })
    }

    func testSubmitStartsTourWithChosenDuration() async throws {
        let env = try await makeSocialEnvironment()
        let model = StartTourViewModel(services: env.services)
        await model.load(near: .modaKadikoy, preselected: DemoData.id(2, 1))
        model.durationMinutes = 120
        let outcome = await model.submit()
        guard case .started(let meetupId, let conversationId) = outcome else { return XCTFail("\(String(describing: outcome))") }
        XCTAssertNil(model.message)
        let tour = try await env.backend.meetup(id: meetupId, near: nil)
        XCTAssertEqual(tour?.isTour, true)
        XCTAssertEqual(tour?.conversationId, conversationId)
        XCTAssertEqual(tour.map { $0.endsAt.timeIntervalSince($0.startsAt) }, 120 * 60)

        let again = await model.submit()
        XCTAssertEqual(again, .alreadyTouring)
        XCTAssertEqual(model.message, SocialMessages.message(for: StartTourOutcome.alreadyTouring))
    }

    func testSubmitWithoutSpotDoesNothing() async throws {
        let env = try await makeSocialEnvironment()
        let model = StartTourViewModel(services: env.services)
        XCTAssertFalse(model.canSubmit)
        let outcome = await model.submit()
        XCTAssertNil(outcome)
    }

    func testConsentRequiredOutcome() async throws {
        let env = try await makeSocialEnvironment(consented: false)
        let model = StartTourViewModel(services: env.services)
        await model.load(near: .modaKadikoy, preselected: nil)
        let outcome = await model.submit()
        XCTAssertEqual(outcome, .consentRequired)
    }

    func testMessages() async {
        XCTAssertNil(SocialMessages.message(for: StartTourOutcome.started(meetupId: UUID(), conversationId: UUID())))
        XCTAssertEqual(SocialMessages.message(for: StartTourOutcome.limitReached(3)), "Bugün 3 tur başlattın, yarın devam edebilirsin.")
        XCTAssertNotNil(SocialMessages.message(for: StartTourOutcome.spotNotFound))
        XCTAssertNotNil(SocialMessages.message(for: StartTourOutcome.durationRange))
    }
}
