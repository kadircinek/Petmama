import Foundation

public enum MamaError: Error, Equatable, Sendable {
    /// Bu işlem için giriş gerekiyor (FR-P1).
    case notSignedIn
    /// Bağlantı yok veya zaman aşımı.
    case offline
    case notFound
    case invalidCredentials
    case emailAlreadyInUse
    case invalidInput(String)
    case rejectedContent
    case permissionDenied
    case server(String)

    /// Kullanıcıya gösterilecek sıcak, suçlayıcı olmayan mesaj (PRD 6.4 "Ton").
    public var userMessage: String {
        switch self {
        case .notSignedIn: return "Bunu yapmak için giriş yapman gerekiyor."
        case .offline: return "Şu an bağlantı yok. Bağlantı gelince tekrar deneriz."
        case .notFound: return "Aradığın kayıt artık yok gibi görünüyor."
        case .invalidCredentials: return "E-posta veya şifre eşleşmedi."
        case .emailAlreadyInUse: return "Bu e-posta ile zaten bir hesap var."
        case .invalidInput(let message): return message
        case .rejectedContent: return "Metinde uygunsuz bir ifade var gibi görünüyor. Biraz düzenler misin?"
        case .permissionDenied: return "Bu işlem için yetkin yok."
        case .server: return "Bir şeyler ters gitti. Birazdan tekrar dener misin?"
        }
    }

    /// URLError ve benzeri hataları bağlantı hatası olarak sınıflandırır.
    public static func classify(_ error: Error) -> MamaError {
        if let mama = error as? MamaError { return mama }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            default:
                return .server(urlError.localizedDescription)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .offline }
        return .server(String(describing: error))
    }

    public var isConnectivity: Bool { self == .offline }
}
