import Foundation
import MamaCore
import Supabase

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// MamaCore repository protokollerinin Supabase implementasyonu (docs/backend-contract.md).
///
/// - Konum içeren tüm okumalar `security definer` RPC'ler üzerinden yapılır (PRD 9.1).
/// - Doğrudan tablo erişimi yalnızca sözleşmedeki RLS matrisinin izin verdiği tablolarda.
/// - Oturum gerektiren işlemler ağa çıkmadan önce yerelde kontrol edilir (`MamaError.notSignedIn`),
///   böylece `OfflineCheckInQueue` oturumsuz check-in'i kuyruğa almaz.
/// - Tüm hatalar `MamaError`'a çevrilir (`URLError` → `.offline`).
///
/// Değişken durum tutmaz; oturum `SupabaseClient.auth` içindedir.
public final class SupabaseBackend: Sendable {
    /// Sunucunun profil adı varsayılanı (`profiles.display_name default 'Mama Dostu'`).
    public static let placeholderDisplayName = "Mama Dostu"

    public let client: SupabaseClient
    let now: @Sendable () -> Date

    public init(client: SupabaseClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    /// - Parameter authRedirectURL: Şifre sıfırlama / e-posta doğrulama bağlantılarının döneceği adres (deep link).
    public convenience init(
        url: URL,
        anonKey: String,
        authRedirectURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: Self.defaultAuthStorage(),
                    redirectToURL: authRedirectURL,
                    // Oturum `currentSession` ile okunur; ilk oturum olayına güvenilmez. `true`, 2.x'te her
                    // açılışta tetiklenen "initial session" reportIssue uyarısını da kapatır.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        self.init(client: client, now: now)
    }

    /// Apple platformlarında Keychain; Linux'ta (testler, CI) bellek içi.
    static func defaultAuthStorage() -> any AuthLocalStorage {
        #if os(Linux) || os(Android)
        return InMemoryAuthLocalStorage()
        #else
        return AuthClient.Configuration.defaultLocalStorage
        #endif
    }

    // MARK: - Ortak yardımcılar

    /// Hataları `MamaError`'a çevirerek çalıştırır.
    func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// Yerel oturumdaki kullanıcı. Süresi dolmuş erişim jetonunu istek sırasında supabase-swift yeniler.
    var signedInUserId: UUID? {
        client.auth.currentSession?.user.id
    }

    func requireUserId() throws -> UUID {
        guard let userId = signedInUserId else { throw MamaError.notSignedIn }
        return userId
    }

    /// `POST /rpc/<name>` ve ham yanıt gövdesi.
    func rpc(_ name: String, _ params: JSONObject = [:]) async throws -> Data {
        let builder = params.isEmpty ? try client.rpc(name) : try client.rpc(name, params: params)
        let response: PostgrestResponse<Void> = try await builder.execute()
        return response.data
    }

    func fetchProfile(id: UUID) async throws -> UserProfile? {
        let response: PostgrestResponse<Void> = try await client.from("profiles")
            .select()
            .eq("id", value: id.postgresString)
            .limit(1)
            .execute()
        return try SupabaseDecoding.profiles(from: response.data).first
    }

    /// Profil satırı normalde `auth.users` trigger'ıyla oluşur; yoksa (eski hesap, yarış) eklemeyi dener.
    func ensureProfile(userId: UUID, preferredName: String) async throws -> UserProfile {
        if let existing = try await fetchProfile(id: userId) { return existing }
        let name = Self.sanitizedName(preferredName) ?? Self.placeholderDisplayName
        do {
            let response: PostgrestResponse<Void> = try await client.from("profiles")
                .insert(["id": Param.uuid(userId), "display_name": .string(name)] as JSONObject, returning: .representation)
                .select()
                .execute()
            if let created = try SupabaseDecoding.profiles(from: response.data).first { return created }
        } catch {
            if let existing = try? await fetchProfile(id: userId) { return existing }
        }
        return UserProfile(id: userId, displayName: name, createdAt: now())
    }

    func updateOwnProfile(userId: UUID, fields: JSONObject) async throws -> UserProfile {
        let response: PostgrestResponse<Void> = try await client.from("profiles")
            .update(fields, returning: .representation)
            .eq("id", value: userId.postgresString)
            .select()
            .execute()
        guard let profile = try SupabaseDecoding.profiles(from: response.data).first else { throw MamaError.notFound }
        return profile
    }

    static func sanitizedName(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }

    static func isPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == placeholderDisplayName
    }
}

// MARK: - AuthRepository

extension SupabaseBackend: AuthRepository {
    public func currentUserId() async -> UUID? {
        signedInUserId
    }

    public func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> UserProfile {
        try await perform {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            let userId = session.user.id
            let name = Self.sanitizedName(fullName)
            let profile = try await ensureProfile(userId: userId, preferredName: name ?? "")
            // Apple adı yalnızca ilk girişte verir; profil hâlâ varsayılan addaysa yaz.
            if let name, Self.isPlaceholderName(profile.displayName) {
                return (try? await updateOwnProfile(userId: userId, fields: ["display_name": .string(name)])) ?? profile
            }
            return profile
        }
    }

    public func signIn(email: String, password: String) async throws -> UserProfile {
        try await perform {
            let session = try await client.auth.signIn(email: Self.normalizedEmail(email), password: password)
            return try await ensureProfile(userId: session.user.id, preferredName: "")
        }
    }

    public func signUp(email: String, password: String, displayName: String) async throws -> UserProfile {
        try await perform {
            let key = Self.normalizedEmail(email)
            guard key.contains("@"), password.count >= 8 else {
                throw MamaError.invalidInput(SupabaseErrorMapper.invalidSignUpMessage)
            }
            let name = Self.sanitizedName(displayName)
            // handle_new_user trigger'ı profili `display_name` metadata'sından oluşturur.
            let metadata: JSONObject? = name.map { ["display_name": .string($0)] }
            let response = try await client.auth.signUp(email: key, password: password, data: metadata)
            guard let session = response.session else {
                // E-posta doğrulaması açıksa oturum gelmez. Kayıtlı e-postada GoTrue kimliksiz sahte kullanıcı döner.
                if response.user.identities?.isEmpty == true { throw MamaError.emailAlreadyInUse }
                throw MamaError.invalidInput(SupabaseErrorMapper.emailNotConfirmedMessage)
            }
            return try await ensureProfile(userId: session.user.id, preferredName: name ?? "")
        }
    }

    public func sendPasswordReset(email: String) async throws {
        try await perform {
            try await client.auth.resetPasswordForEmail(Self.normalizedEmail(email))
        }
    }

    public func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            // Yerel oturum ağ çağrısından önce silinir; çevrimdışıyken de çıkış yapılmış sayılır.
            if client.auth.currentSession == nil { return }
            throw SupabaseErrorMapper.map(error)
        }
    }

    public func deleteAccount() async throws {
        try await perform {
            _ = try requireUserId()
            try await client.functions.invoke("delete-account")
            // Kullanıcı sunucuda silindi; logout çağrısı 401/404 dönebilir, yerel oturum yine kapanır.
            try? await client.auth.signOut(scope: .local)
        }
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Linux için oturum deposu

#if os(Linux) || os(Android)
/// Keychain olmayan platformlarda oturumu süreç ömrü boyunca bellekte tutar.
final class InMemoryAuthLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}
#endif
