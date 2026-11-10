import Foundation
import MamaCore
@testable import MamaSupabase
import Supabase
import XCTest

/// Mahalle (docs/backend-contract.md → "Mahalle (topluluk) — v0.2"): sözleşmedeki satır ve jsonb
/// şekilleriyle çözme + domain eşleme testleri.
final class MahalleDecodingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Double = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        return base.addingTimeInterval(second)
    }

    private func uuid(_ text: String) -> UUID { UUID(uuidString: text)! }

    private func assertServerError<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case .server = error as? MamaError else {
                return XCTFail("server bekleniyordu: \(error)", file: file, line: line)
            }
        }
    }

    static let ayse = "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11"
    static let mehmet = "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11"
    static let coverPost = "c0000000-0000-4000-8000-000000000001"
    static let notePost = "c0000000-0000-4000-8000-000000000002"

    // MARK: - community_post_row

    /// `community_feed` yanıtı: sütun adları ve sırası sözleşmedeki `community_post_row` ile aynı.
    static let postRows = """
    [
      {
        "id": "c0000000-0000-4000-8000-000000000001", "kind": "cover_request",
        "body": "15-22 Kasım arası yokum. Moda Parkı'ndaki kedilere bakabilecek var mı?",
        "photo_url": "https://x.supabase.co/storage/v1/object/public/photos/u/post.jpg",
        "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "author_name": "Ayşe",
        "author_avatar_url": "https://x.supabase.co/storage/v1/object/public/photos/u/ayse.jpg",
        "author_is_verified": true,
        "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "spot_title": "Moda Parkı girişi",
        "animal_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "animal_name": "Pamuk",
        "cover_from": "2026-11-15", "cover_to": "2026-11-22", "volunteer_count": 2, "viewer_volunteered": true,
        "paw_count": 7, "viewer_pawed": true, "comment_count": 3,
        "distance_m": 412.7,
        "moderation_state": "approved", "created_at": "2026-11-10T08:15:00.123+00:00"
      },
      {
        "id": "c0000000-0000-4000-8000-000000000002", "kind": "note",
        "body": "Pamuk bugün çok neşeliydi.",
        "photo_url": null,
        "author_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "author_name": "Mehmet",
        "author_avatar_url": null,
        "author_is_verified": false,
        "spot_id": null, "spot_title": null,
        "animal_id": null, "animal_name": null,
        "cover_from": null, "cover_to": null, "volunteer_count": 0, "viewer_volunteered": false,
        "paw_count": 0, "viewer_pawed": false, "comment_count": 0,
        "distance_m": null,
        "moderation_state": "approved", "created_at": "2026-11-09T19:00:00+00:00"
      }
    ]
    """

    func testPostRowFull() throws {
        let posts = try SupabaseDecoding.communityPosts(from: data(Self.postRows))
        XCTAssertEqual(posts.map(\.id), [uuid(Self.coverPost), uuid(Self.notePost)], "Sunucu sırası korunmalı (yeniden eskiye)")

        let post = posts[0]
        XCTAssertEqual(post.kind, .coverRequest)
        XCTAssertEqual(post.body, "15-22 Kasım arası yokum. Moda Parkı'ndaki kedilere bakabilecek var mı?")
        XCTAssertEqual(post.photoURL?.lastPathComponent, "post.jpg")
        XCTAssertEqual(post.authorId, uuid(Self.ayse))
        XCTAssertEqual(post.authorName, "Ayşe")
        XCTAssertEqual(post.authorAvatarURL?.lastPathComponent, "ayse.jpg")
        XCTAssertTrue(post.authorIsVerified)
        XCTAssertEqual(post.spotId, uuid("6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10"))
        XCTAssertEqual(post.spotTitle, "Moda Parkı girişi")
        XCTAssertEqual(post.animalId, uuid("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        XCTAssertEqual(post.animalName, "Pamuk")
        // Postgres `date` → Europe/Istanbul (UTC+3) gece yarısı.
        XCTAssertEqual(post.coverFrom, utc(2026, 11, 14, 21))
        XCTAssertEqual(post.coverTo, utc(2026, 11, 21, 21))
        XCTAssertEqual(post.volunteerCount, 2)
        XCTAssertTrue(post.viewerVolunteered)
        XCTAssertEqual(post.pawCount, 7)
        XCTAssertTrue(post.viewerPawed)
        XCTAssertEqual(post.commentCount, 3)
        XCTAssertEqual(post.distanceMeters, 412.7)
        XCTAssertFalse(post.isPendingModeration)
        XCTAssertEqual(post.createdAt.timeIntervalSince1970, utc(2026, 11, 10, 8, 15, 0.123).timeIntervalSince1970, accuracy: 0.0005)

        // Bitiş günü dahil: istek 22 Kasım İstanbul günü boyunca açık, 23'ünde kapalı.
        XCTAssertTrue(CommunityPolicy.isCoverOpen(post, now: utc(2026, 11, 22, 20, 59)))
        XCTAssertFalse(CommunityPolicy.isCoverOpen(post, now: utc(2026, 11, 22, 21)))
    }

    func testPostRowWithNulls() throws {
        let post = try XCTUnwrap(SupabaseDecoding.communityPosts(from: data(Self.postRows)).last)
        XCTAssertEqual(post.id, uuid(Self.notePost))
        XCTAssertEqual(post.kind, .note)
        XCTAssertEqual(post.authorId, uuid(Self.mehmet))
        XCTAssertEqual(post.authorName, "Mehmet")
        XCTAssertNil(post.photoURL)
        XCTAssertNil(post.authorAvatarURL)
        XCTAssertFalse(post.authorIsVerified)
        XCTAssertNil(post.spotId)
        XCTAssertNil(post.spotTitle)
        XCTAssertNil(post.animalId)
        XCTAssertNil(post.animalName)
        XCTAssertNil(post.coverFrom)
        XCTAssertNil(post.coverTo)
        XCTAssertEqual(post.volunteerCount, 0)
        XCTAssertFalse(post.viewerVolunteered)
        XCTAssertEqual(post.pawCount, 0)
        XCTAssertFalse(post.viewerPawed)
        XCTAssertEqual(post.commentCount, 0)
        XCTAssertNil(post.distanceMeters)
        XCTAssertFalse(post.isPendingModeration)
        XCTAssertEqual(post.createdAt, utc(2026, 11, 9, 19))
    }

    func testPostRowModerationStates() throws {
        func post(_ state: String) throws -> CommunityPost {
            try XCTUnwrap(SupabaseDecoding.communityPosts(from: data("""
            [{"id": "c0000000-0000-4000-8000-000000000003", "kind": "question", "body": "Kedi maması önerisi?",
              "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "author_name": "Ayşe",
              "moderation_state": \(state), "created_at": "2026-11-10T08:15:00Z"}]
            """)).first)
        }
        XCTAssertTrue(try post(#""pending""#).isPendingModeration)
        XCTAssertFalse(try post(#""approved""#).isPendingModeration)
        XCTAssertFalse(try post(#""rejected""#).isPendingModeration)
        XCTAssertFalse(try post("null").isPendingModeration)
    }

    func testPostRowKindsAndUnknownKindFallsBackToNote() throws {
        let kinds = ["note", "question", "cover_request", "supply", "alert", "poll"]
        let rows = kinds.enumerated().map { index, kind in
            """
            {"id": "c0000000-0000-4000-8000-00000000001\(index)", "kind": "\(kind)", "body": "x",
             "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "created_at": "2026-11-10T08:15:00Z"}
            """
        }
        let posts = try SupabaseDecoding.communityPosts(from: data("[\(rows.joined(separator: ","))]"))
        XCTAssertEqual(posts.map(\.kind), [.note, .question, .coverRequest, .supply, .alert, .note],
                       "Bilinmeyen tür satırı düşürmez; nötr türe (.note) düşer")
        XCTAssertEqual(posts.last?.body, "x")
    }

    func testPostRowIsLenientAndSkipsBrokenRows() throws {
        let json = """
        [
          {"id": "c0000000-0000-4000-8000-000000000004", "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11",
           "kind": null, "body": null, "photo_url": "", "author_name": null, "author_avatar_url": "",
           "author_is_verified": null, "cover_from": "soon", "volunteer_count": null, "viewer_volunteered": null,
           "paw_count": null, "viewer_pawed": null, "comment_count": null, "moderation_state": null,
           "created_at": "not a date", "extra_future_column": {"a": 1}},
          {"id": "not-a-uuid", "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "kind": "note"},
          {"id": "c0000000-0000-4000-8000-000000000005", "author_id": null, "kind": "note", "body": "yazarsız"},
          {"id": "c0000000-0000-4000-8000-000000000006", "author_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11"}
        ]
        """
        let posts = try SupabaseDecoding.communityPosts(from: data(json))
        XCTAssertEqual(posts.map(\.id), [
            uuid("c0000000-0000-4000-8000-000000000004"),
            uuid("c0000000-0000-4000-8000-000000000006"),
        ], "Bozuk uuid ve yazarsız satır atlanmalı")

        let lenient = posts[0]
        XCTAssertEqual(lenient.kind, .note)
        XCTAssertEqual(lenient.body, "")
        XCTAssertNil(lenient.photoURL)
        XCTAssertEqual(lenient.authorName, SupabaseBackend.placeholderDisplayName)
        XCTAssertNil(lenient.authorAvatarURL)
        XCTAssertFalse(lenient.authorIsVerified)
        XCTAssertNil(lenient.coverFrom)
        XCTAssertEqual(lenient.volunteerCount, 0)
        XCTAssertFalse(lenient.viewerVolunteered)
        XCTAssertEqual(lenient.pawCount, 0)
        XCTAssertFalse(lenient.viewerPawed)
        XCTAssertEqual(lenient.commentCount, 0)
        XCTAssertFalse(lenient.isPendingModeration)
        XCTAssertEqual(lenient.createdAt, Date(timeIntervalSince1970: 0))
    }

    /// `community_post_detail` 0/1 satır döner: gizli, engelli ya da silinmiş paylaşım → `nil`.
    func testPostDetailIsFirstRowOrNil() throws {
        XCTAssertNil(try SupabaseDecoding.communityPosts(from: data("[]")).first)
        XCTAssertNil(try SupabaseDecoding.communityPosts(from: Data()).first)
        XCTAssertNil(try SupabaseDecoding.communityPosts(from: data("null")).first)
        XCTAssertEqual(try SupabaseDecoding.communityPosts(from: data(Self.postRows)).first?.id, uuid(Self.coverPost))
    }

    // MARK: - community_comment_row

    func testCommentRows() throws {
        let json = """
        [
          {"id": "d0000000-0000-4000-8000-000000000001", "post_id": "c0000000-0000-4000-8000-000000000001",
           "body": "Ben hafta içi bakabilirim.",
           "author_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "author_name": "Mehmet",
           "author_avatar_url": "https://x.supabase.co/storage/v1/object/public/photos/u/mehmet.jpg",
           "author_is_verified": true, "created_at": "2026-11-10T09:00:00.5+00:00"},
          {"id": "d0000000-0000-4000-8000-000000000002", "post_id": "c0000000-0000-4000-8000-000000000001",
           "body": "Çok teşekkürler!",
           "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "author_name": null,
           "author_avatar_url": null, "author_is_verified": null, "created_at": "2026-11-10T09:05:00+00:00"},
          {"id": "d0000000-0000-4000-8000-000000000003", "post_id": null, "body": "paylaşımsız",
           "author_id": "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "created_at": "2026-11-10T09:06:00+00:00"},
          {"id": "d0000000-0000-4000-8000-000000000004", "post_id": "c0000000-0000-4000-8000-000000000001",
           "body": "yazarsız", "created_at": "2026-11-10T09:07:00+00:00"}
        ]
        """
        let comments = try SupabaseDecoding.communityComments(from: data(json))
        XCTAssertEqual(comments, [
            CommunityComment(
                id: uuid("d0000000-0000-4000-8000-000000000001"), postId: uuid(Self.coverPost),
                body: "Ben hafta içi bakabilirim.", authorId: uuid(Self.mehmet), authorName: "Mehmet",
                authorAvatarURL: URL(string: "https://x.supabase.co/storage/v1/object/public/photos/u/mehmet.jpg"),
                authorIsVerified: true, createdAt: utc(2026, 11, 10, 9, 0, 0.5)
            ),
            CommunityComment(
                id: uuid("d0000000-0000-4000-8000-000000000002"), postId: uuid(Self.coverPost),
                body: "Çok teşekkürler!", authorId: uuid(Self.ayse), authorName: SupabaseBackend.placeholderDisplayName,
                authorAvatarURL: nil, authorIsVerified: false, createdAt: utc(2026, 11, 10, 9, 5)
            ),
        ], "Sunucu sırası korunmalı (eskiden yeniye); paylaşımsız ve yazarsız satır atlanmalı")
        XCTAssertEqual(try SupabaseDecoding.communityComments(from: data("[]")), [])
    }

    // MARK: - cover_volunteers_of

    func testVolunteers() throws {
        let volunteers = try SupabaseDecoding.communityVolunteers(from: data("""
        [
          {"user_id": "0c9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": "Mehmet",
           "avatar_url": "https://x.supabase.co/storage/v1/object/public/photos/u/mehmet.jpg", "is_verified_feeder": true},
          {"user_id": "0d9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11", "display_name": null, "avatar_url": null,
           "is_verified_feeder": null},
          {"user_id": null, "display_name": "Kimliksiz"}
        ]
        """))
        XCTAssertEqual(volunteers, [
            CommunityVolunteer(
                userId: uuid(Self.mehmet), displayName: "Mehmet",
                avatarURL: URL(string: "https://x.supabase.co/storage/v1/object/public/photos/u/mehmet.jpg"), isVerifiedFeeder: true
            ),
            CommunityVolunteer(
                userId: uuid("0d9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11"), displayName: SupabaseBackend.placeholderDisplayName,
                avatarURL: nil, isVerifiedFeeder: false
            ),
        ])
        XCTAssertEqual(try SupabaseDecoding.communityVolunteers(from: data("[]")), [])
    }

    // MARK: - community_summary

    func testSummaryRowAndEmpty() throws {
        let summary = try SupabaseDecoding.communitySummary(from: data("""
        [{"fed_spot_days_7d": 41, "active_feeders_7d": 9, "open_cover_requests": 2, "posts_7d": 17}]
        """))
        XCTAssertEqual(summary, CommunitySummary(fedSpotDays7d: 41, activeFeeders7d: 9, openCoverRequests: 2, posts7d: 17))

        XCTAssertEqual(try SupabaseDecoding.communitySummary(from: data("[]")), .empty)
        XCTAssertEqual(try SupabaseDecoding.communitySummary(from: data("null")), .empty)
        let nulls = try SupabaseDecoding.communitySummary(from: data("""
        [{"fed_spot_days_7d": null, "active_feeders_7d": null, "open_cover_requests": null, "posts_7d": 3}]
        """))
        XCTAssertEqual(nulls, CommunitySummary(fedSpotDays7d: 0, activeFeeders7d: 0, openCoverRequests: 0, posts7d: 3))
    }

    // MARK: - create_community_post

    func testCreatePostStatuses() throws {
        let id = uuid(Self.coverPost)
        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data("""
        {"status": "created", "post_id": "c0000000-0000-4000-8000-000000000001", "moderation_state": "approved"}
        """)), .created(id: id, pendingModeration: false))
        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data("""
        {"status": "created", "post_id": "c0000000-0000-4000-8000-000000000001", "moderation_state": "pending"}
        """)), .created(id: id, pendingModeration: true))

        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "rejected_content"}"#)), .rejectedContent)
        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "limit_reached", "limit": 10}"#)), .limitReached(limit: 10))
        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "limit_reached", "limit": 4}"#)), .limitReached(limit: 4))
        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "limit_reached"}"#)),
                       .limitReached(limit: CommunityPolicy.dailyPostLimit))

        // jsonb tek elemanlı dizi olarak gelirse de çözülür.
        XCTAssertEqual(try SupabaseDecoding.createPostOutcome(from: data(#"[{"status": "rejected_content"}]"#)), .rejectedContent)
    }

    func testCreatePostInvalidReasons() throws {
        let reasons: [(String, CommunityValidationError)] = [
            ("body_empty", .bodyEmpty),
            ("body_too_long", .bodyTooLong),
            ("cover_needs_spot", .coverNeedsSpot),
            ("cover_dates", .coverDates),
            ("spot_not_found", .spotNotFound),
        ]
        for (reason, expected) in reasons {
            let outcome = try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "invalid", "reason": "\#(reason)"}"#))
            XCTAssertEqual(outcome, .invalid(expected), reason)
        }
    }

    func testCreatePostUnexpectedResultsThrowServerError() {
        assertServerError(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "invalid", "reason": "bad_vibes"}"#)))
        assertServerError(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "invalid"}"#)))
        assertServerError(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "invalid", "reason": null}"#)))
        assertServerError(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "mystery"}"#)))
        assertServerError(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "post_not_found"}"#)))
        assertServerError(try SupabaseDecoding.createPostOutcome(from: data(#"{"status": "created", "moderation_state": "approved"}"#)))
        XCTAssertThrowsError(try SupabaseDecoding.createPostOutcome(from: data(#"{"post_id": "c0000000-0000-4000-8000-000000000001"}"#)))
        XCTAssertThrowsError(try SupabaseDecoding.createPostOutcome(from: data("null")))
    }

    // MARK: - add_community_comment

    func testAddCommentStatuses() throws {
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data("""
        {"status": "created", "comment_id": "d0000000-0000-4000-8000-000000000001"}
        """)), .created(id: uuid("d0000000-0000-4000-8000-000000000001")))
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "rejected_content"}"#)), .rejectedContent)
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "limit_reached", "limit": 60}"#)), .limitReached(limit: 60))
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "limit_reached"}"#)),
                       .limitReached(limit: CommunityPolicy.dailyCommentLimit))
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "invalid", "reason": "body_empty"}"#)), .invalid(.bodyEmpty))
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "invalid", "reason": "body_too_long"}"#)), .invalid(.bodyTooLong))
        XCTAssertEqual(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "post_not_found"}"#)), .postNotFound)

        assertServerError(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "invalid", "reason": "too_chatty"}"#)))
        assertServerError(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "invalid"}"#)))
        assertServerError(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "created"}"#)))
        assertServerError(try SupabaseDecoding.commentOutcome(from: data(#"{"status": "mystery"}"#)))
    }

    // MARK: - toggle_post_paw

    func testPawToggle() throws {
        XCTAssertEqual(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "ok", "pawed": true, "paw_count": 8}"#)),
                       PawToggleResult(pawed: true, pawCount: 8))
        XCTAssertEqual(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "ok", "pawed": false, "paw_count": 0}"#)),
                       PawToggleResult(pawed: false, pawCount: 0))
        XCTAssertNil(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "post_not_found"}"#)))

        // Sayaç eksikse tepkinin durumundan türetilir; durum eksikse sonuç kullanılamaz.
        XCTAssertEqual(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "ok", "pawed": true}"#)),
                       PawToggleResult(pawed: true, pawCount: 1))
        XCTAssertEqual(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "ok", "pawed": false, "paw_count": null}"#)),
                       PawToggleResult(pawed: false, pawCount: 0))
        assertServerError(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "ok", "paw_count": 3}"#)))
        assertServerError(try SupabaseDecoding.pawToggleResult(from: data(#"{"status": "mystery"}"#)))
    }

    // MARK: - toggle_cover_volunteer

    func testCoverVolunteerStatuses() throws {
        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "ok", "volunteered": true, "volunteer_count": 2}"#)),
                       .ok(volunteered: true, volunteerCount: 2))
        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "ok", "volunteered": false, "volunteer_count": 1}"#)),
                       .ok(volunteered: false, volunteerCount: 1))
        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "not_cover_request"}"#)), .notCoverRequest)
        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "own_post"}"#)), .ownPost)
        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "closed"}"#)), .closed)
        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "post_not_found"}"#)), .postNotFound)

        XCTAssertEqual(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "ok", "volunteered": true}"#)),
                       .ok(volunteered: true, volunteerCount: 1))
        assertServerError(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "ok", "volunteer_count": 2}"#)))
        assertServerError(try SupabaseDecoding.coverVolunteerOutcome(from: data(#"{"status": "mystery"}"#)))
    }

    // MARK: - delete_community_post / delete_community_comment

    func testDeleteStatuses() throws {
        for rpc in ["delete_community_post", "delete_community_comment"] {
            XCTAssertTrue(try SupabaseDecoding.communityDeleteAllowed(from: data(#"{"status": "ok"}"#), rpc: rpc), rpc)
            XCTAssertFalse(try SupabaseDecoding.communityDeleteAllowed(from: data(#"{"status": "not_allowed"}"#), rpc: rpc), rpc)
            assertServerError(try SupabaseDecoding.communityDeleteAllowed(from: data(#"{"status": "mystery"}"#), rpc: rpc))
            // Sözleşmedeki iki değerin dışında: kayıt yoksa InMemoryBackend gibi `.notFound`.
            for status in ["post_not_found", "comment_not_found", "not_found"] {
                XCTAssertThrowsError(try SupabaseDecoding.communityDeleteAllowed(from: data(#"{"status": "\#(status)"}"#), rpc: rpc)) { error in
                    XCTAssertEqual(error as? MamaError, .notFound, status)
                }
            }
        }
    }

    /// Mahalle RPC'lerinin iş kuralı dışı durumları exception'dır (migration 0014); `perform` bunları
    /// `SupabaseErrorMapper` ile çevirir.
    func testCommunityRpcExceptionsMapToMamaErrors() {
        func mapped(_ error: PostgrestError) -> MamaError? { SupabaseErrorMapper.map(error) as? MamaError }
        // delete_community_post / delete_community_comment: kayıt yok (InMemoryBackend de `.notFound` fırlatır).
        XCTAssertEqual(mapped(PostgrestError(detail: "post", code: "P0002", message: "not_found")), .notFound)
        XCTAssertEqual(mapped(PostgrestError(detail: "comment", code: "P0002", message: "not_found")), .notFound)
        // create_community_post: bağlanan hayvan yok.
        XCTAssertEqual(mapped(PostgrestError(detail: "animal", code: "P0002", message: "not_found")), .notFound)
        // Oturum sunucuda geçersiz (private.require_uid).
        XCTAssertEqual(mapped(PostgrestError(code: "42501", message: "not_authenticated")), .notSignedIn)
        // Geçersiz konum / parametre.
        XCTAssertEqual(mapped(PostgrestError(code: "22023", message: "invalid_coordinates")),
                       .invalidInput(SupabaseErrorMapper.invalidLocationMessage))
        XCTAssertEqual(mapped(PostgrestError(code: "22023", message: "invalid_kind")),
                       .invalidInput(SupabaseErrorMapper.invalidValueMessage))
        XCTAssertEqual(mapped(PostgrestError(code: "22P02", message: #"invalid input value for enum community_post_kind: "poll""#)),
                       .invalidInput(SupabaseErrorMapper.invalidValueMessage))
    }

    // MARK: - notifications.post_id + yeni türler

    func testNotificationsWithPostIdAndCommunityKinds() throws {
        let notifications = try SupabaseDecoding.notifications(from: data("""
        [
          {"id": "11111111-2222-3333-4444-555555555555", "kind": "community_comment",
           "title": "Paylaşımına yorum geldi", "body": "Mehmet: Ben hafta içi bakabilirim.",
           "spot_id": null, "need_id": null, "post_id": "c0000000-0000-4000-8000-000000000001",
           "read_at": null, "created_at": "2026-11-10T09:00:00.5+00:00"},
          {"id": "21111111-2222-3333-4444-555555555555", "kind": "cover_volunteered",
           "title": "Yerine bakacak biri var!", "body": "Mehmet, Moda Parkı girişi için \\"Ben bakarım\\" dedi.",
           "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "need_id": null,
           "post_id": "c0000000-0000-4000-8000-000000000001",
           "read_at": "2026-11-10T10:00:00+00:00", "created_at": "2026-11-10T09:30:00+00:00"},
          {"id": "31111111-2222-3333-4444-555555555555", "kind": "thanks_fed", "title": "Teşekkürler!",
           "body": "Ayşe mama koydu.", "spot_id": "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10", "need_id": null,
           "post_id": null, "read_at": null, "created_at": "2026-11-10T08:00:00+00:00"},
          {"id": "41111111-2222-3333-4444-555555555555", "kind": "future_kind", "title": "?", "body": "?",
           "post_id": "c0000000-0000-4000-8000-000000000001", "created_at": "2026-11-10T07:00:00Z"},
          {"id": "51111111-2222-3333-4444-555555555555", "kind": "need_resolved", "title": "Çözüldü", "body": "",
           "need_id": "11111111-2222-3333-4444-555555555555", "created_at": "2026-11-10T06:00:00Z"}
        ]
        """))
        XCTAssertEqual(notifications.map(\.kind), [.communityComment, .coverVolunteered, .thanksFed, .needResolved],
                       "Bilinmeyen tür eskisi gibi atlanmalı")

        let comment = notifications[0]
        XCTAssertEqual(comment.postId, uuid(Self.coverPost))
        XCTAssertNil(comment.spotId)
        XCTAssertNil(comment.needId)
        XCTAssertFalse(comment.isRead)
        XCTAssertEqual(comment.title, "Paylaşımına yorum geldi")
        XCTAssertEqual(comment.createdAt, utc(2026, 11, 10, 9, 0, 0.5))

        let volunteered = notifications[1]
        XCTAssertEqual(volunteered.postId, uuid(Self.coverPost))
        XCTAssertEqual(volunteered.spotId, uuid("6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10"))
        XCTAssertEqual(volunteered.body, "Mehmet, Moda Parkı girişi için \"Ben bakarım\" dedi.")
        XCTAssertTrue(volunteered.isRead)

        XCTAssertNil(notifications[2].postId, "post_id null")
        XCTAssertNil(notifications[3].postId, "post_id sütunu yok (eski satır şekli)")
        XCTAssertEqual(notifications[3].needId, uuid("11111111-2222-3333-4444-555555555555"))
    }

    func testNotificationColumnsIncludePostId() {
        XCTAssertEqual(NotificationDTO.columns.split(separator: ",").map(String.init),
                       ["id", "kind", "title", "body", "spot_id", "need_id", "post_id", "read_at", "created_at"])
        // Seçilen her sütun DTO'da karşılığı olan bir anahtar olmalı.
        let keys: [NotificationDTO.CodingKeys] = [.id, .kind, .title, .body, .spotId, .needId, .postId, .readAt, .createdAt]
        XCTAssertEqual(Set(keys.map(\.rawValue)), Set(NotificationDTO.columns.split(separator: ",").map(String.init)))
    }

    func testEveryNotificationKindInContractDecodes() throws {
        let contractKinds = ["need_food_nearby", "followed_spot_changed", "guardian_spot_unfed", "need_resolved",
                             "thanks_fed", "donation_delivered", "community_comment", "cover_volunteered"]
        XCTAssertEqual(Set(NotificationKind.allCases.map(\.rawValue)), Set(contractKinds))
        let rows = contractKinds.enumerated().map { index, kind in
            #"{"id": "11111111-2222-3333-4444-55555555550\#(index)", "kind": "\#(kind)", "title": "t", "body": "b", "created_at": "2026-11-10T06:00:00Z"}"#
        }
        let decoded = try SupabaseDecoding.notifications(from: data("[\(rows.joined(separator: ","))]"))
        XCTAssertEqual(decoded.map(\.kind.rawValue), contractKinds)
    }

    // MARK: - notification_prefs.community_updates

    func testPreferencesWithAndWithoutCommunityUpdates() throws {
        let off = try SupabaseDecoding.notificationPreferences(from: data("""
        [{"radius_m": 2000, "quiet_start": 23, "quiet_end": 8, "need_food_nearby": false,
          "followed_updates": true, "guardian_alerts": false, "community_updates": false}]
        """))
        XCTAssertEqual(off, NotificationPreferences(radiusMeters: 2000, quietStartHour: 23, quietEndHour: 8, needFoodNearby: false,
                                                    followedUpdates: true, guardianAlerts: false, communityUpdates: false))

        let on = try SupabaseDecoding.notificationPreferences(from: data("""
        [{"radius_m": 500, "quiet_start": 22, "quiet_end": 7, "need_food_nearby": true,
          "followed_updates": true, "guardian_alerts": true, "community_updates": true}]
        """))
        XCTAssertEqual(on?.communityUpdates, true)

        // Sütun yok (eski satır şekli) veya null → varsayılan: açık.
        let missing = try SupabaseDecoding.notificationPreferences(from: data("""
        [{"radius_m": 2000, "quiet_start": 23, "quiet_end": 8, "need_food_nearby": false,
          "followed_updates": false, "guardian_alerts": false}]
        """))
        XCTAssertEqual(missing?.communityUpdates, true)
        XCTAssertEqual(missing?.followedUpdates, false)
        let null = try SupabaseDecoding.notificationPreferences(from: data(#"[{"radius_m": 1000, "community_updates": null}]"#))
        XCTAssertEqual(null, .default)
        XCTAssertTrue(NotificationPreferences.default.communityUpdates)
    }

    func testPreferenceColumnsAndWriteFieldsCoverCommunityUpdates() throws {
        let columns = NotificationPrefsDTO.columns.split(separator: ",").map(String.init)
        XCTAssertEqual(columns, ["radius_m", "quiet_start", "quiet_end", "need_food_nearby", "followed_updates",
                                 "guardian_alerts", "community_updates"])

        let preferences = NotificationPreferences(radiusMeters: 2000, quietStartHour: 23, quietEndHour: 8, needFoodNearby: false,
                                                  followedUpdates: true, guardianAlerts: false, communityUpdates: false)
        let fields = SupabaseBackend.notificationPrefsFields(preferences)
        // Sütun bazlı yetkiler: yalnızca izin verilen sütunlar yazılır (`user_id` update'te yok).
        XCTAssertEqual(Set(fields.keys), Set(columns))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fields)) as? [String: Any])
        XCTAssertEqual(json["community_updates"] as? Bool, false)
        XCTAssertEqual(json["need_food_nearby"] as? Bool, false)
        XCTAssertEqual(json["followed_updates"] as? Bool, true)
        XCTAssertEqual(json["radius_m"] as? Int, 2000)
        XCTAssertEqual(json["quiet_start"] as? Int, 23)
        XCTAssertEqual(json["quiet_end"] as? Int, 8)

        // Yazılan satır geri okununca aynı tercihleri verir.
        let roundTrip = try SupabaseDecoding.notificationPreferences(from: JSONEncoder().encode([fields]))
        XCTAssertEqual(roundTrip, preferences)
        let enabled = SupabaseBackend.notificationPrefsFields(.default)
        XCTAssertEqual(enabled["community_updates"], .bool(true))
    }

    // MARK: - report_target

    /// `reports.target_type` ham değerle yazılır; sözleşmedeki `report_target` enum'u ile aynı olmalı.
    func testReportTargetsMatchContractEnum() {
        XCTAssertEqual(ReportTarget.post.rawValue, "post")
        XCTAssertEqual(ReportTarget.comment.rawValue, "comment")
        XCTAssertEqual(Set(ReportTarget.allCases.map(\.rawValue)),
                       ["spot", "animal", "need", "checkin", "photo", "user", "post", "comment"])
    }
}

// MARK: - RPC parametreleri

final class MahalleParamTests: XCTestCase {
    private func json(_ params: JSONObject) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let createPostKeys: Set<String> = ["p_kind", "p_body", "p_photo_url", "p_spot_id", "p_animal_id", "lat", "lng",
                                               "p_cover_from", "p_cover_to"]

    func testCreatePostParamsSendEveryParameterWithExplicitNulls() throws {
        let draft = CommunityPostDraft(kind: .note, body: "  Pamuk bugün çok neşeliydi.\n",
                                       coordinate: Coordinate(latitude: 40.98621, longitude: 29.02544))
        let params = try json(SupabaseBackend.createPostParams(draft))
        XCTAssertEqual(Set(params.keys), Self.createPostKeys, "Varsayılanı olmayan dokuz parametrenin hepsi gönderilmeli")
        XCTAssertEqual(params["p_kind"] as? String, "note")
        XCTAssertEqual(params["p_body"] as? String, "Pamuk bugün çok neşeliydi.")
        XCTAssertTrue(params["p_photo_url"] is NSNull)
        XCTAssertTrue(params["p_spot_id"] is NSNull)
        XCTAssertTrue(params["p_animal_id"] is NSNull)
        XCTAssertEqual(params["lat"] as? Double, 40.98621)
        XCTAssertEqual(params["lng"] as? Double, 29.02544)
        XCTAssertTrue(params["p_cover_from"] is NSNull)
        XCTAssertTrue(params["p_cover_to"] is NSNull)
    }

    func testCreatePostParamsForCoverRequestUseIstanbulDays() throws {
        let draft = CommunityPostDraft(
            kind: .coverRequest,
            body: "Yerime bakar mısın?",
            photoURL: URL(string: "https://x.supabase.co/storage/v1/object/public/photos/u/post.jpg"),
            spotId: UUID(uuidString: "6F1C2A6E-1B7D-4C39-9C39-0D5D1F4B8A10"),
            animalId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            coordinate: nil,
            // İstanbul'da 15 Kasım 00:30 (UTC'de hâlâ 14 Kasım) ve 22 Kasım 23:59.
            coverFrom: utc(2026, 11, 14, 21, 30),
            coverTo: utc(2026, 11, 22, 20, 59)
        )
        let params = try json(SupabaseBackend.createPostParams(draft))
        XCTAssertEqual(Set(params.keys), Self.createPostKeys)
        XCTAssertEqual(params["p_kind"] as? String, "cover_request")
        XCTAssertEqual(params["p_photo_url"] as? String, "https://x.supabase.co/storage/v1/object/public/photos/u/post.jpg")
        XCTAssertEqual(params["p_spot_id"] as? String, "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10")
        XCTAssertEqual(params["p_animal_id"] as? String, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertTrue(params["lat"] is NSNull)
        XCTAssertTrue(params["lng"] is NSNull)
        XCTAssertEqual(params["p_cover_from"] as? String, "2026-11-15")
        XCTAssertEqual(params["p_cover_to"] as? String, "2026-11-22")
    }

    func testCreatePostParamsRoundTripDecodedCoverDates() throws {
        // Sunucudan okunan `date` (İstanbul gece yarısı) aynı gün olarak geri yazılır.
        let from = try XCTUnwrap(PostgresDate.parse("2026-11-15"))
        let to = try XCTUnwrap(PostgresDate.parse("2026-11-22"))
        let draft = CommunityPostDraft(kind: .coverRequest, body: "x", spotId: UUID(), coverFrom: from, coverTo: to)
        let params = try json(SupabaseBackend.createPostParams(draft))
        XCTAssertEqual(params["p_cover_from"] as? String, "2026-11-15")
        XCTAssertEqual(params["p_cover_to"] as? String, "2026-11-22")
    }

    func testCreatePostParamsDropCoverDatesForOtherKinds() throws {
        let draft = CommunityPostDraft(kind: .supply, body: "Elimde fazla mama var.", coordinate: .modaKadikoy,
                                       coverFrom: utc(2026, 11, 15), coverTo: utc(2026, 11, 22))
        let params = try json(SupabaseBackend.createPostParams(draft))
        XCTAssertEqual(params["p_kind"] as? String, "supply")
        XCTAssertTrue(params["p_cover_from"] is NSNull)
        XCTAssertTrue(params["p_cover_to"] is NSNull)
    }

    func testFeedParams() throws {
        let center = Coordinate(latitude: 40.98621, longitude: 29.02544)
        let first = try json(SupabaseBackend.feedParams(center: center, radiusMeters: CommunityPolicy.feedRadiusMeters,
                                                        kind: nil, before: nil, limit: CommunityPolicy.pageSize))
        XCTAssertEqual(Set(first.keys), ["lat", "lng", "radius_m", "p_kind", "p_before", "max_rows"])
        XCTAssertEqual(first["lat"] as? Double, 40.98621)
        XCTAssertEqual(first["lng"] as? Double, 29.02544)
        XCTAssertEqual(first["radius_m"] as? Int, 3000)
        XCTAssertTrue(first["p_kind"] is NSNull)
        XCTAssertTrue(first["p_before"] is NSNull)
        XCTAssertEqual(first["max_rows"] as? Int, 30)

        // Sonraki sayfa: önceki sayfanın son satırının `created_at`'i milisaniyesiyle geri gider.
        let cursor = try XCTUnwrap(PostgresDate.parse("2026-11-09T19:00:00.123+00:00"))
        let next = try json(SupabaseBackend.feedParams(center: center, radiusMeters: 50_000, kind: .coverRequest,
                                                       before: cursor, limit: 500))
        XCTAssertEqual(next["p_kind"] as? String, "cover_request")
        XCTAssertEqual(next["p_before"] as? String, "2026-11-09T19:00:00.123Z")
        XCTAssertEqual(next["radius_m"] as? Int, 10_000, "Sözleşme: en fazla 10 000 m")
        XCTAssertEqual(next["max_rows"] as? Int, 50, "Sözleşme: en fazla 50 satır")

        let clampedLow = try json(SupabaseBackend.feedParams(center: center, radiusMeters: -5, kind: .alert, before: nil, limit: 0))
        XCTAssertEqual(clampedLow["radius_m"] as? Int, 0)
        XCTAssertEqual(clampedLow["max_rows"] as? Int, 1)
        XCTAssertEqual(clampedLow["p_kind"] as? String, "alert")
    }

    /// Nokta ve konum birlikte yoksa sunucu `status` yerine exception fırlatır: sonuç yerelde verilir.
    func testCreatePostWithoutSpotOrLocationIsAnsweredLocally() {
        let now = utc(2026, 11, 10, 9)
        XCTAssertEqual(SupabaseBackend.localCreatePostOutcome(CommunityPostDraft(kind: .note, body: "Merhaba"), now: now),
                       .invalid(.locationMissing))
        XCTAssertEqual(SupabaseBackend.localCreatePostOutcome(CommunityPostDraft(kind: .alert, body: "  \n"), now: now),
                       .invalid(.bodyEmpty))
        XCTAssertEqual(SupabaseBackend.localCreatePostOutcome(
            CommunityPostDraft(kind: .question, body: String(repeating: "a", count: CommunityPolicy.maxBodyLength + 1)), now: now
        ), .invalid(.bodyTooLong))
        XCTAssertEqual(SupabaseBackend.localCreatePostOutcome(
            CommunityPostDraft(kind: .coverRequest, body: "Yerime bakar mısın?", coverFrom: now, coverTo: now), now: now
        ), .invalid(.coverNeedsSpot))

        // Nokta ya da konum varsa karar sunucunun (boş metin, geçmiş tarih dahil).
        XCTAssertNil(SupabaseBackend.localCreatePostOutcome(CommunityPostDraft(kind: .note, body: "", coordinate: .modaKadikoy), now: now))
        XCTAssertNil(SupabaseBackend.localCreatePostOutcome(CommunityPostDraft(kind: .note, body: "Merhaba", spotId: UUID()), now: now))
        XCTAssertNil(SupabaseBackend.localCreatePostOutcome(
            CommunityPostDraft(kind: .coverRequest, body: "x", spotId: UUID(), coverFrom: utc(2020, 1, 1), coverTo: utc(2020, 1, 2)), now: now
        ))
        XCTAssertNil(SupabaseBackend.localCreatePostOutcome(
            CommunityPostDraft(kind: .coverRequest, body: "x", coordinate: .modaKadikoy), now: now
        ))
    }

    func testEveryPostKindIsSentAsContractEnumValue() {
        XCTAssertEqual(Set(CommunityPostKind.allCases.map(\.rawValue)), ["note", "question", "cover_request", "supply", "alert"])
    }
}
