import Foundation
import Observation

/// Oturum durumu. Haritayı gezmek için giriş gerekmez; check-in ve nokta eklemek için gerekir (FR-P1).
@MainActor
@Observable
public final class SessionStore {
    public private(set) var profile: UserProfile?
    public private(set) var isRestoring = false
    public private(set) var lastError: MamaError?

    /// Çıkıştan hemen önce, oturum hâlâ açıkken çağrılır (ör. cihaz token'ını sunucudan silmek için).
    @ObservationIgnored public var willEndSession: (@MainActor () async -> Void)?
    /// Çıkış veya hesap silme tamamlanınca çağrılır (ör. çevrimdışı kuyruğu temizlemek için).
    @ObservationIgnored public var didEndSession: (@MainActor () async -> Void)?

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let profiles: any ProfileRepository

    public init(auth: any AuthRepository, profiles: any ProfileRepository, profile: UserProfile? = nil) {
        self.auth = auth
        self.profiles = profiles
        self.profile = profile
    }

    /// Şifre sıfırlama bağlantısıyla girildi; "yeni şifre" ekranı gösterilmeli.
    public private(set) var isRecoveringPassword = false

    public var isSignedIn: Bool { profile != nil }
    public var userId: UUID? { profile?.id }

    public func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        guard let id = await auth.currentUserId() else {
            profile = nil
            return
        }
        profile = try? await profiles.profile(id: id)
    }

    @discardableResult
    public func signInWithApple(idToken: String, nonce: String, fullName: String?) async -> Bool {
        await perform { try await self.auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName) }
    }

    @discardableResult
    public func signIn(email: String, password: String) async -> Bool {
        await perform { try await self.auth.signIn(email: email, password: password) }
    }

    @discardableResult
    public func signUp(email: String, password: String, displayName: String) async -> Bool {
        await perform { try await self.auth.signUp(email: email, password: password, displayName: displayName) }
    }

    public func signOut() async {
        await willEndSession?()
        try? await auth.signOut()
        profile = nil
        isRecoveringPassword = false
        await didEndSession?()
    }

    /// FR-P3. Başarılıysa oturum kapanır.
    @discardableResult
    public func deleteAccount(appleAuthorizationCode: String? = nil) async -> Bool {
        do {
            try await auth.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
            profile = nil
            // Sunucu hesabı silerken cihaz token'ları da cascade ile silinir.
            await didEndSession?()
            return true
        } catch {
            lastError = MamaError.classify(error)
            return false
        }
    }

    /// E-posta doğrulama / şifre sıfırlama bağlantısını işler. Bizim bağlantımız değilse `nil`.
    public func handleAuthLink(_ url: URL) async -> AuthLink.Kind? {
        guard let kind = AuthLink.parse(url) else { return nil }
        if case .failed(let message) = kind {
            lastError = .invalidInput(message)
            return kind
        }
        guard await perform({ try await self.auth.completeAuthLink(url) }) else {
            return .failed((lastError ?? .server("auth-link")).userMessage)
        }
        isRecoveringPassword = kind == .passwordRecovery
        return kind
    }

    @discardableResult
    public func updatePassword(_ newPassword: String) async -> Bool {
        lastError = nil
        guard newPassword.count >= Self.minimumPasswordLength else {
            lastError = .invalidInput("Şifren en az \(Self.minimumPasswordLength) karakter olmalı.")
            return false
        }
        do {
            try await auth.updatePassword(newPassword)
            isRecoveringPassword = false
            return true
        } catch {
            lastError = MamaError.classify(error)
            return false
        }
    }

    /// Kullanıcı yeni şifre belirlemeden kapattı; oturum açık kalır.
    public func dismissPasswordRecovery() {
        isRecoveringPassword = false
    }

    public static let minimumPasswordLength = 8
    public static let appleConfirmationRequiredMessage =
        "Hesabını silmek için Apple ile bir kez daha onaylaman gerekiyor."

    public func update(_ profile: UserProfile) {
        self.profile = profile
    }

    public func clearError() {
        lastError = nil
    }

    private func perform(_ operation: @escaping () async throws -> UserProfile) async -> Bool {
        lastError = nil
        do {
            profile = try await operation()
            return true
        } catch {
            lastError = MamaError.classify(error)
            return false
        }
    }
}
