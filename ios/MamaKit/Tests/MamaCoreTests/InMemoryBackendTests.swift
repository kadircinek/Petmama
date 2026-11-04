import XCTest
@testable import MamaCore

final class InMemoryBackendTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeBackend(signedIn: Bool = true) -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
    }

    func testAnonymousSeesFuzzedAndNoPrivateSpots() async throws {
        let backend = makeBackend(signedIn: false)
        let bounds = GeoBounds(center: .modaKadikoy, radiusMeters: 3000)
        let spots = try await backend.spots(in: bounds)
        XCTAssertFalse(spots.isEmpty)
        XCTAssertTrue(spots.allSatisfy { !$0.isLocationExact })
        XCTAssertFalse(spots.contains { $0.visibility == .private })
    }

    func testSignedInSeesExactPublicButFuzzedPrivate() async throws {
        let backend = makeBackend()
        let spots = try await backend.spots(in: GeoBounds(center: .modaKadikoy, radiusMeters: 3000))
        XCTAssertTrue(spots.filter { $0.visibility == .public }.allSatisfy(\.isLocationExact))
        let privateSpot = try XCTUnwrap(spots.first { $0.visibility == .private })
        XCTAssertFalse(privateSpot.isLocationExact)
    }

    func testGuardianSeesExactPrivateSpot() async throws {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.zeynepId) // Zeynep "Gönüllü bahçesi" koruyucusu
        let spot = try await backend.spot(id: DemoData.id(2, 14))
        XCTAssertEqual(spot?.isLocationExact, true)
    }

    func testCheckInRequiresSignIn() async {
        let backend = makeBackend(signedIn: false)
        let draft = CheckInDraft(spotId: DemoData.id(2, 1), kind: .fed, userCoordinate: .modaKadikoy)
        do {
            _ = try await backend.checkIn(draft)
            XCTFail("giriş gerekmeli")
        } catch {
            XCTAssertEqual(error as? MamaError, .notSignedIn)
        }
    }

    func testFedCheckInClosesRequestAndThanksOpener() async throws {
        let backend = makeBackend()
        let spotId = DemoData.id(2, 6) // "Moda İskelesi arkası": Emre'nin açık talebi var
        let before = try await backend.spot(id: spotId)
        XCTAssertEqual(before?.status, .needsFood)

        let rawValue = await backend.rawSpot(spotId)
        let raw = try XCTUnwrap(rawValue)
        let user = GeoMath.offset(raw.coordinate, north: 30, east: 0)
        let outcome = try await backend.checkIn(CheckInDraft(spotId: spotId, kind: .fed, amount: .full, userCoordinate: user))
        guard case .success(let receipt) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(receipt.closedNeedCount, 1)
        XCTAssertEqual(receipt.spotStatus, .fedRecent)
        XCTAssertEqual(receipt.distanceMeters, 30, accuracy: 1)

        let thanks = await backend.notifications(for: DemoData.emreId)
        XCTAssertEqual(thanks.first?.kind, .thanksFed)
    }

    func testCheckInTooFar() async throws {
        let backend = makeBackend()
        let spotId = DemoData.id(2, 1)
        let rawValue = await backend.rawSpot(spotId)
        let raw = try XCTUnwrap(rawValue)
        let far = GeoMath.offset(raw.coordinate, north: 150, east: 0)
        let outcome = try await backend.checkIn(CheckInDraft(spotId: spotId, kind: .fed, userCoordinate: far))
        guard case .tooFar(let distance, let max) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(max, 100)
        XCTAssertEqual(distance, 150, accuracy: 1)

        // Aynı mesafe "mama gerekli" için yeterli (300 m).
        let request = try await backend.checkIn(CheckInDraft(spotId: spotId, kind: .needFood, userCoordinate: far))
        guard case .success = request else { return XCTFail("\(request)") }
        let after = try await backend.spot(id: spotId)
        XCTAssertEqual(after?.status, .needsFood)
    }

    func testRateLimitAndIdempotency() async throws {
        let backend = makeBackend()
        let spotId = DemoData.id(2, 3)
        let rawValue = await backend.rawSpot(spotId)
        let raw = try XCTUnwrap(rawValue)
        let draft = CheckInDraft(spotId: spotId, kind: .fed, userCoordinate: raw.coordinate)
        guard case .success = try await backend.checkIn(draft) else { return XCTFail() }
        guard case .success = try await backend.checkIn(draft) else { return XCTFail("aynı id idempotent olmalı") }
        let second = CheckInDraft(spotId: spotId, kind: .fed, userCoordinate: raw.coordinate)
        let outcome = try await backend.checkIn(second)
        XCTAssertEqual(outcome, .rateLimited)
    }

    func testDuplicateDetectionAndForce() async throws {
        let backend = makeBackend()
        let rawValue = await backend.rawSpot(DemoData.id(2, 1))
        let raw = try XCTUnwrap(rawValue)
        let near = GeoMath.offset(raw.coordinate, north: 8, east: 0)
        let first = try await backend.createSpot(SpotDraft(coordinate: near, title: "Park girişi"))
        guard case .duplicate(let candidates) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(candidates.first?.id, raw.id)

        let forced = try await backend.createSpot(SpotDraft(coordinate: near, title: "Park girişi", force: true))
        guard case .created = forced else { return XCTFail("\(forced)") }
    }

    func testDailySpotLimit() async throws {
        let backend = makeBackend()
        for index in 0..<5 {
            let coordinate = GeoMath.offset(.modaKadikoy, north: 2000 + Double(index) * 100, east: 0)
            guard case .created = try await backend.createSpot(SpotDraft(coordinate: coordinate, title: "n\(index)")) else { return XCTFail() }
        }
        let sixth = try await backend.createSpot(SpotDraft(coordinate: GeoMath.offset(.modaKadikoy, north: 3000, east: 0), title: "n6"))
        XCTAssertEqual(sixth, .limitReached(limit: 5))
    }

    func testProfanityRejected() async throws {
        let backend = makeBackend()
        let outcome = try await backend.createSpot(SpotDraft(coordinate: GeoMath.offset(.modaKadikoy, north: 5000, east: 0), title: "siktir"))
        XCTAssertEqual(outcome, .rejectedContent)
    }

    func testGoneReportsDeactivateAtThree() async throws {
        let backend = makeBackend()
        let spotId = DemoData.id(2, 9)
        for user in [DemoData.ayseId, DemoData.emreId] {
            await backend.setCurrentUser(user)
            let outcome = try await backend.reportGone(spotId: spotId)
            XCTAssertFalse(outcome.deactivated)
        }
        await backend.setCurrentUser(DemoData.emreId)
        let value1 = try await backend.reportGone(spotId: spotId).reportCount
        XCTAssertEqual(value1, 2, "aynı kişi iki kez sayılmaz")
        await backend.setCurrentUser(DemoData.zeynepId)
        let value2 = try await backend.reportGone(spotId: spotId).deactivated
        XCTAssertTrue(value2)
        let gone = try await backend.spot(id: spotId)
        XCTAssertNil(gone)
    }

    func testNeedClaimAndResolveFlow() async throws {
        let backend = makeBackend()
        let needId = DemoData.id(5, 1)
        let value3 = try await backend.claim(needId: needId)
        XCTAssertEqual(value3, .ok)
        await backend.setCurrentUser(DemoData.emreId)
        let value4 = try await backend.claim(needId: needId)
        XCTAssertEqual(value4, .alreadyClaimed)
        let value5 = try await backend.resolve(needId: needId)
        XCTAssertFalse(value5, "Emre ne açtı ne üstlendi")
        await backend.signInAsDemoUser()
        let value6 = try await backend.resolve(needId: needId)
        XCTAssertTrue(value6)
        let resolved = try await backend.need(id: needId)
        XCTAssertEqual(resolved?.status, .resolved)
        let creatorNotes = await backend.notifications(for: DemoData.zeynepId)
        XCTAssertEqual(creatorNotes.first?.kind, .needResolved)
    }

    func testNeedsNearSortedUrgentFirst() async throws {
        let backend = makeBackend()
        let needs = try await backend.needs(near: .modaKadikoy, radiusMeters: 5000, includeResolved: false)
        XCTAssertEqual(needs.first?.urgency, .urgent)
        XCTAssertFalse(needs.contains { $0.status == .resolved })
        XCTAssertTrue(needs.allSatisfy { $0.distanceMeters != nil })
    }

    func testSpotShowsUrgentRingFromAnimalNeed() async throws {
        let backend = makeBackend()
        let spot = try await backend.spot(id: DemoData.id(2, 7))
        XCTAssertEqual(spot?.hasUrgentNeed, true)
        XCTAssertGreaterThan(spot?.animalCount ?? 0, 0)
    }

    func testTimelineHasSevenDays() async throws {
        let backend = makeBackend()
        let days = try await backend.feedingTimeline(spotId: DemoData.id(2, 1), days: 7)
        XCTAssertEqual(days.count, 7)
        XCTAssertGreaterThan(days.map(\.fedCount).reduce(0, +), 0)
        XCTAssertEqual(days, days.sorted { $0.day < $1.day })
    }

    func testSearchIsTurkishCaseInsensitive() async throws {
        let backend = makeBackend()
        let results = try await backend.search(query: "İSKELE", near: .modaKadikoy)
        XCTAssertEqual(results.first?.title, "Moda İskelesi arkası")
    }

    func testDeleteAccountAnonymizes() async throws {
        let backend = makeBackend()
        let rawValue = await backend.rawSpot(DemoData.id(2, 4))
        let raw = try XCTUnwrap(rawValue)
        guard case .created(let newId, _) = try await backend.createSpot(
            SpotDraft(coordinate: GeoMath.offset(raw.coordinate, north: 500, east: 500), title: "Benim noktam")
        ) else { return XCTFail() }
        try await backend.deleteAccount()
        let userId = await backend.currentUserId()
        XCTAssertNil(userId)
        let spot = await backend.rawSpot(newId)
        XCTAssertNotNil(spot, "nokta kalır")
        XCTAssertNil(spot?.createdBy, "ama anonimleşir")
    }

    func testFollowAndGuardian() async throws {
        let backend = makeBackend()
        let spotId = DemoData.id(2, 3)
        try await backend.setFollowing(true, target: .spot, id: spotId)
        let value7 = try await backend.followedSpotIds()
        XCTAssertEqual(value7, [spotId])
        try await backend.setGuardian(spotId: spotId, schedule: [.monday])
        let guardians = try await backend.guardians(spotId: spotId)
        XCTAssertTrue(guardians.contains { $0.userId == DemoData.meId && $0.schedule == [.monday] })
        try await backend.setGuardian(spotId: spotId, schedule: nil)
        let value8 = try await backend.guardedSpotIds().contains(spotId)
        XCTAssertFalse(value8)
    }
}

