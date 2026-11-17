import Foundation
import MamaCore
@testable import MamaSupabase
import Supabase
import XCTest

/// Tanışma: sunucu satırı ve jsonb şekilleriyle çözme + domain eşleme testleri
/// (supabase/migrations/20261114000020…24).
final class SocialDecodingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }
    private func uuid(_ text: String) -> UUID { UUID(uuidString: text)! }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func assertServerError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case .server = error as? MamaError else {
                return XCTFail("server bekleniyordu: \(error)", file: file, line: line)
            }
        }
    }

    private func result(_ json: String) throws -> SocialResultDTO {
        try SupabaseDecoding.socialResult(from: data(json))
    }

    static let meetupId = "d0000000-0000-4000-8000-000000000001"
    static let convId = "e0000000-0000-4000-8000-000000000001"
    static let userId = "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11"

    // MARK: - social_profile_me

    func testSocialProfileDecodesAndEmptyMeansNil() throws {
        let profile = try SupabaseDecoding.socialProfile(from: data("""
        [{"is_visible": true, "about": "Kedi sever", "interests": ["cats", "fostering", "future_tag"], "consented": true}]
        """))
        XCTAssertEqual(profile, SocialProfile(isVisible: true, about: "Kedi sever", interests: [.cats, .fostering], hasConsented: true))
        XCTAssertNil(try SupabaseDecoding.socialProfile(from: data("[]")))
        XCTAssertNil(try SupabaseDecoding.socialProfile(from: data("")))
    }

    // MARK: - meetup_row

    func testMeetupRowDecodesWithViewerRoleAndNullConversation() throws {
        let meetups = try SupabaseDecoding.meetups(from: data("""
        [{"id": "\(Self.meetupId)", "title": "Moda'da mama turu", "description": "Birlikte mama koyalım",
          "starts_at": "2026-11-20T14:00:00+00:00", "ends_at": "2026-11-20T16:00:00+00:00",
          "place_name": "Moda Parkı", "lat": 40.98, "lng": 29.03, "spot_id": null, "spot_title": null,
          "capacity": 8, "participant_count": 3, "status": "active", "organizer_id": "\(Self.userId)",
          "organizer_name": "Ayşe", "organizer_avatar_url": "https://x.supabase.co/a.jpg",
          "organizer_is_verified": true, "viewer_role": "none", "conversation_id": null, "distance_m": 850.5,
          "created_at": "2026-11-14T09:00:00.5+00:00"},
         {"id": "d0000000-0000-4000-8000-000000000002", "title": "İptal", "description": "",
          "starts_at": "2026-11-21T14:00:00Z", "ends_at": "2026-11-21T15:00:00Z", "place_name": "Park",
          "lat": 41.0, "lng": 29.0, "capacity": null, "participant_count": 1, "status": "cancelled",
          "organizer_id": "\(Self.userId)", "organizer_name": "Ayşe", "viewer_role": "organizer",
          "conversation_id": "\(Self.convId)", "distance_m": null, "created_at": "2026-11-14T09:00:00Z"}]
        """))
        XCTAssertEqual(meetups.count, 2)
        let first = meetups[0]
        XCTAssertEqual(first.id, uuid(Self.meetupId))
        XCTAssertEqual(first.viewerRole, MeetupViewerRole.none)
        XCTAssertNil(first.conversationId)
        XCTAssertNil(first.spotId)
        XCTAssertEqual(first.capacity, 8)
        XCTAssertEqual(first.participantCount, 3)
        XCTAssertEqual(first.status, .active)
        XCTAssertEqual(first.startsAt, utc(2026, 11, 20, 14))
        XCTAssertEqual(first.endsAt, utc(2026, 11, 20, 16))
        XCTAssertEqual(first.coordinate, Coordinate(latitude: 40.98, longitude: 29.03))
        XCTAssertEqual(first.distanceMeters, 850.5)
        XCTAssertTrue(first.organizerIsVerified)
        XCTAssertEqual(first.organizerAvatarURL, URL(string: "https://x.supabase.co/a.jpg"))

        let second = meetups[1]
        XCTAssertEqual(second.viewerRole, .organizer)
        XCTAssertEqual(second.conversationId, uuid(Self.convId))
        XCTAssertEqual(second.status, .cancelled)
        XCTAssertNil(second.capacity)
        XCTAssertNil(second.distanceMeters)
        XCTAssertFalse(first.isTour, "is_tour yoksa (eski sunucu) normal buluşma")
    }

    func testMeetupRowDecodesIsTour() throws {
        let meetups = try SupabaseDecoding.meetups(from: data("""
        [{"id": "\(Self.meetupId)", "title": "Mama turu: Moda sahil", "starts_at": "2026-11-16T09:00:00Z",
          "ends_at": "2026-11-16T10:30:00Z", "place_name": "Moda sahil", "lat": 40.98, "lng": 29.03,
          "organizer_id": "\(Self.userId)", "status": "active", "viewer_role": "none", "is_tour": true},
         {"id": "d0000000-0000-4000-8000-000000000002", "starts_at": "2026-11-16T09:00:00Z",
          "ends_at": "2026-11-16T10:00:00Z", "lat": 41.0, "lng": 29.0, "organizer_id": "\(Self.userId)", "is_tour": false}]
        """))
        XCTAssertEqual(meetups.map(\.isTour), [true, false])
    }

    func testMeetupRowWithoutCoordinateOrUnknownStatus() throws {
        let meetups = try SupabaseDecoding.meetups(from: data("""
        [{"id": "\(Self.meetupId)", "starts_at": "2026-11-20T14:00:00Z", "ends_at": "2026-11-20T16:00:00Z",
          "lat": null, "lng": null, "organizer_id": "\(Self.userId)"},
         {"id": "d0000000-0000-4000-8000-000000000002", "starts_at": "2026-11-20T14:00:00Z",
          "ends_at": "2026-11-20T16:00:00Z", "lat": 41.0, "lng": 29.0, "status": "paused",
          "viewer_role": "wizard", "organizer_id": "\(Self.userId)"}]
        """))
        XCTAssertEqual(meetups.count, 1, "Konumsuz satır atlanır")
        XCTAssertEqual(meetups[0].status, .cancelled, "Bilinmeyen durum güvenli tarafta: iptal")
        XCTAssertEqual(meetups[0].viewerRole, MeetupViewerRole.none)
        XCTAssertTrue(try SupabaseDecoding.meetups(from: data("[]")).isEmpty)
    }

    func testMeetupParticipantsDecode() throws {
        let people = try SupabaseDecoding.meetupParticipants(from: data("""
        [{"user_id": "\(Self.userId)", "display_name": "Ayşe", "avatar_url": null, "is_verified_feeder": true, "is_organizer": true},
         {"user_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": null, "avatar_url": "", "is_verified_feeder": false, "is_organizer": false}]
        """))
        XCTAssertEqual(people.map(\.id), [uuid(Self.userId), uuid("0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11")])
        XCTAssertEqual(people.map(\.isOrganizer), [true, false])
        XCTAssertEqual(people[1].displayName, SupabaseBackend.placeholderDisplayName)
        XCTAssertNil(people[1].avatarURL)
    }

    // MARK: - animal_lovers_near

    func testAnimalLoversMapConnectionStates() throws {
        let req = "f0000000-0000-4000-8000-000000000001"
        let lovers = try SupabaseDecoding.animalLovers(from: data("""
        [{"user_id": "\(Self.userId)", "display_name": "Ayşe", "avatar_url": null, "about": "Merhaba",
          "interests": ["cats", "dogs"], "is_verified_feeder": true, "fed_30d": 12, "distance_band": "under_1km",
          "shared_interest_count": 2, "connection_state": "outgoing_pending", "request_id": "\(req)", "conversation_id": null},
         {"user_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Mehmet", "interests": [],
          "distance_band": "1_3km", "connection_state": "incoming_pending", "request_id": "\(req)"},
         {"user_id": "1c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Can", "interests": ["birds"],
          "distance_band": "3_10km", "connection_state": "connected", "conversation_id": "\(Self.convId)"},
         {"user_id": "2c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Deniz", "distance_band": "3_10km",
          "connection_state": "none"},
         {"user_id": "3c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Bilinmeyen", "distance_band": "far_away",
          "connection_state": "none"}]
        """))
        XCTAssertEqual(lovers.count, 4, "Bilinmeyen bantlı satır atlanır")
        XCTAssertEqual(lovers[0].connection, .outgoingPending(requestId: uuid(req)))
        XCTAssertEqual(lovers[0].distanceBand, .under1km)
        XCTAssertEqual(lovers[0].interests, [.cats, .dogs])
        XCTAssertEqual(lovers[0].fedLast30Days, 12)
        XCTAssertEqual(lovers[0].sharedInterestCount, 2)
        XCTAssertTrue(lovers[0].isVerifiedFeeder)
        XCTAssertEqual(lovers[1].connection, .incomingPending(requestId: uuid(req)))
        XCTAssertEqual(lovers[1].distanceBand, .from1to3km)
        XCTAssertEqual(lovers[2].connection, .connected(conversationId: uuid(Self.convId)))
        XCTAssertEqual(lovers[2].distanceBand, .from3to10km)
        XCTAssertEqual(lovers[3].connection, ConnectionState.none)
        XCTAssertFalse(lovers[0].fedToday, "fed_today yoksa (eski sunucu) false")
        XCTAssertNil(lovers[0].onTourMeetupId)
    }

    func testAnimalLoversDecodeFedTodayAndTour() throws {
        let lovers = try SupabaseDecoding.animalLovers(from: data("""
        [{"user_id": "\(Self.userId)", "distance_band": "under_1km", "connection_state": "none",
          "fed_today": true, "on_tour_meetup_id": "\(Self.meetupId)"},
         {"user_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "distance_band": "1_3km", "connection_state": "none",
          "fed_today": false, "on_tour_meetup_id": null}]
        """))
        XCTAssertEqual(lovers.map(\.fedToday), [true, false])
        XCTAssertEqual(lovers[0].onTourMeetupId, uuid(Self.meetupId))
        XCTAssertTrue(lovers[0].isOnTour)
        XCTAssertNil(lovers[1].onTourMeetupId)
    }

    func testAnimalLoverConnectionWithoutIdFallsBackToNone() throws {
        let lovers = try SupabaseDecoding.animalLovers(from: data("""
        [{"user_id": "\(Self.userId)", "distance_band": "under_1km", "connection_state": "outgoing_pending", "request_id": null},
         {"user_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "distance_band": "under_1km", "connection_state": "connected"}]
        """))
        XCTAssertEqual(lovers.map(\.connection), [.none, .none])
    }

    func testIncomingConnectionRequestsDecode() throws {
        let requests = try SupabaseDecoding.incomingConnectionRequests(from: data("""
        [{"request_id": "f0000000-0000-4000-8000-000000000001", "user_id": "\(Self.userId)", "display_name": "Ayşe",
          "avatar_url": null, "about": "Merhaba", "interests": ["cats"], "is_verified_feeder": false,
          "note": "Birlikte mama koyalım mı?", "created_at": "2026-11-14T08:00:00+00:00"},
         {"request_id": "f0000000-0000-4000-8000-000000000002", "user_id": null, "created_at": "2026-11-14T08:00:00Z"}]
        """))
        XCTAssertEqual(requests.count, 1, "Göndereni olmayan satır atlanır")
        XCTAssertEqual(requests[0].id, uuid("f0000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(requests[0].userId, uuid(Self.userId))
        XCTAssertEqual(requests[0].note, "Birlikte mama koyalım mı?")
        XCTAssertEqual(requests[0].interests, [.cats])
        XCTAssertEqual(requests[0].createdAt, utc(2026, 11, 14, 8))
    }

    // MARK: - sohbet

    func testConversationSummaryDecodes() throws {
        let rows = try SupabaseDecoding.conversations(from: data("""
        [{"conversation_id": "\(Self.convId)", "kind": "meetup", "title": "Moda'da mama turu",
          "meetup_id": "\(Self.meetupId)", "other_user_id": null, "other_avatar_url": null,
          "last_body": "Görüşürüz", "last_at": "2026-11-14T10:00:00.250+00:00", "unread": 3, "read_only": false},
         {"conversation_id": "e0000000-0000-4000-8000-000000000002", "kind": "direct", "title": "Silinmiş kullanıcı",
          "meetup_id": null, "other_user_id": null, "last_body": null, "last_at": null, "unread": 0, "read_only": true},
         {"conversation_id": "e0000000-0000-4000-8000-000000000003", "kind": "group", "title": "?"}]
        """))
        XCTAssertEqual(rows.count, 2, "Bilinmeyen tür atlanır")
        XCTAssertEqual(rows[0].kind, .meetup)
        XCTAssertEqual(rows[0].meetupId, uuid(Self.meetupId))
        XCTAssertEqual(rows[0].unreadCount, 3)
        XCTAssertEqual(rows[0].lastBody, "Görüşürüz")
        XCTAssertEqual(try XCTUnwrap(rows[0].lastAt).timeIntervalSince1970, utc(2026, 11, 14, 10).timeIntervalSince1970 + 0.25, accuracy: 0.0005)
        XCTAssertFalse(rows[0].isReadOnly)
        XCTAssertEqual(rows[1].kind, .direct)
        XCTAssertNil(rows[1].otherUserId)
        XCTAssertNil(rows[1].lastAt)
        XCTAssertTrue(rows[1].isReadOnly)
    }

    func testChatMessagesDecodeWithPendingFlag() throws {
        let messages = try SupabaseDecoding.chatMessages(from: data("""
        [{"id": "a0000000-0000-4000-8000-000000000001", "author_id": "\(Self.userId)", "author_name": "Ayşe",
          "author_avatar_url": null, "body": "Merhaba", "created_at": "2026-11-14T10:00:00.123+00:00", "is_pending": false},
         {"id": "a0000000-0000-4000-8000-000000000002", "author_id": "\(Self.userId)", "author_name": null,
          "body": "İncelemede", "created_at": "2026-11-14T10:01:00Z", "is_pending": true}]
        """))
        XCTAssertEqual(messages.map(\.body), ["Merhaba", "İncelemede"])
        XCTAssertEqual(messages.map(\.isPendingModeration), [false, true])
        XCTAssertEqual(messages[0].createdAt.timeIntervalSince1970, utc(2026, 11, 14, 10).timeIntervalSince1970 + 0.123, accuracy: 0.0005)
        XCTAssertEqual(messages[1].authorName, SupabaseBackend.placeholderDisplayName)
    }

    // MARK: - update_social_profile / consent

    func testUpdateProfileOutcomes() throws {
        XCTAssertEqual(try result(#"{"status":"ok"}"#).updateProfileOutcome(), .saved)
        XCTAssertEqual(try result(#"{"status":"consent_required"}"#).updateProfileOutcome(), .consentRequired)
        XCTAssertEqual(try result(#"{"status":"rejected_content"}"#).updateProfileOutcome(), .rejectedContent)
        XCTAssertEqual(try result(#"{"status":"invalid","reason":"about_too_long"}"#).updateProfileOutcome(), .aboutTooLong)
        XCTAssertEqual(try result(#"{"status":"invalid","reason":"location_required"}"#).updateProfileOutcome(), .locationRequired)
        assertServerError(try result(#"{"status":"invalid","reason":"new_reason"}"#).updateProfileOutcome())
        assertServerError(try result(#"{"status":"nope"}"#).updateProfileOutcome())
    }

    func testConsentRequiresOK() throws {
        XCTAssertNoThrow(try result(#"{"status":"ok"}"#).requireOK(rpc: "give_social_consent"))
        assertServerError(try result(#"{"status":"weird"}"#).requireOK(rpc: "give_social_consent"))
    }

    // MARK: - create_meetup / join_meetup

    func testCreateMeetupOutcomes() throws {
        XCTAssertEqual(
            try result(#"{"status":"created","meetup_id":"\#(Self.meetupId)","conversation_id":"\#(Self.convId)"}"#).createMeetupOutcome(),
            .created(meetupId: uuid(Self.meetupId), conversationId: uuid(Self.convId))
        )
        XCTAssertEqual(try result(#"{"status":"consent_required"}"#).createMeetupOutcome(), .consentRequired)
        XCTAssertEqual(try result(#"{"status":"rejected_content"}"#).createMeetupOutcome(), .rejectedContent)
        XCTAssertEqual(try result(#"{"status":"limit_reached","limit":3}"#).createMeetupOutcome(), .limitReached(3))
        XCTAssertEqual(try result(#"{"status":"limit_reached"}"#).createMeetupOutcome(), .limitReached(SocialPolicy.dailyMeetups))
        for reason in ["title_length", "description_too_long", "place_name_length", "start_too_soon", "start_too_late",
                       "duration_range", "capacity_range", "spot_not_found"] {
            let outcome = try result(#"{"status":"invalid","reason":"\#(reason)"}"#).createMeetupOutcome()
            XCTAssertEqual(outcome, .invalid(MeetupInvalidReason(rawValue: reason)!), reason)
        }
        assertServerError(try result(#"{"status":"invalid","reason":"brand_new"}"#).createMeetupOutcome())
        assertServerError(try result(#"{"status":"created"}"#).createMeetupOutcome())
        assertServerError(try result(#"{"status":"mystery"}"#).createMeetupOutcome())
    }

    func testStartTourOutcomes() throws {
        XCTAssertEqual(
            try result(#"{"status":"started","meetup_id":"\#(Self.meetupId)","conversation_id":"\#(Self.convId)"}"#).startTourOutcome(),
            .started(meetupId: uuid(Self.meetupId), conversationId: uuid(Self.convId))
        )
        XCTAssertEqual(try result(#"{"status":"consent_required"}"#).startTourOutcome(), .consentRequired)
        XCTAssertEqual(try result(#"{"status":"spot_not_found"}"#).startTourOutcome(), .spotNotFound)
        XCTAssertEqual(try result(#"{"status":"already_touring"}"#).startTourOutcome(), .alreadyTouring)
        XCTAssertEqual(try result(#"{"status":"limit_reached","limit":3}"#).startTourOutcome(), .limitReached(3))
        XCTAssertEqual(try result(#"{"status":"limit_reached"}"#).startTourOutcome(), .limitReached(SocialPolicy.dailyTours))
        XCTAssertEqual(try result(#"{"status":"invalid","reason":"duration_range"}"#).startTourOutcome(), .durationRange)
        assertServerError(try result(#"{"status":"invalid","reason":"brand_new"}"#).startTourOutcome())
        assertServerError(try result(#"{"status":"started","meetup_id":"\#(Self.meetupId)"}"#).startTourOutcome())
        assertServerError(try result(#"{"status":"mystery"}"#).startTourOutcome())
    }

    func testStartTourParamsMatchServerSignature() throws {
        let params = try json(SupabaseBackend.startTourParams(spotId: uuid(Self.meetupId), durationMinutes: 90))
        XCTAssertEqual(Set(params.keys), ["p_spot_id", "p_duration_minutes"])
        XCTAssertEqual(params["p_spot_id"] as? String, Self.meetupId)
        XCTAssertEqual(params["p_duration_minutes"] as? Int, 90)
    }

    func testJoinMeetupOutcomes() throws {
        XCTAssertEqual(try result(#"{"status":"joined","conversation_id":"\#(Self.convId)"}"#).joinMeetupOutcome(),
                       .joined(conversationId: uuid(Self.convId)))
        XCTAssertEqual(try result(#"{"status":"full"}"#).joinMeetupOutcome(), .full)
        XCTAssertEqual(try result(#"{"status":"removed"}"#).joinMeetupOutcome(), .removed)
        XCTAssertEqual(try result(#"{"status":"cancelled"}"#).joinMeetupOutcome(), .cancelled)
        XCTAssertEqual(try result(#"{"status":"ended"}"#).joinMeetupOutcome(), .ended)
        XCTAssertEqual(try result(#"{"status":"consent_required"}"#).joinMeetupOutcome(), .consentRequired)
        XCTAssertEqual(try result(#"{"status":"not_found"}"#).joinMeetupOutcome(), .notFound)
        assertServerError(try result(#"{"status":"joined"}"#).joinMeetupOutcome())
        assertServerError(try result(#"{"status":"mystery"}"#).joinMeetupOutcome())
    }

    func testLeaveRemoveCancelResults() throws {
        XCTAssertTrue(try result(#"{"status":"ok"}"#).leaveAllowed())
        XCTAssertFalse(try result(#"{"status":"organizer_cannot_leave"}"#).leaveAllowed())
        assertServerError(try result(#"{"status":"mystery"}"#).leaveAllowed())
        for rpc in ["remove_meetup_participant", "cancel_meetup"] {
            XCTAssertTrue(try result(#"{"status":"ok"}"#).moderationAllowed(rpc: rpc))
            XCTAssertFalse(try result(#"{"status":"not_allowed"}"#).moderationAllowed(rpc: rpc))
            assertServerError(try result(#"{"status":"mystery"}"#).moderationAllowed(rpc: rpc))
        }
    }

    // MARK: - bağlantılar

    func testSendRequestOutcomes() throws {
        let req = "f0000000-0000-4000-8000-000000000001"
        XCTAssertEqual(try result(#"{"status":"sent","request_id":"\#(req)"}"#).sendRequestOutcome(), .sent(requestId: uuid(req)))
        XCTAssertEqual(try result(#"{"status":"auto_accepted","conversation_id":"\#(Self.convId)"}"#).sendRequestOutcome(),
                       .autoAccepted(conversationId: uuid(Self.convId)))
        XCTAssertEqual(try result(#"{"status":"consent_required"}"#).sendRequestOutcome(), .consentRequired)
        XCTAssertEqual(try result(#"{"status":"not_visible"}"#).sendRequestOutcome(), .notVisible)
        XCTAssertEqual(try result(#"{"status":"already_connected"}"#).sendRequestOutcome(), .alreadyConnected)
        XCTAssertEqual(try result(#"{"status":"already_pending"}"#).sendRequestOutcome(), .alreadyPending)
        XCTAssertEqual(try result(#"{"status":"cooldown"}"#).sendRequestOutcome(), .cooldown)
        XCTAssertEqual(try result(#"{"status":"rejected_content"}"#).sendRequestOutcome(), .rejectedContent)
        XCTAssertEqual(try result(#"{"status":"limit_reached","limit":10}"#).sendRequestOutcome(), .limitReached(10))
        XCTAssertEqual(try result(#"{"status":"invalid","reason":"note_too_long"}"#).sendRequestOutcome(), .noteTooLong)
        XCTAssertEqual(try result(#"{"status":"not_found"}"#).sendRequestOutcome(), .notFound)
        assertServerError(try result(#"{"status":"invalid","reason":"x"}"#).sendRequestOutcome())
        assertServerError(try result(#"{"status":"sent"}"#).sendRequestOutcome())
        assertServerError(try result(#"{"status":"mystery"}"#).sendRequestOutcome())
    }

    func testRespondReturnsConversationOnlyWhenAccepted() throws {
        XCTAssertEqual(try result(#"{"status":"accepted","conversation_id":"\#(Self.convId)"}"#).respondOutcome(), uuid(Self.convId))
        XCTAssertNil(try result(#"{"status":"declined"}"#).respondOutcome())
        XCTAssertNil(try result(#"{"status":"not_found"}"#).respondOutcome())
        assertServerError(try result(#"{"status":"accepted"}"#).respondOutcome())
        assertServerError(try result(#"{"status":"mystery"}"#).respondOutcome())
    }

    func testWithdrawAndRemoveAreIdempotent() throws {
        XCTAssertNoThrow(try result(#"{"status":"ok"}"#).requireOKOrNotFound(rpc: "remove_connection"))
        XCTAssertNoThrow(try result(#"{"status":"not_found"}"#).requireOKOrNotFound(rpc: "remove_connection"))
        assertServerError(try result(#"{"status":"mystery"}"#).requireOKOrNotFound(rpc: "remove_connection"))
    }

    // MARK: - send_chat_message

    func testSendMessageOutcomes() throws {
        let author = uuid(Self.userId)
        func outcome(_ json: String) throws -> SendMessageOutcome {
            try result(json).sendMessageOutcome(authorId: author, authorName: "Ayşe", body: "Merhaba")
        }
        let sent = try outcome(#"{"status":"sent","message_id":"a0000000-0000-4000-8000-000000000001","created_at":"2026-11-14T10:00:00.123+00:00"}"#)
        guard case .sent(let message) = sent else { return XCTFail("sent bekleniyordu: \(sent)") }
        XCTAssertEqual(message.id, uuid("a0000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(message.authorId, author)
        XCTAssertEqual(message.authorName, "Ayşe")
        XCTAssertEqual(message.body, "Merhaba")
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, utc(2026, 11, 14, 10).timeIntervalSince1970 + 0.123, accuracy: 0.0005)
        XCTAssertFalse(message.isPendingModeration)

        XCTAssertEqual(try outcome(#"{"status":"not_member"}"#), .notMember)
        XCTAssertEqual(try outcome(#"{"status":"consent_required"}"#), .notMember, "Onay yoksa üyelik de yok")
        XCTAssertEqual(try outcome(#"{"status":"read_only"}"#), .readOnly)
        XCTAssertEqual(try outcome(#"{"status":"rejected_content"}"#), .rejectedContent)
        XCTAssertEqual(try outcome(#"{"status":"rate_limited"}"#), .rateLimited)
        XCTAssertEqual(try outcome(#"{"status":"invalid","reason":"body_empty"}"#), .bodyEmpty)
        XCTAssertEqual(try outcome(#"{"status":"invalid","reason":"body_too_long"}"#), .bodyTooLong)
        assertServerError(try outcome(#"{"status":"invalid","reason":"x"}"#))
        assertServerError(try outcome(#"{"status":"sent"}"#))
        assertServerError(try outcome(#"{"status":"mystery"}"#))
    }

    // MARK: - RPC parametreleri

    private func json(_ object: JSONObject) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(object)) as? [String: Any])
    }

    func testCreateMeetupParamsMatchServerSignature() throws {
        let draft = MeetupDraft(title: "  Tur ", description: "", startsAt: utc(2026, 11, 20, 14), durationMinutes: 90,
                                placeName: "Moda Parkı", coordinate: Coordinate(latitude: 40.98, longitude: 29.03),
                                spotId: nil, capacity: nil)
        let params = try json(SupabaseBackend.createMeetupParams(draft))
        XCTAssertEqual(Set(params.keys), ["p_title", "p_description", "p_starts_at", "p_duration_minutes", "p_place_name",
                                          "lat", "lng", "p_spot_id", "p_capacity"])
        XCTAssertEqual(params["p_title"] as? String, "Tur")
        XCTAssertEqual(params["p_starts_at"] as? String, "2026-11-20T14:00:00.000Z")
        XCTAssertEqual(params["p_duration_minutes"] as? Int, 90)
        XCTAssertTrue(params["p_spot_id"] is NSNull)
        XCTAssertTrue(params["p_capacity"] is NSNull)
    }

    func testUpdateProfileParamsRoundLocationToCell() throws {
        let params = try json(SupabaseBackend.updateProfileParams(
            isVisible: true, about: " Merhaba ", interests: [.cats, .vetTransport],
            coordinate: Coordinate(latitude: 40.98765, longitude: 29.03456)
        ))
        XCTAssertEqual(Set(params.keys), ["p_is_visible", "p_about", "p_interests", "lat", "lng"])
        XCTAssertEqual(params["p_about"] as? String, "Merhaba")
        XCTAssertEqual(params["p_interests"] as? [String], ["cats", "vet_transport"])
        XCTAssertEqual(params["lat"] as? Double, 40.99)
        XCTAssertEqual(params["lng"] as? Double, 29.03)

        let none = try json(SupabaseBackend.updateProfileParams(isVisible: false, about: "", interests: [], coordinate: nil))
        XCTAssertTrue(none["lat"] is NSNull)
        XCTAssertTrue(none["lng"] is NSNull)
    }

    func testMessagesParamsClampAndKeepMillisecondCursor() throws {
        let cursor = utc(2026, 11, 14, 10).addingTimeInterval(0.123)
        let params = try json(SupabaseBackend.messagesParams(conversationId: uuid(Self.convId), before: cursor, limit: 500))
        XCTAssertEqual(Set(params.keys), ["p_conversation_id", "p_before", "max_rows"])
        XCTAssertEqual(params["p_before"] as? String, "2026-11-14T10:00:00.123Z")
        XCTAssertEqual(params["max_rows"] as? Int, 100)
        XCTAssertEqual(params["p_conversation_id"] as? String, Self.convId)
        let first = try json(SupabaseBackend.messagesParams(conversationId: uuid(Self.convId), before: nil, limit: 0))
        XCTAssertTrue(first["p_before"] is NSNull)
        XCTAssertEqual(first["max_rows"] as? Int, 1)
    }

    // MARK: - bildirimler: meetup_id / conversation_id, social_updates

    func testNotificationsDecodeMeetupAndConversationIds() throws {
        let notifications = try SupabaseDecoding.notifications(from: data("""
        [{"id": "11111111-2222-3333-4444-555555555555", "kind": "meetup_joined", "title": "Yeni katılımcı", "body": "Ayşe katıldı",
          "meetup_id": "\(Self.meetupId)", "conversation_id": null, "created_at": "2026-11-14T09:00:00Z"},
         {"id": "21111111-2222-3333-4444-555555555555", "kind": "chat_message", "title": "Yeni mesaj", "body": "Ayşe",
          "meetup_id": null, "conversation_id": "\(Self.convId)", "created_at": "2026-11-14T09:01:00Z"},
         {"id": "31111111-2222-3333-4444-555555555555", "kind": "thanks_fed", "title": "t", "body": "b",
          "created_at": "2026-11-14T09:02:00Z"}]
        """))
        XCTAssertEqual(notifications[0].meetupId, uuid(Self.meetupId))
        XCTAssertNil(notifications[0].conversationId)
        XCTAssertNil(notifications[1].meetupId)
        XCTAssertEqual(notifications[1].conversationId, uuid(Self.convId))
        XCTAssertNil(notifications[2].meetupId, "sütun yok (eski satır şekli)")
        XCTAssertNil(notifications[2].conversationId)
    }

    func testAppNotificationCodableIsBackwardCompatible() throws {
        // `meetupId` / `conversationId` eklenmeden kaydedilmiş JSON.
        let old = Data("""
        {"id": "11111111-2222-3333-4444-555555555555", "kind": "thanks_fed", "title": "t", "body": "b",
         "createdAt": 800000000}
        """.utf8)
        let decoded = try JSONDecoder().decode(AppNotification.self, from: old)
        XCTAssertNil(decoded.meetupId)
        XCTAssertNil(decoded.conversationId)

        let full = AppNotification(kind: .chatMessage, title: "t", body: "b", meetupId: uuid(Self.meetupId), conversationId: uuid(Self.convId))
        let roundTrip = try JSONDecoder().decode(AppNotification.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(roundTrip, full)
    }

    func testPreferencesMapSocialUpdates() throws {
        let off = try SupabaseDecoding.notificationPreferences(from: data("""
        [{"radius_m": 1000, "quiet_start": 22, "quiet_end": 7, "need_food_nearby": true, "followed_updates": true,
          "guardian_alerts": true, "community_updates": true, "social_updates": false}]
        """))
        XCTAssertEqual(off?.socialUpdates, false)
        XCTAssertEqual(off?.communityUpdates, true)
        // Sütun yok veya null → varsayılan: açık.
        let missing = try SupabaseDecoding.notificationPreferences(from: data(#"[{"radius_m": 1000}]"#))
        XCTAssertEqual(missing?.socialUpdates, true)
        let null = try SupabaseDecoding.notificationPreferences(from: data(#"[{"radius_m": 1000, "social_updates": null}]"#))
        XCTAssertEqual(null, .default)

        let fields = SupabaseBackend.notificationPrefsFields(NotificationPreferences(socialUpdates: false))
        XCTAssertEqual(try json(fields)["social_updates"] as? Bool, false)
        XCTAssertTrue(NotificationPrefsDTO.columns.split(separator: ",").contains("social_updates"))
    }

    // MARK: - SupabaseChatUpdates

    func testChatTopicUsesLowercasedUUID() {
        let id = uuid("E0000000-0000-4000-8000-0000000000AB")
        XCTAssertEqual(SupabaseChatUpdates.topic(for: id), "conversation:e0000000-0000-4000-8000-0000000000ab")
    }
}
