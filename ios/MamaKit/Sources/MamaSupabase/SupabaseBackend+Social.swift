import Foundation
import MamaCore
import Supabase

// MARK: - SocialRepository (Tanışma)

/// Buluşmalar, Hayvanseverler ve sohbet (docs/superpowers/specs/2026-11-14-tanisma-design.md).
///
/// Tablolara doğrudan erişim yoktur; her şey `security definer` RPC'lerden geçer ve hiçbiri `anon`
/// rolüne açık değildir: tüm çağrılar ağa çıkmadan önce oturumu kontrol eder (`MamaError.notSignedIn`).
/// Sosyal onay yoksa okuma RPC'leri boş döner, yazma RPC'leri `consent_required` verir.
extension SupabaseBackend: SocialRepository {
    static let maxMeetupRadiusMeters = 50_000
    static let maxMessagePageSize = 100

    // MARK: Profil

    public func socialProfile() async throws -> SocialProfile? {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("social_profile_me")
            return try SupabaseDecoding.socialProfile(from: data)
        }
    }

    public func giveSocialConsent() async throws -> SocialProfile {
        try await perform {
            _ = try requireUserId()
            let result = try SupabaseDecoding.socialResult(from: try await rpc("give_social_consent"))
            try result.requireOK(rpc: "give_social_consent")
            let data = try await rpc("social_profile_me")
            return try SupabaseDecoding.socialProfile(from: data) ?? SocialProfile(hasConsented: true)
        }
    }

    public func updateSocialProfile(isVisible: Bool, about: String, interests: [SocialInterest], at coordinate: Coordinate?) async throws -> SocialProfileOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("update_social_profile", Self.updateProfileParams(
                isVisible: isVisible, about: about, interests: interests, coordinate: coordinate
            ))
            return try SupabaseDecoding.socialResult(from: data).updateProfileOutcome()
        }
    }

    // MARK: Buluşmalar

    public func meetups(near center: Coordinate, radiusMeters: Int) async throws -> [Meetup] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("meetups_near", [
                "lat": .double(center.latitude),
                "lng": .double(center.longitude),
                "radius_m": .integer(min(max(radiusMeters, 1), Self.maxMeetupRadiusMeters)),
            ])
            return try SupabaseDecoding.meetups(from: data)
        }
    }

    public func meetup(id: UUID, near center: Coordinate?) async throws -> Meetup? {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("meetup_detail", [
                "p_meetup_id": Param.uuid(id),
                "lat": Param.double(center?.latitude),
                "lng": Param.double(center?.longitude),
            ])
            return try SupabaseDecoding.meetups(from: data).first
        }
    }

    public func meetupParticipants(meetupId: UUID) async throws -> [MeetupParticipant] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("meetup_participants", ["p_meetup_id": Param.uuid(meetupId)])
            return try SupabaseDecoding.meetupParticipants(from: data)
        }
    }

    public func createMeetup(_ draft: MeetupDraft) async throws -> CreateMeetupOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("create_meetup", Self.createMeetupParams(draft))
            return try SupabaseDecoding.socialResult(from: data).createMeetupOutcome()
        }
    }

    public func joinMeetup(id: UUID) async throws -> JoinMeetupOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("join_meetup", ["p_meetup_id": Param.uuid(id)])
            return try SupabaseDecoding.socialResult(from: data).joinMeetupOutcome()
        }
    }

    public func leaveMeetup(id: UUID) async throws -> Bool {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("leave_meetup", ["p_meetup_id": Param.uuid(id)])
            return try SupabaseDecoding.socialResult(from: data).leaveAllowed()
        }
    }

    public func removeParticipant(meetupId: UUID, userId: UUID) async throws -> Bool {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("remove_meetup_participant", [
                "p_meetup_id": Param.uuid(meetupId),
                "p_user_id": Param.uuid(userId),
            ])
            return try SupabaseDecoding.socialResult(from: data).moderationAllowed(rpc: "remove_meetup_participant")
        }
    }

    public func cancelMeetup(id: UUID) async throws -> Bool {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("cancel_meetup", ["p_meetup_id": Param.uuid(id)])
            return try SupabaseDecoding.socialResult(from: data).moderationAllowed(rpc: "cancel_meetup")
        }
    }

    // MARK: Hayvanseverler ve bağlantılar

    public func animalLovers(interest: SocialInterest?) async throws -> [AnimalLover] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("animal_lovers_near", ["p_interest": Param.string(interest?.rawValue)])
            return try SupabaseDecoding.animalLovers(from: data)
        }
    }

    public func sendConnectionRequest(to userId: UUID, note: String?) async throws -> SendRequestOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("send_connection_request", [
                "p_user_id": Param.uuid(userId),
                "p_note": Param.text(note),
            ])
            return try SupabaseDecoding.socialResult(from: data).sendRequestOutcome()
        }
    }

    public func respondToConnection(requestId: UUID, accept: Bool) async throws -> UUID? {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("respond_connection", [
                "p_request_id": Param.uuid(requestId),
                "p_accept": .bool(accept),
            ])
            return try SupabaseDecoding.socialResult(from: data).respondOutcome()
        }
    }

    public func withdrawConnectionRequest(id: UUID) async throws {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("withdraw_connection_request", ["p_request_id": Param.uuid(id)])
            try SupabaseDecoding.socialResult(from: data).requireOKOrNotFound(rpc: "withdraw_connection_request")
        }
    }

    public func removeConnection(userId: UUID) async throws {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("remove_connection", ["p_user_id": Param.uuid(userId)])
            try SupabaseDecoding.socialResult(from: data).requireOKOrNotFound(rpc: "remove_connection")
        }
    }

    public func incomingConnectionRequests() async throws -> [ConnectionRequest] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("incoming_connection_requests")
            return try SupabaseDecoding.incomingConnectionRequests(from: data)
        }
    }

    // MARK: Sohbet

    public func conversations() async throws -> [ConversationSummary] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("my_conversations")
            return try SupabaseDecoding.conversations(from: data)
        }
    }

    public func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("conversation_messages", Self.messagesParams(
                conversationId: conversationId, before: before, limit: limit
            ))
            return try SupabaseDecoding.chatMessages(from: data)
        }
    }

    public func sendMessage(conversationId: UUID, body: String) async throws -> SendMessageOutcome {
        try await perform {
            let userId = try requireUserId()
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = try await rpc("send_chat_message", [
                "p_conversation_id": Param.uuid(conversationId),
                "p_body": .string(text),
            ])
            let result = try SupabaseDecoding.socialResult(from: data)
            // Yazar adı yalnızca başarılı gönderimde gerekir; alınamazsa ekran mesajları yeniden okur.
            let name = result.status == "sent" ? ((try? await fetchProfile(id: userId))?.displayName) : nil
            return try result.sendMessageOutcome(
                authorId: userId, authorName: name ?? Self.placeholderDisplayName, body: text
            )
        }
    }

    public func markConversationRead(id: UUID) async throws {
        try await perform {
            _ = try requireUserId()
            _ = try await rpc("mark_conversation_read", ["p_conversation_id": Param.uuid(id)])
        }
    }

    // MARK: Parametreler

    /// Konum ≈1 km'ye (2 ondalık) yuvarlanarak gönderilir; kesin konum cihazdan çıkmaz.
    static func updateProfileParams(isVisible: Bool, about: String, interests: [SocialInterest], coordinate: Coordinate?) -> JSONObject {
        let cell = coordinate.map(SocialPolicy.roundedCell)
        return [
            "p_is_visible": .bool(isVisible),
            "p_about": .string(about.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_interests": Param.strings(interests.map(\.rawValue)),
            "lat": Param.double(cell?.latitude),
            "lng": Param.double(cell?.longitude),
        ]
    }

    /// `create_meetup`: varsayılanı olmayan yedi parametre ve iki isteğe bağlı parametrenin hepsi gönderilir.
    static func createMeetupParams(_ draft: MeetupDraft) -> JSONObject {
        [
            "p_title": .string(draft.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_description": .string(draft.description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_starts_at": Param.date(draft.startsAt),
            "p_duration_minutes": .integer(draft.durationMinutes),
            "p_place_name": .string(draft.placeName.trimmingCharacters(in: .whitespacesAndNewlines)),
            "lat": .double(draft.coordinate.latitude),
            "lng": .double(draft.coordinate.longitude),
            "p_spot_id": Param.uuid(draft.spotId),
            "p_capacity": draft.capacity.map(AnyJSON.integer) ?? .null,
        ]
    }

    /// `conversation_messages`. `p_before` milisaniye hassasiyetindedir (`PostgresDate.format`).
    static func messagesParams(conversationId: UUID, before: Date?, limit: Int) -> JSONObject {
        [
            "p_conversation_id": Param.uuid(conversationId),
            "p_before": Param.date(before),
            "max_rows": .integer(min(max(limit, 1), maxMessagePageSize)),
        ]
    }
}
