import Foundation
import MamaCore
import Supabase

// MARK: - NeedRepository

extension SupabaseBackend: NeedRepository {
    public func needs(near center: Coordinate, radiusMeters: Int, includeResolved: Bool) async throws -> [Need] {
        try await perform {
            let data = try await rpc("needs_near", [
                "lat": .double(center.latitude),
                "lng": .double(center.longitude),
                "radius_m": .integer(radiusMeters),
                "include_resolved": .bool(includeResolved),
            ])
            return NeedSorting.sorted(try SupabaseDecoding.needs(from: data))
        }
    }

    public func needs(spotId: UUID?, animalId: UUID?, includeResolved: Bool) async throws -> [Need] {
        guard spotId != nil || animalId != nil else { return [] }
        return try await perform {
            let data = try await rpc("needs_for", [
                "p_spot_id": Param.uuid(spotId),
                "p_animal_id": Param.uuid(animalId),
                "include_resolved": .bool(includeResolved),
            ])
            return NeedSorting.sorted(try SupabaseDecoding.needs(from: data))
        }
    }

    public func need(id: UUID) async throws -> Need? {
        try await perform {
            let data = try await rpc("need_detail", ["p_need_id": Param.uuid(id)])
            return try SupabaseDecoding.needs(from: data).first
        }
    }

    public func createNeed(_ draft: NeedDraft) async throws -> UUID {
        try await perform {
            _ = try requireUserId()
            guard draft.isValid else {
                throw MamaError.invalidInput("Bir açıklama yaz ve ihtiyacı bir noktaya veya hayvana bağla.")
            }
            let data = try await rpc("create_need", [
                "p_spot_id": Param.uuid(draft.spotId),
                "p_animal_id": Param.uuid(draft.animalId),
                "p_type": .string(draft.type.rawValue),
                "p_urgency": .string(draft.urgency.rawValue),
                "p_description": .string(draft.description.trimmingCharacters(in: .whitespacesAndNewlines)),
                "p_photos": Param.strings(draft.photoURLs.map(\.absoluteString)),
            ])
            return try SupabaseDecoding.createdId(from: data)
        }
    }

    public func claim(needId: UUID) async throws -> ClaimOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("claim_need", ["p_need_id": Param.uuid(needId)])
            return try SupabaseDecoding.claimOutcome(from: data)
        }
    }

    public func resolve(needId: UUID) async throws -> Bool {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("resolve_need", ["p_need_id": Param.uuid(needId)])
            return try SupabaseDecoding.resolveAllowed(from: data)
        }
    }
}

// MARK: - ProfileRepository

extension SupabaseBackend: ProfileRepository {
    public func profile(id: UUID) async throws -> UserProfile? {
        try await perform { try await fetchProfile(id: id) }
    }

    public func stats(userId: UUID) async throws -> ProfileStats {
        try await perform {
            let data = try await rpc("profile_stats", ["p_user_id": Param.uuid(userId)])
            return try SupabaseDecoding.profileStats(from: data)
        }
    }

    /// `avatarURL == nil` mevcut avatarı korur (InMemoryBackend ile aynı).
    public func updateProfile(displayName: String, neighborhood: String?, avatarURL: URL?) async throws -> UserProfile {
        try await perform {
            let userId = try requireUserId()
            guard let name = Self.sanitizedName(displayName) else {
                throw MamaError.invalidInput("Bir görünen ad yaz.")
            }
            var fields: JSONObject = [
                "display_name": .string(name),
                "neighborhood": Param.text(neighborhood),
            ]
            if let avatarURL { fields["avatar_url"] = .string(avatarURL.absoluteString) }
            return try await updateOwnProfile(userId: userId, fields: fields)
        }
    }

    public func followedSpotIds() async throws -> Set<UUID> {
        guard let userId = signedInUserId else { return [] }
        return try await perform { Set(try await followedIds(userId: userId, target: .spot)) }
    }

    public func followedSpots() async throws -> [Spot] {
        guard signedInUserId != nil else { return [] }
        return try await perform {
            let data = try await rpc("followed_spots")
            return try SupabaseDecoding.spots(from: data).sorted { $0.title < $1.title }
        }
    }

    public func followedAnimals() async throws -> [Animal] {
        guard let userId = signedInUserId else { return [] }
        return try await perform {
            let ids = try await followedIds(userId: userId, target: .animal)
            guard !ids.isEmpty else { return [] }
            let response: PostgrestResponse<Void> = try await client.from("animals")
                .select()
                .in("id", values: ids.map { $0.postgresString as any PostgrestFilterValue })
                .execute()
            return try SupabaseDecoding.animals(from: response.data).sorted { $0.displayName < $1.displayName }
        }
    }

    public func setFollowing(_ following: Bool, target: FollowTarget, id: UUID) async throws {
        try await perform {
            let userId = try requireUserId()
            if following {
                let row: JSONObject = [
                    "user_id": Param.uuid(userId),
                    "target_type": .string(target.rawValue),
                    "target_id": Param.uuid(id),
                ]
                try await insertIgnoringDuplicate(into: "follows", row)
            } else {
                try await client.from("follows")
                    .delete(returning: .minimal)
                    .eq("user_id", value: userId.postgresString)
                    .eq("target_type", value: target.rawValue)
                    .eq("target_id", value: id.postgresString)
                    .execute()
            }
        }
    }

