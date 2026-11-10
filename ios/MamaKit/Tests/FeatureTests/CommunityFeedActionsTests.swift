import XCTest
import MamaCore
@testable import FeatureCommunity

/// Bellek içi backend'i sarar: çağrıları kaydeder, seçilen çağrıyı hata ile düşürür, patiyi bekletebilir.
actor CommunityRepositoryStub: CommunityRepository {
    enum Call: Hashable, Sendable {
        case feed, post, comments, volunteers, createPost, addComment
        case togglePaw, toggleVolunteer, deletePost, deleteComment, summary
    }

    private let base: InMemoryBackend
    private var failures: [Call: MamaError] = [:]
    private(set) var calls: [Call] = []
    private(set) var feedBefores: [Date?] = []
    private(set) var feedLimits: [Int] = []
    private var holdsPaw = false
    private var pawGate: CheckedContinuation<Void, Never>?

    init(_ base: InMemoryBackend) {
        self.base = base
    }

    func fail(_ call: Call, with error: MamaError = .offline) { failures[call] = error }
    func heal(_ call: Call) { failures[call] = nil }

    /// Sonraki pati isteği `releasePaw()` çağrılana kadar bekler (iyimser durumu gözlemek için).
    func holdPaw() { holdsPaw = true }
    var isPawHeld: Bool { pawGate != nil }
    func releasePaw() {
        holdsPaw = false
        pawGate?.resume()
        pawGate = nil
    }

    private func record(_ call: Call) throws {
        calls.append(call)
        if let error = failures[call] { throw error }
    }

    func feed(near center: Coordinate, radiusMeters: Int, kind: CommunityPostKind?, before: Date?, limit: Int) async throws -> [CommunityPost] {
        try record(.feed)
        feedBefores.append(before)
        feedLimits.append(limit)
        return try await base.feed(near: center, radiusMeters: radiusMeters, kind: kind, before: before, limit: limit)
    }

    func post(id: UUID, near center: Coordinate?) async throws -> CommunityPost? {
        try record(.post)
        return try await base.post(id: id, near: center)
    }

    func comments(postId: UUID) async throws -> [CommunityComment] {
        try record(.comments)
        return try await base.comments(postId: postId)
    }

    func volunteers(postId: UUID) async throws -> [CommunityVolunteer] {
        try record(.volunteers)
        return try await base.volunteers(postId: postId)
    }

    func createPost(_ draft: CommunityPostDraft) async throws -> CreatePostOutcome {
        try record(.createPost)
        return try await base.createPost(draft)
    }

    func addComment(postId: UUID, body: String) async throws -> CommentOutcome {
        try record(.addComment)
        return try await base.addComment(postId: postId, body: body)
    }

    func togglePaw(postId: UUID) async throws -> PawToggleResult? {
        calls.append(.togglePaw)
        if holdsPaw {
            await withCheckedContinuation { pawGate = $0 }
        }
        if let error = failures[.togglePaw] { throw error }
        return try await base.togglePaw(postId: postId)
    }

    func toggleVolunteer(postId: UUID) async throws -> CoverVolunteerOutcome {
        try record(.toggleVolunteer)
        return try await base.toggleVolunteer(postId: postId)
    }

    func deletePost(id: UUID) async throws -> Bool {
        try record(.deletePost)
        return try await base.deletePost(id: id)
    }

    func deleteComment(id: UUID) async throws -> Bool {
        try record(.deleteComment)
        return try await base.deleteComment(id: id)
    }

    func summary(near center: Coordinate, radiusMeters: Int) async throws -> CommunitySummary {
        try record(.summary)
        return try await base.summary(near: center, radiusMeters: radiusMeters)
    }
}

