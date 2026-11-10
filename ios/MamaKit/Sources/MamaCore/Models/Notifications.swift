import Foundation

public enum NotificationKind: String, Codable, CaseIterable, Sendable, Hashable {
    case needFoodNearby = "need_food_nearby"
    case followedSpotChanged = "followed_spot_changed"
    case guardianSpotUnfed = "guardian_spot_unfed"
    case needResolved = "need_resolved"
    case thanksFed = "thanks_fed"
    case donationDelivered = "donation_delivered"
    /// Paylaşımına yorum geldi (Mahalle).
    case communityComment = "community_comment"
    /// "Yerime bakar mısın?" isteğine biri "Ben bakarım" dedi.
    case coverVolunteered = "cover_volunteered"
}

public struct AppNotification: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: NotificationKind
    public var title: String
    public var body: String
    public var spotId: UUID?
    public var needId: UUID?
    public var postId: UUID?
    public var readAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: NotificationKind,
        title: String,
        body: String,
        spotId: UUID? = nil,
        needId: UUID? = nil,
        postId: UUID? = nil,
        readAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.spotId = spotId
        self.needId = needId
        self.postId = postId
        self.readAt = readAt
        self.createdAt = createdAt
    }

    public var isRead: Bool { readAt != nil }
}

/// Ayarlar ekranındaki bildirim tercihleri (PRD 5.7, ekran 23).
public struct NotificationPreferences: Hashable, Codable, Sendable {
    /// Yakındaki "mama gerekli" yarıçapı. Varsayılan 1 km (FR-C4).
    public var radiusMeters: Int
    public var quietStartHour: Int
    public var quietEndHour: Int
    public var needFoodNearby: Bool
    public var followedUpdates: Bool
    public var guardianAlerts: Bool
    /// Mahalle: paylaşımına yorum, "Ben bakarım" bildirimleri.
    public var communityUpdates: Bool

    public init(
        radiusMeters: Int = 1000,
        quietStartHour: Int = NotificationPolicy.defaultQuietStartHour,
        quietEndHour: Int = NotificationPolicy.defaultQuietEndHour,
        needFoodNearby: Bool = true,
        followedUpdates: Bool = true,
        guardianAlerts: Bool = true,
        communityUpdates: Bool = true
    ) {
        self.radiusMeters = radiusMeters
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
        self.needFoodNearby = needFoodNearby
        self.followedUpdates = followedUpdates
        self.guardianAlerts = guardianAlerts
        self.communityUpdates = communityUpdates
    }

    public static let `default` = NotificationPreferences()

    /// Ayarlardaki yarıçap seçenekleri.
    public static let radiusOptions: [Int] = [500, 1000, 2000, 5000]
}
