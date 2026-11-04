import Foundation
import Observation
import MamaCore

/// Harita aramasından gelen veteriner kliniği (platformdan bağımsız).
public struct VetClinic: Identifiable, Hashable, Sendable {
    public var name: String
    public var address: String?
    public var phone: String?
    public var coordinate: Coordinate
    public var distanceMeters: Double?

    public init(name: String, address: String? = nil, phone: String? = nil, coordinate: Coordinate, distanceMeters: Double? = nil) {
        self.name = name
        self.address = address
        self.phone = phone
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
    }

    public var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }
}

/// En yakın veteriner aramasını soyutlar: iOS'ta MapKit `MKLocalSearch`, testlerde sahte (FR-I4).
public protocol VetClinicSearching: Sendable {
    func clinics(near center: Coordinate, radiusMeters: Double) async throws -> [VetClinic]
}

/// Acil veteriner bilgisi. Uygulama tıbbi tavsiye vermez; yalnızca yön gösterir (FR-I4, PRD 9.1).
@MainActor
@Observable
public final class VetHelpViewModel {
    public static let searchRadiusMeters: Double = 5000
    public static let maxClinics = 8
    public static let disclaimer = "Mama Haritası tıbbi tavsiye vermez. Hayvanın durumu için bir veterinere danış."
    public static let municipalLine = "Belediyenin Beyaz Masa hattı: Alo 153"
    public static let emergencyLine = "Hayvana kasıtlı zarar veya zehirleme şüphesinde 112'yi ara"

    public private(set) var need: Need?
    public private(set) var clinics: [VetClinic] = []
    public private(set) var isSearching = false
    public private(set) var hasSearched = false
    public private(set) var searchFailed = false

    public let needId: UUID?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let searcher: any VetClinicSearching

    public init(needId: UUID?, services: AppServices, searcher: any VetClinicSearching) {
        self.needId = needId
        self.services = services
        self.searcher = searcher
    }

    /// Arama merkezi: kullanıcı konumu → ihtiyacın konumu → Moda.
    public func searchCenter(user: Coordinate?) -> Coordinate {
        user ?? need?.coordinate ?? .modaKadikoy
    }

    public func load(near user: Coordinate?) async {
        if let needId, need == nil {
            need = try? await services.needs.need(id: needId)
        }
        let center = searchCenter(user: user)
        isSearching = true
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            let found = try await searcher.clinics(near: center, radiusMeters: Self.searchRadiusMeters)
            clinics = Self.nearest(found, to: center, limit: Self.maxClinics)
            searchFailed = false
        } catch {
            clinics = []
            searchFailed = true
        }
    }

    /// Mesafeyi hesaplar, sıralar ve sınırlar.
    public static func nearest(_ clinics: [VetClinic], to center: Coordinate, limit: Int) -> [VetClinic] {
        clinics
            .map { clinic -> VetClinic in
                var copy = clinic
                copy.distanceMeters = GeoMath.distance(center, clinic.coordinate)
                return copy
            }
            .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
            .prefix(limit)
            .map { $0 }
    }

    /// Arama sonuç vermezse Haritalar'da "veteriner" araması.
    public static func mapsSearchURL(near center: Coordinate) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "veteriner"),
            URLQueryItem(name: "sll", value: "\(center.latitude),\(center.longitude)"),
        ]
        return components?.url
    }

    /// "+90 (216) 555 01 02" → `tel:+902165550102`. Geçersizse `nil`.
    public static func telURL(_ phone: String?) -> URL? {
        guard let phone else { return nil }
        let allowed = Set("+0123456789")
        let digits = String(phone.filter { allowed.contains($0) })
        guard digits.filter(\.isNumber).count >= 3 else { return nil }
        return URL(string: "tel:\(digits)")
    }
}
