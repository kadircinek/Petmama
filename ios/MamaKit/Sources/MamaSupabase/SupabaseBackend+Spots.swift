import Foundation
import MamaCore
import Supabase

// MARK: - SpotRepository

extension SupabaseBackend: SpotRepository {
    public func spots(in bounds: GeoBounds) async throws -> [Spot] {
        try await perform {
            let data = try await rpc("spots_in_bounds", [
                "min_lat": .double(bounds.minLatitude),
                "min_lng": .double(bounds.minLongitude),
                "max_lat": .double(bounds.maxLatitude),
                "max_lng": .double(bounds.maxLongitude),
            ])
            return try SupabaseDecoding.spots(from: data)
        }
    }

    public func spots(near center: Coordinate, radiusMeters: Int) async throws -> [Spot] {
        try await perform {
            let data = try await rpc("spots_near", [
                "lat": .double(center.latitude),
                "lng": .double(center.longitude),
                "radius_m": .integer(radiusMeters),
            ])
            return try SupabaseDecoding.spots(from: data)
        }
    }

    public func spot(id: UUID) async throws -> Spot? {
        try await perform {
            let data = try await rpc("spot_detail", ["p_spot_id": Param.uuid(id)])
            return try SupabaseDecoding.spots(from: data).first
        }
    }

    public func search(query: String, near center: Coordinate?) async throws -> [Spot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await perform {
            var params: JSONObject = ["q": .string(trimmed)]
            if let center {
                params["lat"] = .double(center.latitude)
                params["lng"] = .double(center.longitude)
            }
            let data = try await rpc("search_spots", params)
            return try SupabaseDecoding.spots(from: data)
        }
    }

    public func feedingTimeline(spotId: UUID, days: Int) async throws -> [FeedingDay] {
        try await perform {
            let data = try await rpc("spot_feeding_timeline", [
                "p_spot_id": Param.uuid(spotId),
                "days": .integer(max(1, days)),
            ])
            return try SupabaseDecoding.feedingTimeline(from: data)
        }
    }

    public func guardians(spotId: UUID) async throws -> [Guardian] {
        try await perform {
            let data = try await rpc("spot_guardians", ["p_spot_id": Param.uuid(spotId)])
            return try SupabaseDecoding.guardians(from: data).sorted { $0.displayName < $1.displayName }
        }
    }

    public func duplicates(near coordinate: Coordinate) async throws -> [DuplicateCandidate] {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("find_duplicate_spots", [
                "lat": .double(coordinate.latitude),
                "lng": .double(coordinate.longitude),
            ])
            return try SupabaseDecoding.duplicates(from: data)
        }
    }

    public func createSpot(_ draft: SpotDraft) async throws -> CreateSpotOutcome {
        try await perform {
            _ = try requireUserId()
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = try await rpc("create_spot", [
                "lat": .double(draft.coordinate.latitude),
                "lng": .double(draft.coordinate.longitude),
                "p_type": .string(draft.type.rawValue),
                "p_species": .string(draft.species.rawValue),
                "p_title": .string(title.isEmpty ? "Yeni nokta" : String(title.prefix(80))),
                "p_note": Param.text(draft.note),
                "p_photo_url": Param.string(draft.photoURL?.absoluteString),
                "p_visibility": .string(draft.visibility.rawValue),
                "p_force": .bool(draft.force),
            ])
            return try SupabaseDecoding.createSpotOutcome(from: data)
        }
    }

    public func reportGone(spotId: UUID) async throws -> GoneReportOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("report_spot_gone", ["p_spot_id": Param.uuid(spotId)])
            return try SupabaseDecoding.goneReportOutcome(from: data)
        }
    }

    public func neighborhoodSummary(near center: Coordinate) async throws -> NeighborhoodSummary {
        try await perform {
            let data = try await rpc("neighborhood_summary", [
                "lat": .double(center.latitude),
                "lng": .double(center.longitude),
            ])
            return try SupabaseDecoding.neighborhoodSummary(from: data)
        }
    }
}

