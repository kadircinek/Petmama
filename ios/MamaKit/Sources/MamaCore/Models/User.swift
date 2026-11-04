import Foundation

public struct UserProfile: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var neighborhood: String?
    public var trustScore: Int
    /// 30 günde 20+ konumu doğrulanmış check-in → otomatik (FR-P4).
    public var isVerifiedFeeder: Bool
    public var isModerator: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        avatarURL: URL? = nil,
        neighborhood: String? = nil,
        trustScore: Int = TrustPolicy.initialTrustScore,
        isVerifiedFeeder: Bool = false,
        isModerator: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.neighborhood = neighborhood
        self.trustScore = trustScore
        self.isVerifiedFeeder = isVerifiedFeeder
        self.isModerator = isModerator
        self.createdAt = createdAt
    }
}

/// Profil şeridi: beslediği nokta / check-in / kapatılan ihtiyaç (FR-P2).
public struct ProfileStats: Hashable, Codable, Sendable {
    public var fedSpotCount: Int
    public var checkInCount: Int
    public var resolvedNeedCount: Int
    public var verifiedCheckInsLast30Days: Int

    public init(fedSpotCount: Int, checkInCount: Int, resolvedNeedCount: Int, verifiedCheckInsLast30Days: Int) {
        self.fedSpotCount = fedSpotCount
        self.checkInCount = checkInCount
        self.resolvedNeedCount = resolvedNeedCount
        self.verifiedCheckInsLast30Days = verifiedCheckInsLast30Days
    }

    public static let zero = ProfileStats(fedSpotCount: 0, checkInCount: 0, resolvedNeedCount: 0, verifiedCheckInsLast30Days: 0)
}

/// ISO hafta günü (1 = Pazartesi … 7 = Pazar). Koruyucu takvimi için.
public enum Weekday: Int, Codable, CaseIterable, Sendable, Hashable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public var shortName: String {
        ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"][rawValue - 1]
    }
}

/// Noktayı sahiplenen kişi (FR-N4, PRD persona Ayşe).
public struct Guardian: Identifiable, Hashable, Codable, Sendable {
    public var userId: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var isVerifiedFeeder: Bool
    public var schedule: Set<Weekday>

    public var id: UUID { userId }

    public init(userId: UUID, displayName: String, avatarURL: URL? = nil, isVerifiedFeeder: Bool = false, schedule: Set<Weekday> = []) {
        self.userId = userId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isVerifiedFeeder = isVerifiedFeeder
        self.schedule = schedule
    }
}

public enum FollowTarget: String, Codable, Sendable, Hashable {
    case spot, animal
}
