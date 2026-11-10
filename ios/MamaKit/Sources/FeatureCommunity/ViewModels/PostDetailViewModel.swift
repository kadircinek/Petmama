import Foundation
import Observation
import MamaCore

/// Paylaşım detayı: paylaşım, yorumlar ve "Yerime bakar mısın?" gönüllüleri.
@MainActor
@Observable
public final class PostDetailViewModel {
    /// Kalan karakter bu sayıya inince sayaç görünür.
    public static let counterThreshold = 40

    public let postId: UUID
    public private(set) var post: CommunityPost?
    public private(set) var comments: [CommunityComment] = []
    public private(set) var volunteers: [CommunityVolunteer] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    /// Silinmiş, incelemeye alınmış ya da engel nedeniyle görünmüyor.
    public private(set) var isNotFound = false
    public private(set) var requiresSignIn = false
    public var error: MamaError?

    /// Yorum kutusundaki metin.
    public var commentText = ""
    public private(set) var isSending = false
    /// Yorum gönderilemediyse kutunun üstünde gösterilen dostça açıklama.
    public private(set) var commentProblem: String?
    /// "Ben bakarım" veya silme isteği sürüyor.
    public private(set) var isWorking = false

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var isTogglingPaw = false

    public init(postId: UUID, services: AppServices) {
        self.postId = postId
        self.services = services
    }

    public var now: Date { services.now() }

    // MARK: - Yükleme

    public func load(near coordinate: Coordinate?, signedIn: Bool = true) async {
        guard signedIn else {
            showSignInGate()
            return
        }
        if requiresSignIn {
            // Giriş yapıldı: davet yerine yükleniyor durumu görünsün.
            requiresSignIn = false
            hasLoaded = false
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            guard let fresh = try await services.community.post(id: postId, near: coordinate) else {
                markNotFound()
                return
            }
            let freshComments = try await services.community.comments(postId: postId)
            var freshVolunteers: [CommunityVolunteer] = []
            if fresh.kind == .coverRequest {
                freshVolunteers = try await services.community.volunteers(postId: postId)
            }
            post = fresh
            comments = freshComments
            volunteers = freshVolunteers
            isNotFound = false
            requiresSignIn = false
            error = nil
        } catch {
            switch MamaError.classify(error) {
            case .notSignedIn: showSignInGate()
            case .notFound: markNotFound()
            case let other: self.error = other
            }
        }
    }

    // MARK: - Yorum yazma

    public var trimmedComment: String {
        commentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var remainingCommentCharacters: Int {
        CommunityPolicy.maxCommentLength - trimmedComment.count
    }

    /// Sınıra 40 karakter kala sayaç görünür.
    public var showsCommentCounter: Bool { remainingCommentCharacters <= Self.counterThreshold }

    public var canSendComment: Bool {
        !isSending && !trimmedComment.isEmpty && remainingCommentCharacters >= 0
    }

    /// Yorumu gönderir; başarılıysa kutuyu temizleyip yorumları tazeler. `nil` = zaten gönderiliyor.
    public func sendComment(near coordinate: Coordinate?) async -> CommunityCommentResult? {
        guard !isSending else { return nil }
        commentProblem = nil
        if let invalid = CommunityPolicy.validateComment(commentText) {
            let result = CommunityCommentResult.invalid(invalid)
            commentProblem = result.message
            return result
        }
        isSending = true
        defer { isSending = false }

        let result: CommunityCommentResult
        do {
            result = CommunityCommentResult(try await services.community.addComment(postId: postId, body: trimmedComment))
        } catch {
            result = .failed(MamaError.classify(error))
        }
        switch result {
        case .sent:
            commentText = ""
            await load(near: coordinate)
        case .postNotFound:
            markNotFound()
        case .limitReached, .rejectedContent, .invalid, .failed:
            commentProblem = result.message
        }
        return result
    }

    // MARK: - Yetkiler (son kararı sunucu verir)

    public func isOwnPost(userId: UUID?) -> Bool {
        guard let userId, let post else { return false }
        return post.authorId == userId
    }

    /// Yorumu yazan ya da paylaşımın sahibi silebilir.
    public func canDeleteComment(_ comment: CommunityComment, userId: UUID?) -> Bool {
        guard let userId else { return false }
        return comment.authorId == userId || post?.authorId == userId
    }

    public var isCoverOpen: Bool {
        guard let post else { return false }
        return CommunityPolicy.isCoverOpen(post, now: services.now())
    }

    // MARK: - Eylemler

    /// İyimser pati. `nil` = süren bir istek var ya da paylaşım yüklenmedi.
    public func togglePaw() async -> CommunityPawResult? {
        guard !isTogglingPaw, let original = post else { return nil }
        isTogglingPaw = true
        defer { isTogglingPaw = false }
        post?.applyOptimisticPawToggle()
        do {
            guard let result = try await services.community.togglePaw(postId: postId) else {
                markNotFound()
                return .postGone
            }
            post?.apply(result)
            return .toggled(pawed: result.pawed)
        } catch {
            post?.viewerPawed = original.viewerPawed
            post?.pawCount = original.pawCount
            return .failed(MamaError.classify(error))
        }
    }

    /// "Ben bakarım" / "Vazgeç"; başarıda gönüllü listesi tazelenir. `nil` = süren bir istek var.
    public func toggleVolunteer() async -> CommunityVolunteerResult? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await services.community.toggleVolunteer(postId: postId)
            switch outcome {
            case .ok(let volunteered, let count):
                post?.viewerVolunteered = volunteered
                post?.volunteerCount = count
                if let fresh = try? await services.community.volunteers(postId: postId) { volunteers = fresh }
            case .postNotFound:
                markNotFound()
            case .notCoverRequest, .ownPost, .closed:
                break
            }
            return CommunityVolunteerResult(outcome)
        } catch {
            return .failed(MamaError.classify(error))
        }
    }

    /// `nil` = süren bir istek var.
    public func deleteComment(_ commentId: UUID) async -> CommunityDeleteResult? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            guard try await services.community.deleteComment(id: commentId) else { return .notAllowed }
            removeComment(commentId)
            return .deleted
        } catch {
            let classified = MamaError.classify(error)
            // Zaten silinmiş: kullanıcının istediği sonuç.
            guard classified == .notFound else { return .failed(classified) }
            removeComment(commentId)
            return .deleted
        }
    }

    /// Kendi paylaşımını siler; başarılıysa ekran kapatılır. `nil` = süren bir istek var.
    public func deletePost() async -> CommunityDeleteResult? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            guard try await services.community.deletePost(id: postId) else { return .notAllowed }
            markNotFound()
            return .deleted
        } catch {
            let classified = MamaError.classify(error)
            guard classified == .notFound else { return .failed(classified) }
            markNotFound()
            return .deleted
        }
    }

    // MARK: - Yardımcılar

    private func removeComment(_ commentId: UUID) {
        guard comments.contains(where: { $0.id == commentId }) else { return }
        comments.removeAll { $0.id == commentId }
        if let count = post?.commentCount { post?.commentCount = max(0, count - 1) }
    }

    private func markNotFound() {
        post = nil
        comments = []
        volunteers = []
        isNotFound = true
        error = nil
        hasLoaded = true
    }

    /// Oturum yokken besleyicilerin konuşmaları bellekte de tutulmaz.
    private func showSignInGate() {
        post = nil
        comments = []
        volunteers = []
        isNotFound = false
        requiresSignIn = true
        error = nil
        isLoading = false
        hasLoaded = true
    }
}