final class OfflineQueueTests: XCTestCase {
    actor FlakyRepository: CheckInRepository {
        var online = false
        var received: [CheckInDraft] = []
        func setOnline(_ value: Bool) { online = value }
        func checkIn(_ draft: CheckInDraft) async throws -> CheckInOutcome {
            guard online else { throw URLError(.notConnectedToInternet) }
            received.append(draft)
            return .success(CheckInReceipt(checkInId: draft.id, distanceMeters: 10, closedNeedCount: 0, spotStatus: .fedRecent))
        }
    }

    func testQueuesWhenOfflineAndFlushesLater() async throws {
        let repo = FlakyRepository()
        let queue = OfflineCheckInQueue(store: InMemoryPendingCheckInStore(), repository: repo)
        let draft = CheckInDraft(spotId: UUID(), kind: .fed, userCoordinate: .modaKadikoy)
        let outcome = try await queue.checkIn(draft)
        XCTAssertEqual(outcome, .queuedOffline)
        _ = try await queue.checkIn(draft)
        let pending = await queue.pendingCount()
        XCTAssertEqual(pending, 1, "aynı taslak iki kez kuyruğa girmez")

        await repo.setOnline(true)
        let results = await queue.flush(now: draft.createdAt.addingTimeInterval(60))
        XCTAssertEqual(results.count, 1)
        let afterFlush = await queue.pendingCount()
        XCTAssertEqual(afterFlush, 0)
        let received = await repo.received
        XCTAssertEqual(received.map(\.id), [draft.id])
    }

