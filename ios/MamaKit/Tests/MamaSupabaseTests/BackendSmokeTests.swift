import Foundation
import MamaCore
@testable import MamaSupabase
import XCTest

/// Ağa çıkmadan doğrulanabilen davranışlar: kurulum ve oturumsuz çağrılar.
final class BackendSmokeTests: XCTestCase {
    private func makeServices(store: InMemoryPendingCheckInStore = InMemoryPendingCheckInStore()) -> AppServices {
        AppServices.supabase(
            url: URL(string: "https://example-ref.supabase.co")!,
            anonKey: "test-anon-key",
            config: AppConfig(isDemo: false),
            spotCache: InMemorySpotCache(),
            pendingStore: store
        )
    }

    func testFactoryWiresBackendAndQueue() async {
        let services = makeServices()
        XCTAssertTrue(services.auth is SupabaseBackend)
        XCTAssertTrue(services.spots is SupabaseBackend)
        XCTAssertTrue(services.media is SupabaseBackend)
        XCTAssertTrue(services.checkIns is OfflineCheckInQueue)
        XCTAssertFalse(services.config.isDemo)
        let userId = await services.auth.currentUserId()
        XCTAssertNil(userId)
    }

    func testSignedOutReadsOfOwnDataAreEmpty() async throws {
        let services = makeServices()
        let followed = try await services.profiles.followedSpotIds()
        XCTAssertEqual(followed, [])
        let followedSpots = try await services.profiles.followedSpots()
        XCTAssertEqual(followedSpots, [])
        let followedAnimals = try await services.profiles.followedAnimals()
        XCTAssertEqual(followedAnimals, [])
        let guarded = try await services.profiles.guardedSpotIds()
        XCTAssertEqual(guarded, [])
        let notifications = try await services.notifications.notifications()
        XCTAssertEqual(notifications, [])
        let preferences = try await services.notifications.preferences()
        XCTAssertEqual(preferences, .default)
        let blocked = try await services.moderation.blockedUserIds()
        XCTAssertEqual(blocked, [])
        let search = try await services.spots.search(query: "   ", near: nil)
        XCTAssertEqual(search, [])
        let needs = try await services.needs.needs(spotId: nil, animalId: nil, includeResolved: false)
        XCTAssertEqual(needs, [])
    }

    func testSignedOutWritesThrowNotSignedInWithoutQueueing() async {
        let store = InMemoryPendingCheckInStore()
        let services = makeServices(store: store)
        let draft = CheckInDraft(spotId: UUID(), kind: .fed, userCoordinate: .modaKadikoy)

        do {
            _ = try await services.checkIns.checkIn(draft)
            XCTFail("notSignedIn bekleniyordu")
        } catch {
            XCTAssertEqual(error as? MamaError, .notSignedIn)
        }
        let pending = await store.load()
        XCTAssertEqual(pending, [], "Oturumsuz check-in çevrimdışı kuyruğa girmemeli")

        await assertNotSignedIn { _ = try await services.spots.createSpot(SpotDraft(coordinate: .modaKadikoy, title: "Test")) }
        await assertNotSignedIn { _ = try await services.spots.duplicates(near: .modaKadikoy) }
        await assertNotSignedIn { _ = try await services.spots.reportGone(spotId: UUID()) }
        await assertNotSignedIn { _ = try await services.animals.createAnimal(AnimalDraft()) }
        await assertNotSignedIn { _ = try await services.needs.createNeed(NeedDraft(spotId: UUID(), description: "x")) }
        await assertNotSignedIn { _ = try await services.needs.claim(needId: UUID()) }
        await assertNotSignedIn { try await services.profiles.setFollowing(true, target: .spot, id: UUID()) }
        await assertNotSignedIn { try await services.profiles.setGuardian(spotId: UUID(), schedule: [.monday]) }
        await assertNotSignedIn { try await services.notifications.updatePreferences(.default) }
        await assertNotSignedIn { try await services.moderation.report(ReportDraft(target: .spot, targetId: UUID(), reason: .spam)) }
        await assertNotSignedIn { _ = try await services.media.uploadJPEG(Data([0xFF, 0xD8])) }
        await assertNotSignedIn { try await services.auth.deleteAccount() }
    }

    func testSignUpValidatesLocallyLikeInMemoryBackend() async {
        let services = makeServices()
        do {
            _ = try await services.auth.signUp(email: "no-at-sign", password: "longenough", displayName: "Ayşe")
            XCTFail("invalidInput bekleniyordu")
        } catch {
            XCTAssertEqual(error as? MamaError, .invalidInput(SupabaseErrorMapper.invalidSignUpMessage))
        }
    }

    func testSignOutWithoutSessionIsNoOp() async throws {
        let services = makeServices()
        try await services.auth.signOut()
    }

    private func assertNotSignedIn(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("notSignedIn bekleniyordu", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? MamaError, .notSignedIn, file: file, line: line)
        }
    }
}
