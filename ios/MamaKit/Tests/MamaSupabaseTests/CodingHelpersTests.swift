import Foundation
import MamaCore
@testable import MamaSupabase
import Supabase
import XCTest

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PostgresDateTests: XCTestCase {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Double = 0) -> TimeInterval {
        Double(PostgresDate.daysFromCivil(year: y, month: mo, day: d)) * 86_400 + Double(h * 3600 + mi * 60) + s
    }

    func testDaysFromCivil() {
        XCTAssertEqual(PostgresDate.daysFromCivil(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(PostgresDate.daysFromCivil(year: 2000, month: 3, day: 1), 11_017)
        XCTAssertEqual(PostgresDate.daysFromCivil(year: 2024, month: 2, day: 29), 19_782)
        XCTAssertEqual(PostgresDate.daysFromCivil(year: 1969, month: 12, day: 31), -1)
    }

    func testTimestamptzVariants() throws {
        let expected = utc(2026, 11, 4, 8, 15, 0.123)
        let variants = [
            "2026-11-04T08:15:00.123Z",
            "2026-11-04T08:15:00.123+00:00",
            "2026-11-04 08:15:00.123+00",
            "2026-11-04T11:15:00.123+03:00",
            "2026-11-04T11:15:00.123+0300",
            "2026-11-04T05:15:00.123-03:00",
            "2026-11-04T08:15:00.123",
        ]
        for text in variants {
            let date = try XCTUnwrap(PostgresDate.parse(text), text)
            XCTAssertEqual(date.timeIntervalSince1970, expected, accuracy: 0.000_5, text)
        }
        let micro = try XCTUnwrap(PostgresDate.parse("2026-11-04T08:15:00.123456+00:00"))
        XCTAssertEqual(micro.timeIntervalSince1970, utc(2026, 11, 4, 8, 15, 0.123456), accuracy: 0.000_01)
        let whole = try XCTUnwrap(PostgresDate.parse("2026-11-04T08:15:00Z"))
        XCTAssertEqual(whole.timeIntervalSince1970, utc(2026, 11, 4, 8, 15))
        let noSeconds = try XCTUnwrap(PostgresDate.parse("2026-11-04T08:15Z"))
        XCTAssertEqual(noSeconds.timeIntervalSince1970, utc(2026, 11, 4, 8, 15))
    }

    func testDateOnlyIsIstanbulMidnight() throws {
        let date = try XCTUnwrap(PostgresDate.parse("2026-11-04"))
        XCTAssertEqual(date.timeIntervalSince1970, utc(2026, 11, 3, 21))
    }

    func testInvalidStrings() {
        for text in ["", "infinity", "2026-13-01", "2026-11-04T", "2026-11-04T08", "2026-11-04T08:15:00.Z",
                     "2026-11-04T08:15:00+3", "2026/11/04", "2026-11-04T08:15:00Zjunk"] {
            XCTAssertNil(PostgresDate.parse(text), text)
        }
    }

    func testFormatRoundTrips() throws {
        let date = Date(timeIntervalSince1970: utc(2026, 11, 4, 8, 15, 0.25))
        let text = PostgresDate.format(date)
        XCTAssertEqual(text, "2026-11-04T08:15:00.250Z")
        XCTAssertEqual(try XCTUnwrap(PostgresDate.parse(text)).timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    /// Mahalle akışı `p_before` ile sayfalanır (keyset): sunucudan okunan `created_at` aynı milisaniyeyle
    /// geri gönderilmezse sayfa sınırındaki satır tekrar gelir ya da atlanır.
    func testFormatIsMillisecondExactForParsedTimestamps() throws {
        for millis in 0..<1000 {
            let fraction = String(repeating: "0", count: 3 - String(millis).count) + String(millis)
            let text = "2026-11-10T08:15:59.\(fraction)Z"
            let parsed = try XCTUnwrap(PostgresDate.parse(text), text)
            XCTAssertEqual(PostgresDate.format(parsed), text)
        }
        // Postgres çıktısı (+00:00) da aynı metne döner.
        let fromServer = try XCTUnwrap(PostgresDate.parse("2026-11-10T08:15:59.123+00:00"))
        XCTAssertEqual(PostgresDate.format(fromServer), "2026-11-10T08:15:59.123Z")
        XCTAssertEqual(PostgresDate.format(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        // Mikrosaniyeli değerler en yakın milisaniyeye yuvarlanır; saniye ve gün sınırı taşar.
        XCTAssertEqual(PostgresDate.format(Date(timeIntervalSince1970: utc(2026, 11, 10, 8, 15, 59.123456))), "2026-11-10T08:15:59.123Z")
        XCTAssertEqual(PostgresDate.format(Date(timeIntervalSince1970: utc(2026, 11, 10, 8, 15, 59.1236))), "2026-11-10T08:15:59.124Z")
        XCTAssertEqual(PostgresDate.format(Date(timeIntervalSince1970: utc(2026, 12, 31, 23, 59, 59.9996))), "2027-01-01T00:00:00.000Z")
        XCTAssertEqual(PostgresDate.format(Date(timeIntervalSince1970: -0.001)), "1969-12-31T23:59:59.999Z")
        XCTAssertEqual(PostgresDate.format(Date(timeIntervalSince1970: -1.5)), "1969-12-31T23:59:58.500Z")
    }

    func testFormatDayIsIstanbulCalendarDay() throws {
        // 21:30 UTC = İstanbul'da ertesi gün 00:30.
        XCTAssertEqual(PostgresDate.formatDay(Date(timeIntervalSince1970: utc(2026, 11, 14, 21, 30))), "2026-11-15")
        XCTAssertEqual(PostgresDate.formatDay(Date(timeIntervalSince1970: utc(2026, 11, 14, 20, 59, 59))), "2026-11-14")
        XCTAssertEqual(PostgresDate.formatDay(Date(timeIntervalSince1970: utc(2027, 1, 1, 12))), "2027-01-01")
        XCTAssertEqual(PostgresDate.formatDay(Date(timeIntervalSince1970: utc(2026, 12, 31, 21))), "2027-01-01")
        // `date` metni → İstanbul gece yarısı → aynı metin.
        for text in ["2026-11-15", "2026-03-01", "2028-02-29"] {
            XCTAssertEqual(PostgresDate.formatDay(try XCTUnwrap(PostgresDate.parse(text))), text)
        }
    }
}

final class ParamEncodingTests: XCTestCase {
    func testNilParamsEncodeAsExplicitNull() throws {
        let params: JSONObject = [
            "p_note": Param.text("   "),
            "p_photo_url": Param.string(nil),
            "p_spot_id": Param.uuid(UUID(uuidString: "6F1C2A6E-1B7D-4C39-9C39-0D5D1F4B8A10")!),
            "p_animal_id": Param.uuid(nil as UUID?),
            "p_title": Param.text("  Moda  "),
        ]
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        XCTAssertTrue(json["p_note"] is NSNull)
        XCTAssertTrue(json["p_photo_url"] is NSNull)
        XCTAssertTrue(json["p_animal_id"] is NSNull)
        XCTAssertEqual(json["p_spot_id"] as? String, "6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10")
        XCTAssertEqual(json["p_title"] as? String, "Moda")
    }

    func testOptionalParamsEncodeValueOrNull() throws {
        let params: JSONObject = [
            "lat": Param.double(40.98621),
            "lng": Param.double(nil),
            "p_before": Param.date(Date(timeIntervalSince1970: 1_794_298_559.123)),
            "p_none": Param.date(nil as Date?),
            "p_cover_from": Param.day(Date(timeIntervalSince1970: 1_794_691_800)), // 2026-11-14T21:30:00Z
            "p_cover_to": Param.day(nil),
        ]
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        XCTAssertEqual(json["lat"] as? Double, 40.98621)
        XCTAssertTrue(json["lng"] is NSNull)
        XCTAssertEqual(json["p_before"] as? String, "2026-11-10T08:15:59.123Z")
        XCTAssertTrue(json["p_none"] is NSNull)
        XCTAssertEqual(json["p_cover_from"] as? String, "2026-11-15")
        XCTAssertTrue(json["p_cover_to"] is NSNull)
    }

    func testStoragePathUsesLowercasedAuthUid() {
        let user = UUID(uuidString: "0B9D7C1E-58A6-4D0B-8F7F-3F8F6A6E2C11")!
        let file = UUID(uuidString: "6F1C2A6E-1B7D-4C39-9C39-0D5D1F4B8A10")!
        XCTAssertEqual(SupabaseBackend.storagePath(userId: user, fileId: file),
                       "0b9d7c1e-58a6-4d0b-8f7f-3f8f6a6e2c11/6f1c2a6e-1b7d-4c39-9c39-0d5d1f4b8a10.jpg")
    }
}

final class ErrorMappingTests: XCTestCase {
    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.supabase.co")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func mapped(_ error: any Error) -> MamaError? {
        SupabaseErrorMapper.map(error) as? MamaError
    }

    func testConnectivity() {
        XCTAssertEqual(mapped(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(mapped(URLError(.timedOut)), .offline)
        XCTAssertTrue(SupabaseErrorMapper.map(CancellationError()) is CancellationError)
    }

    func testPostgrestErrors() {
        XCTAssertEqual(mapped(PostgrestError(code: "42501", message: "not_authenticated")), .notSignedIn)
        XCTAssertEqual(mapped(PostgrestError(code: "42501", message: "new row violates row-level security policy for table \"guardians\"")), .permissionDenied)
        XCTAssertEqual(mapped(PostgrestError(code: "PGRST301", message: "JWT expired")), .notSignedIn)
        XCTAssertEqual(mapped(PostgrestError(hint: "profanity", code: "P0001", message: "rejected_content")), .rejectedContent)
        XCTAssertEqual(mapped(PostgrestError(code: "22023", message: "invalid_coordinates")), .invalidInput(SupabaseErrorMapper.invalidLocationMessage))
        XCTAssertEqual(mapped(PostgrestError(code: "23503", message: "insert or update violates foreign key constraint")), .notFound)
        XCTAssertEqual(mapped(PostgrestError(code: "23514", message: "new row violates check constraint")), .invalidInput(SupabaseErrorMapper.invalidValueMessage))
        XCTAssertEqual(mapped(PostgrestError(code: "XX000", message: "boom")), .server("boom"))
        XCTAssertTrue(SupabaseErrorMapper.isUniqueViolation(PostgrestError(code: "23505", message: "duplicate key")))
        XCTAssertFalse(SupabaseErrorMapper.isUniqueViolation(PostgrestError(code: "23503", message: "fk")))
    }

    func testHTTPAndFunctionErrors() {
        XCTAssertEqual(mapped(HTTPError(data: Data(), response: response(401))), .notSignedIn)
        XCTAssertEqual(mapped(HTTPError(data: Data(), response: response(403))), .permissionDenied)
        XCTAssertEqual(mapped(FunctionsError.httpError(code: 401, data: Data())), .notSignedIn)
        guard case .server = mapped(FunctionsError.httpError(code: 500, data: Data("x".utf8))) else {
            return XCTFail("server bekleniyordu")
        }
    }

    func testAuthErrors() {
        func api(_ code: ErrorCode, _ message: String, status: Int = 400) -> AuthError {
            .api(message: message, errorCode: code, underlyingData: Data(), underlyingResponse: response(status))
        }
        XCTAssertEqual(mapped(api(.invalidCredentials, "Invalid login credentials")), .invalidCredentials)
        XCTAssertEqual(mapped(api(.unknown, "Invalid login credentials")), .invalidCredentials)
        XCTAssertEqual(mapped(api(.userAlreadyExists, "User already registered", status: 422)), .emailAlreadyInUse)
        XCTAssertEqual(mapped(api(.unknown, "User already registered", status: 422)), .emailAlreadyInUse)
        XCTAssertEqual(mapped(api(.emailNotConfirmed, "Email not confirmed")), .invalidInput(SupabaseErrorMapper.emailNotConfirmedMessage))
        XCTAssertEqual(mapped(AuthError.sessionMissing), .notSignedIn)
        XCTAssertEqual(mapped(AuthError.weakPassword(message: "weak", reasons: ["length"])), .invalidInput(SupabaseErrorMapper.weakPasswordMessage))
    }

    func testStorageErrors() {
        XCTAssertEqual(mapped(StorageError(statusCode: "403", message: "new row violates row-level security policy", error: "Unauthorized")), .permissionDenied)
        XCTAssertEqual(mapped(StorageError(statusCode: "413", message: "Payload too large")), .invalidInput(SupabaseErrorMapper.photoTooLargeMessage))
    }
}