    func testStaleQueuedCheckInsAreDropped() async throws {
        let repo = FlakyRepository()
        await repo.setOnline(true)
        let old = CheckInDraft(spotId: UUID(), kind: .fed, userCoordinate: .modaKadikoy, createdAt: Date(timeIntervalSince1970: 0))
        let queue = OfflineCheckInQueue(store: InMemoryPendingCheckInStore([old]), repository: repo)
        let results = await queue.flush(now: Date(timeIntervalSince1970: 13 * 3600))
        XCTAssertTrue(results.isEmpty)
        let pending = await queue.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    func testFileStoreRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString).json")
        let store = FilePendingCheckInStore(url: url)
        let draft = CheckInDraft(spotId: UUID(), kind: .needWater, userCoordinate: .modaKadikoy)
        await store.save([draft])
        let loaded = await store.load()
        XCTAssertEqual(loaded.map(\.id), [draft.id])
        XCTAssertEqual(loaded.first?.kind, .needWater)
    }
}

@MainActor
final class StoreTests: XCTestCase {
    func testRouterGatesSignInRequiredSheets() async {
        let services = AppServices.demo()
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        let router = AppRouter()
        router.present(.checkIn(spotId: UUID(), kind: .fed), session: session)
        XCTAssertEqual(router.sheet, .signIn)
        _ = await session.signInWithApple(idToken: "t", nonce: "n", fullName: nil)
        router.signInFinished(success: session.isSignedIn)
        if case .checkIn = router.sheet {} else { XCTFail("giriş sonrası asıl modal açılmalı") }
    }

    func testAddTabOpensMenuInsteadOfSelecting() async {
        let router = AppRouter()
        router.select(.add)
        XCTAssertEqual(router.selectedTab, .map)
        XCTAssertEqual(router.sheet, .addMenu)
    }

    func testSessionSignInWithDemoCredentials() async {
        let services = AppServices.demo()
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        let wrong = await session.signIn(email: "demo@mamaharitasi.app", password: "nope")
        XCTAssertFalse(wrong)
        XCTAssertEqual(session.lastError, .invalidCredentials)
        let ok = await session.signIn(email: "demo@mamaharitasi.app", password: "demo1234")
        XCTAssertTrue(ok)
        XCTAssertEqual(session.profile?.id, DemoData.meId)
    }

    func testLocationStoreWithStaticDriver() async {
        let driver = StaticLocationDriver(location: .modaKadikoy, authorization: .notDetermined)
        let store = LocationStore(driver: driver)
        XCTAssertNil(store.coordinate)
        await store.requestAuthorization()
        XCTAssertTrue(store.isAuthorized)
        XCTAssertEqual(store.coordinate, .modaKadikoy)
        let moved = GeoMath.offset(.modaKadikoy, north: 50, east: 0)
        driver.move(to: moved)
        XCTAssertEqual(store.coordinate, moved)
    }
}
