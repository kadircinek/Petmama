import Foundation
import Observation

/// Oturum durumu. Haritayı gezmek için giriş gerekmez; check-in ve nokta eklemek için gerekir (FR-P1).
@MainActor
@Observable
public final class SessionStore {
    public private(set) var profile: UserProfile?
    public private(set) var isRestoring = false
    public private(set) var lastError: MamaError?

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let profiles: any ProfileRepository

    public init(auth: any AuthRepository, profiles: any ProfileRepository, profile: UserProfile? = nil) {
        self.auth = auth
        self.profiles = profiles
        self.profile = profile
    }

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
        try? await auth.signOut()
        profile = nil
    }

    /// FR-P3. Başarılıysa oturum kapanır.
    @discardableResult
    public func deleteAccount() async -> Bool {
        do {
            try await auth.deleteAccount()
            profile = nil
            return true
        } catch {
            lastError = MamaError.classify(error)
            return false
        }
    }

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
