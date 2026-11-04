import Foundation

/// Bir besleme noktasının tipi (FR-N1).
public enum SpotType: String, Codable, CaseIterable, Sendable, Hashable {
    case food, water, shelter, mixed
}

/// Noktada beslenen tür. `both` hem kedi hem köpek.
public enum SpotSpecies: String, Codable, CaseIterable, Sendable, Hashable {
    case cat, dog, both

    public func matches(_ species: AnimalSpecies) -> Bool {
        switch self {
        case .both: return true
        case .cat: return species == .cat
        case .dog: return species == .dog
        }
    }
}

/// Pin rengini belirleyen durum (FR-H3, 7.5). Sunucuda hesaplanır, istemci çevrimdışıyken eskitir.
public enum SpotStatus: String, Codable, CaseIterable, Sendable, Hashable {
    /// Yeşil: son 12 saatte mama kondu.
    case fedRecent = "fed_recent"
    /// Sarı: 12–24 saat önce.
    case fedStale = "fed_stale"
    /// Gri: 24 saat+ veya bilinmiyor.
    case unknown
    /// Turuncu: açık "mama gerekli" bildirimi var.
    case needsFood = "needs_food"
}

/// Konum hassasiyeti seviyesi (PRD 9.1). Ayrıntı: docs/backend-contract.md.
public enum SpotVisibility: String, Codable, CaseIterable, Sendable, Hashable {
    case `public`, fuzzed, `private`
}

public enum ModerationState: String, Codable, Sendable, Hashable {
    case approved, pending, rejected
}

public struct Spot: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var coordinate: Coordinate
    /// `false` ise konum 50–100 m bulanıklaştırılmıştır.
    public var isLocationExact: Bool
    public var type: SpotType
    public var species: SpotSpecies
    public var title: String
    public var note: String?
    public var photoURL: URL?
    public var status: SpotStatus
    public var lastFedAt: Date?
    /// Kırmızı halka: noktada veya noktadaki bir hayvanda acil ihtiyaç var.
    public var hasUrgentNeed: Bool
    public var openNeedCount: Int
    public var visibility: SpotVisibility
    public var isActive: Bool
    public var createdBy: UUID?
    public var createdAt: Date
    public var animalCount: Int
    public var guardianCount: Int
    /// Sorgudaki referans noktaya uzaklık (metre). Bilinmiyorsa `nil`.
    public var distanceMeters: Double?

    public init(
        id: UUID = UUID(),
        coordinate: Coordinate,
        isLocationExact: Bool = true,
        type: SpotType,
        species: SpotSpecies,
        title: String,
        note: String? = nil,
        photoURL: URL? = nil,
        status: SpotStatus = .unknown,
        lastFedAt: Date? = nil,
        hasUrgentNeed: Bool = false,
        openNeedCount: Int = 0,
        visibility: SpotVisibility = .public,
        isActive: Bool = true,
        createdBy: UUID? = nil,
        createdAt: Date = Date(),
        animalCount: Int = 0,
        guardianCount: Int = 0,
        distanceMeters: Double? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.isLocationExact = isLocationExact
        self.type = type
        self.species = species
        self.title = title
        self.note = note
        self.photoURL = photoURL
        self.status = status
        self.lastFedAt = lastFedAt
        self.hasUrgentNeed = hasUrgentNeed
        self.openNeedCount = openNeedCount
        self.visibility = visibility
        self.isActive = isActive
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.animalCount = animalCount
        self.guardianCount = guardianCount
        self.distanceMeters = distanceMeters
    }

    /// Önbellekten gelen bir noktanın durumunu "şimdi"ye göre yeniden hesaplar (FR-N5, FR-H8).
    /// Açık "mama gerekli" durumu zamanla eskimez; yalnızca yeni bir "mama koydum" kapatır.
    public func currentStatus(now: Date = Date()) -> SpotStatus {
        SpotStatusRules.status(lastFedAt: lastFedAt, hasOpenFoodRequest: status == .needsFood, now: now)
    }

    /// Verilen konuma göre `distanceMeters` güncellenmiş kopya.
    public func withDistance(from origin: Coordinate?) -> Spot {
        var copy = self
        copy.distanceMeters = origin.map { GeoMath.distance($0, coordinate) }
        return copy
    }
}

/// Nokta ekleme akışının çıktısı (FR-N2).
public struct SpotDraft: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    public var type: SpotType
    public var species: SpotSpecies
    public var title: String
    public var note: String?
    public var photoURL: URL?
    public var visibility: SpotVisibility
    /// Mükerrer uyarısına rağmen ekle (FR-N3).
    public var force: Bool

    public init(
        coordinate: Coordinate,
        type: SpotType = .food,
        species: SpotSpecies = .cat,
        title: String = "",
        note: String? = nil,
        photoURL: URL? = nil,
        visibility: SpotVisibility = .public,
        force: Bool = false
    ) {
        self.coordinate = coordinate
        self.type = type
        self.species = species
        self.title = title
        self.note = note
        self.photoURL = photoURL
        self.visibility = visibility
        self.force = force
    }
}

public struct DuplicateCandidate: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var distanceMeters: Double

    public init(id: UUID, title: String, distanceMeters: Double) {
        self.id = id
        self.title = title
        self.distanceMeters = distanceMeters
    }
}

public enum CreateSpotOutcome: Hashable, Sendable {
    case created(id: UUID, pendingModeration: Bool)
    case duplicate([DuplicateCandidate])
    case limitReached(limit: Int)
    case rejectedContent
}

public struct GoneReportOutcome: Hashable, Sendable {
    public var reportCount: Int
    public var deactivated: Bool

    public init(reportCount: Int, deactivated: Bool) {
        self.reportCount = reportCount
        self.deactivated = deactivated
    }
}

/// Nokta detayındaki 7 günlük besleme çizelgesinin bir günü (FR-N4).
public struct FeedingDay: Hashable, Codable, Sendable, Identifiable {
    public var day: Date
    public var fedCount: Int
    public var needCount: Int
    public var lastFedAt: Date?

    public var id: Date { day }

    public init(day: Date, fedCount: Int, needCount: Int, lastFedAt: Date? = nil) {
        self.day = day
        self.fedCount = fedCount
        self.needCount = needCount
        self.lastFedAt = lastFedAt
    }
}

/// Ana sayfadaki "Bugün mahallende" kartı.
public struct NeighborhoodSummary: Hashable, Codable, Sendable {
    public var fedSpotsToday: Int
    public var openNeeds: Int
    public var needsFoodSpots: Int
    public var activeSpots7d: Int

    public init(fedSpotsToday: Int, openNeeds: Int, needsFoodSpots: Int, activeSpots7d: Int) {
        self.fedSpotsToday = fedSpotsToday
        self.openNeeds = openNeeds
        self.needsFoodSpots = needsFoodSpots
        self.activeSpots7d = activeSpots7d
    }

    public static let empty = NeighborhoodSummary(fedSpotsToday: 0, openNeeds: 0, needsFoodSpots: 0, activeSpots7d: 0)
}
