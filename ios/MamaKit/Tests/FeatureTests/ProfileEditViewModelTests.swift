import XCTest
import MamaCore
import FeatureProfile

private let editNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class EditProfileViewModelTests: XCTestCase {
    private func makeEnvironment() async -> (AppServices, SessionStore) {
        let now = editNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { now })
        let services = AppServices.inMemory(backend, now: { now })
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        await session.restore()
        return (services, session)
    }

    func testStartsFromSessionProfile() async {
        let (services, session) = await makeEnvironment()
        let model = EditProfileViewModel(profile: session.profile, services: services)
        XCTAssertEqual(model.displayName, "Sen")
        XCTAssertEqual(model.neighborhood, "Moda")
        XCTAssertTrue(model.canSave)
    }

    func testValidation() async {
        let (services, session) = await makeEnvironment()
        let model = EditProfileViewModel(profile: session.profile, services: services)
        model.displayName = "   "
        XCTAssertEqual(model.validationIssue, "Görünen ad boş olamaz.")
        XCTAssertFalse(model.canSave)
        let saved = await model.save(session: session)
        XCTAssertFalse(saved)
        XCTAssertEqual(model.errorMessage, "Görünen ad boş olamaz.")

        model.displayName = "Pezevenk"
        XCTAssertEqual(model.validationIssue, MamaError.rejectedContent.userMessage)
        model.displayName = "Deniz"
        model.neighborhood = String(repeating: "x", count: EditProfileViewModel.maximumNeighborhoodLength + 1)
        XCTAssertNotNil(model.validationIssue)
    }

    func testSaveUpdatesBackendAndSession() async throws {
        let (services, session) = await makeEnvironment()
        let model = EditProfileViewModel(profile: session.profile, services: services)
        model.displayName = "  Deniz "
        model.neighborhood = " Caferağa "
        let saved = await model.save(session: session)
        XCTAssertTrue(saved)
        XCTAssertEqual(session.profile?.displayName, "Deniz")
        XCTAssertEqual(session.profile?.neighborhood, "Caferağa")
        let stored = try await services.profiles.profile(id: DemoData.meId)
        XCTAssertEqual(stored?.displayName, "Deniz")
    }

    func testEmptyNeighborhoodIsCleared() async throws {
        let (services, session) = await makeEnvironment()
        let model = EditProfileViewModel(profile: session.profile, services: services)
        model.neighborhood = "  "
        let saved = await model.save(session: session)
        XCTAssertTrue(saved)
        XCTAssertNil(session.profile?.neighborhood)
    }

    func testAvatarIsUploadedOnSave() async throws {
        let (services, session) = await makeEnvironment()
        let model = EditProfileViewModel(profile: session.profile, services: services)
        model.setAvatar(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertNotNil(model.pendingAvatar)
        let saved = await model.save(session: session)
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingAvatar)
        let url = try XCTUnwrap(session.profile?.avatarURL)
        XCTAssertEqual(model.avatarURL, url)
        XCTAssertEqual(url.pathExtension, "jpg")
    }

    func testDiscardPendingAvatarKeepsOldPhoto() async {
        let (services, session) = await makeEnvironment()
        let model = EditProfileViewModel(profile: session.profile, services: services)
        model.setAvatar(Data([1, 2, 3]))
        model.discardPendingAvatar()
        let saved = await model.save(session: session)
        XCTAssertTrue(saved)
        XCTAssertNil(session.profile?.avatarURL)
    }
}
