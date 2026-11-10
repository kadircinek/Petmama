import Foundation
import MamaCore
import Supabase

// Supabase/PostgREST JSON'unu çözmek için yardımcılar.
//
// supabase-swift'in PostgREST decoder'ı (`JSONDecoder.supabase()`) snake_case dönüştürmez ve yalnızca
// `yyyy-MM-dd'T'HH:mm:ss(.SSS)` biçimini çözer; Postgres `date` ("2026-11-04") ve `+00:00` ofsetli
// `timestamptz` için güvenilir değildir. Bu yüzden yanıtın ham `Data`'sını kendi decoder'ımızla çözüyoruz:
// DTO'lar açık CodingKeys kullanır, tarih ve enum alanları `String` olarak okunup eşlemede yorumlanır
// (bilinmeyen değerler çözümü bozmaz).

/// Postgres tarih/zaman metinlerini çözer ve üretir.
enum PostgresDate {
    /// `date` sütunlarının (ör. `spot_feeding_timeline.day`) yorumlandığı saat dilimi.
    static var dayTimeZone: TimeZone { NotificationPolicy.timeZone }

    /// `timestamptz` ("2026-11-04T08:15:00.123Z", "2026-11-04 08:15:00.123456+00:00", "…+03") veya
    /// `date` ("2026-11-04" → Europe/Istanbul gece yarısı) metnini çözer. Ofset yoksa UTC kabul edilir.
    static func parse(_ raw: String) -> Date? {
        let bytes = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        var index = 0

        func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for offset in 0..<count {
                let byte = bytes[index + offset]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            index += count
            return value
        }
        func consume(_ character: Character) -> Bool {
            guard index < bytes.count, let ascii = character.asciiValue, bytes[index] == ascii else { return false }
            index += 1
            return true
        }

        guard let year = digits(4), consume("-"), let month = digits(2), consume("-"), let day = digits(2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        if index == bytes.count {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = dayTimeZone
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }

        guard consume("T") || consume(" ") || consume("t") else { return nil }
        guard let hour = digits(2), consume(":"), let minute = digits(2), hour <= 24, minute <= 59 else { return nil }

        var seconds = 0.0
        if consume(":") {
            guard let whole = digits(2), whole <= 60 else { return nil }
            seconds = Double(whole)
            if consume(".") || consume(",") {
                var fraction = 0
                var scale = 1
                var count = 0
                while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                    if count < 9 {
                        fraction = fraction * 10 + Int(bytes[index] - 48)
                        scale *= 10
                    }
                    count += 1
                    index += 1
                }
                guard count > 0 else { return nil }
                seconds += Double(fraction) / Double(scale)
            }
        }

        var offsetSeconds = 0
        if index < bytes.count {
            if consume("Z") || consume("z") {
                // UTC
            } else if bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                let sign = bytes[index] == UInt8(ascii: "-") ? -1 : 1
                index += 1
                guard let offsetHours = digits(2) else { return nil }
                var offsetMinutes = 0
                if consume(":") {
                    guard let value = digits(2) else { return nil }
                    offsetMinutes = value
                } else if let value = digits(2) {
                    offsetMinutes = value
                }
                offsetSeconds = sign * (offsetHours * 3600 + offsetMinutes * 60)
            } else {
                return nil
            }
        }
        guard index == bytes.count else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let interval = Double(days) * 86_400 + Double(hour * 3600 + minute * 60) + seconds - Double(offsetSeconds)
        return Date(timeIntervalSince1970: interval)
    }

    /// 1970-01-01'den bu yana gün sayısı (proleptik Gregoryen; H. Hinnant'ın algoritması).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12 // Mart = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// `timestamptz` sütununa / parametresine yazmak için ISO-8601 (UTC, milisaniyeli).
    ///
    /// En yakın milisaniyeye yuvarlar: `parse` ile okunan milisaniyeli bir damga aynı metne döner. Mahalle
    /// akışının `p_before` imleci buna dayanır (bir milisaniye kayarsa sayfa sınırında satır atlanır ya da
    /// tekrar gelir). Kesrin kırpılıp kırpılmayacağı platform biçimleyicisine bırakılmaz: biçimleyici
    /// yalnızca tam saniyeyi yazar, milisaniye tamsayı olarak eklenir.
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let rounded = (date.timeIntervalSince1970 * 1000).rounded()
        // Tamsayıya sığmayan (anlamsız) tarihlerde biçimleyicinin kendi çıktısı.
        guard rounded.isFinite, abs(rounded) < 1e15 else {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
        let totalMillis = Int64(rounded)
        var seconds = totalMillis / 1000
        var millis = totalMillis % 1000
        if millis < 0 { // 1970 öncesi: aşağı yuvarlayan bölme
            millis += 1000
            seconds -= 1
        }
        formatter.formatOptions = [.withInternetDateTime]
        // "2026-11-04T08:15:00Z" → "2026-11-04T08:15:00.123Z"
        let wholeSecond = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds))).dropLast()
        let fraction = String(millis)
        return "\(wholeSecond).\(String(repeating: "0", count: 3 - fraction.count))\(fraction)Z"
    }

    /// `date` sütununa / parametresine yazmak için "YYYY-MM-DD": anın `dayTimeZone` (Europe/Istanbul)
    /// takvimindeki günü. `parse` ile tersinir (gün metni → o günün İstanbul gece yarısı).
    static func formatDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dayTimeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func padded(_ value: Int?, _ width: Int) -> String {
            let text = String(max(value ?? 0, 0))
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(padded(parts.year, 4))-\(padded(parts.month, 2))-\(padded(parts.day, 2))"
    }
}

