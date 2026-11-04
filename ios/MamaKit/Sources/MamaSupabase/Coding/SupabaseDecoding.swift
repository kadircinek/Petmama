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

    /// `create_need` → `uuid`.
    static func createdId(from data: Data) throws -> UUID {
        guard let id = SupabaseJSON.scalarUUID(from: data) else {
            throw MamaError.server("Beklenmeyen sunucu yanıtı: uuid bekleniyordu")
        }
        return id
    }
}
