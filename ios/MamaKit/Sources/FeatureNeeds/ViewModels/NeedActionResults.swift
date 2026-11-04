import Foundation
import MamaCore

/// "Ben ilgileniyorum" sonucu (FR-I3). `ClaimOutcome` + hata, kullanıcı mesajıyla.
public enum NeedClaimResult: Equatable, Sendable {
    case claimed
    case alreadyClaimed
    case resolved
    case failed(MamaError)

    public init(_ outcome: ClaimOutcome) {
        switch outcome {
        case .ok: self = .claimed
        case .alreadyClaimed: self = .alreadyClaimed
        case .resolved: self = .resolved
        }
    }

    public var message: String {
        switch self {
        case .claimed: return "Teşekkürler! Bu ihtiyaçla ilgilendiğini herkes görecek."
        case .alreadyClaimed: return "Başka bir gönüllü ilgileniyor"
        case .resolved: return "Bu ihtiyaç zaten çözülmüş. Harika!"
        case .failed(let error): return error.userMessage
        }
    }

    public var toastStyle: AppRouter.Toast.Style {
        switch self {
        case .claimed: return .success
        case .alreadyClaimed, .resolved: return .info
        case .failed: return .warning
        }
    }
}

/// "Çözüldü olarak işaretle" sonucu. Son kararı sunucu verir.
public enum NeedResolveResult: Equatable, Sendable {
    case resolved
    case notAllowed
    case failed(MamaError)

    public var message: String {
        switch self {
        case .resolved: return "Harika! İhtiyaç çözüldü olarak işaretlendi."
        case .notAllowed:
            return "Bu ihtiyacı açan kişi, üstlenen gönüllü veya doğrulanmış besleyiciler kapatabilir."
        case .failed(let error): return error.userMessage
        }
    }

    public var toastStyle: AppRouter.Toast.Style {
        switch self {
        case .resolved: return .success
        case .notAllowed: return .info
        case .failed: return .warning
        }
    }
}

/// Formda seçilmiş, henüz yüklenmemiş fotoğraf.
public struct NeedPhotoDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let data: Data

    public init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }
}
