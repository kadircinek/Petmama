import Foundation
import MamaCore
import Supabase

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// supabase-swift hatalarını `MamaError`'a çevirir.
enum SupabaseErrorMapper {
    static let invalidSignUpMessage = "Geçerli bir e-posta ve en az 8 karakterli şifre gir."
    static let weakPasswordMessage = "Daha güçlü bir şifre seç: en az 8 karakter, harf ve rakam karışık."
    static let emailNotConfirmedMessage = "E-postana gelen bağlantıyla hesabını doğrula, sonra giriş yap."
    static let invalidValueMessage = "Girdiğin bilgilerden biri geçersiz görünüyor. Kontrol edip tekrar dener misin?"
    static let invalidLocationMessage = "Konum bilgisi geçersiz görünüyor. Tekrar dener misin?"
    static let photoTooLargeMessage = "Fotoğraf çok büyük. Başka bir fotoğraf dener misin?"

    static func map(_ error: any Error) -> any Error {
        // İptal, çağıranın görmezden gelebilmesi için olduğu gibi kalır.
        if error is CancellationError { return error }
        return mamaError(error)
    }

    static func mamaError(_ error: any Error) -> MamaError {
        switch error {
        case let error as MamaError:
            return error
        case let error as URLError:
            return MamaError.classify(error)
        case let error as AuthError:
            return map(auth: error)
        case let error as PostgrestError:
            return map(postgrest: error)
        case let error as HTTPError:
            return map(status: error.response.statusCode, message: String(decoding: error.data, as: UTF8.self))
        case let error as FunctionsError:
            switch error {
            case .httpError(let code, let data):
                return map(status: code, message: String(decoding: data, as: UTF8.self))
            case .relayError:
                return .server("Edge function relay error")
            }
        case let error as StorageError:
            return map(storage: error)
        case is DecodingError:
            return .server("Beklenmeyen sunucu yanıtı: \(error)")
        default:
            return MamaError.classify(error)
        }
    }

    // MARK: - Auth

    static func map(auth error: AuthError) -> MamaError {
        switch error {
        case .sessionMissing:
            return .notSignedIn
        case .weakPassword:
            return .invalidInput(weakPasswordMessage)
        case .api(let message, let code, _, let response):
            return map(authCode: code, message: message, status: response.statusCode)
        case .jwtVerificationFailed:
            return .notSignedIn
        default:
            return .server(error.message)
        }
    }

    static func map(authCode code: ErrorCode, message: String, status: Int) -> MamaError {
        let lowered = message.lowercased()
        switch code {
        case .invalidCredentials:
            return .invalidCredentials
        case .userAlreadyExists, .emailExists, .identityAlreadyExists:
            return .emailAlreadyInUse
        case .emailNotConfirmed:
            return .invalidInput(emailNotConfirmedMessage)
        case .weakPassword:
            return .invalidInput(weakPasswordMessage)
        case .validationFailed, .emailAddressNotAuthorized:
            return .invalidInput(invalidSignUpMessage)
        case .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed,
             .badJWT, .invalidJWT, .noAuthorization, .userNotFound:
            return .notSignedIn
        case .userBanned, .signupDisabled, .providerDisabled, .emailProviderDisabled:
            return .permissionDenied
        default:
            break
        }
        // Eski GoTrue sürümleri hata kodu göndermez; mesajdan tanı.
        if lowered.contains("invalid login credentials") || lowered.contains("invalid_grant") {
            return .invalidCredentials
        }
        if lowered.contains("already registered") || lowered.contains("already exists") {
            return .emailAlreadyInUse
        }
        if lowered.contains("email not confirmed") {
            return .invalidInput(emailNotConfirmedMessage)
        }
        if status == 401 { return .notSignedIn }
        if status == 403 { return .permissionDenied }
        return .server(message)
    }

    // MARK: - PostgREST

    static func map(postgrest error: PostgrestError) -> MamaError {
        let message = error.message
        let lowered = message.lowercased()
        let code = error.code ?? ""

        // Sözleşmedeki `raise exception` mesajları (supabase/migrations).
        switch lowered {
        case "not_authenticated": return .notSignedIn
        case "rejected_content": return .rejectedContent
        case "invalid_coordinates": return .invalidInput(invalidLocationMessage)
        case "not_found": return .notFound
        default: break
        }
        if error.hint?.lowercased() == "profanity" { return .rejectedContent }

        switch code {
        case "PGRST301", "PGRST302", "PGRST303":
            // JWT süresi dolmuş / geçersiz / anonim erişim kapalı.
            return .notSignedIn
        case "PGRST116":
            return .notFound
        case "42501":
            return lowered.contains("not authenticated") ? .notSignedIn : .permissionDenied
        case "23503":
            // Yabancı anahtar: hedef kayıt (nokta, hayvan) artık yok.
            return .notFound
        case "22023":
            return lowered.contains("coordinat") ? .invalidInput(invalidLocationMessage) : .invalidInput(invalidValueMessage)
        case "23514", "22001", "22P02", "23502":
            return .invalidInput(invalidValueMessage)
        default:
            break
        }
        if lowered.contains("not authenticated") || lowered.contains("jwt expired") { return .notSignedIn }
        if lowered.contains("permission denied") || lowered.contains("row-level security") { return .permissionDenied }
        return .server(message)
    }

    static func isUniqueViolation(_ error: any Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }

    // MARK: - HTTP / Storage

    static func map(status: Int, message: String) -> MamaError {
        // delete-account: Apple hesabında onay kodu eksik / süresi dolmuş (istemci yeniden Apple onayı alır).
        if status == 400, message.contains("apple_reauth_required") {
            return .invalidInput(SessionStore.appleConfirmationRequiredMessage)
        }
        switch status {
        case 401: return .notSignedIn
        case 403: return .permissionDenied
        case 404: return .notFound
        case 413: return .invalidInput(photoTooLargeMessage)
        default: return .server("HTTP \(status): \(message)")
        }
    }

    static func map(storage error: StorageError) -> MamaError {
        let lowered = error.message.lowercased()
        if lowered.contains("row-level security") || (lowered.contains("unauthorized") && error.statusCode == "403") {
            return .permissionDenied
        }
        if let status = error.statusCode.flatMap(Int.init) {
            if status == 400, lowered.contains("jwt") { return .notSignedIn }
            return map(status: status, message: error.message)
        }
        if lowered.contains("payload too large") || lowered.contains("maximum allowed size") {
            return .invalidInput(photoTooLargeMessage)
        }
        return .server(error.message)
    }
}
