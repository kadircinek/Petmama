import Foundation

/// İhtiyaç tipleri (FR-I1).
public enum NeedType: String, Codable, CaseIterable, Sendable, Hashable {
    case vet
    case neuter
    case vaccine
    case meds
    case shelter
    case water
    case adoption
    case lostFound = "lost_found"
}

public enum NeedUrgency: String, Codable, CaseIterable, Sendable, Hashable {
    case normal, urgent
}

/// açık → üstlenildi → çözüldü (FR-I2).
public enum NeedStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case open, claimed, resolved
}

public struct Need: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var type: NeedType
    public var urgency: NeedUrgency
    public var status: NeedStatus
    public var description: String
    public var photoURLs: [URL]
    public var spotId: UUID?
    public var spotTitle: String?
    public var animalId: UUID?
    public var animalName: String?
    public var animalPhotoURL: URL?
    public var coordinate: Coordinate?
    public var isLocationExact: Bool
    public var distanceMeters: Double?
    public var createdBy: UUID?
    public var claimedBy: UUID?
    public var claimedByName: String?
    public var createdAt: Date
    public var claimedAt: Date?
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        type: NeedType,
        urgency: NeedUrgency = .normal,
        status: NeedStatus = .open,
        description: String,
        photoURLs: [URL] = [],
        spotId: UUID? = nil,
        spotTitle: String? = nil,
        animalId: UUID? = nil,
        animalName: String? = nil,
        animalPhotoURL: URL? = nil,
        coordinate: Coordinate? = nil,
        isLocationExact: Bool = true,
        distanceMeters: Double? = nil,
        createdBy: UUID? = nil,
        claimedBy: UUID? = nil,
        claimedByName: String? = nil,
        createdAt: Date = Date(),
        claimedAt: Date? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.urgency = urgency
        self.status = status
        self.description = description
        self.photoURLs = photoURLs
        self.spotId = spotId
        self.spotTitle = spotTitle
        self.animalId = animalId
        self.animalName = animalName
        self.animalPhotoURL = animalPhotoURL
        self.coordinate = coordinate
        self.isLocationExact = isLocationExact
        self.distanceMeters = distanceMeters
        self.createdBy = createdBy
        self.claimedBy = claimedBy
        self.claimedByName = claimedByName
        self.createdAt = createdAt
        self.claimedAt = claimedAt
        self.resolvedAt = resolvedAt
    }

    public var isUrgent: Bool { urgency == .urgent && status != .resolved }

    /// Yaralı veya hasta hayvan fotoğrafı içerebilir; varsayılan olarak bulanık gösterilir (PRD 9.2).
    public var mayContainSensitiveImagery: Bool { type == .vet || type == .meds }

    public func withDistance(from origin: Coordinate?) -> Need {
        var copy = self
        if let origin, let coordinate { copy.distanceMeters = GeoMath.distance(origin, coordinate) }
        return copy
    }
}

public struct NeedDraft: Hashable, Codable, Sendable {
    public var spotId: UUID?
    public var animalId: UUID?
    public var type: NeedType
    public var urgency: NeedUrgency
    public var description: String
    public var photoURLs: [URL]

    public init(
        spotId: UUID? = nil,
        animalId: UUID? = nil,
        type: NeedType = .vet,
        urgency: NeedUrgency = .normal,
        description: String = "",
        photoURLs: [URL] = []
    ) {
        self.spotId = spotId
        self.animalId = animalId
        self.type = type
        self.urgency = urgency
        self.description = description
        self.photoURLs = photoURLs
    }

    public var isValid: Bool {
        (spotId != nil || animalId != nil) && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ClaimOutcome: String, Hashable, Sendable {
    case ok
    case alreadyClaimed = "already_claimed"
    case resolved
}