/// Satırlardan biri çözülemezse (ör. bozuk uuid) yalnızca o satırı atlayan dizi.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else if (try? container.decode(Skip.self)) == nil {
                break
            }
        }
        elements = result
    }

    /// Hiçbir şey okumadan başarılı olur; kapsayıcıyı bir sonraki elemana ilerletir.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

/// Sayı veya metin olarak gelebilen `numeric` değerleri.
struct FlexibleDouble: Decodable {
    var value: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}

enum SupabaseJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // DTO'lar tarihleri String olarak okur; yine de bir Date alanı eklenirse aynı kurallarla çözülsün.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = PostgresDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Geçersiz tarih: \(text)")
            }
            return date
        }
        return decoder
    }

    /// `setof` / `table(...)` dönen RPC'lerin ve tablo sorgularının satırları (bozuk satırlar atlanır).
    static func rows<Row: Decodable>(_ type: Row.Type, from data: Data) throws -> [Row] {
        if isEmptyBody(data) { return [] }
        return try decoder().decode(LossyArray<Row>.self, from: data).elements
    }

    /// Tek nesne dönen RPC'ler (`jsonb`). Dizi gelirse ilk eleman alınır.
    static func object<Object: Decodable>(_ type: Object.Type, from data: Data) throws -> Object {
        let decoder = decoder()
        if let value = try? decoder.decode(Object.self, from: data) { return value }
        if let first = try? decoder.decode([Object].self, from: data).first { return first }
        return try decoder.decode(Object.self, from: data)
    }

    /// `select("x")` sorgusundan tek bir uuid sütunu.
    static func uuidColumn(_ column: String, from data: Data) -> [UUID] {
        guard !isEmptyBody(data),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { ($0[column] as? String).flatMap(UUID.init(uuidString:)) }
    }

    /// Skaler `uuid` dönen RPC (ör. `create_need`): `"…"` gövdesi.
    static func scalarUUID(from data: Data) -> UUID? {
        if let value = try? decoder().decode(UUID.self, from: data) { return value }
        if let values = try? decoder().decode([UUID].self, from: data), let first = values.first { return first }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"[]")))
        return UUID(uuidString: text)
    }

    static func isEmptyBody(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "null"
    }
}

/// RPC parametreleri ve tablo gövdeleri için açık JSON değerleri. `nil` → `null` (anahtar korunur;
/// PostgREST fonksiyonu parametre adlarıyla eşlediği için varsayılanı olmayan parametreler atlanmamalı).
enum Param {
    static func uuid(_ value: UUID) -> AnyJSON { .string(value.postgresString) }
    static func uuid(_ value: UUID?) -> AnyJSON { value.map { .string($0.postgresString) } ?? .null }
    static func string(_ value: String?) -> AnyJSON { value.map(AnyJSON.string) ?? .null }
    static func bool(_ value: Bool?) -> AnyJSON { value.map(AnyJSON.bool) ?? .null }
    static func strings(_ values: [String]) -> AnyJSON { .array(values.map(AnyJSON.string)) }
    static func ints(_ values: [Int]) -> AnyJSON { .array(values.map(AnyJSON.integer)) }
    static func double(_ value: Double?) -> AnyJSON { value.map(AnyJSON.double) ?? .null }
    static func date(_ value: Date) -> AnyJSON { .string(PostgresDate.format(value)) }
    static func date(_ value: Date?) -> AnyJSON { value.map { .string(PostgresDate.format($0)) } ?? .null }
    /// Postgres `date` ("YYYY-MM-DD", Europe/Istanbul günü).
    static func day(_ value: Date?) -> AnyJSON { value.map { .string(PostgresDate.formatDay($0)) } ?? .null }

    /// Boşsa `null`; kırpılmış metin.
    static func text(_ value: String?) -> AnyJSON {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return .null }
        return .string(trimmed)
    }
}

extension UUID {
    /// Postgres `auth.uid()::text` ile aynı biçim (küçük harf). Storage yolu bununla karşılaştırılır.
    var postgresString: String { uuidString.lowercased() }
}

extension String {
    /// Boş olmayan geçerli URL.
    var nonEmptyURL: URL? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
