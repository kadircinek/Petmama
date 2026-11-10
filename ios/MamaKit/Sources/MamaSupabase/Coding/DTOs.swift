import Foundation
import MamaCore

// Sunucu satırları (docs/backend-contract.md). Alanlar bilerek gevşek: neredeyse hepsi opsiyonel,
// enum ve tarihler String. Eşleme sırasında bilinmeyen enum değeri makul bir varsayılana düşer
// ya da (anlamı değişecekse) satır atlanır.

private func date(_ text: String?) -> Date? {
    text.flatMap(PostgresDate.parse)
}

private let unknownDate = Date(timeIntervalSince1970: 0)

// MARK: - spot_row

struct SpotRowDTO: Decodable {
    var id: UUID
    var lat: Double?
    var lng: Double?
    var isLocationExact: Bool?
    var type: String?
    var species: String?
    var title: String?
    var note: String?
    var photoUrl: String?
    var status: String?
    var lastFedAt: String?
    var hasUrgentNeed: Bool?
    var openNeedCount: Int?
    var visibility: String?
    var isActive: Bool?
    var createdBy: UUID?
    var createdAt: String?
    var animalCount: Int?
    var guardianCount: Int?
    var distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case id, lat, lng
        case isLocationExact = "is_location_exact"
        case type, species, title, note
        case photoUrl = "photo_url"
        case status
        case lastFedAt = "last_fed_at"
        case hasUrgentNeed = "has_urgent_need"
        case openNeedCount = "open_need_count"
        case visibility
        case isActive = "is_active"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case animalCount = "animal_count"
        case guardianCount = "guardian_count"
        case distanceM = "distance_m"
    }

    /// Koordinatı olmayan satır haritada gösterilemez → `nil`.
    func toDomain() -> Spot? {
        guard let lat, let lng else { return nil }
        return Spot(
            id: id,
            coordinate: Coordinate(latitude: lat, longitude: lng),
            isLocationExact: isLocationExact ?? false,
            type: type.flatMap(SpotType.init(rawValue:)) ?? .mixed,
            species: species.flatMap(SpotSpecies.init(rawValue:)) ?? .both,
            title: title ?? "",
            note: note,
            photoURL: photoUrl?.nonEmptyURL,
            status: status.flatMap(SpotStatus.init(rawValue:)) ?? .unknown,
            lastFedAt: date(lastFedAt),
            hasUrgentNeed: hasUrgentNeed ?? false,
            openNeedCount: openNeedCount ?? 0,
            visibility: visibility.flatMap(SpotVisibility.init(rawValue:)) ?? .fuzzed,
            isActive: isActive ?? true,
            createdBy: createdBy,
            createdAt: date(createdAt) ?? unknownDate,
            animalCount: animalCount ?? 0,
            guardianCount: guardianCount ?? 0,
            distanceMeters: distanceM
        )
    }
}

// MARK: - need_row