// MARK: - CheckInRepository

extension SupabaseBackend: CheckInRepository {
    /// Kullanıcının konumu yalnızca mesafe doğrulaması için gönderilir; sunucu saklamaz (PRD 9.5).
    public func checkIn(_ draft: CheckInDraft) async throws -> CheckInOutcome {
        try await perform {
            _ = try requireUserId()
            let data = try await rpc("check_in", [
                "p_spot_id": Param.uuid(draft.spotId),
                "p_kind": .string(draft.kind.rawValue),
                "p_amount": Param.string(draft.amount?.rawValue),
                "p_photo_url": Param.string(draft.photoURL?.absoluteString),
                "user_lat": .double(draft.userCoordinate.latitude),
                "user_lng": .double(draft.userCoordinate.longitude),
                // Çevrimdışı kuyruktan tekrar gönderimde çift kaydı önler (idempotent).
                "p_client_id": Param.uuid(draft.id),
            ])
            return try SupabaseDecoding.checkInOutcome(from: data, kind: draft.kind, fallbackId: draft.id)
        }
    }
}

// MARK: - AnimalRepository

extension SupabaseBackend: AnimalRepository {
    public func animals(atSpot spotId: UUID) async throws -> [Animal] {
        try await perform {
            let data = try await rpc("animals_at_spot", ["p_spot_id": Param.uuid(spotId)])
            return try SupabaseDecoding.animals(from: data)
        }
    }

    public func animal(id: UUID) async throws -> Animal? {
        try await perform {
            let response: PostgrestResponse<Void> = try await client.from("animals")
                .select()
                .eq("id", value: id.postgresString)
                .limit(1)
                .execute()
            return try SupabaseDecoding.animals(from: response.data).first
        }
    }

    public func spots(forAnimal animalId: UUID) async throws -> [Spot] {
        try await perform {
            let data = try await rpc("animal_spots_of", ["p_animal_id": Param.uuid(animalId)])
            return try SupabaseDecoding.spots(from: data)
        }
    }

    /// `animals` tablosuna doğrudan ekler (RLS: `created_by = auth.uid()`). `last_seen_spot_id` verilirse
    /// sunucu trigger'ı `animal_spots` bağlantısını oluşturur (FR-A2); ayrıca `mark_animal_seen` çağrılmaz.
    public func createAnimal(_ draft: AnimalDraft) async throws -> Animal {
        try await perform {
            let userId = try requireUserId()
            let row: JSONObject = [
                "species": .string(draft.species.rawValue),
                "name": Param.text(draft.name),
                "color_pattern": Param.text(draft.colorPattern),
                "sex": .string(draft.sex.rawValue),
                "age_estimate": .string(draft.ageEstimate.rawValue),
                "is_neutered": Param.bool(draft.isNeutered),
                "ear_tag": .bool(draft.earTag),
                "vaccination_info": Param.text(draft.vaccinationInfo),
                "temperament_tags": Param.strings(draft.temperamentTags.map(\.rawValue)),
                "warning": Param.string(draft.warning?.rawValue),
                "about": Param.text(draft.about),
                "photos": Param.strings(draft.photoURLs.map(\.absoluteString)),
                "last_seen_at": Param.date(now()),
                "last_seen_spot_id": Param.uuid(draft.spotId),
                "created_by": Param.uuid(userId),
            ]
            let response: PostgrestResponse<Void> = try await client.from("animals")
                .insert(row, returning: .representation)
                .select()
                .execute()
            guard let animal = try SupabaseDecoding.animals(from: response.data).first else {
                throw MamaError.server("animals insert: satır dönmedi")
            }
            return animal
        }
    }

    public func markSeen(animalId: UUID, spotId: UUID) async throws {
        try await perform {
            _ = try requireUserId()
            _ = try await rpc("mark_animal_seen", [
                "p_animal_id": Param.uuid(animalId),
                "p_spot_id": Param.uuid(spotId),
            ])
        }
    }
}
