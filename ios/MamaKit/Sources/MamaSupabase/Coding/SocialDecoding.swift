import Foundation
import MamaCore

// Tanışma (buluşmalar, Hayvanseverler, sohbet): sunucu satırları ve jsonb `status` sonuçları → domain.
// Sunucu karşılıkları: supabase/migrations/20261114000020…23.

private func date(_ text: String?) -> Date? {
    text.flatMap(PostgresDate.parse)
}

private let unknownDate = Date(timeIntervalSince1970: 0)

/// Bilinmeyen etiketler (daha yeni sunucu) sessizce düşer.
private func socialInterests(_ raw: [String]?) -> [SocialInterest] {
    (raw ?? []).compactMap(SocialInterest.init(rawValue:))
}

// MARK: - Satırlar

/// `social_profile_me` satırı.
struct SocialProfileRowDTO: Decodable {
    var isVisible: Bool?
    var about: String?
    var interests: [String]?
    var consented: Bool?

    enum CodingKeys: String, CodingKey {
        case isVisible = "is_visible"
        case about, interests, consented
    }

    func toDomain() -> SocialProfile {
        SocialProfile(
            isVisible: isVisible ?? false,
            about: about ?? "",
            interests: socialInterests(interests),
            hasConsented: consented ?? false
        )
    }
}

/// `meetups_near` / `meetup_detail` satırı (`public.meetup_row`).
struct MeetupRowDTO: Decodable {
    var id: UUID
    var title: String?
    var description: String?
    var startsAt: String?
    var endsAt: String?
    var placeName: String?
    var lat: Double?
    var lng: Double?
    var spotId: UUID?
    var spotTitle: String?
    var capacity: Int?
    var participantCount: Int?
    var status: String?
    var organizerId: UUID?
    var organizerName: String?
    var organizerAvatarUrl: String?
    var organizerIsVerified: Bool?
    var viewerRole: String?
    var conversationId: UUID?
    var distanceM: Double?
    var createdAt: String?
    var isTour: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, description, lat, lng, capacity, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case placeName = "place_name"
        case spotId = "spot_id"
        case spotTitle = "spot_title"
        case participantCount = "participant_count"
        case organizerId = "organizer_id"
        case organizerName = "organizer_name"
        case organizerAvatarUrl = "organizer_avatar_url"
        case organizerIsVerified = "organizer_is_verified"
        case viewerRole = "viewer_role"
        case conversationId = "conversation_id"
        case distanceM = "distance_m"
        case createdAt = "created_at"
        case isTour = "is_tour"
    }

    /// Konumu, düzenleyeni ya da zamanı olmayan satır atlanır. Bilinmeyen `status` iptal sayılır
    /// (katılınamaz, güvenli taraf); bilinmeyen `viewer_role` `.none`.
    func toDomain() -> Meetup? {
        guard let lat, let lng, let organizerId, let start = date(startsAt), let end = date(endsAt) else { return nil }
        return Meetup(
            id: id,
            title: title ?? "",
            description: description ?? "",
            startsAt: start,
            endsAt: end,
            placeName: placeName ?? "",
            coordinate: Coordinate(latitude: lat, longitude: lng),
            spotId: spotId,
            spotTitle: spotTitle,
            capacity: capacity,
            participantCount: participantCount ?? 1,
            status: status.flatMap(MeetupStatus.init(rawValue:)) ?? .cancelled,
            organizerId: organizerId,
            organizerName: organizerName ?? SupabaseBackend.placeholderDisplayName,
            organizerAvatarURL: organizerAvatarUrl?.nonEmptyURL,
            organizerIsVerified: organizerIsVerified ?? false,
            viewerRole: viewerRole.flatMap(MeetupViewerRole.init(rawValue:)) ?? .none,
            conversationId: conversationId,
            distanceMeters: distanceM,
            createdAt: date(createdAt) ?? unknownDate,
            isTour: isTour ?? false
        )
    }
}

/// `meetup_participants` satırı.
struct MeetupParticipantRowDTO: Decodable {
    var userId: UUID
    var displayName: String?
    var avatarUrl: String?
    var isVerifiedFeeder: Bool?
    var isOrganizer: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isVerifiedFeeder = "is_verified_feeder"
        case isOrganizer = "is_organizer"
    }

    func toDomain() -> MeetupParticipant {
        MeetupParticipant(
            id: userId,
            displayName: displayName ?? SupabaseBackend.placeholderDisplayName,
            avatarURL: avatarUrl?.nonEmptyURL,
            isVerifiedFeeder: isVerifiedFeeder ?? false,
            isOrganizer: isOrganizer ?? false
        )
    }
}