struct NeedRowDTO: Decodable {
    var id: UUID
    var type: String?
    var urgency: String?
    var status: String?
    var description: String?
    var photos: [String]?
    var spotId: UUID?
    var spotTitle: String?
    var animalId: UUID?
    var animalName: String?
    var animalPhotoUrl: String?
    var lat: Double?
    var lng: Double?
    var isLocationExact: Bool?
    var distanceM: Double?
    var createdBy: UUID?
    var claimedBy: UUID?
    var claimedByName: String?
    var createdAt: String?
    var claimedAt: String?
    var resolvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, urgency, status, description, photos
        case spotId = "spot_id"
        case spotTitle = "spot_title"
        case animalId = "animal_id"
        case animalName = "animal_name"
        case animalPhotoUrl = "animal_photo_url"
        case lat, lng
        case isLocationExact = "is_location_exact"
        case distanceM = "distance_m"
        case createdBy = "created_by"
        case claimedBy = "claimed_by"
        case claimedByName = "claimed_by_name"
        case createdAt = "created_at"
        case claimedAt = "claimed_at"
        case resolvedAt = "resolved_at"
    }

    /// Bilinmeyen ihtiyaç tipi yanlış etiketle gösterilmesin diye atlanır.
    func toDomain() -> Need? {
        guard let type = type.flatMap(NeedType.init(rawValue:)) else { return nil }
        let coordinate: Coordinate?
        if let lat, let lng {
            coordinate = Coordinate(latitude: lat, longitude: lng)
        } else {
            coordinate = nil
        }
        return Need(
            id: id,
            type: type,
            urgency: urgency.flatMap(NeedUrgency.init(rawValue:)) ?? .normal,
            status: status.flatMap(NeedStatus.init(rawValue:)) ?? .open,
            description: description ?? "",
            photoURLs: (photos ?? []).compactMap(\.nonEmptyURL),
            spotId: spotId,
            spotTitle: spotTitle,
            animalId: animalId,
            animalName: animalName,
            animalPhotoURL: animalPhotoUrl?.nonEmptyURL,
            coordinate: coordinate,
            isLocationExact: coordinate == nil ? true : (isLocationExact ?? false),
            distanceMeters: distanceM,
            createdBy: createdBy,
            claimedBy: claimedBy,
            claimedByName: claimedByName,
            createdAt: date(createdAt) ?? unknownDate,
            claimedAt: date(claimedAt),
            resolvedAt: date(resolvedAt)
        )
    }
}

// MARK: - animal_row / animals tablosu

struct AnimalRowDTO: Decodable {
    var id: UUID
    var species: String?
    var name: String?
    var colorPattern: String?
    var sex: String?
    var ageEstimate: String?
    var isNeutered: Bool?
    var earTag: Bool?
    var vaccinationInfo: String?
    var temperamentTags: [String]?
    var warning: String?
    var about: String?
    var photos: [String]?
    var lastSeenAt: String?
    var lastSeenSpotId: UUID?
    var createdBy: UUID?
    var createdAt: String?
    /// Yalnızca `animal_row` (ör. `animals_at_spot`); tablo satırında yok.
    var seenCount: Int?
    var spotLastSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case id, species, name
        case colorPattern = "color_pattern"
        case sex
        case ageEstimate = "age_estimate"
        case isNeutered = "is_neutered"
        case earTag = "ear_tag"
        case vaccinationInfo = "vaccination_info"
        case temperamentTags = "temperament_tags"
        case warning, about, photos
        case lastSeenAt = "last_seen_at"
        case lastSeenSpotId = "last_seen_spot_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case seenCount = "seen_count"
        case spotLastSeenAt = "spot_last_seen_at"
    }

    /// Bilinmeyen tür (kedi/köpek dışı) atlanır; bilinmeyen etiketler düşürülür.
    func toDomain() -> Animal? {
        guard let species = species.flatMap(AnimalSpecies.init(rawValue:)) else { return nil }
        return Animal(
            id: id,
            species: species,
            name: name,
            colorPattern: colorPattern,
            sex: sex.flatMap(AnimalSex.init(rawValue:)) ?? .unknown,
            ageEstimate: ageEstimate.flatMap(AgeEstimate.init(rawValue:)) ?? .unknown,
            isNeutered: isNeutered,
            earTag: earTag ?? false,
            vaccinationInfo: vaccinationInfo,
            temperamentTags: Self.tags(temperamentTags ?? []),
            warning: warning.flatMap(AnimalWarning.init(rawValue:)),
            about: about,
            photoURLs: (photos ?? []).compactMap(\.nonEmptyURL),
            lastSeenAt: date(lastSeenAt),
            lastSeenSpotId: lastSeenSpotId,
            createdBy: createdBy,
            createdAt: date(createdAt) ?? unknownDate,
            seenCount: seenCount
        )
    }

    static func tags(_ raw: [String]) -> [TemperamentTag] {
        var seen = Set<TemperamentTag>()
        return raw.compactMap { TemperamentTag(rawValue: $0) }.filter { seen.insert($0).inserted }
    }
}

// MARK: - profiles