@MainActor
final class CommunityFeedActionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let coverId = DemoData.id(6, 1)
    private let questionId = DemoData.id(6, 3)

    /// `clock` verilirse veriler `now` anına göre üretilir ama backend saati `clock` olur (süresi dolmuş istek için).
    private func makeBackend(clock: Date? = nil) -> InMemoryBackend {
        let fixed = now
        let current = clock ?? now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { current })
    }

    private func makeServices(_ backend: InMemoryBackend, community: (any CommunityRepository)? = nil, clock: Date? = nil) -> AppServices {
        let current = clock ?? now
        var services = AppServices.inMemory(backend, now: { current })
        if let community { services.community = community }
        return services
    }

    private func post(_ id: UUID, in model: CommunityFeedViewModel) -> CommunityPost? {
        model.posts.first { $0.id == id }
    }

    // MARK: - Pati

    func testPawToggleUpdatesCountAndServer() async throws {
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(post(questionId, in: model)?.pawCount, 1)

        let first = await model.togglePaw(questionId)
        XCTAssertEqual(first, .toggled(pawed: true))
        XCTAssertNil(first?.message)
        XCTAssertEqual(post(questionId, in: model)?.pawCount, 2)
        XCTAssertEqual(post(questionId, in: model)?.viewerPawed, true)
        let stored = try await backend.post(id: questionId, near: nil)
        XCTAssertEqual(stored?.pawCount, 2)

        let second = await model.togglePaw(questionId)
        XCTAssertEqual(second, .toggled(pawed: false))
        XCTAssertEqual(post(questionId, in: model)?.pawCount, 1)
        XCTAssertEqual(post(questionId, in: model)?.viewerPawed, false)
    }

    func testPawIsOptimisticAndRollsBackOnFailure() async throws {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)
        await stub.holdPaw()
        await stub.fail(.togglePaw, with: .offline)

        let questionId = self.questionId
        let pending = Task { await model.togglePaw(questionId) }
        var held = false
        for _ in 0..<2000 where !held {
            held = await stub.isPawHeld
            if !held { await Task.yield() }
        }
        XCTAssertTrue(held, "pati isteği sunucuda bekliyor olmalı")

        // Yanıt gelmeden ekranda çevrilmiş olmalı.
        XCTAssertEqual(post(questionId, in: model)?.viewerPawed, true)
        XCTAssertEqual(post(questionId, in: model)?.pawCount, 2)
        // Aynı paylaşım için ikinci dokunuş beklerken yok sayılır.
        let ignored = await model.togglePaw(questionId)
        XCTAssertNil(ignored)

        await stub.releasePaw()
        let result = await pending.value
        XCTAssertEqual(result, .failed(.offline))
        XCTAssertEqual(result?.message, MamaError.offline.userMessage)
        XCTAssertEqual(post(questionId, in: model)?.viewerPawed, false, "başarısız olunca geri alınır")
        XCTAssertEqual(post(questionId, in: model)?.pawCount, 1)
        let stored = try await backend.post(id: questionId, near: nil)
        XCTAssertEqual(stored?.pawCount, 1)
    }

    func testPawOnVanishedPostRemovesCard() async throws {
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        await backend.setCurrentUser(DemoData.emreId)
        _ = try await backend.deletePost(id: questionId)
        await backend.setCurrentUser(DemoData.meId)

        let result = await model.togglePaw(questionId)
        XCTAssertEqual(result, .postGone)
        XCTAssertNotNil(result?.message)
        XCTAssertNil(post(questionId, in: model))

        let unknown = await model.togglePaw(UUID())
        XCTAssertNil(unknown, "listede olmayan paylaşım için istek atılmaz")
    }

    // MARK: - "Ben bakarım"

    func testVolunteerAndWithdraw() async {
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let joined = await model.toggleVolunteer(coverId)
        XCTAssertEqual(joined, .volunteered(count: 2))
        XCTAssertEqual(joined?.toastStyle, .success)
        XCTAssertEqual(post(coverId, in: model)?.viewerVolunteered, true)
        XCTAssertEqual(post(coverId, in: model)?.volunteerCount, 2)
        XCTAssertTrue(model.busyPostIds.isEmpty)

        let notifications = await backend.notifications(for: DemoData.ayseId)
        XCTAssertEqual(notifications.filter { $0.kind == .coverVolunteered && $0.postId == coverId }.count, 1)

        let left = await model.toggleVolunteer(coverId)
        XCTAssertEqual(left, .withdrawn(count: 1))
        XCTAssertEqual(left?.toastStyle, .info)
        XCTAssertEqual(post(coverId, in: model)?.viewerVolunteered, false)
        XCTAssertEqual(post(coverId, in: model)?.volunteerCount, 1)
    }

    func testVolunteerOnOwnPost() async {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.ayseId)
        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        XCTAssertTrue(model.isOwn(model.posts[0], userId: DemoData.ayseId))
        XCTAssertFalse(model.isOwn(model.posts[0], userId: DemoData.meId))
        XCTAssertFalse(model.isOwn(model.posts[0], userId: nil))

        let result = await model.toggleVolunteer(coverId)
        XCTAssertEqual(result, .ownPost)
        XCTAssertEqual(post(coverId, in: model)?.volunteerCount, 1)
    }

    func testVolunteerOnClosedRequest() async {
        // İstek 2–3 gün sonrasını kapsıyor; saat 5 gün ileri alınınca süresi dolmuş olur.
        let later = now.addingTimeInterval(5 * 86_400)
        let backend = makeBackend(clock: later)
        let model = CommunityFeedViewModel(services: makeServices(backend, clock: later))
        await model.load(near: .modaKadikoy)
        let cover = post(coverId, in: model)
        XCTAssertNotNil(cover)
        XCTAssertEqual(cover.map { model.isCoverOpen($0) }, false)

        let result = await model.toggleVolunteer(coverId)
        XCTAssertEqual(result, .closed)
        XCTAssertEqual(result?.message, "Bu isteğin süresi dolmuş.")
        XCTAssertEqual(post(coverId, in: model)?.volunteerCount, 1)
    }

    func testVolunteerOtherOutcomes() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)

        let notCover = await model.toggleVolunteer(DemoData.id(6, 2))
        XCTAssertEqual(notCover, .notCoverRequest)
        let gone = await model.toggleVolunteer(UUID())
        XCTAssertEqual(gone, .postGone)

        await stub.fail(.toggleVolunteer, with: .offline)
        let failed = await model.toggleVolunteer(coverId)
        XCTAssertEqual(failed, .failed(.offline))
        XCTAssertEqual(failed?.message, MamaError.offline.userMessage)
        XCTAssertEqual(failed?.toastStyle, .warning)
        XCTAssertEqual(post(coverId, in: model)?.volunteerCount, 1)
    }

    func testVolunteerOutcomeMapping() async {
        XCTAssertEqual(CommunityVolunteerResult(.ok(volunteered: true, volunteerCount: 3)), .volunteered(count: 3))
        XCTAssertEqual(CommunityVolunteerResult(.ok(volunteered: false, volunteerCount: 0)), .withdrawn(count: 0))
        XCTAssertEqual(CommunityVolunteerResult(.ownPost), .ownPost)
        XCTAssertEqual(CommunityVolunteerResult(.closed), .closed)
        XCTAssertEqual(CommunityVolunteerResult(.notCoverRequest), .notCoverRequest)
        XCTAssertEqual(CommunityVolunteerResult(.postNotFound), .postGone)
        let all: [CommunityVolunteerResult] = [
            .volunteered(count: 1), .withdrawn(count: 0), .ownPost, .closed, .notCoverRequest, .postGone, .failed(.offline),
        ]
        XCTAssertTrue(all.allSatisfy { !$0.message.isEmpty })
        XCTAssertEqual(Set(all.map(\.message)).count, all.count, "her sonuç kendi mesajını taşır")
    }

    // MARK: - Silme

    func testDeleteOwnPost() async throws {
        let backend = makeBackend()
        let outcome = try await backend.createPost(CommunityPostDraft(body: "Bugün kapları yıkadım.", coordinate: .modaKadikoy))
        guard case .created(let id, _) = outcome else { return XCTFail("paylaşım oluşmalıydı") }

        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.posts.first?.id, id)
        XCTAssertEqual(model.posts.count, 6)

        let result = await model.deletePost(id)
        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(result?.message(for: .post), "Paylaşımın silindi.")
        XCTAssertFalse(model.posts.contains { $0.id == id })
        let raw = await backend.rawPost(id)
        XCTAssertNil(raw)

        // Zaten silinmiş bir paylaşım için yeniden silme isteği de "silindi" sayılır.
        let again = await model.deletePost(id)
        XCTAssertEqual(again, .deleted)
    }

    func testDeleteSomeoneElsesPostIsNotAllowed() async {
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        let result = await model.deletePost(questionId)
        XCTAssertEqual(result, .notAllowed)
        XCTAssertEqual(result?.toastStyle, .info)
        XCTAssertNotNil(post(questionId, in: model))
        let raw = await backend.rawPost(questionId)
        XCTAssertNotNil(raw)
    }

    func testDeleteFailureKeepsPost() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        await stub.fail(.deletePost, with: .offline)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)

        let result = await model.deletePost(questionId)
        XCTAssertEqual(result, .failed(.offline))
        XCTAssertEqual(result?.message(for: .post), MamaError.offline.userMessage)
        XCTAssertNotNil(post(questionId, in: model))
    }
}