/// `animal_lovers_near` satırı.
struct AnimalLoverRowDTO: Decodable {
    var userId: UUID
    var displayName: String?
    var avatarUrl: String?
    var about: String?
    var interests: [String]?
    var isVerifiedFeeder: Bool?
    var fed30d: Int?
    var distanceBand: String?
    var sharedInterestCount: Int?
    var connectionState: String?
    var requestId: UUID?
    var conversationId: UUID?
    var fedToday: Bool?
    var onTourMeetupId: UUID?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case about, interests
        case isVerifiedFeeder = "is_verified_feeder"
        case fed30d = "fed_30d"
        case distanceBand = "distance_band"
        case sharedInterestCount = "shared_interest_count"
        case connectionState = "connection_state"
        case requestId = "request_id"
        case conversationId = "conversation_id"
        case fedToday = "fed_today"
        case onTourMeetupId = "on_tour_meetup_id"
    }

    /// Mesafe bandı bilinmeyen satır atlanır (bant olmadan mesafe gösterilemez). Gereken kimliği eksik
    /// bağlantı durumu `.none`'a düşer: yanlış bir "bağlı" göstermek yerine isteğe izin verir, sunucu karar verir.
    func toDomain() -> AnimalLover? {
        guard let band = distanceBand.flatMap(DistanceBand.init(rawValue:)) else { return nil }
        return AnimalLover(
            id: userId,
            displayName: displayName ?? SupabaseBackend.placeholderDisplayName,
            avatarURL: avatarUrl?.nonEmptyURL,
            about: about ?? "",
            interests: socialInterests(interests),
            isVerifiedFeeder: isVerifiedFeeder ?? false,
            fedLast30Days: fed30d ?? 0,
            distanceBand: band,
            sharedInterestCount: sharedInterestCount ?? 0,
            connection: connection,
            fedToday: fedToday ?? false,
            onTourMeetupId: onTourMeetupId
        )
    }

    var connection: ConnectionState {
        switch connectionState {
        case "outgoing_pending": requestId.map { .outgoingPending(requestId: $0) } ?? .none
        case "incoming_pending": requestId.map { .incomingPending(requestId: $0) } ?? .none
        case "connected": conversationId.map { .connected(conversationId: $0) } ?? .none
        default: .none
        }
    }
}

/// `incoming_connection_requests` satırı.
struct ConnectionRequestRowDTO: Decodable {
    var requestId: UUID
    var userId: UUID?
    var displayName: String?
    var avatarUrl: String?
    var about: String?
    var interests: [String]?
    var isVerifiedFeeder: Bool?
    var note: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case about, interests
        case isVerifiedFeeder = "is_verified_feeder"
        case note
        case createdAt = "created_at"
    }

    func toDomain() -> ConnectionRequest? {
        guard let userId else { return nil }
        return ConnectionRequest(
            id: requestId,
            userId: userId,
            displayName: displayName ?? SupabaseBackend.placeholderDisplayName,
            avatarURL: avatarUrl?.nonEmptyURL,
            about: about ?? "",
            interests: socialInterests(interests),
            isVerifiedFeeder: isVerifiedFeeder ?? false,
            note: note,
            createdAt: date(createdAt) ?? unknownDate
        )
    }
}

/// `my_conversations` satırı.
struct ConversationRowDTO: Decodable {
    var conversationId: UUID
    var kind: String?
    var title: String?
    var meetupId: UUID?
    var otherUserId: UUID?
    var otherAvatarUrl: String?
    var lastBody: String?
    var lastAt: String?
    var unread: Int?
    var readOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case kind, title, unread
        case meetupId = "meetup_id"
        case otherUserId = "other_user_id"
        case otherAvatarUrl = "other_avatar_url"
        case lastBody = "last_body"
        case lastAt = "last_at"
        case readOnly = "read_only"
    }

    /// Bilinmeyen sohbet türü (daha yeni sunucu) atlanır.
    func toDomain() -> ConversationSummary? {
        guard let kind = kind.flatMap(ConversationKind.init(rawValue:)) else { return nil }
        return ConversationSummary(
            id: conversationId,
            kind: kind,
            title: title ?? "",
            meetupId: meetupId,
            otherUserId: otherUserId,
            otherAvatarURL: otherAvatarUrl?.nonEmptyURL,
            lastBody: lastBody,
            lastAt: date(lastAt),
            unreadCount: max(unread ?? 0, 0),
            isReadOnly: readOnly ?? false
        )
    }
}