    public func guardedSpotIds() async throws -> Set<UUID> {
        guard let userId = signedInUserId else { return [] }
        return try await perform {
            let response: PostgrestResponse<Void> = try await client.from("guardians")
                .select("spot_id")
                .eq("user_id", value: userId.postgresString)
                .execute()
            return Set(SupabaseJSON.uuidColumn("spot_id", from: response.data))
        }
    }

    /// Yalnızca `schedule` sütununa update yetkisi olduğundan PostgREST upsert'i (tüm sütunları SET eder)
    /// kullanılmaz: önce güncelle, satır yoksa ekle.
    public func setGuardian(spotId: UUID, schedule: Set<Weekday>?) async throws {
        try await perform {
            let userId = try requireUserId()
            guard let schedule else {
                try await client.from("guardians")
                    .delete(returning: .minimal)
                    .eq("user_id", value: userId.postgresString)
                    .eq("spot_id", value: spotId.postgresString)
                    .execute()
                return
            }
            let days = Param.ints(schedule.sorted().map(\.rawValue))
            let updated: PostgrestResponse<Void> = try await client.from("guardians")
                .update(["schedule": days] as JSONObject, returning: .representation)
                .eq("user_id", value: userId.postgresString)
                .eq("spot_id", value: spotId.postgresString)
                .select("spot_id")
                .execute()
            guard SupabaseJSON.uuidColumn("spot_id", from: updated.data).isEmpty else { return }
            try await insertIgnoringDuplicate(into: "guardians", [
                "user_id": Param.uuid(userId),
                "spot_id": Param.uuid(spotId),
                "schedule": days,
            ])
        }
    }

    func followedIds(userId: UUID, target: FollowTarget) async throws -> [UUID] {
        let response: PostgrestResponse<Void> = try await client.from("follows")
            .select("target_id")
            .eq("user_id", value: userId.postgresString)
            .eq("target_type", value: target.rawValue)
            .execute()
        return SupabaseJSON.uuidColumn("target_id", from: response.data)
    }

    /// Bileşik birincil anahtarlı satırlar (follows, blocks, guardians): zaten varsa sessizce geç.
    func insertIgnoringDuplicate(into table: String, _ row: JSONObject) async throws {
        do {
            try await client.from(table).insert(row, returning: .minimal).execute()
        } catch where SupabaseErrorMapper.isUniqueViolation(error) {
            return
        }
    }
}

// MARK: - NotificationRepository

extension SupabaseBackend: NotificationRepository {
    public func notifications() async throws -> [AppNotification] {
        guard let userId = signedInUserId else { return [] }
        return try await perform {
            let response: PostgrestResponse<Void> = try await client.from("notifications")
                .select(NotificationDTO.columns)
                .eq("user_id", value: userId.postgresString)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
            return try SupabaseDecoding.notifications(from: response.data)
        }
    }

    public func markRead(ids: [UUID]) async throws {
        guard let userId = signedInUserId, !ids.isEmpty else { return }
        try await perform {
            _ = try await client.from("notifications")
                .update(["read_at": Param.date(now())] as JSONObject, returning: .minimal)
                .eq("user_id", value: userId.postgresString)
                .in("id", values: ids.map { $0.postgresString as any PostgrestFilterValue })
                .is("read_at", value: nil)
                .execute()
        }
    }

    public func preferences() async throws -> NotificationPreferences {
        guard let userId = signedInUserId else { return .default }
        return try await perform {
            let response: PostgrestResponse<Void> = try await client.from("notification_prefs")
                .select(NotificationPrefsDTO.columns)
                .eq("user_id", value: userId.postgresString)
                .limit(1)
                .execute()
            return try SupabaseDecoding.notificationPreferences(from: response.data) ?? .default
        }
    }

    /// Satır `auth.users` trigger'ıyla oluşur; `user_id` sütununa update yetkisi olmadığından upsert yerine
    /// güncelle, satır yoksa ekle.
    public func updatePreferences(_ preferences: NotificationPreferences) async throws {
        try await perform {
            let userId = try requireUserId()
            let fields = Self.notificationPrefsFields(preferences)
            let updated: PostgrestResponse<Void> = try await client.from("notification_prefs")
                .update(fields, returning: .representation)
                .eq("user_id", value: userId.postgresString)
                .select("user_id")
                .execute()
            guard SupabaseJSON.uuidColumn("user_id", from: updated.data).isEmpty else { return }
            var row = fields
            row["user_id"] = Param.uuid(userId)
            try await insertIgnoringDuplicate(into: "notification_prefs", row)
        }
    }

