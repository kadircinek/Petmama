import Foundation
import MamaCore

/// Ham yanıt gövdesi → domain modeli. Backend ve testler aynı fonksiyonları kullanır.
enum SupabaseDecoding {
    // MARK: Satır listeleri

    static func spots(from data: Data) throws -> [Spot] {
        try SupabaseJSON.rows(SpotRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func needs(from data: Data) throws -> [Need] {
        try SupabaseJSON.rows(NeedRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func animals(from data: Data) throws -> [Animal] {
        try SupabaseJSON.rows(AnimalRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func profiles(from data: Data) throws -> [UserProfile] {
        try SupabaseJSON.rows(ProfileDTO.self, from: data).map { $0.toDomain() }
    }

    /// Gün sırasına göre (eskiden yeniye).
    static func feedingTimeline(from data: Data) throws -> [FeedingDay] {
        try SupabaseJSON.rows(FeedingDayDTO.self, from: data).compactMap { $0.toDomain() }.sorted { $0.day < $1.day }
    }

    static func guardians(from data: Data) throws -> [Guardian] {
        try SupabaseJSON.rows(GuardianDTO.self, from: data).map { $0.toDomain() }
    }

    static func duplicates(from data: Data) throws -> [DuplicateCandidate] {
        try SupabaseJSON.rows(DuplicateDTO.self, from: data).map { $0.toDomain() }.sorted { $0.distanceMeters < $1.distanceMeters }
    }

    static func notifications(from data: Data) throws -> [AppNotification] {
        try SupabaseJSON.rows(NotificationDTO.self, from: data).compactMap { $0.toDomain() }
    }

    /// `community_feed` / `community_post_detail`: sunucu sırası korunur (`created_at` azalan).
    static func communityPosts(from data: Data) throws -> [CommunityPost] {
        try SupabaseJSON.rows(CommunityPostRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    /// `community_comments_of`: sunucu sırası korunur (`created_at` artan).
    static func communityComments(from data: Data) throws -> [CommunityComment] {
        try SupabaseJSON.rows(CommunityCommentRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func communityVolunteers(from data: Data) throws -> [CommunityVolunteer] {
        try SupabaseJSON.rows(CommunityVolunteerDTO.self, from: data).map { $0.toDomain() }
    }

    // MARK: Tek satır dönen `table(...)` RPC'leri

    static func profileStats(from data: Data) throws -> ProfileStats {
        try SupabaseJSON.rows(ProfileStatsDTO.self, from: data).first?.toDomain() ?? .zero
    }

    static func neighborhoodSummary(from data: Data) throws -> NeighborhoodSummary {
        try SupabaseJSON.rows(NeighborhoodSummaryDTO.self, from: data).first?.toDomain() ?? .empty
    }

    static func notificationPreferences(from data: Data) throws -> NotificationPreferences? {
        try SupabaseJSON.rows(NotificationPrefsDTO.self, from: data).first?.toDomain()
    }

    static func donationOverview(from data: Data) throws -> DonationOverview? {
        try SupabaseJSON.rows(DonationOverviewDTO.self, from: data).first?.toDomain()
    }

    static func communitySummary(from data: Data) throws -> CommunitySummary {
        try SupabaseJSON.rows(CommunitySummaryDTO.self, from: data).first?.toDomain() ?? .empty
    }

    // MARK: jsonb `status` sonuçları

    static func createSpotOutcome(from data: Data) throws -> CreateSpotOutcome {
        try SupabaseJSON.object(CreateSpotResultDTO.self, from: data).toDomain()
    }

    static func checkInOutcome(from data: Data, kind: CheckInKind, fallbackId: UUID) throws -> CheckInOutcome {
        try SupabaseJSON.object(CheckInResultDTO.self, from: data).toDomain(kind: kind, fallbackId: fallbackId)
    }

    static func claimOutcome(from data: Data) throws -> ClaimOutcome {
        try SupabaseJSON.object(StatusResultDTO.self, from: data).claimOutcome()
    }

    static func resolveAllowed(from data: Data) throws -> Bool {
        try SupabaseJSON.object(StatusResultDTO.self, from: data).resolveAllowed()
    }

    static func goneReportOutcome(from data: Data) throws -> GoneReportOutcome {
        try SupabaseJSON.object(StatusResultDTO.self, from: data).goneReportOutcome()
    }

    // MARK: Mahalle jsonb sonuçları

    static func createPostOutcome(from data: Data) throws -> CreatePostOutcome {
        try SupabaseJSON.object(CommunityResultDTO.self, from: data).createPostOutcome()
    }

    static func commentOutcome(from data: Data) throws -> CommentOutcome {
        try SupabaseJSON.object(CommunityResultDTO.self, from: data).commentOutcome()
    }

    /// `nil` = `post_not_found`.
    static func pawToggleResult(from data: Data) throws -> PawToggleResult? {
        try SupabaseJSON.object(CommunityResultDTO.self, from: data).pawToggleResult()
    }

    static func coverVolunteerOutcome(from data: Data) throws -> CoverVolunteerOutcome {
        try SupabaseJSON.object(CommunityResultDTO.self, from: data).coverVolunteerOutcome()
    }

    static func communityDeleteAllowed(from data: Data, rpc: String) throws -> Bool {
        try SupabaseJSON.object(CommunityResultDTO.self, from: data).deleteAllowed(rpc: rpc)
    }

    /// `create_need` → `uuid`.
    static func createdId(from data: Data) throws -> UUID {
        guard let id = SupabaseJSON.scalarUUID(from: data) else {
            throw MamaError.server("Beklenmeyen sunucu yanıtı: uuid bekleniyordu")
        }
        return id
    }
}
