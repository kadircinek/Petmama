import Foundation
import MamaCore
@testable import MamaSupabase
import Supabase
import XCTest

/// Moderasyon RPC'leri (supabase/migrations/20261117000026_moderation.sql) → domain.
final class ModerationDecodingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testQueueRows() throws {
        let json = """
        [{"target_type":"post","target_id":"00000000-0000-4000-8006-000000000004","title":"supply","body":"Elimde mama var",
          "photo_url":"https://x.test/p.jpg","owner_id":"00000000-0000-4000-8001-000000000003","owner_name":"Zeynep",
          "report_count":2,"reasons":["spam","inappropriate","new_reason"],"first_reported_at":"2026-11-17T08:00:00+00:00",
          "last_reported_at":"2026-11-17T10:00:00+00:00","content_state":"pending","decision":null,"decided_at":null},
         {"target_type":"chat_message","target_id":"00000000-0000-4000-8010-000000000003","title":null,"body":"Mesaj",
          "photo_url":null,"owner_id":null,"owner_name":null,"report_count":1,"reasons":["harassment"],
          "first_reported_at":"2026-11-17T09:00:00+00:00","last_reported_at":"2026-11-17T09:00:00+00:00",
          "content_state":"removed","decision":"remove","decided_at":"2026-11-17T11:00:00+00:00"},
         {"target_type":"future_target","target_id":"00000000-0000-4000-8010-000000000009","report_count":1,"reasons":[],
          "first_reported_at":"2026-11-17T09:00:00+00:00","last_reported_at":"2026-11-17T09:00:00+00:00","content_state":"live"}]
        """
        let cases = try SupabaseDecoding.moderationCases(from: data(json))
        XCTAssertEqual(cases.count, 2, "bilinmeyen hedef türü düşer")
        let post = cases[0]
        XCTAssertEqual(post.target, .post)
        XCTAssertEqual(post.targetId, DemoData.id(6, 4))
        XCTAssertEqual(post.title, "supply")
        XCTAssertEqual(post.photoURL, URL(string: "https://x.test/p.jpg"))
        XCTAssertEqual(post.ownerId, DemoData.zeynepId)
        XCTAssertEqual(post.ownerName, "Zeynep")
        XCTAssertEqual(post.reportCount, 2)
        XCTAssertEqual(post.reasons, [.spam, .inappropriate], "bilinmeyen neden düşer")
        XCTAssertEqual(post.contentState, .pending)
        XCTAssertNil(post.decision)
        XCTAssertEqual(post.firstReportedAt, PostgresDate.parse("2026-11-17T08:00:00Z"))
        let chat = cases[1]
        XCTAssertEqual(chat.target, .chatMessage)
        XCTAssertEqual(chat.decision, .remove)
        XCTAssertEqual(chat.contentState, .removed)
        XCTAssertNotNil(chat.decidedAt)
    }

    func testCaseDetail() throws {
        let json = """
        {"status":"ok",
         "case":{"target_type":"user","target_id":"00000000-0000-4000-8001-000000000002","title":"Emre","body":null,
                 "photo_url":null,"owner_id":"00000000-0000-4000-8001-000000000002","owner_name":"Emre",
                 "content_state":"live","decision":null,"decided_at":null,"restorable":false},
         "reports":[{"id":"00000000-0000-4000-8099-000000000001","reason":"harassment","details":"Kaba","created_at":"2026-11-17T10:00:00+00:00",
                     "reporter_id":"00000000-0000-4000-8001-000000000003","reporter_name":"Zeynep","status":"open"},
                    {"id":"00000000-0000-4000-8099-000000000002","reason":"spam","details":null,"created_at":"2026-11-10T10:00:00+00:00",
                     "reporter_id":null,"reporter_name":null,"status":"actioned"}],
         "owner":{"user_id":"00000000-0000-4000-8001-000000000002","display_name":"Emre","is_moderator":false,
                  "avatar_url":"https://x.test/emre.jpg","removed_count_90d":2,"suspension_count_90d":1,"suspended_until":"infinity"}}
        """
        let detail = try XCTUnwrap(try SupabaseDecoding.moderationCaseDetail(from: data(json)))
        XCTAssertEqual(detail.moderationCase.target, .user)
        XCTAssertEqual(detail.moderationCase.title, "Emre")
        XCTAssertEqual(detail.moderationCase.reportCount, 1, "açık rapor sayısı")
        XCTAssertEqual(detail.moderationCase.reasons, [.harassment])
        XCTAssertEqual(detail.reports.count, 2)
        XCTAssertEqual(detail.reports[0].reporterName, "Zeynep")
        XCTAssertEqual(detail.reports[0].details, "Kaba")
        XCTAssertEqual(detail.reports[1].status, .actioned)
        XCTAssertNil(detail.reports[1].reporterName)
        XCTAssertEqual(detail.owner?.removedCount90d, 2)
        XCTAssertEqual(detail.owner?.suspensionCount90d, 1)
        XCTAssertEqual(detail.owner?.suspendedUntil, .distantFuture, "'infinity' = süresiz")
        XCTAssertEqual(detail.owner?.avatarURL, URL(string: "https://x.test/emre.jpg"))
        XCTAssertFalse(detail.moderationCase.isRestorable)

        XCTAssertNil(try SupabaseDecoding.moderationCaseDetail(from: data(#"{"status":"not_found"}"#)))
        XCTAssertThrowsError(try SupabaseDecoding.moderationCaseDetail(from: data(#"{"status":"not_allowed"}"#))) { error in
            XCTAssertEqual(error as? MamaError, .permissionDenied)
        }
    }

    func testOutcomes() throws {
        XCTAssertEqual(try SupabaseDecoding.moderationOutcome(from: data(#"{"status":"ok","closed_reports":3}"#)), .done(closedReports: 3))
        XCTAssertEqual(try SupabaseDecoding.moderationOutcome(from: data(#"{"status":"ok"}"#)), .done(closedReports: 0))
        XCTAssertEqual(try SupabaseDecoding.moderationOutcome(from: data(#"{"status":"not_allowed"}"#)), .notAllowed)
        XCTAssertEqual(try SupabaseDecoding.moderationOutcome(from: data(#"{"status":"not_found"}"#)), .notFound)
        XCTAssertEqual(try SupabaseDecoding.moderationOutcome(from: data(#"{"status":"invalid","reason":"note_too_long"}"#)),
                       .invalid(reason: "note_too_long"))
        XCTAssertThrowsError(try SupabaseDecoding.moderationOutcome(from: data(#"{"status":"weird"}"#)))

        let until = try XCTUnwrap(PostgresDate.parse("2026-11-24T10:00:00Z"))
        XCTAssertEqual(try SupabaseDecoding.suspendOutcome(from: data(#"{"status":"ok","suspended_until":"2026-11-24T10:00:00Z"}"#)),
                       .suspended(until: until))
        XCTAssertEqual(try SupabaseDecoding.suspendOutcome(from: data(#"{"status":"ok","suspended_until":"infinity"}"#)),
                       .suspended(until: .distantFuture))
        XCTAssertEqual(try SupabaseDecoding.suspendOutcome(from: data(#"{"status":"not_allowed"}"#)), .notAllowed)
        XCTAssertEqual(try SupabaseDecoding.suspendOutcome(from: data(#"{"status":"invalid","reason":"days"}"#)), .invalid(reason: "days"))
    }

    func testScalars() throws {
        XCTAssertEqual(SupabaseDecoding.mySuspension(from: data("null")), nil)
        XCTAssertEqual(SupabaseDecoding.mySuspension(from: data(#""infinity""#)), .distantFuture)
        XCTAssertEqual(SupabaseDecoding.mySuspension(from: data(#""2026-11-24T10:00:00+00:00""#)), PostgresDate.parse("2026-11-24T10:00:00Z"))
        XCTAssertEqual(SupabaseDecoding.openCaseCount(from: data("4")), 4)
        XCTAssertEqual(SupabaseDecoding.openCaseCount(from: data("null")), 0)
    }

    func testParams() {
        let decide = SupabaseBackend.decideParams(target: .chatMessage, id: DemoData.id(10, 3), decision: .remove, note: "  Not  ")
        XCTAssertEqual(decide["p_target_type"], .string("chat_message"))
        XCTAssertEqual(decide["p_action"], .string("remove"))
        XCTAssertEqual(decide["p_note"], .string("Not"))
        let noNote = SupabaseBackend.decideParams(target: .post, id: DemoData.id(6, 4), decision: .approve, note: "   ")
        XCTAssertEqual(noNote["p_note"], .null)
        XCTAssertEqual(SupabaseBackend.suspendParams(userId: DemoData.emreId, length: .month, note: nil)["p_days"], .integer(30))
        XCTAssertEqual(SupabaseBackend.suspendParams(userId: DemoData.emreId, length: .indefinite, note: nil)["p_days"], .null)
    }

    func testProfileSelectNeverAsksForSuspension() {
        // `suspended_until` başkalarına kapalı (sütun yetkisi yok): `select=*` hata verir.
        XCTAssertFalse(SupabaseBackend.profileColumns.contains("suspended_until"))
        XCTAssertFalse(SupabaseBackend.profileColumns.contains("*"))
        XCTAssertTrue(SupabaseBackend.profileColumns.contains("is_moderator"))
    }

    func testSuspendedExceptionMapsToSuspended() throws {
        let until = try XCTUnwrap(PostgresDate.parse("2026-11-24T10:00:00Z"))
        let dated = SupabaseErrorMapper.map(PostgrestError(detail: "2026-11-24T10:00:00Z", hint: "suspended", code: "P0001", message: "suspended"))
        XCTAssertEqual(dated as? MamaError, .suspended(until: until))
        let indefinite = SupabaseErrorMapper.map(PostgrestError(detail: "infinity", hint: "suspended", code: "P0001", message: "suspended"))
        XCTAssertEqual(indefinite as? MamaError, .suspendedIndefinitely)
        let noDetail = SupabaseErrorMapper.map(PostgrestError(code: "P0001", message: "suspended"))
        XCTAssertEqual(noDetail as? MamaError, .suspended(until: nil), "bitiş bilinmiyor: süresiz denmez")
        let garbage = SupabaseErrorMapper.map(PostgrestError(detail: "yarın", hint: "suspended", code: "P0001", message: "suspended"))
        XCTAssertEqual(garbage as? MamaError, .suspended(until: nil))
        XCTAssertFalse(MamaError.suspended(until: nil).userMessage.contains("süresiz"))
    }
}