struct ProfileDTO: Decodable {
    var id: UUID
    var displayName: String?
    var avatarUrl: String?
    var neighborhood: String?
    var trustScore: Int?
    var isVerifiedFeeder: Bool?
    var isModerator: Bool?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case neighborhood
        case trustScore = "trust_score"
        case isVerifiedFeeder = "is_verified_feeder"
        case isModerator = "is_moderator"
        case createdAt = "created_at"
    }

    func toDomain() -> UserProfile {
        UserProfile(
            id: id,
            displayName: displayName ?? SupabaseBackend.placeholderDisplayName,
            avatarURL: avatarUrl?.nonEmptyURL,
            neighborhood: neighborhood,
            trustScore: trustScore ?? TrustPolicy.initialTrustScore,
            isVerifiedFeeder: isVerifiedFeeder ?? false,
            isModerator: isModerator ?? false,
            createdAt: date(createdAt) ?? unknownDate
        )
    }
}

struct ProfileStatsDTO: Decodable {
    var fedSpotCount: Int?
    var checkinCount: Int?
    var resolvedNeedCount: Int?
    var verifiedCheckins30d: Int?

    enum CodingKeys: String, CodingKey {
        case fedSpotCount = "fed_spot_count"
        case checkinCount = "checkin_count"
        case resolvedNeedCount = "resolved_need_count"
        case verifiedCheckins30d = "verified_checkins_30d"
    }

    func toDomain() -> ProfileStats {
        ProfileStats(
            fedSpotCount: fedSpotCount ?? 0,
            checkInCount: checkinCount ?? 0,
            resolvedNeedCount: resolvedNeedCount ?? 0,
            verifiedCheckInsLast30Days: verifiedCheckins30d ?? 0
        )
    }
}

// MARK: - Nokta yardımcı satırları

struct FeedingDayDTO: Decodable {
    var day: String
    var fedCount: Int?
    var needCount: Int?
    var lastFedAt: String?

    enum CodingKeys: String, CodingKey {
        case day
        case fedCount = "fed_count"
        case needCount = "need_count"
        case lastFedAt = "last_fed_at"
    }

    func toDomain() -> FeedingDay? {
        guard let parsedDay = PostgresDate.parse(day) else { return nil }
        return FeedingDay(day: parsedDay, fedCount: fedCount ?? 0, needCount: needCount ?? 0, lastFedAt: date(lastFedAt))
    }
}

struct GuardianDTO: Decodable {
    var userId: UUID
    var displayName: String?
    var avatarUrl: String?
    var isVerifiedFeeder: Bool?
    var schedule: [Int]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isVerifiedFeeder = "is_verified_feeder"
        case schedule
    }

    func toDomain() -> Guardian {
        Guardian(
            userId: userId,
            displayName: displayName ?? SupabaseBackend.placeholderDisplayName,
            avatarURL: avatarUrl?.nonEmptyURL,
            isVerifiedFeeder: isVerifiedFeeder ?? false,
            schedule: Set((schedule ?? []).compactMap(Weekday.init(rawValue:)))
        )
    }
}

struct DuplicateDTO: Decodable {
    var id: UUID
    var title: String?
    var distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case id, title
        case distanceM = "distance_m"
    }

    func toDomain() -> DuplicateCandidate {
        DuplicateCandidate(id: id, title: title ?? "", distanceMeters: distanceM ?? 0)
    }
}

struct NeighborhoodSummaryDTO: Decodable {
    var fedSpotsToday: Int?
    var openNeeds: Int?
    var needsFoodSpots: Int?
    var activeSpots7d: Int?

    enum CodingKeys: String, CodingKey {
        case fedSpotsToday = "fed_spots_today"
        case openNeeds = "open_needs"
        case needsFoodSpots = "needs_food_spots"
        case activeSpots7d = "active_spots_7d"
    }

    func toDomain() -> NeighborhoodSummary {
        NeighborhoodSummary(
            fedSpotsToday: fedSpotsToday ?? 0,
            openNeeds: openNeeds ?? 0,
            needsFoodSpots: needsFoodSpots ?? 0,
            activeSpots7d: activeSpots7d ?? 0
        )
    }
}

// MARK: - jsonb `status` sonuçları