    /// `notification_prefs` satırına yazılan alanlar: güncelleme ve ekleme için ortak (`user_id` hariç).
    /// Yetkiler sütun bazlı olduğundan her alanın insert + update yetkisi migration'da verilmiş olmalı.
    static func notificationPrefsFields(_ preferences: NotificationPreferences) -> JSONObject {
        [
            "radius_m": .integer(preferences.radiusMeters),
            "quiet_start": .integer(preferences.quietStartHour),
            "quiet_end": .integer(preferences.quietEndHour),
            "need_food_nearby": .bool(preferences.needFoodNearby),
            "followed_updates": .bool(preferences.followedUpdates),
            "guardian_alerts": .bool(preferences.guardianAlerts),
            "community_updates": .bool(preferences.communityUpdates),
        ]
    }

    public func registerDeviceToken(_ token: String) async throws {
        try await perform {
            _ = try requireUserId()
            _ = try await rpc("register_device_token", ["p_token": .string(token)])
        }
    }

    /// Sunucu 3 ondalığa yuvarlar ve yalnızca son değeri tutar (D8).
    public func updateNotifyCenter(_ coordinate: Coordinate) async throws {
        try await perform {
            _ = try requireUserId()
            _ = try await rpc("update_notify_center", [
                "lat": .double(coordinate.latitude),
                "lng": .double(coordinate.longitude),
            ])
        }
    }
}

// MARK: - ModerationRepository

extension SupabaseBackend: ModerationRepository {
    /// Şikâyetleri yalnızca moderatör okuyabildiğinden `return=minimal` ile eklenir.
    public func report(_ draft: ReportDraft) async throws {
        try await perform {
            let userId = try requireUserId()
            let row: JSONObject = [
                "reporter_id": Param.uuid(userId),
                "target_type": .string(draft.target.rawValue),
                "target_id": Param.uuid(draft.targetId),
                "reason": .string(draft.reason.rawValue),
                "details": Param.text(draft.details),
            ]
            try await client.from("reports").insert(row, returning: .minimal).execute()
        }
    }

    public func block(userId blockedId: UUID) async throws {
        try await perform {
            let userId = try requireUserId()
            try await insertIgnoringDuplicate(into: "blocks", [
                "user_id": Param.uuid(userId),
                "blocked_user_id": Param.uuid(blockedId),
            ])
        }
    }

    public func unblock(userId blockedId: UUID) async throws {
        try await perform {
            let userId = try requireUserId()
            try await client.from("blocks")
                .delete(returning: .minimal)
                .eq("user_id", value: userId.postgresString)
                .eq("blocked_user_id", value: blockedId.postgresString)
                .execute()
        }
    }

    public func blockedUserIds() async throws -> Set<UUID> {
        guard let userId = signedInUserId else { return [] }
        return try await perform {
            let response: PostgrestResponse<Void> = try await client.from("blocks")
                .select("blocked_user_id")
                .eq("user_id", value: userId.postgresString)
                .execute()
            return Set(SupabaseJSON.uuidColumn("blocked_user_id", from: response.data))
        }
    }
}

// MARK: - DonationRepository

extension SupabaseBackend: DonationRepository {
    public func overview() async throws -> DonationOverview? {
        try await perform {
            let data = try await rpc("donation_overview")
            return try SupabaseDecoding.donationOverview(from: data)
        }
    }

    /// Yalnızca "bağış sayfasına gidildi" (PRD 8.2); anonim de çağrılabilir.
    public func logDonationClick(refCode: String) async throws {
        try await perform {
            _ = try await rpc("log_donation_click", ["p_ref_code": .string(refCode)])
        }
    }
}

// MARK: - MediaUploader

extension SupabaseBackend: MediaUploader {
    static let photosBucket = "photos"

    /// `photos/{uid}/{uuid}.jpg` yoluna yükler ve herkese açık URL döner. ImageIO olan platformlarda önce
    /// EXIF/GPS silinir ve uzun kenar 1600 px'e indirilir (PRD 7.1).
    public func uploadJPEG(_ data: Data) async throws -> URL {
        try await perform {
            let userId = try requireUserId()
            let payload = try Self.sanitizedJPEG(data)
            let path = Self.storagePath(userId: userId, fileId: UUID())
            let bucket = client.storage.from(Self.photosBucket)
            try await bucket.upload(path, data: payload, options: FileOptions(contentType: "image/jpeg"))
            return try bucket.getPublicURL(path: path)
        }
    }

    /// Storage politikası klasör adını `auth.uid()::text` (küçük harf) ile karşılaştırır.
    static func storagePath(userId: UUID, fileId: UUID) -> String {
        "\(userId.postgresString)/\(fileId.postgresString).jpg"
    }

    static func sanitizedJPEG(_ data: Data) throws -> Data {
        #if canImport(ImageIO)
        do {
            return try PhotoProcessor.sanitizedJPEG(from: data)
        } catch {
            // Konum içerebilecek ham veriyi göndermektense yüklemeyi reddet.
            throw MamaError.invalidInput("Bu fotoğraf işlenemedi. Başka bir fotoğraf dener misin?")
        }
        #else
        return data
        #endif
    }
}
