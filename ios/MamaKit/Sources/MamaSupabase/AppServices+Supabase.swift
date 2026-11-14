import Foundation
import MamaCore

extension AppServices {
    /// Gerçek backend'e bağlı servisler. Check-in'ler `AppServices.inMemory` ile aynı şekilde
    /// `OfflineCheckInQueue` üzerinden gider (bağlantı yoksa kuyruğa alınır, FR-H8).
    ///
    /// - Parameters:
    ///   - url: Supabase proje adresi (`https://<ref>.supabase.co`).
    ///   - anonKey: Herkese açık anon/publishable anahtar. Gizli (service_role) anahtar asla istemciye konmaz.
    ///   - spotCache: Çevrimdışı harita önbelleği (ör. `MamaPersistence.SwiftDataStore`).
    ///   - pendingStore: Çevrimdışı check-in kuyruğunun kalıcı deposu.
    ///   - authRedirectURL: Şifre sıfırlama / e-posta doğrulama bağlantılarının döneceği deep link.
    public static func supabase(
        url: URL,
        anonKey: String,
        config: AppConfig,
        spotCache: any SpotCache,
        pendingStore: any PendingCheckInStore,
        authRedirectURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AppServices {
        let backend = SupabaseBackend(url: url, anonKey: anonKey, authRedirectURL: authRedirectURL, now: now)
        return supabase(backend: backend, config: config, spotCache: spotCache, pendingStore: pendingStore, now: now)
    }

    /// Hazır bir `SupabaseBackend` ile (ör. özel `SupabaseClient` yapılandırması).
    public static func supabase(
        backend: SupabaseBackend,
        config: AppConfig,
        spotCache: any SpotCache,
        pendingStore: any PendingCheckInStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AppServices {
        let queue = OfflineCheckInQueue(store: pendingStore, repository: backend)
        return AppServices(
            auth: backend,
            spots: backend,
            checkIns: queue,
            animals: backend,
            needs: backend,
            profiles: backend,
            notifications: backend,
            moderation: backend,
            donations: backend,
            community: backend,
            social: UnavailableSocialRepository(),
            chatUpdates: PollingChatUpdates(),
            media: backend,
            spotCache: spotCache,
            checkInQueue: queue,
            config: config,
            now: now
        )
    }
}

/// Geçici: Supabase sosyal eşlemesi gelene kadar (Tanışma görev 7) her çağrı sunucu hatası verir.
/// Sosyal ekranlar henüz yok; bu tip yalnızca `AppServices` kurulsun diye var.
struct UnavailableSocialRepository: SocialRepository {
    private func unavailable<T>() throws -> T { throw MamaError.server("social_unavailable") }

    func socialProfile() async throws -> SocialProfile? { try unavailable() }
    func giveSocialConsent() async throws -> SocialProfile { try unavailable() }
    func updateSocialProfile(isVisible: Bool, about: String, interests: [SocialInterest], at coordinate: Coordinate?) async throws -> SocialProfileOutcome { try unavailable() }
    func meetups(near center: Coordinate, radiusMeters: Int) async throws -> [Meetup] { try unavailable() }
    func meetup(id: UUID, near center: Coordinate?) async throws -> Meetup? { try unavailable() }
    func meetupParticipants(meetupId: UUID) async throws -> [MeetupParticipant] { try unavailable() }
    func createMeetup(_ draft: MeetupDraft) async throws -> CreateMeetupOutcome { try unavailable() }
    func joinMeetup(id: UUID) async throws -> JoinMeetupOutcome { try unavailable() }
    func leaveMeetup(id: UUID) async throws -> Bool { try unavailable() }
    func removeParticipant(meetupId: UUID, userId: UUID) async throws -> Bool { try unavailable() }
    func cancelMeetup(id: UUID) async throws -> Bool { try unavailable() }
    func animalLovers(interest: SocialInterest?) async throws -> [AnimalLover] { try unavailable() }
    func sendConnectionRequest(to userId: UUID, note: String?) async throws -> SendRequestOutcome { try unavailable() }
    func respondToConnection(requestId: UUID, accept: Bool) async throws -> UUID? { try unavailable() }
    func withdrawConnectionRequest(id: UUID) async throws { try unavailable() as Void }
    func removeConnection(userId: UUID) async throws { try unavailable() as Void }
    func incomingConnectionRequests() async throws -> [ConnectionRequest] { try unavailable() }
    func conversations() async throws -> [ConversationSummary] { try unavailable() }
    func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] { try unavailable() }
    func sendMessage(conversationId: UUID, body: String) async throws -> SendMessageOutcome { try unavailable() }
    func markConversationRead(id: UUID) async throws { try unavailable() as Void }
}