struct CreateSpotResultDTO: Decodable {
    var status: String
    var spotId: UUID?
    var moderationState: String?
    var duplicates: [DuplicateDTO]?
    var limit: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case spotId = "spot_id"
        case moderationState = "moderation_state"
        case duplicates, limit
    }

    func toDomain() throws -> CreateSpotOutcome {
        switch status {
        case "created":
            guard let spotId else { throw MamaError.server("create_spot: spot_id eksik") }
            return .created(id: spotId, pendingModeration: moderationState == ModerationState.pending.rawValue)
        case "duplicate":
            return .duplicate((duplicates ?? []).map { $0.toDomain() })
        case "limit_reached":
            return .limitReached(limit: limit ?? TrustPolicy.dailySpotLimitNew)
        case "rejected_content":
            return .rejectedContent
        default:
            throw StatusError.unexpected(rpc: "create_spot", status: status)
        }
    }
}

struct CheckInResultDTO: Decodable {
    var status: String
    var checkinId: UUID?
    var distanceM: Double?
    var maxDistanceM: Double?
    var closedNeedCount: Int?
    var spotStatus: String?

    enum CodingKeys: String, CodingKey {
        case status
        case checkinId = "checkin_id"
        case distanceM = "distance_m"
        case maxDistanceM = "max_distance_m"
        case closedNeedCount = "closed_need_count"
        case spotStatus = "spot_status"
    }

    /// `kind` ve `fallbackId`, sunucu bir alanı eksik bırakırsa kullanılır.
    func toDomain(kind: CheckInKind, fallbackId: UUID) throws -> CheckInOutcome {
        switch status {
        case "ok":
            return .success(CheckInReceipt(
                checkInId: checkinId ?? fallbackId,
                distanceMeters: distanceM ?? 0,
                closedNeedCount: closedNeedCount ?? 0,
                spotStatus: spotStatus.flatMap(SpotStatus.init(rawValue:)) ?? (kind == .fed ? .fedRecent : .unknown)
            ))
        case "too_far":
            return .tooFar(distanceMeters: distanceM ?? 0, maxDistanceMeters: maxDistanceM ?? kind.maxDistanceMeters)
        case "spot_inactive":
            return .spotInactive
        case "rate_limited":
            return .rateLimited
        default:
            throw StatusError.unexpected(rpc: "check_in", status: status)
        }
    }
}

struct StatusResultDTO: Decodable {
    var status: String
    /// `report_spot_gone`
    var count: Int?
    var deactivated: Bool?

    func claimOutcome() throws -> ClaimOutcome {
        guard let outcome = ClaimOutcome(rawValue: status) else {
            throw StatusError.unexpected(rpc: "claim_need", status: status)
        }
        return outcome
    }

    func resolveAllowed() throws -> Bool {
        switch status {
        case "ok": return true
        case "not_allowed": return false
        default: throw StatusError.unexpected(rpc: "resolve_need", status: status)
        }
    }

    func goneReportOutcome() throws -> GoneReportOutcome {
        guard status == "ok" else { throw StatusError.unexpected(rpc: "report_spot_gone", status: status) }
        return GoneReportOutcome(reportCount: count ?? 0, deactivated: deactivated ?? false)
    }
}

/// Sözleşmede olmayan `status` değeri. `not_found` gibi bilinen genel durumlar `MamaError`'a çevrilir.
enum StatusError {
    static func unexpected(rpc: String, status: String) -> MamaError {
        switch status {
        case "not_found": return .notFound
        case "not_authenticated": return .notSignedIn
        case "not_allowed", "forbidden": return .permissionDenied
        case "rejected_content": return .rejectedContent
        default: return .server("\(rpc): beklenmeyen durum '\(status)'")
        }
    }
}

// MARK: - Bildirimler

struct NotificationDTO: Decodable {
    var id: UUID
    var kind: String?
    var title: String?
    var body: String?
    var spotId: UUID?
    var needId: UUID?
    /// Mahalle bildirimleri (`community_comment`, `cover_volunteered`).
    var postId: UUID?
    var readAt: String?
    var createdAt: String?

