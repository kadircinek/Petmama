import Foundation
import MamaCore

// Mahalle eylemlerinin sonuçları: sunucu çıktısı + hata, kullanıcıya gösterilecek sıcak mesajla.

/// "Pati bırak" sonucu. Yalnızca sorun olduğunda mesaj gösterilir.
public enum CommunityPawResult: Equatable, Sendable {
    case toggled(pawed: Bool)
    /// Paylaşım silinmiş veya artık görünmüyor.
    case postGone
    case failed(MamaError)

    public var message: String? {
        switch self {
        case .toggled: return nil
        case .postGone: return "Bu paylaşım artık yok."
        case .failed(let error): return error.userMessage
        }
    }
}

/// "Ben bakarım" / "Vazgeç" sonucu.
public enum CommunityVolunteerResult: Equatable, Sendable {
    case volunteered(count: Int)
    case withdrawn(count: Int)
    case ownPost
    /// Tarih aralığı geçmişte kaldı.
    case closed
    case notCoverRequest
    case postGone
    case failed(MamaError)

    public init(_ outcome: CoverVolunteerOutcome) {
        switch outcome {
        case .ok(let volunteered, let count): self = volunteered ? .volunteered(count: count) : .withdrawn(count: count)
        case .notCoverRequest: self = .notCoverRequest
        case .ownPost: self = .ownPost
        case .closed: self = .closed
        case .postNotFound: self = .postGone
        }
    }

    public var message: String {
        switch self {
        case .volunteered: return "Teşekkürler! Bakacağını paylaşımın sahibine haber verdik."
        case .withdrawn: return "Tamam, gönüllülüğünü geri aldık."
        case .ownPost: return "Bu senin paylaşımın. Bakacak olanları burada göreceksin."
        case .closed: return "Bu isteğin süresi dolmuş."
        case .notCoverRequest: return "Bu paylaşım için gönüllü aranmıyor."
        case .postGone: return "Bu paylaşım artık yok."
        case .failed(let error): return error.userMessage
        }
    }

    public var toastStyle: AppRouter.Toast.Style {
        switch self {
        case .volunteered: return .success
        case .withdrawn, .ownPost, .closed, .notCoverRequest, .postGone: return .info
        case .failed: return .warning
        }
    }
}

/// Paylaşım veya yorum silme sonucu. Son kararı sunucu verir.
public enum CommunityDeleteResult: Equatable, Sendable {
    public enum Subject: Sendable { case post, comment }

    case deleted
    case notAllowed
    case failed(MamaError)

    public func message(for subject: Subject) -> String {
        switch (self, subject) {
        case (.deleted, .post): return "Paylaşımın silindi."
        case (.deleted, .comment): return "Yorum silindi."
        case (.notAllowed, .post): return "Bu paylaşımı yalnızca yazarı silebilir."
        case (.notAllowed, .comment): return "Bu yorumu yalnızca yazarı veya paylaşımın sahibi silebilir."
        case (.failed(let error), _): return error.userMessage
        }
    }

    public var toastStyle: AppRouter.Toast.Style {
        switch self {
        case .deleted: return .success
        case .notAllowed: return .info
        case .failed: return .warning
        }
    }
}

/// Yorum gönderme sonucu.
public enum CommunityCommentResult: Equatable, Sendable {
    case sent(id: UUID)
    case limitReached(limit: Int)
    case rejectedContent
    case invalid(CommunityValidationError)
    case postNotFound
    case failed(MamaError)

    public init(_ outcome: CommentOutcome) {
        switch outcome {
        case .created(let id): self = .sent(id: id)
        case .rejectedContent: self = .rejectedContent
        case .limitReached(let limit): self = .limitReached(limit: limit)
        case .invalid(let reason): self = .invalid(reason)
        case .postNotFound: self = .postNotFound
        }
    }

    public var isSent: Bool {
        if case .sent = self { return true }
        return false
    }

    /// Gönderildiyse `nil`.
    public var message: String? {
        switch self {
        case .sent: return nil
        case .limitReached: return "Bugünlük yorum sınırına ulaştın, yarın devam edebilirsin."
        case .rejectedContent: return MamaError.rejectedContent.userMessage
        // `CommunityValidationError.userMessage` paylaşım sınırını (600) söyler; yorumun sınırı farklı.
        case .invalid(.bodyTooLong): return "Yorum biraz uzun oldu. En fazla \(CommunityPolicy.maxCommentLength) karakter olabilir."
        case .invalid(let reason): return reason.userMessage
        case .postNotFound: return "Bu paylaşım artık yok."
        case .failed(let error): return error.userMessage
        }
    }
}

/// Paylaşım oluşturma sonucu (`CreatePostOutcome` + istemci ön kontrolü + hata).
public enum CreatePostResult: Equatable, Sendable {
    case created(id: UUID, pendingModeration: Bool)
    case limitReached(limit: Int)
    case rejectedContent
    case invalid(CommunityValidationError)
    case failed(MamaError)

    public init(_ outcome: CreatePostOutcome) {
        switch outcome {
        case .created(let id, let pending): self = .created(id: id, pendingModeration: pending)
        case .rejectedContent: self = .rejectedContent
        case .limitReached(let limit): self = .limitReached(limit: limit)
        case .invalid(let reason): self = .invalid(reason)
        }
    }

    public var isCreated: Bool {
        if case .created = self { return true }
        return false
    }

    /// Başarıda toast, diğerlerinde formdaki uyarı metni.
    public var message: String {
        switch self {
        case .created(_, let pending):
            return pending ? "Paylaşımın kısa bir incelemeden sonra görünecek." : "Paylaşımın mahallede!"
        case .limitReached(let limit): return "Bugün \(limit) paylaşım yaptın, yarın devam edebilirsin."
        case .rejectedContent: return MamaError.rejectedContent.userMessage
        case .invalid(let reason): return reason.userMessage
        case .failed(let error): return error.userMessage
        }
    }

    public var toastStyle: AppRouter.Toast.Style {
        switch self {
        case .created(_, let pending): return pending ? .info : .success
        case .limitReached, .rejectedContent, .invalid: return .info
        case .failed: return .warning
        }
    }
}

/// Formda seçilmiş, henüz yüklenmemiş fotoğraf.
public struct CommunityPhotoDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let data: Data

    public init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }
}
