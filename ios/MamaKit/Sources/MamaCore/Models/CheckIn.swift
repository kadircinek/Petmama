import Foundation

/// Check-in türü (FR-C1…C3).
public enum CheckInKind: String, Codable, CaseIterable, Sendable, Hashable {
    /// "Mama koydum"
    case fed
    /// "Su koydum"
    case water
    /// "Mama gerekli": mama bitti
    case needFood = "need_food"
    /// "Mama gerekli": su bitti
    case needWater = "need_water"
    /// "Mama gerekli": kap kirli veya kırık
    case broken

    /// Bu tür bir "gerekli" bildirimi mi (turuncu akış)?
    public var isRequest: Bool {
        switch self {
        case .fed, .water: return false
        case .needFood, .needWater, .broken: return true
        }
    }

    /// Sahte check-in'i önleyen azami mesafe (FR-C2: 100 m, FR-C3: 300 m).
    public var maxDistanceMeters: Double {
        isRequest ? CheckInPolicy.requestMaxDistance : CheckInPolicy.feedMaxDistance
    }

    /// "Mama gerekli" akışında seçilebilen tipler (FR-C3).
    public static let requestKinds: [CheckInKind] = [.needFood, .needWater, .broken]
}

/// Kaba miktar seçimi, isteğe bağlı (FR-C2).
public enum FoodAmount: String, Codable, CaseIterable, Sendable, Hashable {
    case low, medium, full
}

public struct CheckIn: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var spotId: UUID
    public var userId: UUID?
    public var kind: CheckInKind
    public var amount: FoodAmount?
    public var photoURL: URL?
    public var userDistanceMeters: Double?
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        spotId: UUID,
        userId: UUID?,
        kind: CheckInKind,
        amount: FoodAmount? = nil,
        photoURL: URL? = nil,
        userDistanceMeters: Double? = nil,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.spotId = spotId
        self.userId = userId
        self.kind = kind
        self.amount = amount
        self.photoURL = photoURL
        self.userDistanceMeters = userDistanceMeters
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

/// İstemcinin gönderdiği check-in. Çevrimdışıyken kuyruğa bu haliyle girer (FR-H8).
public struct CheckInDraft: Identifiable, Hashable, Codable, Sendable {
    /// İstemci tarafı kimlik. Kuyruktan tekrar gönderimlerde çift kaydı önlemek için.
    public let id: UUID
    public var spotId: UUID
    public var kind: CheckInKind
    public var amount: FoodAmount?
    public var photoURL: URL?
    /// Yalnızca sunucuda mesafe hesabı için gönderilir; sunucu saklamaz (PRD 9.5).
    public var userCoordinate: Coordinate
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        spotId: UUID,
        kind: CheckInKind,
        amount: FoodAmount? = nil,
        photoURL: URL? = nil,
        userCoordinate: Coordinate,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.spotId = spotId
        self.kind = kind
        self.amount = amount
        self.photoURL = photoURL
        self.userCoordinate = userCoordinate
        self.createdAt = createdAt
    }
}

public struct CheckInReceipt: Hashable, Codable, Sendable {
    public var checkInId: UUID
    public var distanceMeters: Double
    public var closedNeedCount: Int
    public var spotStatus: SpotStatus

    public init(checkInId: UUID, distanceMeters: Double, closedNeedCount: Int, spotStatus: SpotStatus) {
        self.checkInId = checkInId
        self.distanceMeters = distanceMeters
        self.closedNeedCount = closedNeedCount
        self.spotStatus = spotStatus
    }
}

public enum CheckInOutcome: Hashable, Sendable {
    case success(CheckInReceipt)
    case tooFar(distanceMeters: Double, maxDistanceMeters: Double)
    case spotInactive
    case rateLimited
    /// Bağlantı yok; check-in kuyruğa alındı, bağlantı gelince gönderilecek (FR-H8).
    case queuedOffline
}