    /// `notifications` tablosundan seçilen sütunlar.
    static let columns = "id,kind,title,body,spot_id,need_id,post_id,read_at,created_at"

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case spotId = "spot_id"
        case needId = "need_id"
        case postId = "post_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    /// Bilinmeyen bildirim türü (daha yeni sunucu) atlanır.
    func toDomain() -> AppNotification? {
        guard let kind = kind.flatMap(NotificationKind.init(rawValue:)) else { return nil }
        return AppNotification(
            id: id,
            kind: kind,
            title: title ?? "",
            body: body ?? "",
            spotId: spotId,
            needId: needId,
            postId: postId,
            readAt: date(readAt),
            createdAt: date(createdAt) ?? unknownDate
        )
    }
}

struct NotificationPrefsDTO: Decodable {
    var radiusM: Int?
    var quietStart: Int?
    var quietEnd: Int?
    var needFoodNearby: Bool?
    var followedUpdates: Bool?
    var guardianAlerts: Bool?
    var communityUpdates: Bool?

    static let columns = "radius_m,quiet_start,quiet_end,need_food_nearby,followed_updates,guardian_alerts,community_updates"

    enum CodingKeys: String, CodingKey {
        case radiusM = "radius_m"
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
        case needFoodNearby = "need_food_nearby"
        case followedUpdates = "followed_updates"
        case guardianAlerts = "guardian_alerts"
        case communityUpdates = "community_updates"
    }

    func toDomain() -> NotificationPreferences {
        let defaults = NotificationPreferences.default
        return NotificationPreferences(
            radiusMeters: radiusM ?? defaults.radiusMeters,
            quietStartHour: quietStart ?? defaults.quietStartHour,
            quietEndHour: quietEnd ?? defaults.quietEndHour,
            needFoodNearby: needFoodNearby ?? defaults.needFoodNearby,
            followedUpdates: followedUpdates ?? defaults.followedUpdates,
            guardianAlerts: guardianAlerts ?? defaults.guardianAlerts,
            communityUpdates: communityUpdates ?? defaults.communityUpdates
        )
    }
}

// MARK: - Bağış

struct DonationOverviewDTO: Decodable {
    var month: String?
    var kgDistributed: FlexibleDouble?
    var donorCount: Int?

    enum CodingKeys: String, CodingKey {
        case month
        case kgDistributed = "kg_distributed"
        case donorCount = "donor_count"
    }

    func toDomain() -> DonationOverview? {
        guard let parsedMonth = month.flatMap(PostgresDate.parse) else { return nil }
        return DonationOverview(month: parsedMonth, kgDistributed: kgDistributed?.value ?? 0, donorCount: donorCount ?? 0)
    }
}

// MARK: - Mahalle: community_post_row / community_comment_row

