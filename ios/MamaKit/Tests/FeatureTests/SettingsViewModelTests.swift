import XCTest
import MamaCore
import FeatureProfile

private let settingsNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeEnvironment(signedIn: Bool = true) async -> (InMemoryBackend, AppServices, SessionStore) {
        let now = settingsNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: signedIn, now: { now })
        let services = AppServices.inMemory(backend, now: { now })
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        await session.restore()
        return (backend, services, session)
    }

    func testLoadsDefaultPreferences() async {
        let (_, services, _) = await makeEnvironment()
        let model = SettingsViewModel(services: services)
        await model.load(isSignedIn: true)
        XCTAssertTrue(model.hasLoadedPreferences)
        XCTAssertEqual(model.preferences, .default)
        XCTAssertEqual(model.preferences.quietStartHour, 22)
        XCTAssertEqual(model.preferences.quietEndHour, 7)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.supportEmail, "destek@mamaharitasi.app")
    }

    func testPreferencesRoundTrip() async throws {
        let (_, services, _) = await makeEnvironment()
        let model = SettingsViewModel(services: services)
        await model.load(isSignedIn: true)
        model.preferences.radiusMeters = 2000
        model.preferences.quietStartHour = 23
        model.preferences.quietEndHour = 8
        model.preferences.needFoodNearby = false
        model.preferences.guardianAlerts = false
        XCTAssertTrue(model.hasUnsavedChanges)
        let saved = await model.savePreferences()
        XCTAssertTrue(saved)
        XCTAssertFalse(model.hasUnsavedChanges)

        let stored = try await services.notifications.preferences()
        XCTAssertEqual(stored, NotificationPreferences(radiusMeters: 2000, quietStartHour: 23, quietEndHour: 8,
                                                       needFoodNearby: false, followedUpdates: true, guardianAlerts: false))
        let reloaded = SettingsViewModel(services: services)
        await reloaded.load(isSignedIn: true)
        XCTAssertEqual(reloaded.preferences, stored)
        XCTAssertEqual(reloaded.quietHoursSummary, "23:00–08:00 arası bildirim gönderilmez.")
    }

    func testSaveIsNoopWithoutChangesOrBeforeLoad() async {
        let (_, services, _) = await makeEnvironment()
        let model = SettingsViewModel(services: services)
        model.preferences.radiusMeters = 5000
        let beforeLoad = await model.savePreferences()
        XCTAssertFalse(beforeLoad, "yüklenmeden kaydedilmez")
        await model.load(isSignedIn: true)
        let unchanged = await model.savePreferences()
        XCTAssertFalse(unchanged)
    }

    func testSignedOutHasNoPreferencesToSave() async {
        let (_, services, _) = await makeEnvironment(signedIn: false)
        let model = SettingsViewModel(services: services)
        await model.load(isSignedIn: false)
        XCTAssertFalse(model.hasLoadedPreferences)
        model.preferences.needFoodNearby = false
        let saved = await model.savePreferences()
        XCTAssertFalse(saved)
        XCTAssertNil(model.error)
    }

    func testBlockedUsersAreListedByNameAndCanBeUnblocked() async throws {
        let (_, services, _) = await makeEnvironment()
        try await services.moderation.block(userId: DemoData.emreId)
        try await services.moderation.block(userId: DemoData.ayseId)
        let model = SettingsViewModel(services: services)
        await model.load(isSignedIn: true)
        XCTAssertEqual(model.blockedUsers.map(\.displayName), ["Ayşe", "Emre"])

        let emre = try XCTUnwrap(model.blockedUsers.first { $0.id == DemoData.emreId })
        await model.unblock(emre)
        XCTAssertEqual(model.blockedUsers.map(\.id), [DemoData.ayseId])
        let remaining = try await services.moderation.blockedUserIds()
        XCTAssertEqual(remaining, [DemoData.ayseId])
    }

    func testDeleteAccountSignsOutAndAnonymisesCommunityData() async throws {
        let (backend, services, session) = await makeEnvironment()
        // Demo kullanıcı bir nokta ekler, check-in yapar ve bir noktayı takip eder.
        let coordinate = GeoMath.offset(.modaKadikoy, north: 900, east: 900)
        let outcome = try await services.spots.createSpot(SpotDraft(coordinate: coordinate, title: "Benim noktam", force: true))
        guard case .created(let spotId, _) = outcome else { return XCTFail("\(outcome)") }
        _ = try await backend.checkIn(CheckInDraft(spotId: spotId, kind: .fed, userCoordinate: coordinate))
        try await services.profiles.setFollowing(true, target: .spot, id: DemoData.id(2, 1))

        let model = SettingsViewModel(services: services)
        await model.load(isSignedIn: true)
        let deleted = await model.deleteAccount(session: session)

        XCTAssertTrue(deleted)
        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.hasLoadedPreferences)
        let currentUser = await services.auth.currentUserId()
        XCTAssertNil(currentUser)
        let profile = try await services.profiles.profile(id: DemoData.meId)
        XCTAssertNil(profile, "kişisel veri silinir")
        let rawSpot = await backend.rawSpot(spotId)
        let spot = try XCTUnwrap(rawSpot, "nokta topluluk için kalır")
        XCTAssertNil(spot.createdBy, "nokta anonimleşir")
        let stats = try await services.profiles.stats(userId: DemoData.meId)
        XCTAssertEqual(stats.checkInCount, 0, "check-in'ler kullanıcıdan ayrılır")

        // Silinen hesapla tekrar giriş yapılamaz.
        let signedInAgain = await session.signIn(email: "demo@mamaharitasi.app", password: "demo1234")
        XCTAssertFalse(signedInAgain)
    }

    func testDeleteAccountFailureKeepsSessionAndShowsError() async {
        let (_, services, _) = await makeEnvironment(signedIn: false)
        // Oturum store'da açık görünür ama sunucuda oturum yok → silme reddedilir.
        let session = SessionStore(auth: services.auth, profiles: services.profiles,
                                   profile: UserProfile(id: DemoData.meId, displayName: "Sen"))
        let model = SettingsViewModel(services: services)
        let deleted = await model.deleteAccount(session: session)
        XCTAssertFalse(deleted)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(model.error, .notSignedIn)
        XCTAssertFalse(model.isDeletingAccount)
    }

    func testSignOutClearsSession() async {
        let (_, services, session) = await makeEnvironment()
        let model = SettingsViewModel(services: services)
        await model.load(isSignedIn: true)
        await model.signOut(session: session)
        XCTAssertFalse(session.isSignedIn)
        XCTAssertFalse(model.hasLoadedPreferences)
    }

    func testLabels() async {
        XCTAssertEqual(SettingsViewModel.radiusOptions.map(SettingsViewModel.radiusLabel), ["500 m", "1 km", "2 km", "5 km"])
        XCTAssertEqual(SettingsViewModel.radiusLabel(1500), "1,5 km")
        XCTAssertEqual(SettingsViewModel.hourLabel(7), "07:00")
        XCTAssertEqual(SettingsViewModel.hourLabel(22), "22:00")
        XCTAssertEqual(SettingsViewModel.hourOptions.count, 24)
        XCTAssertEqual(SettingsViewModel.dailyLimitNote, "Günde en fazla 3 \"mama gerekli\" bildirimi gönderilir.")
    }
}
