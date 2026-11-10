import Foundation
import MamaCore
import Supabase

// MARK: - CommunityRepository (Mahalle)

/// Mahalle akışı: paylaşım, yorum, "pati" tepkisi ve "Ben bakarım" gönüllülüğü
/// (docs/backend-contract.md → "Mahalle (topluluk) — v0.2").
///
/// Dört tabloya da doğrudan erişim yoktur; her şey `security definer` RPC'lerden geçer. Bölümdeki hiçbir
/// RPC `anon` rolüne açık olmadığından tüm çağrılar ağa çıkmadan önce oturumu kontrol eder
/// (`MamaError.notSignedIn`).
extension SupabaseBackend: CommunityRepository {
    /// Sözleşme → Kurallar: akış yarıçapı en fazla 10 000 m, sayfa en fazla 50 satır.
    static let maxFeedRadiusMeters = 10_000
    static let maxFeedPageSize = 50

    /// Yeniden eskiye. Sayfalama `before` ile (keyset): bir önceki sayfanın son paylaşımının `createdAt`'i.
    public func feed(near center: Coordinate, radiusMeters: Int, kind: CommunityPostKind?, before: Date?, limit: Int) async throws -> [CommunityPost] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("community_feed", Self.feedParams(
                center: center, radiusMeters: radiusMeters, kind: kind, before: before, limit: limit
            ))
            return try SupabaseDecoding.communityPosts(from: data)
        }
    }

    /// Gizli, engelli veya silinmiş paylaşım → `nil` (sunucu 0 satır döner).
    public func post(id: UUID, near center: Coordinate?) async throws -> CommunityPost? {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("community_post_detail", [
                "p_post_id": Param.uuid(id),
                "lat": Param.double(center?.latitude),
                "lng": Param.double(center?.longitude),
            ])
            return try SupabaseDecoding.communityPosts(from: data).first
        }
    }

    /// Eskiden yeniye (sunucu sırası).
    public func comments(postId: UUID) async throws -> [CommunityComment] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("community_comments_of", ["p_post_id": Param.uuid(postId)])
            return try SupabaseDecoding.communityComments(from: data)
        }
    }

    public func volunteers(postId: UUID) async throws -> [CommunityVolunteer] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("cover_volunteers_of", ["p_post_id": Param.uuid(postId)])
            return try SupabaseDecoding.communityVolunteers(from: data)
        }
    }

    /// Metin, limit, küfür ve "Yerime bakar mısın?" kurallarına sunucu karar verir.
    public func createPost(_ draft: CommunityPostDraft) async throws -> CreatePostOutcome {
        try await perform {
            _ = try requireUserId()
            if draft.spotId == nil, draft.coordinate == nil {
                // Nokta bağlı değilken konumsuz çağrıda sunucu exception fırlatır (sözleşme). InMemoryBackend
                // gibi doğrulama sonucu olarak dönülür; bu dalda ön kontrol hiçbir zaman `nil` vermez.
                return .invalid(CommunityPolicy.validate(draft, now: now()) ?? .locationMissing)
            }
            let data = try await rpc("create_community_post", Self.createPostParams(draft))
            return try SupabaseDecoding.createPostOutcome(from: data)
        }
    }

    public func addComment(postId: UUID, body: String) async throws -> CommentOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("add_community_comment", [
                "p_post_id": Param.uuid(postId),
                "p_body": .string(body.trimmingCharacters(in: .whitespacesAndNewlines)),
            ])
            return try SupabaseDecoding.commentOutcome(from: data)
        }
    }

    public func togglePaw(postId: UUID) async throws -> PawToggleResult? {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("toggle_post_paw", ["p_post_id": Param.uuid(postId)])
            return try SupabaseDecoding.pawToggleResult(from: data)
        }
    }

    public func toggleVolunteer(postId: UUID) async throws -> CoverVolunteerOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("toggle_cover_volunteer", ["p_post_id": Param.uuid(postId)])
            return try SupabaseDecoding.coverVolunteerOutcome(from: data)
        }
    }

    public func deletePost(id: UUID) async throws -> Bool {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("delete_community_post", ["p_post_id": Param.uuid(id)])
            return try SupabaseDecoding.communityDeleteAllowed(from: data, rpc: "delete_community_post")
        }
    }

    public func deleteComment(id: UUID) async throws -> Bool {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("delete_community_comment", ["p_comment_id": Param.uuid(id)])
            return try SupabaseDecoding.communityDeleteAllowed(from: data, rpc: "delete_community_comment")
        }
    }

    public func summary(near center: Coordinate, radiusMeters: Int) async throws -> CommunitySummary {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("community_summary", [
                "lat": .double(center.latitude),
                "lng": .double(center.longitude),
                "radius_m": .integer(max(0, radiusMeters)),
            ])
            return try SupabaseDecoding.communitySummary(from: data)
        }
    }

    // MARK: Parametreler

    /// `community_feed` parametreleri. Filtre ve imleç yoksa `null` açıkça gönderilir.
    /// `p_before` milisaniye hassasiyetindedir; sunucu `created_at`'i milisaniyeye kırparak saklar.
    static func feedParams(center: Coordinate, radiusMeters: Int, kind: CommunityPostKind?, before: Date?, limit: Int) -> JSONObject {
        [
            "lat": .double(center.latitude),
            "lng": .double(center.longitude),
            "radius_m": .integer(min(max(radiusMeters, 0), maxFeedRadiusMeters)),
            "p_kind": Param.string(kind?.rawValue),
            "p_before": Param.date(before),
            "max_rows": .integer(min(max(limit, 1), maxFeedPageSize)),
        ]
    }

    /// `create_community_post` parametreleri. Varsayılanı olmayan dokuz parametrenin hepsi gönderilir
    /// (boş olanlar `null`). `p_cover_*` yalnızca `cover_request`'te dolu: Europe/Istanbul günü, "YYYY-MM-DD".
    static func createPostParams(_ draft: CommunityPostDraft) -> JSONObject {
        let isCover = draft.kind == .coverRequest
        return [
            "p_kind": .string(draft.kind.rawValue),
            "p_body": .string(draft.body.trimmingCharacters(in: .whitespacesAndNewlines)),
            "p_photo_url": Param.string(draft.photoURL?.absoluteString),
            "p_spot_id": Param.uuid(draft.spotId),
            "p_animal_id": Param.uuid(draft.animalId),
            "lat": Param.double(draft.coordinate?.latitude),
            "lng": Param.double(draft.coordinate?.longitude),
            "p_cover_from": Param.day(isCover ? draft.coverFrom : nil),
            "p_cover_to": Param.day(isCover ? draft.coverTo : nil),
        ]
    }
}