struct CommunityPostRowDTO: Decodable {
    var id: UUID
    var kind: String?
    var body: String?
    var photoUrl: String?
    var authorId: UUID?
    var authorName: String?
    var authorAvatarUrl: String?
    var authorIsVerified: Bool?
    var spotId: UUID?
    var spotTitle: String?
    var animalId: UUID?
    var animalName: String?
    /// Postgres `date` ("2026-11-14").
    var coverFrom: String?
    var coverTo: String?
    var volunteerCount: Int?
    var viewerVolunteered: Bool?
    var pawCount: Int?
    var viewerPawed: Bool?
    var commentCount: Int?
    var distanceM: Double?
    var moderationState: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case photoUrl = "photo_url"
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case authorIsVerified = "author_is_verified"
        case spotId = "spot_id"
        case spotTitle = "spot_title"
        case animalId = "animal_id"
        case animalName = "animal_name"
        case coverFrom = "cover_from"
        case coverTo = "cover_to"
        case volunteerCount = "volunteer_count"
        case viewerVolunteered = "viewer_volunteered"
        case pawCount = "paw_count"
        case viewerPawed = "viewer_pawed"
        case commentCount = "comment_count"
        case distanceM = "distance_m"
        case moderationState = "moderation_state"
        case createdAt = "created_at"
    }

    /// Yazarı olmayan satır atlanır (engelleme ve silme yetkisi yazara bağlı).
    ///
    /// Bilinmeyen `kind` (daha yeni sunucu) `spot_row.type → .mixed` gibi nötr türe, `.note`'a düşer: metin
    /// yazarın yazdığı haliyle okunur kalır. Satır atlansaydı `p_before` ile sayfalanan akışta sayfa
    /// eksik gelir, bildirimden açılan paylaşım da "artık yok" görünürdü.
    func toDomain() -> CommunityPost? {
        guard let authorId else { return nil }
        return CommunityPost(
            id: id,
            kind: kind.flatMap(CommunityPostKind.init(rawValue:)) ?? .note,
            body: body ?? "",
            photoURL: photoUrl?.nonEmptyURL,
            authorId: authorId,
            authorName: authorName ?? SupabaseBackend.placeholderDisplayName,
            authorAvatarURL: authorAvatarUrl?.nonEmptyURL,
            authorIsVerified: authorIsVerified ?? false,
            spotId: spotId,
            spotTitle: spotTitle,
            animalId: animalId,
            animalName: animalName,
            coverFrom: date(coverFrom),
            coverTo: date(coverTo),
            volunteerCount: volunteerCount ?? 0,
            viewerVolunteered: viewerVolunteered ?? false,
            pawCount: pawCount ?? 0,
            viewerPawed: viewerPawed ?? false,
            commentCount: commentCount ?? 0,
            distanceMeters: distanceM,
            isPendingModeration: moderationState == ModerationState.pending.rawValue,
            createdAt: date(createdAt) ?? unknownDate
        )
    }
}

struct CommunityCommentRowDTO: Decodable {
    var id: UUID
    var postId: UUID?
    var body: String?
    var authorId: UUID?
    var authorName: String?
    var authorAvatarUrl: String?
    var authorIsVerified: Bool?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case authorIsVerified = "author_is_verified"
        case createdAt = "created_at"
    }

    /// Paylaşımı veya yazarı olmayan satır atlanır.
    func toDomain() -> CommunityComment? {
        guard let postId, let authorId else { return nil }
        return CommunityComment(
            id: id,
            postId: postId,
            body: body ?? "",
            authorId: authorId,
            authorName: authorName ?? SupabaseBackend.placeholderDisplayName,
            authorAvatarURL: authorAvatarUrl?.nonEmptyURL,
            authorIsVerified: authorIsVerified ?? false,
            createdAt: date(createdAt) ?? unknownDate
        )
    }
}

/// `cover_volunteers_of` satırı.
struct CommunityVolunteerDTO: Decodable {
    var userId: UUID
    var displayName: String?
    var avatarUrl: String?
    var isVerifiedFeeder: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isVerifiedFeeder = "is_verified_feeder"
    }

    func toDomain() -> CommunityVolunteer {
        CommunityVolunteer(
            userId: userId,
            displayName: displayName ?? SupabaseBackend.placeholderDisplayName,
            avatarURL: avatarUrl?.nonEmptyURL,
            isVerifiedFeeder: isVerifiedFeeder ?? false
        )
    }
}

/// `community_summary` satırı.
struct CommunitySummaryDTO: Decodable {
    var fedSpotDays7d: Int?
    var activeFeeders7d: Int?
    var openCoverRequests: Int?
    var posts7d: Int?

    enum CodingKeys: String, CodingKey {
        case fedSpotDays7d = "fed_spot_days_7d"
        case activeFeeders7d = "active_feeders_7d"
        case openCoverRequests = "open_cover_requests"
        case posts7d = "posts_7d"
    }

    func toDomain() -> CommunitySummary {
        CommunitySummary(
            fedSpotDays7d: fedSpotDays7d ?? 0,
            activeFeeders7d: activeFeeders7d ?? 0,
            openCoverRequests: openCoverRequests ?? 0,
            posts7d: posts7d ?? 0
        )
    }
}

// MARK: - Mahalle: jsonb `status` sonuçları

