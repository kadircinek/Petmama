import XCTest
import MamaCore
@testable import FeatureCommunity

@MainActor
final class CommunityPostDetailActionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let coverId = DemoData.id(6, 1)
    private let questionId = DemoData.id(6, 3)

    private func makeBackend() -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { fixed })
    }

    private func makeServices(_ backend: InMemoryBackend, community: (any CommunityRepository)? = nil) -> AppServices {
        let fixed = now
        var services = AppServices.inMemory(backend, now: { fixed })
        if let community { services.community = community }
        return services
    }

    // MARK: - Yetkiler

    func testCommentDeletePermissions() async throws {
        let model = PostDetailViewModel(postId: questionId, services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        // Emre'nin sorusuna Ayşe'nin yorumu.
        let comment = try XCTUnwrap(model.comments.first { $0.id == DemoData.id(7, 1) })

        XCTAssertTrue(model.canDeleteComment(comment, userId: DemoData.ayseId), "yorumun yazarı")
        XCTAssertTrue(model.canDeleteComment(comment, userId: DemoData.emreId), "paylaşımın sahibi")
        XCTAssertFalse(model.canDeleteComment(comment, userId: DemoData.zeynepId))
        XCTAssertFalse(model.canDeleteComment(comment, userId: DemoData.meId))
        XCTAssertFalse(model.canDeleteComment(comment, userId: nil))

        XCTAssertTrue(model.isOwnPost(userId: DemoData.emreId))
        XCTAssertFalse(model.isOwnPost(userId: DemoData.meId))
        XCTAssertFalse(model.isOwnPost(userId: nil))
    }

    // MARK: - Silme

    func testCommentAuthorDeletesOwnComment() async {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.ayseId)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let result = await model.deleteComment(DemoData.id(7, 1))
        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(result?.message(for: .comment), "Yorum silindi.")
        XCTAssertEqual(model.comments.map(\.id), [DemoData.id(7, 2)])
        XCTAssertEqual(model.post?.commentCount, 1)
        XCTAssertFalse(model.isWorking)

        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.comments.map(\.id), [DemoData.id(7, 2)], "sunucuda da silindi")
    }

    func testPostAuthorDeletesCommentOnOwnPost() async {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.emreId)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let result = await model.deleteComment(DemoData.id(7, 2))
        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(model.comments.map(\.id), [DemoData.id(7, 1)])
    }

    func testStrangerCannotDeleteComment() async {
        let model = PostDetailViewModel(postId: questionId, services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)

        let result = await model.deleteComment(DemoData.id(7, 1))
        XCTAssertEqual(result, .notAllowed)
        XCTAssertEqual(model.comments.count, 2)
        XCTAssertEqual(model.post?.commentCount, 2)
    }

    func testDeleteOwnPostMarksGone() async throws {
        let backend = makeBackend()
        let outcome = try await backend.createPost(CommunityPostDraft(kind: .question, body: "Su kabı öneren var mı?", coordinate: .modaKadikoy))
        guard case .created(let id, _) = outcome else { return XCTFail("paylaşım oluşmalıydı") }
        let model = PostDetailViewModel(postId: id, services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        XCTAssertTrue(model.isOwnPost(userId: DemoData.meId))

        let result = await model.deletePost()
        XCTAssertEqual(result, .deleted)
        XCTAssertNil(model.post)
        XCTAssertTrue(model.isNotFound)
        let raw = await backend.rawPost(id)
        XCTAssertNil(raw)
    }

    func testDeleteSomeoneElsesPostIsNotAllowed() async {
        let backend = makeBackend()
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let result = await model.deletePost()
        XCTAssertEqual(result, .notAllowed)
        XCTAssertNotNil(model.post)
        XCTAssertFalse(model.isNotFound)
    }

    // MARK: - Pati ve "Ben bakarım"

    func testPawToggleAndRollback() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.post?.pawCount, 1)

        let pawed = await model.togglePaw()
        XCTAssertEqual(pawed, .toggled(pawed: true))
        XCTAssertEqual(model.post?.pawCount, 2)
        XCTAssertEqual(model.post?.viewerPawed, true)

        await stub.fail(.togglePaw, with: .offline)
        let failed = await model.togglePaw()
        XCTAssertEqual(failed, .failed(.offline))
        XCTAssertEqual(model.post?.pawCount, 2, "başarısız olunca eski değer geri gelir")
        XCTAssertEqual(model.post?.viewerPawed, true)
    }

    func testVolunteerRefreshesVolunteerList() async {
        let backend = makeBackend()
        let model = PostDetailViewModel(postId: coverId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let joined = await model.toggleVolunteer()
        XCTAssertEqual(joined, .volunteered(count: 2))
        XCTAssertEqual(model.post?.viewerVolunteered, true)
        XCTAssertEqual(model.post?.volunteerCount, 2)
        XCTAssertEqual(model.volunteers.map(\.userId), [DemoData.emreId, DemoData.meId])

        let left = await model.toggleVolunteer()
        XCTAssertEqual(left, .withdrawn(count: 1))
        XCTAssertEqual(model.volunteers.map(\.userId), [DemoData.emreId])
        XCTAssertFalse(model.isWorking)
    }

    func testVolunteerOnOwnAndNonCoverPosts() async {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.ayseId)
        let own = PostDetailViewModel(postId: coverId, services: makeServices(backend))
        await own.load(near: nil)
        let ownResult = await own.toggleVolunteer()
        XCTAssertEqual(ownResult, .ownPost)
        XCTAssertEqual(own.post?.volunteerCount, 1)

        let question = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await question.load(near: nil)
        let questionResult = await question.toggleVolunteer()
        XCTAssertEqual(questionResult, .notCoverRequest)
    }
}
