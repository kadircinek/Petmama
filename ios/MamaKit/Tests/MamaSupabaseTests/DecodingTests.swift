import Foundation
import MamaCore
@testable import MamaSupabase
import XCTest

/// Sözleşmedeki (docs/backend-contract.md) satır şekilleriyle çözme + domain eşleme testleri.
final class DecodingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Double = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        return base.addingTimeInterval(second)
    }

    // MARK: - spot_row

    static let spotRows = """
    [
      {
        "id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10",
        "lat": 40.98621, "lng": 29.02544, "is_location_exact": false,
        "type": "food", "species": "cat", "title": "Moda Parkı girişi", "note": "Bankın arkası",
        "photo_url": "https://x.supabase.co/storage/v1/object/public/photos/u/p.jpg",
        "status": "fed_recent", "last_fed_at": "2026-11-04T08:15:00.123+00:00",
        "has_urgent_need": true, "open_need_count": 2,
        "visibility": "public", "is_active": true,
        "created_by": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "created_at": "2026-10-01T10:00:00Z",
        "animal_count": 4, "guardian_count": 1, "distance_m": null
      },
      {
        "id": "a3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22",
        "lat": 40.99, "lng": 29.03, "is_location_exact": true,
        "type": "water", "species": "dog", "title": "Yoğurtçu", "note": null, "photo_url": null,
        "status": "unknown", "last_fed_at": null, "has_urgent_need": false, "open_need_count": 0,
        "visibility": "fuzzed", "is_active": true, "created_by": null,
        "created_at": "2026-10-02T10:00:00.5Z", "animal_count": 0, "guardian_count": 0, "distance_m": 42.5
      }
    ]
    """

    func testSpotRowDecodesWithNullDistance() throws {
        let spots = try SupabaseDecoding.spots(from: data(Self.spotRows))
        XCTAssertEqual(spots.count, 2)

        let first = spots[0]
        XCTAssertEqual(first.id, UUID(uuidString: "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10"))
        XCTAssertEqual(first.coordinate, Coordinate(latitude: 40.98621, longitude: 29.02544))
        XCTAssertFalse(first.isLocationExact)
        XCTAssertEqual(first.type, .food)
        XCTAssertEqual(first.species, .cat)
        XCTAssertEqual(first.title, "Moda Parkı girişi")
        XCTAssertEqual(first.note, "Bankın arkası")
        XCTAssertEqual(first.photoURL?.lastPathComponent, "p.jpg")
        XCTAssertEqual(first.status, .fedRecent)
        XCTAssertEqual(first.lastFedAt!.timeIntervalSince1970, utc(2026, 11, 4, 8, 15, 0.123).timeIntervalSince1970, accuracy: 0.0005)
        XCTAssertTrue(first.hasUrgentNeed)
        XCTAssertEqual(first.openNeedCount, 2)
        XCTAssertEqual(first.visibility, .public)
        XCTAssertTrue(first.isActive)
        XCTAssertEqual(first.createdBy, UUID(uuidString: "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11"))
        XCTAssertEqual(first.createdAt, utc(2026, 10, 1, 10))
        XCTAssertEqual(first.animalCount, 4)
        XCTAssertEqual(first.guardianCount, 1)
        XCTAssertNil(first.distanceMeters)

        let second = spots[1]
        XCTAssertEqual(second.type, .water)
        XCTAssertEqual(second.species, .dog)
        XCTAssertNil(second.note)
        XCTAssertNil(second.photoURL)
        XCTAssertNil(second.lastFedAt)
        XCTAssertNil(second.createdBy)
        XCTAssertEqual(second.visibility, .fuzzed)
        XCTAssertEqual(second.distanceMeters, 42.5)
        XCTAssertEqual(second.createdAt.timeIntervalSince1970, utc(2026, 10, 2, 10, 0, 0.5).timeIntervalSince1970, accuracy: 0.0005)
    }

    func testSpotRowUnknownEnumsFallBackAndBadRowsAreSkipped() throws {
        let json = """
        [
          {"id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "lat": 41, "lng": 29, "type": "bowl", "species": "bird",
           "status": "sparkly", "visibility": "secret", "title": "X", "photo_url": "", "last_fed_at": "not a date"},
          {"id": "not-a-uuid", "lat": 41, "lng": 29},
          {"id": "a3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22", "lat": null, "lng": 29},
          {"id": "b3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22", "lat": 41.1, "lng": 29.1, "extra_future_column": [1, 2]}
        ]
        """
        let spots = try SupabaseDecoding.spots(from: data(json))
        XCTAssertEqual(spots.map(\.id.uuidString), [
            "6F1C2A6E-1B7D-4C39-9C39-0D5D1F4B8A10",
            "B3E0D4C2-9F61-4F0E-9A51-2B6F0C7D8E22",
        ])
        let lenient = spots[0]
        XCTAssertEqual(lenient.type, .mixed)
        XCTAssertEqual(lenient.species, .both)
        XCTAssertEqual(lenient.status, .unknown)
        XCTAssertEqual(lenient.visibility, .fuzzed)
        XCTAssertNil(lenient.photoURL)
        XCTAssertNil(lenient.lastFedAt)
        XCTAssertFalse(spots[1].isLocationExact)
        XCTAssertEqual(spots[1].title, "")
    }

    func testEmptyBodiesDecodeAsEmptyLists() throws {
        XCTAssertEqual(try SupabaseDecoding.spots(from: data("[]")), [])
        XCTAssertEqual(try SupabaseDecoding.spots(from: Data()), [])
        XCTAssertEqual(try SupabaseDecoding.needs(from: data("null")), [])
    }

    // MARK: - need_row

    func testNeedRowDecoding() throws {
        let json = """
        [
          {
            "id": "11111111-2222-3333-4444-555555555555", "type": "vet", "urgency": "urgent", "status": "claimed",
            "description": "Sol arka bacağı aksıyor", "photos": ["https://cdn/x.jpg", ""],
            "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "spot_title": "Moda Parkı",
            "animal_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "animal_name": "Pamuk",
            "animal_photo_url": "https://cdn/pamuk.jpg",
            "lat": 40.98, "lng": 29.02, "is_location_exact": false, "distance_m": 310.4,
            "created_by": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11",
            "claimed_by": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "claimed_by_name": "Ayşe",
            "created_at": "2026-11-03T18:00:00.000001+00:00", "claimed_at": "2026-11-04T07:00:00+03:00",
            "resolved_at": null
          },
          {
            "id": "21111111-2222-3333-4444-555555555555", "type": "neuter", "urgency": "normal", "status": "open",
            "description": null, "photos": [], "spot_id": null, "spot_title": null,
            "animal_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "animal_name": null, "animal_photo_url": null,
            "lat": null, "lng": null, "is_location_exact": null, "distance_m": null,
            "created_by": null, "claimed_by": null, "claimed_by_name": null,
            "created_at": "2026-11-02T18:00:00Z", "claimed_at": null, "resolved_at": null
          },
          {"id": "31111111-2222-3333-4444-555555555555", "type": "teleport", "urgency": "urgent", "status": "open"}
        ]
        """
        let needs = try SupabaseDecoding.needs(from: data(json))
        XCTAssertEqual(needs.count, 2, "Bilinmeyen ihtiyaç tipi atlanmalı")

        let vet = needs[0]
        XCTAssertEqual(vet.type, .vet)
        XCTAssertEqual(vet.urgency, .urgent)
        XCTAssertEqual(vet.status, .claimed)
        XCTAssertEqual(vet.description, "Sol arka bacağı aksıyor")
        XCTAssertEqual(vet.photoURLs, [URL(string: "https://cdn/x.jpg")!])
        XCTAssertEqual(vet.spotTitle, "Moda Parkı")
        XCTAssertEqual(vet.animalName, "Pamuk")
        XCTAssertEqual(vet.animalPhotoURL, URL(string: "https://cdn/pamuk.jpg"))
        XCTAssertEqual(vet.coordinate, Coordinate(latitude: 40.98, longitude: 29.02))
        XCTAssertFalse(vet.isLocationExact)
        XCTAssertEqual(vet.distanceMeters, 310.4)
        XCTAssertEqual(vet.claimedByName, "Ayşe")
        XCTAssertEqual(vet.claimedAt, utc(2026, 11, 4, 4))
        XCTAssertNil(vet.resolvedAt)
        XCTAssertTrue(vet.isUrgent)

        let neuter = needs[1]
        XCTAssertEqual(neuter.description, "")
        XCTAssertNil(neuter.coordinate)
        XCTAssertNil(neuter.spotId)
        XCTAssertEqual(neuter.photoURLs, [])
        XCTAssertNil(neuter.distanceMeters)
    }

    // MARK: - animal_row

    func testAnimalRowDropsUnknownTemperamentTagsAndWarnings() throws {
        let json = """
        [
          {
            "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "species": "cat", "name": "Pamuk",
            "color_pattern": "Beyaz", "sex": "female", "age_estimate": "adult", "is_neutered": true, "ear_tag": true,
            "vaccination_info": "Kuduz 2026", "temperament_tags": ["friendly", "sleepy", "may_be_aggressive", "friendly"],
            "warning": "breathes_fire", "about": "Çok tatlı", "photos": ["https://cdn/1.jpg", "https://cdn/2.jpg"],
            "last_seen_at": "2026-11-04T06:00:00Z", "last_seen_spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10",
            "created_by": null, "created_at": "2026-09-01T00:00:00Z",
            "seen_count": 12, "spot_last_seen_at": "2026-11-04T06:00:00Z"
          },
          {
            "id": "baaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "species": "dog", "name": null, "color_pattern": null,
            "sex": "hermaphrodite", "age_estimate": "ancient", "is_neutered": null, "ear_tag": false,
            "vaccination_info": null, "temperament_tags": [], "warning": "may_bite", "about": null, "photos": [],
            "last_seen_at": null, "last_seen_spot_id": null, "created_by": null, "created_at": "2026-09-01T00:00:00Z"
          },
          {"id": "caaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "species": "parrot", "created_at": "2026-09-01T00:00:00Z"}
        ]
        """
        let animals = try SupabaseDecoding.animals(from: data(json))
        XCTAssertEqual(animals.count, 2)

        let pamuk = animals[0]
        XCTAssertEqual(pamuk.species, .cat)
        XCTAssertEqual(pamuk.temperamentTags, [.friendly, .mayBeAggressive])
        XCTAssertNil(pamuk.warning)
        XCTAssertEqual(pamuk.sex, .female)
        XCTAssertEqual(pamuk.ageEstimate, .adult)
        XCTAssertEqual(pamuk.isNeutered, true)
        XCTAssertTrue(pamuk.earTag)
        XCTAssertEqual(pamuk.photoURLs.count, 2)
        XCTAssertEqual(pamuk.seenCount, 12)
        XCTAssertEqual(pamuk.lastSeenAt, utc(2026, 11, 4, 6))
        XCTAssertEqual(pamuk.lastSeenSpotId, UUID(uuidString: "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10"))

        let dog = animals[1]
        XCTAssertEqual(dog.sex, .unknown)
        XCTAssertEqual(dog.ageEstimate, .unknown)
        XCTAssertNil(dog.isNeutered)
        XCTAssertEqual(dog.warning, .mayBite)
        XCTAssertNil(dog.seenCount, "animals tablosu satırında seen_count yok")
        XCTAssertEqual(dog.displayName, "İsimsiz köpek")
    }

    // MARK: - create_spot

    func testCreateSpotStatuses() throws {
        let created = try SupabaseDecoding.createSpotOutcome(from: data("""
        {"status": "created", "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "moderation_state": "approved"}
        """))
        XCTAssertEqual(created, .created(id: UUID(uuidString: "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10")!, pendingModeration: false))

        let pending = try SupabaseDecoding.createSpotOutcome(from: data("""
        {"status": "created", "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "moderation_state": "pending"}
        """))
        XCTAssertEqual(pending, .created(id: UUID(uuidString: "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10")!, pendingModeration: true))

        let duplicate = try SupabaseDecoding.createSpotOutcome(from: data("""
        {"status": "duplicate", "duplicates": [
          {"id": "a3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22", "title": "Yoğurtçu", "distance_m": 9.4},
          {"id": "b3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22", "title": "Kilise önü", "distance_m": 14}
        ]}
        """))
        XCTAssertEqual(duplicate, .duplicate([
            DuplicateCandidate(id: UUID(uuidString: "a3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22")!, title: "Yoğurtçu", distanceMeters: 9.4),
            DuplicateCandidate(id: UUID(uuidString: "b3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22")!, title: "Kilise önü", distanceMeters: 14),
        ]))

        XCTAssertEqual(try SupabaseDecoding.createSpotOutcome(from: data(#"{"status": "limit_reached", "limit": 5}"#)), .limitReached(limit: 5))
        XCTAssertEqual(try SupabaseDecoding.createSpotOutcome(from: data(#"{"status": "rejected_content"}"#)), .rejectedContent)

        XCTAssertThrowsError(try SupabaseDecoding.createSpotOutcome(from: data(#"{"status": "mystery"}"#))) { error in
            guard case .server = error as? MamaError else { return XCTFail("server bekleniyordu: \(error)") }
        }
        XCTAssertThrowsError(try SupabaseDecoding.createSpotOutcome(from: data(#"{"status": "created"}"#)))
    }

    // MARK: - check_in

    func testCheckInStatuses() throws {
        let draftId = UUID()
        let ok = try SupabaseDecoding.checkInOutcome(from: data("""
        {"status": "ok", "checkin_id": "11111111-2222-3333-4444-555555555555", "distance_m": 42,
         "closed_need_count": 1, "spot_status": "fed_recent"}
        """), kind: .fed, fallbackId: draftId)
        XCTAssertEqual(ok, .success(CheckInReceipt(
            checkInId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            distanceMeters: 42, closedNeedCount: 1, spotStatus: .fedRecent
        )))

        let tooFar = try SupabaseDecoding.checkInOutcome(from: data(#"{"status": "too_far", "distance_m": 180, "max_distance_m": 100}"#),
                                                         kind: .fed, fallbackId: draftId)
        XCTAssertEqual(tooFar, .tooFar(distanceMeters: 180, maxDistanceMeters: 100))

        let tooFarRequest = try SupabaseDecoding.checkInOutcome(from: data(#"{"status": "too_far", "distance_m": 400}"#),
                                                                kind: .needFood, fallbackId: draftId)
        XCTAssertEqual(tooFarRequest, .tooFar(distanceMeters: 400, maxDistanceMeters: CheckInPolicy.requestMaxDistance))

        XCTAssertEqual(try SupabaseDecoding.checkInOutcome(from: data(#"{"status": "spot_inactive"}"#), kind: .fed, fallbackId: draftId), .spotInactive)
        XCTAssertEqual(try SupabaseDecoding.checkInOutcome(from: data(#"{"status": "rate_limited"}"#), kind: .water, fallbackId: draftId), .rateLimited)

        XCTAssertThrowsError(try SupabaseDecoding.checkInOutcome(from: data(#"{"status": "not_found"}"#), kind: .fed, fallbackId: draftId)) { error in
            XCTAssertEqual(error as? MamaError, .notFound)
        }
    }

    // MARK: - claim / resolve / gone

    func testClaimResolveAndGoneResults() throws {
        XCTAssertEqual(try SupabaseDecoding.claimOutcome(from: data(#"{"status": "ok"}"#)), .ok)
        XCTAssertEqual(try SupabaseDecoding.claimOutcome(from: data(#"{"status": "already_claimed"}"#)), .alreadyClaimed)
        XCTAssertEqual(try SupabaseDecoding.claimOutcome(from: data(#"{"status": "resolved"}"#)), .resolved)
        XCTAssertThrowsError(try SupabaseDecoding.claimOutcome(from: data(#"{"status": "not_found"}"#))) { error in
            XCTAssertEqual(error as? MamaError, .notFound)
        }

        XCTAssertTrue(try SupabaseDecoding.resolveAllowed(from: data(#"{"status": "ok"}"#)))
        XCTAssertFalse(try SupabaseDecoding.resolveAllowed(from: data(#"{"status": "not_allowed"}"#)))

        let gone = try SupabaseDecoding.goneReportOutcome(from: data(#"{"status": "ok", "count": 3, "deactivated": true}"#))
        XCTAssertEqual(gone, GoneReportOutcome(reportCount: 3, deactivated: true))
    }

    func testCreateNeedScalarUUID() throws {
        XCTAssertEqual(try SupabaseDecoding.createdId(from: data(#""11111111-2222-3333-4444-555555555555""#)),
                       UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        XCTAssertEqual(try SupabaseDecoding.createdId(from: data("11111111-2222-3333-4444-555555555555\n")),
                       UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        XCTAssertThrowsError(try SupabaseDecoding.createdId(from: data("null")))
    }

    // MARK: - spot_feeding_timeline

    func testFeedingTimelineParsesDateStringsInIstanbul() throws {
        let json = """
        [
          {"day": "2026-11-04", "fed_count": 2, "need_count": 1, "last_fed_at": "2026-11-04T08:15:00.123456+00:00"},
          {"day": "2026-11-02", "fed_count": 0, "need_count": 0, "last_fed_at": null},
          {"day": "2026-11-03", "fed_count": 1, "need_count": 0, "last_fed_at": "2026-11-03T19:00:00+00:00"}
        ]
        """
        let days = try SupabaseDecoding.feedingTimeline(from: data(json))
        XCTAssertEqual(days.count, 3)
        // Europe/Istanbul = UTC+3 → yerel gece yarısı bir önceki gün 21:00 UTC.
        XCTAssertEqual(days.map(\.day), [utc(2026, 11, 1, 21), utc(2026, 11, 2, 21), utc(2026, 11, 3, 21)])
        XCTAssertEqual(days.map(\.fedCount), [0, 1, 2])
        XCTAssertNil(days[0].lastFedAt)
        XCTAssertEqual(days[2].needCount, 1)
        XCTAssertEqual(days[2].lastFedAt!.timeIntervalSince1970, utc(2026, 11, 4, 8, 15, 0.123456).timeIntervalSince1970, accuracy: 0.000_01)

        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = NotificationPolicy.timeZone
        XCTAssertEqual(istanbul.component(.day, from: days[2].day), 4)
        XCTAssertEqual(istanbul.component(.hour, from: days[2].day), 0)
    }

    // MARK: - Diğer tablolar / RPC'ler

    func testGuardiansProfileAndStats() throws {
        let guardians = try SupabaseDecoding.guardians(from: data("""
        [{"user_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Ayşe", "avatar_url": null,
          "is_verified_feeder": true, "schedule": [1, 3, 9, 7]}]
        """))
        XCTAssertEqual(guardians.first?.displayName, "Ayşe")
        XCTAssertEqual(guardians.first?.schedule, [.monday, .wednesday, .sunday])
        XCTAssertEqual(guardians.first?.isVerifiedFeeder, true)

        let profiles = try SupabaseDecoding.profiles(from: data("""
        [{"id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Ayşe", "avatar_url": "",
          "neighborhood": "Moda", "trust_score": 23, "is_verified_feeder": true, "is_moderator": false,
          "created_at": "2026-01-01T00:00:00+00:00"}]
        """))
        XCTAssertEqual(profiles, [UserProfile(
            id: UUID(uuidString: "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11")!, displayName: "Ayşe", avatarURL: nil,
            neighborhood: "Moda", trustScore: 23, isVerifiedFeeder: true, isModerator: false, createdAt: utc(2026, 1, 1)
        )])

        let stats = try SupabaseDecoding.profileStats(from: data("""
        [{"fed_spot_count": 4, "checkin_count": 31, "resolved_need_count": 2, "verified_checkins_30d": 18}]
        """))
        XCTAssertEqual(stats, ProfileStats(fedSpotCount: 4, checkInCount: 31, resolvedNeedCount: 2, verifiedCheckInsLast30Days: 18))
        XCTAssertEqual(try SupabaseDecoding.profileStats(from: data("[]")), .zero)

        let summary = try SupabaseDecoding.neighborhoodSummary(from: data("""
        [{"fed_spots_today": 7, "open_needs": 3, "needs_food_spots": 2, "active_spots_7d": 19}]
        """))
        XCTAssertEqual(summary, NeighborhoodSummary(fedSpotsToday: 7, openNeeds: 3, needsFoodSpots: 2, activeSpots7d: 19))

        let duplicates = try SupabaseDecoding.duplicates(from: data("""
        [{"id": "b3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22", "title": "B", "distance_m": 12.0},
         {"id": "a3e0d4c2-9f61-4f0e-9a51-2b6f0c7d8e22", "title": "A", "distance_m": 3.5}]
        """))
        XCTAssertEqual(duplicates.map(\.title), ["A", "B"])
    }

    func testNotificationsPreferencesAndDonation() throws {
        let notifications = try SupabaseDecoding.notifications(from: data("""
        [
          {"id": "11111111-2222-3333-4444-555555555555", "kind": "thanks_fed", "title": "Teşekkürler!",
           "body": "Ayşe mama koydu.", "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "need_id": null,
           "read_at": null, "created_at": "2026-11-04T08:15:00.123Z"},
          {"id": "21111111-2222-3333-4444-555555555555", "kind": "future_kind", "title": "?", "body": "?",
           "created_at": "2026-11-04T08:15:00Z"}
        ]
        """))
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.kind, .thanksFed)
        XCTAssertFalse(notifications.first?.isRead ?? true)

        let prefs = try SupabaseDecoding.notificationPreferences(from: data("""
        [{"radius_m": 2000, "quiet_start": 23, "quiet_end": 8, "need_food_nearby": false,
          "followed_updates": true, "guardian_alerts": false}]
        """))
        XCTAssertEqual(prefs, NotificationPreferences(radiusMeters: 2000, quietStartHour: 23, quietEndHour: 8,
                                                      needFoodNearby: false, followedUpdates: true, guardianAlerts: false))
        XCTAssertNil(try SupabaseDecoding.notificationPreferences(from: data("[]")))

        let overview = try SupabaseDecoding.donationOverview(from: data(#"[{"month": "2026-11-01", "kg_distributed": 412.5, "donor_count": 37}]"#))
        XCTAssertEqual(overview, DonationOverview(month: utc(2026, 10, 31, 21), kgDistributed: 412.5, donorCount: 37))
        let numericAsString = try SupabaseDecoding.donationOverview(from: data(#"[{"month": "2026-11-01", "kg_distributed": "12.25", "donor_count": 2}]"#))
        XCTAssertEqual(numericAsString?.kgDistributed, 12.25)
        XCTAssertNil(try SupabaseDecoding.donationOverview(from: data("[]")))
    }

    func testUUIDColumnHelper() {
        let ids = SupabaseJSON.uuidColumn("target_id", from: data("""
        [{"target_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10"}, {"target_id": null}, {"other": 1}]
        """))
        XCTAssertEqual(ids, [UUID(uuidString: "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10")!])
    }
}