/// `create_community_post`, `add_community_comment`, `toggle_post_paw`, `toggle_cover_volunteer`,
/// `delete_community_post` ve `delete_community_comment` sonuçlarının ortak şekli.
struct CommunityResultDTO: Decodable {
    var status: String
    var postId: UUID?
    var commentId: UUID?
    var moderationState: String?
    var limit: Int?
    /// `status == "invalid"`: `CommunityValidationError` ham değeri.
    var reason: String?
    var pawed: Bool?
    var pawCount: Int?
    var volunteered: Bool?
    var volunteerCount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case postId = "post_id"
        case commentId = "comment_id"
        case moderationState = "moderation_state"
        case limit, reason, pawed
        case pawCount = "paw_count"
        case volunteered
        case volunteerCount = "volunteer_count"
    }

    func createPostOutcome() throws -> CreatePostOutcome {
        let rpc = "create_community_post"
        switch status {
        case "created":
            guard let postId else { throw MamaError.server("\(rpc): post_id eksik") }
            return .created(id: postId, pendingModeration: moderationState == ModerationState.pending.rawValue)
        case "rejected_content":
            return .rejectedContent
        case "limit_reached":
            return .limitReached(limit: limit ?? CommunityPolicy.dailyPostLimit)
        case "invalid":
            return .invalid(try validationError(rpc: rpc))
        default:
            throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func commentOutcome() throws -> CommentOutcome {
        let rpc = "add_community_comment"
        switch status {
        case "created":
            guard let commentId else { throw MamaError.server("\(rpc): comment_id eksik") }
            return .created(id: commentId)
        case "rejected_content":
            return .rejectedContent
        case "limit_reached":
            return .limitReached(limit: limit ?? CommunityPolicy.dailyCommentLimit)
        case "invalid":
            return .invalid(try validationError(rpc: rpc))
        case "post_not_found":
            return .postNotFound
        default:
            throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// `nil` = paylaşım artık yok veya görünmüyor (`post_not_found`).
    func pawToggleResult() throws -> PawToggleResult? {
        let rpc = "toggle_post_paw"
        switch status {
        case "ok":
            // Tepkinin yeni durumu bilinmeden arayüz güncellenemez; sayaç eksikse durumdan türetilir.
            guard let pawed else { throw MamaError.server("\(rpc): pawed eksik") }
            return PawToggleResult(pawed: pawed, pawCount: max(pawCount ?? (pawed ? 1 : 0), 0))
        case "post_not_found":
            return nil
        default:
            throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func coverVolunteerOutcome() throws -> CoverVolunteerOutcome {
        let rpc = "toggle_cover_volunteer"
        switch status {
        case "ok":
            guard let volunteered else { throw MamaError.server("\(rpc): volunteered eksik") }
            return .ok(volunteered: volunteered, volunteerCount: max(volunteerCount ?? (volunteered ? 1 : 0), 0))
        case "not_cover_request":
            return .notCoverRequest
        case "own_post":
            return .ownPost
        case "closed":
            return .closed
        case "post_not_found":
            return .postNotFound
        default:
            throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// `delete_community_post` / `delete_community_comment`: `false` = silme yetkisi yok.
    func deleteAllowed(rpc: String) throws -> Bool {
        switch status {
        case "ok":
            return true
        case "not_allowed":
            return false
        case "post_not_found", "comment_not_found":
            // Kayıt yoksa sunucu `not_found` exception'ı fırlatır (SupabaseErrorMapper → `.notFound`,
            // InMemoryBackend ile aynı). Aynı durum `status` olarak gelirse de aynı hataya çevrilir.
            throw MamaError.notFound
        default:
            throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// Bilinmeyen `reason` (daha yeni sunucu) yanlış uyarı göstermek yerine sunucu hatası sayılır.
    private func validationError(rpc: String) throws -> CommunityValidationError {
        guard let error = reason.flatMap(CommunityValidationError.init(rawValue:)) else {
            throw MamaError.server("\(rpc): beklenmeyen reason '\(reason ?? "null")'")
        }
        return error
    }
}
