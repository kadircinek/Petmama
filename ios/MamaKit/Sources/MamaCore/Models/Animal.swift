import Foundation

public enum AnimalSpecies: String, Codable, CaseIterable, Sendable, Hashable {
    case cat, dog
}

public enum AnimalSex: String, Codable, CaseIterable, Sendable, Hashable {
    case female, male, unknown
}

public enum AgeEstimate: String, Codable, CaseIterable, Sendable, Hashable {
    case baby, young, adult, senior, unknown
}

/// Karakter etiketleri (FR-A1).
public enum TemperamentTag: String, Codable, CaseIterable, Sendable, Hashable {
    case friendly
    case shy
    case mayBeAggressive = "may_be_aggressive"
    case goodWithKids = "good_with_kids"
    case energetic
    case calm
}

/// Hem kullanıcı hem hayvan güvenliği için uyarı (FR-A4).
public enum AnimalWarning: String, Codable, CaseIterable, Sendable, Hashable {
    case doNotApproach = "do_not_approach"
    case skittish
    case mayBite = "may_bite"
}

public struct Animal: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var species: AnimalSpecies
    /// Mahallede verilen isim, ör. "Pamuk". İsteğe bağlı.
    public var name: String?
    public var colorPattern: String?
    public var sex: AnimalSex
    public var ageEstimate: AgeEstimate
    /// `nil` = bilinmiyor. Kulak küpesi veya kesiği kısırlık işaretidir.
    public var isNeutered: Bool?
    public var earTag: Bool
    public var vaccinationInfo: String?
    public var temperamentTags: [TemperamentTag]
    public var warning: AnimalWarning?
    public var about: String?
    public var photoURLs: [URL]
    public var lastSeenAt: Date?
    public var lastSeenSpotId: UUID?
    public var createdBy: UUID?
    public var createdAt: Date
    /// Belirli bir nokta bağlamında kaç kez görüldüğü (nokta detayında dolu).
    public var seenCount: Int?

    public init(
        id: UUID = UUID(),
        species: AnimalSpecies,
        name: String? = nil,
        colorPattern: String? = nil,
        sex: AnimalSex = .unknown,
        ageEstimate: AgeEstimate = .unknown,
        isNeutered: Bool? = nil,
        earTag: Bool = false,
        vaccinationInfo: String? = nil,
        temperamentTags: [TemperamentTag] = [],
        warning: AnimalWarning? = nil,
        about: String? = nil,
        photoURLs: [URL] = [],
        lastSeenAt: Date? = nil,
        lastSeenSpotId: UUID? = nil,
        createdBy: UUID? = nil,
        createdAt: Date = Date(),
        seenCount: Int? = nil
    ) {
        self.id = id
        self.species = species
        self.name = name
        self.colorPattern = colorPattern
        self.sex = sex
        self.ageEstimate = ageEstimate
        self.isNeutered = isNeutered
        self.earTag = earTag
        self.vaccinationInfo = vaccinationInfo
        self.temperamentTags = temperamentTags
        self.warning = warning
        self.about = about
        self.photoURLs = photoURLs
        self.lastSeenAt = lastSeenAt
        self.lastSeenSpotId = lastSeenSpotId
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.seenCount = seenCount
    }

    /// İsim yoksa gösterilecek etiket, ör. "Tekir kedi".
    public var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let colorPattern, !colorPattern.isEmpty { return colorPattern }
        return species == .cat ? "İsimsiz kedi" : "İsimsiz köpek"
    }
}

public struct AnimalDraft: Hashable, Codable, Sendable {
    public var species: AnimalSpecies
    public var name: String?
    public var colorPattern: String?
    public var sex: AnimalSex
    public var ageEstimate: AgeEstimate
    public var isNeutered: Bool?
    public var earTag: Bool
    public var vaccinationInfo: String?
    public var temperamentTags: [TemperamentTag]
    public var warning: AnimalWarning?
    public var about: String?
    public var photoURLs: [URL]
    /// Hayvanın ilk görüldüğü nokta (FR-A2).
    public var spotId: UUID?

    public init(
        species: AnimalSpecies = .cat,
        name: String? = nil,
        colorPattern: String? = nil,
        sex: AnimalSex = .unknown,
        ageEstimate: AgeEstimate = .unknown,
        isNeutered: Bool? = nil,
        earTag: Bool = false,
        vaccinationInfo: String? = nil,
        temperamentTags: [TemperamentTag] = [],
        warning: AnimalWarning? = nil,
        about: String? = nil,
        photoURLs: [URL] = [],
        spotId: UUID? = nil
    ) {
        self.species = species
        self.name = name
        self.colorPattern = colorPattern
        self.sex = sex
        self.ageEstimate = ageEstimate
        self.isNeutered = isNeutered
        self.earTag = earTag
        self.vaccinationInfo = vaccinationInfo
        self.temperamentTags = temperamentTags
        self.warning = warning
        self.about = about
        self.photoURLs = photoURLs
        self.spotId = spotId
    }
}