/// `conversation_messages` satırı.
struct ChatMessageRowDTO: Decodable {
    var id: UUID
    var authorId: UUID?
    var authorName: String?
    var authorAvatarUrl: String?
    var body: String?
    var createdAt: String?
    var isPending: Bool?

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatarUrl = "author_avatar_url"
        case createdAt = "created_at"
        case isPending = "is_pending"
    }

    func toDomain() -> ChatMessage? {
        guard let authorId else { return nil }
        return ChatMessage(
            id: id,
            authorId: authorId,
            authorName: authorName ?? SupabaseBackend.placeholderDisplayName,
            authorAvatarURL: authorAvatarUrl?.nonEmptyURL,
            body: body ?? "",
            createdAt: date(createdAt) ?? unknownDate,
            isPendingModeration: isPending ?? false
        )
    }
}

// MARK: - jsonb `status` sonuçları

/// Sosyal yazma RPC'lerinin ortak sonuç şekli.
struct SocialResultDTO: Decodable {
    var status: String
    var reason: String?
    var limit: Int?
    var meetupId: UUID?
    var conversationId: UUID?
    var requestId: UUID?
    var messageId: UUID?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case status, reason, limit
        case meetupId = "meetup_id"
        case conversationId = "conversation_id"
        case requestId = "request_id"
        case messageId = "message_id"
        case createdAt = "created_at"
    }

    /// `give_social_consent`: yalnızca `ok`.
    func requireOK(rpc: String) throws {
        guard status == "ok" else { throw StatusError.unexpected(rpc: rpc, status: status) }
    }

    func updateProfileOutcome() throws -> SocialProfileOutcome {
        let rpc = "update_social_profile"
        switch status {
        case "ok": return .saved
        case "consent_required": return .consentRequired
        case "rejected_content": return .rejectedContent
        case "invalid":
            switch reason {
            case "about_too_long": return .aboutTooLong
            case "location_required": return .locationRequired
            default: throw MamaError.server("\(rpc): beklenmeyen reason '\(reason ?? "null")'")
            }
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func createMeetupOutcome() throws -> CreateMeetupOutcome {
        let rpc = "create_meetup"
        switch status {
        case "created":
            guard let meetupId, let conversationId else { throw MamaError.server("\(rpc): meetup_id/conversation_id eksik") }
            return .created(meetupId: meetupId, conversationId: conversationId)
        case "consent_required": return .consentRequired
        case "rejected_content": return .rejectedContent
        case "limit_reached": return .limitReached(limit ?? SocialPolicy.dailyMeetups)
        case "invalid":
            guard let value = reason.flatMap(MeetupInvalidReason.init(rawValue:)) else {
                throw MamaError.server("\(rpc): beklenmeyen reason '\(reason ?? "null")'")
            }
            return .invalid(value)
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func startTourOutcome() throws -> StartTourOutcome {
        let rpc = "start_feeding_tour"
        switch status {
        case "started":
            guard let meetupId, let conversationId else { throw MamaError.server("\(rpc): meetup_id/conversation_id eksik") }
            return .started(meetupId: meetupId, conversationId: conversationId)
        case "consent_required": return .consentRequired
        case "spot_not_found": return .spotNotFound
        case "already_touring": return .alreadyTouring
        case "limit_reached": return .limitReached(limit ?? SocialPolicy.dailyTours)
        case "invalid":
            guard reason == "duration_range" else {
                throw MamaError.server("\(rpc): beklenmeyen reason '\(reason ?? "null")'")
            }
            return .durationRange
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func joinMeetupOutcome() throws -> JoinMeetupOutcome {
        let rpc = "join_meetup"
        switch status {
        case "joined":
            guard let conversationId else { throw MamaError.server("\(rpc): conversation_id eksik") }
            return .joined(conversationId: conversationId)
        case "full": return .full
        case "removed": return .removed
        case "cancelled": return .cancelled
        case "ended": return .ended
        case "consent_required": return .consentRequired
        case "not_found": return .notFound
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// `leave_meetup`: `false` = düzenleyen ayrılamaz.
    func leaveAllowed() throws -> Bool {
        let rpc = "leave_meetup"
        switch status {
        case "ok": return true
        case "organizer_cannot_leave": return false
        case "not_found": throw MamaError.notFound
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// `remove_meetup_participant` / `cancel_meetup`: `false` = yetki yok.
    func moderationAllowed(rpc: String) throws -> Bool {
        switch status {
        case "ok": return true
        case "not_allowed": return false
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    func sendRequestOutcome() throws -> SendRequestOutcome {
        let rpc = "send_connection_request"
        switch status {
        case "sent":
            guard let requestId else { throw MamaError.server("\(rpc): request_id eksik") }
            return .sent(requestId: requestId)
        case "auto_accepted":
            guard let conversationId else { throw MamaError.server("\(rpc): conversation_id eksik") }
            return .autoAccepted(conversationId: conversationId)
        case "consent_required": return .consentRequired
        case "not_visible": return .notVisible
        case "already_connected": return .alreadyConnected
        case "already_pending": return .alreadyPending
        case "cooldown": return .cooldown
        case "rejected_content": return .rejectedContent
        case "limit_reached": return .limitReached(limit ?? SocialPolicy.dailyRequests)
        case "not_found": return .notFound
        case "invalid":
            guard reason == "note_too_long" else {
                throw MamaError.server("\(rpc): beklenmeyen reason '\(reason ?? "null")'")
            }
            return .noteTooLong
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// `respond_connection`: kabulde sohbet kimliği; reddedince ya da istek yoksa `nil`.
    func respondOutcome() throws -> UUID? {
        let rpc = "respond_connection"
        switch status {
        case "accepted":
            guard let conversationId else { throw MamaError.server("\(rpc): conversation_id eksik") }
            return conversationId
        case "declined", "not_found": return nil
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }

    /// `withdraw_connection_request` / `remove_connection`: kayıt yoksa (`not_found`) sessiz başarı (idempotent).
    func requireOKOrNotFound(rpc: String) throws {
        guard status == "ok" || status == "not_found" else { throw StatusError.unexpected(rpc: rpc, status: status) }
    }

    /// `send_chat_message`. `sent` için kimlik ve zaman döner; gövde ve yazar çağırandan.
    func sendMessageOutcome(authorId: UUID, authorName: String, body: String) throws -> SendMessageOutcome {
        let rpc = "send_chat_message"
        switch status {
        case "sent":
            guard let messageId else { throw MamaError.server("\(rpc): message_id eksik") }
            return .sent(ChatMessage(
                id: messageId,
                authorId: authorId,
                authorName: authorName,
                body: body,
                createdAt: date(createdAt) ?? unknownDate
            ))
        // Onay yoksa üyelik de olamaz.
        case "not_member", "consent_required": return .notMember
        case "read_only": return .readOnly
        case "rejected_content": return .rejectedContent
        case "rate_limited": return .rateLimited
        case "invalid":
            switch reason {
            case "body_empty": return .bodyEmpty
            case "body_too_long": return .bodyTooLong
            default: throw MamaError.server("\(rpc): beklenmeyen reason '\(reason ?? "null")'")
            }
        default: throw StatusError.unexpected(rpc: rpc, status: status)
        }
    }
}

// MARK: - SupabaseDecoding

extension SupabaseDecoding {
    static func socialProfile(from data: Data) throws -> SocialProfile? {
        try SupabaseJSON.rows(SocialProfileRowDTO.self, from: data).first?.toDomain()
    }

    static func meetups(from data: Data) throws -> [Meetup] {
        try SupabaseJSON.rows(MeetupRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func meetupParticipants(from data: Data) throws -> [MeetupParticipant] {
        try SupabaseJSON.rows(MeetupParticipantRowDTO.self, from: data).map { $0.toDomain() }
    }

    static func animalLovers(from data: Data) throws -> [AnimalLover] {
        try SupabaseJSON.rows(AnimalLoverRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func incomingConnectionRequests(from data: Data) throws -> [ConnectionRequest] {
        try SupabaseJSON.rows(ConnectionRequestRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func conversations(from data: Data) throws -> [ConversationSummary] {
        try SupabaseJSON.rows(ConversationRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func chatMessages(from data: Data) throws -> [ChatMessage] {
        try SupabaseJSON.rows(ChatMessageRowDTO.self, from: data).compactMap { $0.toDomain() }
    }

    static func socialResult(from data: Data) throws -> SocialResultDTO {
        try SupabaseJSON.object(SocialResultDTO.self, from: data)
    }
}
