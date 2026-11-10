import XCTest
import MamaCore
@testable import FeatureCommunity

@MainActor
final class CommunityPostDetailViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let coverId = DemoData.id(6, 1)
    private let questionId = DemoData.id(6, 3)

    private func makeBackend(signedIn: Bool = true) -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
    }

    private func makeServices(_ backend: InMemoryBackend, community: (any CommunityRepository)? = nil) -> AppServices {
        let fixed = now
        var services = AppServices.inMemory(backend, now: { fixed })
        if let community { services.community = community }
        return services
    }

    // MARK: - Yükleme

    func testLoadsPostAndCommentsOldestFirst() async {
        let model = PostDetailViewModel(postId: questionId, services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)

        XCTAssertEqual(model.post?.id, questionId)
        XCTAssertEqual(model.post?.authorName, "Emre")
        XCTAssertNotNil(model.post?.distanceMeters)
        XCTAssertEqual(model.comments.map(\.id), [DemoData.id(7, 1), DemoData.id(7, 2)])
        XCTAssertEqual(model.comments.first?.authorIsVerified, true)
        XCTAssertTrue(model.volunteers.isEmpty)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isNotFound)
        XCTAssertFalse(model.isCoverOpen)
        XCTAssertNil(model.error)
    }

    func testCoverRequestLoadsVolunteers() async {
        let model = PostDetailViewModel(postId: coverId, services: makeServices(makeBackend()))
        await model.load(near: nil)

        XCTAssertEqual(model.post?.kind, .coverRequest)
        XCTAssertNil(model.post?.distanceMeters, "konum yoksa mesafe gösterilmez")
        XCTAssertEqual(model.volunteers.map(\.userId), [DemoData.emreId])
        XCTAssertEqual(model.volunteers.first?.displayName, "Emre")
        XCTAssertEqual(model.comments.map(\.id), [DemoData.id(7, 3)])
        XCTAssertTrue(model.isCoverOpen)
    }

    func testUnknownPostIsNotFound() async {
        let model = PostDetailViewModel(postId: UUID(), services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        XCTAssertNil(model.post)
        XCTAssertTrue(model.isNotFound)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.error)
    }

    func testSignedOutShowsGate() async {
        let backend = makeBackend(signedIn: false)
        let stub = CommunityRepositoryStub(backend)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy, signedIn: false)
        XCTAssertTrue(model.requiresSignIn)
        XCTAssertNil(model.post)
        XCTAssertFalse(model.isNotFound)
        let calls = await stub.calls
        XCTAssertTrue(calls.isEmpty)

        // Sunucu reddederse de hata değil giriş daveti.
        await model.load(near: .modaKadikoy, signedIn: true)
        XCTAssertTrue(model.requiresSignIn)
        XCTAssertNil(model.error)
    }

    func testOfflineLoadSurfacesError() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        await stub.fail(.post, with: .offline)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.error, .offline)
        XCTAssertFalse(model.isNotFound)
        XCTAssertNil(model.post)
    }

    // MARK: - Yorum yazma

    func testAddCommentTrimsClearsAndNotifiesAuthor() async {
        let backend = makeBackend()
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        model.commentText = "  Ölçüleri ben de isterim!  \n"
        XCTAssertTrue(model.canSendComment)
        XCTAssertFalse(model.showsCommentCounter)

        let result = await model.sendComment(near: .modaKadikoy)
        XCTAssertEqual(result?.isSent, true)
        XCTAssertNil(result?.message)
        XCTAssertEqual(model.commentText, "")
        XCTAssertNil(model.commentProblem)
        XCTAssertFalse(model.isSending)
        XCTAssertEqual(model.comments.count, 3)
        XCTAssertEqual(model.comments.last?.body, "Ölçüleri ben de isterim!")
        XCTAssertEqual(model.comments.last?.authorId, DemoData.meId)
        XCTAssertEqual(model.post?.commentCount, 3)

        let notifications = await backend.notifications(for: DemoData.emreId)
        XCTAssertEqual(notifications.filter { $0.kind == .communityComment && $0.postId == questionId }.count, 1)
    }

    func testCommentValidationHappensBeforeServer() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)

        model.commentText = "   \n "
        XCTAssertFalse(model.canSendComment)
        let empty = await model.sendComment(near: nil)
        XCTAssertEqual(empty, .invalid(.bodyEmpty))
        XCTAssertEqual(model.commentProblem, CommunityValidationError.bodyEmpty.userMessage)

        model.commentText = String(repeating: "a", count: CommunityPolicy.maxCommentLength + 1)
        XCTAssertFalse(model.canSendComment)
        XCTAssertEqual(model.remainingCommentCharacters, -1)
        let long = await model.sendComment(near: nil)
        XCTAssertEqual(long, .invalid(.bodyTooLong))
        XCTAssertEqual(model.commentProblem, "Yorum biraz uzun oldu. En fazla 300 karakter olabilir.")
        XCTAssertEqual(model.commentText.count, 301, "metin silinmez, kullanıcı düzeltebilir")

        let calls = await stub.calls
        XCTAssertFalse(calls.contains(.addComment))
        XCTAssertEqual(model.comments.count, 2)
    }

    func testCommentCounterAppearsNearLimit() async {
        let model = PostDetailViewModel(postId: questionId, services: makeServices(makeBackend()))
        model.commentText = String(repeating: "a", count: 259)
        XCTAssertFalse(model.showsCommentCounter)
        model.commentText = String(repeating: "a", count: 260)
        XCTAssertTrue(model.showsCommentCounter)
        XCTAssertEqual(model.remainingCommentCharacters, 40)
        model.commentText = String(repeating: "a", count: 300)
        XCTAssertEqual(model.remainingCommentCharacters, 0)
        XCTAssertTrue(model.canSendComment)
    }

    func testRejectedContentKeepsText() async {
        let model = PostDetailViewModel(postId: questionId, services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        model.commentText = "Bu ne amk"

        let result = await model.sendComment(near: nil)
        XCTAssertEqual(result, .rejectedContent)
        XCTAssertEqual(model.commentProblem, MamaError.rejectedContent.userMessage)
        XCTAssertEqual(model.commentText, "Bu ne amk")
        XCTAssertEqual(model.comments.count, 2)
    }

    func testDailyCommentLimitMessage() async throws {
        let backend = makeBackend()
        for index in 0..<CommunityPolicy.dailyCommentLimit {
            let outcome = try await backend.addComment(postId: DemoData.id(6, 2), body: "Yorum \(index)")
            guard case .created = outcome else { return XCTFail("\(index). yorum oluşmalıydı") }
        }
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        model.commentText = "Bir yorum daha"

        let result = await model.sendComment(near: nil)
        XCTAssertEqual(result, .limitReached(limit: CommunityPolicy.dailyCommentLimit))
        XCTAssertEqual(model.commentProblem, "Bugünlük yorum sınırına ulaştın, yarın devam edebilirsin.")
        XCTAssertEqual(model.commentText, "Bir yorum daha")
        XCTAssertEqual(model.comments.count, 2)
    }

    func testCommentOnVanishedPostShowsNotFound() async throws {
        let backend = makeBackend()
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        await backend.setCurrentUser(DemoData.emreId)
        _ = try await backend.deletePost(id: questionId)
        await backend.setCurrentUser(DemoData.meId)

        model.commentText = "Hâlâ burada mısın?"
        let result = await model.sendComment(near: nil)
        XCTAssertEqual(result, .postNotFound)
        XCTAssertTrue(model.isNotFound)
        XCTAssertNil(model.post)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testCommentFailureIsFriendly() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let model = PostDetailViewModel(postId: questionId, services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)
        await stub.fail(.addComment, with: .offline)
        model.commentText = "Merhaba"

        let result = await model.sendComment(near: nil)
        XCTAssertEqual(result, .failed(.offline))
        XCTAssertEqual(model.commentProblem, MamaError.offline.userMessage)
        XCTAssertEqual(model.commentText, "Merhaba")
    }

    func testCommentOutcomeMapping() async {
        let id = UUID()
        XCTAssertEqual(CommunityCommentResult(.created(id: id)), .sent(id: id))
        XCTAssertEqual(CommunityCommentResult(.rejectedContent), .rejectedContent)
        XCTAssertEqual(CommunityCommentResult(.limitReached(limit: 60)), .limitReached(limit: 60))
        XCTAssertEqual(CommunityCommentResult(.invalid(.bodyEmpty)), .invalid(.bodyEmpty))
        XCTAssertEqual(CommunityCommentResult(.postNotFound), .postNotFound)
        XCTAssertNotNil(CommunityCommentResult.postNotFound.message)
    }
}
