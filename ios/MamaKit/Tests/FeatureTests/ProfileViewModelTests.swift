import XCTest
import MamaCore
import FeatureProfile

private let profileNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class ProfileViewModelTests: XCTestCase {
    private func makeEnvironment(signedIn: Bool = true) async -> (InMemoryBackend, AppServices, SessionStore) {
        let now = profileNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: signedIn, now: { now })
        let services = AppServices.inMemory(backend, now: { now })
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        await session.restore()
        return (backend, services, session)
    }

    /// Noktanın 20 m yanından check-in.
    private func checkIn(_ backend: InMemoryBackend, spotIndex: Int, kind: CheckInKind = .fed) async throws {
        let spotId = DemoData.id(2, spotIndex)
        let raw = await backend.rawSpot(spotId)
        let spot = try XCTUnwrap(raw)
        let outcome = try await backend.checkIn(
            CheckInDraft(spotId: spotId, kind: kind, userCoordinate: GeoMath.offset(spot.coordinate, north: 20, east: 0))
        )
        guard case .success = outcome else { return XCTFail("check-in başarısız: \(outcome)") }
    }

    func testSignedOutShowsNothingToLoad() async {
        let (_, services, session) = await makeEnvironment(signedIn: false)
        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        XCTAssertFalse(session.isSignedIn)
        XCTAssertFalse(model.hasLoadedStats)
        XCTAssertEqual(model.stats, .zero)
        XCTAssertEqual(model.unreadNotificationCount, 0)
        XCTAssertNil(model.unreadBadgeText)
    }

    func testNewFeederSeesFullVerificationProgress() async throws {
        let (_, services, session) = await makeEnvironment()
        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        let profile = try XCTUnwrap(session.profile)
        XCTAssertTrue(model.hasLoadedStats)
        XCTAssertFalse(model.isVerified(profile))
        XCTAssertEqual(model.remainingForVerification, TrustPolicy.verifiedFeederCheckIns)
        XCTAssertEqual(model.verificationProgress, 0)
        XCTAssertEqual(model.verificationMessage, "Doğrulanmış besleyici rozetine 20 check-in kaldı")
    }

    func testVerificationProgressCountsVerifiedCheckIns() async throws {
        let (backend, services, session) = await makeEnvironment()
        try await checkIn(backend, spotIndex: 1)
        try await checkIn(backend, spotIndex: 2)
        try await checkIn(backend, spotIndex: 3)
        try await checkIn(backend, spotIndex: 4, kind: .water)

        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        XCTAssertEqual(model.stats.checkInCount, 4)
        XCTAssertEqual(model.stats.fedSpotCount, 3)
        XCTAssertEqual(model.stats.verifiedCheckInsLast30Days, 4)
        XCTAssertEqual(model.remainingForVerification, 16)
        XCTAssertEqual(model.verificationProgress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(model.verificationMessage, "Doğrulanmış besleyici rozetine 16 check-in kaldı")
        XCTAssertEqual(model.statItems.map(\.value), ["3", "4", "0"])
        XCTAssertEqual(model.statItems.map(\.label), ["Beslediğin nokta", "Check-in", "Kapatılan ihtiyaç"])
        // Güven puanı check-in'lerle arttı; oturumdaki profil tazelendi.
        XCTAssertEqual(session.profile?.trustScore, TrustPolicy.initialTrustScore + 4)
    }

    func testVerifiedFeederIsRecognised() async throws {
        let (backend, services, session) = await makeEnvironment()
        await backend.setCurrentUser(DemoData.ayseId)
        await session.restore()
        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        let profile = try XCTUnwrap(session.profile)
        XCTAssertEqual(profile.displayName, "Ayşe")
        XCTAssertTrue(model.isVerified(profile))
    }

    func testUnreadNotificationBadge() async throws {
        let (backend, services, session) = await makeEnvironment()
        // Emre "mama gerekli" der → yakındaki herkes (demo kullanıcı dahil) bildirim alır.
        await backend.setCurrentUser(DemoData.emreId)
        try await checkIn(backend, spotIndex: 1, kind: .needFood)
        await backend.setCurrentUser(DemoData.meId)

        let model = ProfileViewModel(services: services)
        await model.load(session: session)
        XCTAssertEqual(model.unreadNotificationCount, 1)
        XCTAssertEqual(model.unreadBadgeText, "1")
    }

    func testUpcomingBadgesAreTheV11Set() async {
        XCTAssertEqual(ProfileViewModel.upcomingBadges.map(\.title), [
            "İlk mama", "7 gün seri", "Kış kahramanı", "İhtiyaç çözücü", "Mahalle koruyucusu",
        ])
        XCTAssertEqual(Set(ProfileViewModel.upcomingBadges.map(\.id)).count, 5)
    }
}
