import Foundation
import MamaCore

// Mahalle ViewModel testlerinin ortak test ikizleri.

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

/// Yükleme sayısını sayan fotoğraf yükleyici.
actor CommunityCountingUploader: MediaUploader {
    private(set) var uploadCount = 0

    func uploadJPEG(_ data: Data) async throws -> URL {
        uploadCount += 1
        return URL(fileURLWithPath: "/tmp/mahalle-\(uploadCount).jpg")
    }
}
