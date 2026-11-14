#if canImport(UIKit)
import AuthenticationServices
import UIKit

/// Hesap silmeden önce Apple ile yeniden onay: tek kullanımlık `authorizationCode` döner (≈5 dk geçerli).
/// Sunucu (`delete-account`) bu kodla Apple token'ını iptal eder (App Store 5.1.1(v)).
@MainActor
enum AppleReauthorization {
    /// Kullanıcı vazgeçerse `CancellationError` atar.
    static func authorizationCode() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let delegate = Delegate()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            controller.performRequests()
            // Delegate zayıf tutulur: yanıt gelene dek canlı kalsın.
            objc_setAssociatedObject(controller, &Delegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private final class Delegate: NSObject, ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding {
        static var key: UInt8 = 0
        var continuation: CheckedContinuation<String, Error>?

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.authorizationCode,
                  let code = String(data: data, encoding: .utf8) else {
                finish(.failure(ASAuthorizationError(.failed)))
                return
            }
            finish(.success(code))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            if (error as? ASAuthorizationError)?.code == .canceled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(error))
            }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }

        private func finish(_ result: Result<String, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }
}
#endif
