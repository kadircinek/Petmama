import Foundation

// Backend'den bağımsız veri sözleşmeleri. İki implementasyon var:
//   - `InMemoryBackend` (demo modu, önizlemeler, testler)
//   - `MamaSupabase` modülündeki Supabase implementasyonu
// Sunucu tarafı isimler: docs/backend-contract.md

public protocol AuthRepository: Sendable {
    func currentUserId() async -> UUID?
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> UserProfile
    func signIn(email: String, password: String) async throws -> UserProfile
    func signUp(email: String, password: String, displayName: String) async throws -> UserProfile
    func sendPasswordReset(email: String) async throws
    func signOut() async throws
    /// Uygulama içinden hesap silme (FR-P3). Kişisel veri silinir, topluluk verisi anonimleşir.
    func deleteAccount() async throws
}

public protocol SpotRepository: Sendable {
    func spots(in bounds: GeoBounds) async throws -> [Spot]
    func spots(near center: Coordinate, radiusMeters: Int) async throws -> [Spot]
    func spot(id: UUID) async throws -> Spot?
    func search(query: String, near center: Coordinate?) async throws -> [Spot]
    func feedingTimeline(spotId: UUID, days: Int) async throws -> [FeedingDay]
    func guardians(spotId: UUID) async throws -> [Guardian]
    func duplicates(near coordinate: Coordinate) async throws -> [DuplicateCandidate]
    func createSpot(_ draft: SpotDraft) async throws -> CreateSpotOutcome
    func reportGone(spotId: UUID) async throws -> GoneReportOutcome
    func neighborhoodSummary(near center: Coordinate) async throws -> NeighborhoodSummary
}

public protocol CheckInRepository: Sendable {
    func checkIn(_ draft: CheckInDraft) async throws -> CheckInOutcome
}

public protocol AnimalRepository: Sendable {
    func animals(atSpot spotId: UUID) async throws -> [Animal]
    func animal(id: UUID) async throws -> Animal?
    func spots(forAnimal animalId: UUID) async throws -> [Spot]
    func createAnimal(_ draft: AnimalDraft) async throws -> Animal
    func markSeen(animalId: UUID, spotId: UUID) async throws
}

public protocol NeedRepository: Sendable {
    func needs(near center: Coordinate, radiusMeters: Int, includeResolved: Bool) async throws -> [Need]
    func needs(spotId: UUID?, animalId: UUID?, includeResolved: Bool) async throws -> [Need]
    func need(id: UUID) async throws -> Need?
    func createNeed(_ draft: NeedDraft) async throws -> UUID
    func claim(needId: UUID) async throws -> ClaimOutcome
    /// `false` = kullanıcının bu ihtiyacı kapatma yetkisi yok.
    func resolve(needId: UUID) async throws -> Bool
}

public protocol ProfileRepository: Sendable {
    func profile(id: UUID) async throws -> UserProfile?
    func stats(userId: UUID) async throws -> ProfileStats
    func updateProfile(displayName: String, neighborhood: String?, avatarURL: URL?) async throws -> UserProfile

    func followedSpotIds() async throws -> Set<UUID>
    func followedSpots() async throws -> [Spot]
    func followedAnimals() async throws -> [Animal]
    func setFollowing(_ following: Bool, target: FollowTarget, id: UUID) async throws

    func guardedSpotIds() async throws -> Set<UUID>
    /// `schedule == nil` koruyuculuktan çıkar.
    func setGuardian(spotId: UUID, schedule: Set<Weekday>?) async throws
}

public protocol NotificationRepository: Sendable {
    func notifications() async throws -> [AppNotification]
    func markRead(ids: [UUID]) async throws
    func preferences() async throws -> NotificationPreferences
    func updatePreferences(_ preferences: NotificationPreferences) async throws
    func registerDeviceToken(_ token: String) async throws
    /// Yakındaki bildirimler için yalnızca son kaba konum (D8).
    func updateNotifyCenter(_ coordinate: Coordinate) async throws
}

public protocol ModerationRepository: Sendable {
    func report(_ draft: ReportDraft) async throws
    func block(userId: UUID) async throws
    func unblock(userId: UUID) async throws
    func blockedUserIds() async throws -> Set<UUID>
}

public protocol DonationRepository: Sendable {
    func overview() async throws -> DonationOverview?
    /// Yalnızca "bağış sayfasına gidildi" olayı ölçülür (PRD 8.2).
    func logDonationClick(refCode: String) async throws
}

public protocol MediaUploader: Sendable {
    /// EXIF temizlenmiş ve küçültülmüş JPEG yükler, herkese açık URL döner.
    func uploadJPEG(_ data: Data) async throws -> URL
}

/// Son görülen harita bölgesi ve noktalarının çevrimdışı önbelleği (FR-H8).
public protocol SpotCache: Sendable {
    func store(_ spots: [Spot], for bounds: GeoBounds) async
    func cachedSpots(in bounds: GeoBounds) async -> [Spot]
    func lastBounds() async -> GeoBounds?
}

/// Çevrimdışı check-in kuyruğunun kalıcı deposu.
public protocol PendingCheckInStore: Sendable {
    func load() async -> [CheckInDraft]
    func save(_ drafts: [CheckInDraft]) async
}
