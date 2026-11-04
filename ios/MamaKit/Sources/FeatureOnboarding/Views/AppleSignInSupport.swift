#if canImport(UIKit)
import AuthenticationServices
import CryptoKit
import Foundation

/// Sign in with Apple için nonce (Supabase `signInWithIdToken` ile aynı akış):
/// isteğe ham nonce'ın SHA256'sı konur, sunucuya ham nonce gönderilir.
enum AppleSignInNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    /// Kriptografik olarak güvenli rastgele dize (`SystemRandomNumberGenerator` Apple platformlarında CSPRNG'dir).
    static func random(length: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<max(16, length)).map { _ in charset.randomElement(using: &generator) ?? "0" })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// `ASAuthorization` sonucundan token ve ad.
struct AppleCredentialPayload {
    let idToken: String
    let fullName: String?

    init?(authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            return nil
        }
        idToken = token
        // Ad yalnızca ilk girişte gelir; sonrakilerde boş.
        if let components = credential.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            fullName = formatted.isEmpty ? nil : formatted
        } else {
            fullName = nil
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}
#endif
