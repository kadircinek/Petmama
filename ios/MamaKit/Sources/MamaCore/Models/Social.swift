import Foundation

// Tanışma: buluşmalar, Hayvanseverler ve sohbet (docs/superpowers/specs/2026-11-14-tanisma-design.md).
// Sunucu karşılıkları: supabase/migrations/20261114000018…24.

// MARK: - Sabitler

/// Sabit ilgi etiketleri (`public.social_interest`).
public enum SocialInterest: String, Codable, CaseIterable, Sendable, Hashable {
    case cats, dogs, birds, neutering, fostering
    case vetTransport = "vet_transport"
    case foodDonation = "food_donation"
    case photography
}

/// Hayvanseverler listesinde mesafe bandı; kesin mesafe asla gösterilmez.
public enum DistanceBand: String, Codable, Sendable, Hashable {
    case under1km = "under_1km"
    case from1to3km = "1_3km"
    case from3to10km = "3_10km"
}

// MARK: - Buluşmalar

public enum MeetupStatus: String, Codable, Sendable {
    case active, cancelled
}

/// İzleyicinin buluşmadaki rolü.
public enum MeetupViewerRole: String, Codable, Sendable {
    case organizer, participant, removed, none
}

public struct Meetup: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var description: String
    public var startsAt: Date
    public var endsAt: Date
    public var placeName: String
    public var coordinate: Coordinate
    /// Nokta izleyene görünür değilse `spotId` ve `spotTitle` boş.
    public var spotId: UUID?
    public var spotTitle: String?
    public var capacity: Int?
    /// Düzenleyen dahil katılanlar.
    public var participantCount: Int
    public var status: MeetupStatus
    public var organizerId: UUID
    public var organizerName: String
    public var organizerAvatarURL: URL?
    public var organizerIsVerified: Bool
    public var viewerRole: MeetupViewerRole
    /// Yalnızca düzenleyen ve katılımcılar için dolu.
    public var conversationId: UUID?
    /// İzleyicinin verdiği konumdan; konum verilmediyse boş.
    public var distanceMeters: Double?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        startsAt: Date,
        endsAt: Date,
        placeName: String,
        coordinate: Coordinate,
        spotId: UUID? = nil,
        spotTitle: String? = nil,
        capacity: Int? = nil,
        participantCount: Int = 1,
        status: MeetupStatus = .active,
        organizerId: UUID,
        organizerName: String,
        organizerAvatarURL: URL? = nil,
        organizerIsVerified: Bool = false,
        viewerRole: MeetupViewerRole = .none,
        conversationId: UUID? = nil,
        distanceMeters: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.placeName = placeName
        self.coordinate = coordinate
        self.spotId = spotId
        self.spotTitle = spotTitle
        self.capacity = capacity
        self.participantCount = participantCount
        self.status = status
        self.organizerId = organizerId
        self.organizerName = organizerName
        self.organizerAvatarURL = organizerAvatarURL
        self.organizerIsVerified = organizerIsVerified
        self.viewerRole = viewerRole
        self.conversationId = conversationId
        self.distanceMeters = distanceMeters
        self.createdAt = createdAt
    }

    /// Kişi sınırı doldu mu?
    public var isFull: Bool {
        capacity.map { participantCount >= $0 } ?? false
    }
}

public struct MeetupDraft: Hashable, Sendable {
    public var title: String
    public var description: String
    public var startsAt: Date
    public var durationMinutes: Int
    public var placeName: String
    public var coordinate: Coordinate
    public var spotId: UUID?
    public var capacity: Int?

    public init(
        title: String,
        description: String = "",
        startsAt: Date,
        durationMinutes: Int = 120,
        placeName: String,
        coordinate: Coordinate,
        spotId: UUID? = nil,
        capacity: Int? = nil
    ) {
        self.title = title
        self.description = description
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.placeName = placeName
        self.coordinate = coordinate
        self.spotId = spotId
        self.capacity = capacity
    }
}

public struct MeetupParticipant: Identifiable, Hashable, Sendable {
    /// Kullanıcı kimliği.
    public let id: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var isVerifiedFeeder: Bool
    public var isOrganizer: Bool

    public init(id: UUID, displayName: String, avatarURL: URL? = nil, isVerifiedFeeder: Bool = false, isOrganizer: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isVerifiedFeeder = isVerifiedFeeder
        self.isOrganizer = isOrganizer
    }
}

/// `create_meetup` → `{status:'invalid', reason}`.
public enum MeetupInvalidReason: String, Sendable {
    case titleLength = "title_length"
    case descriptionTooLong = "description_too_long"
    case placeNameLength = "place_name_length"
    case startTooSoon = "start_too_soon"
    case startTooLate = "start_too_late"
    case durationRange = "duration_range"
    case capacityRange = "capacity_range"
    case spotNotFound = "spot_not_found"
}

public enum CreateMeetupOutcome: Equatable, Sendable {
    case created(meetupId: UUID, conversationId: UUID)
    case consentRequired
    case rejectedContent
    case limitReached(Int)
    case invalid(MeetupInvalidReason)
}

public enum JoinMeetupOutcome: Equatable, Sendable {
    case joined(conversationId: UUID)
    case full
    /// Düzenleyen çıkardı; tekrar katılamaz.
    case removed
    case cancelled
    case ended
    case consentRequired
    case notFound
}

// MARK: - Sosyal profil

public struct SocialProfile: Hashable, Sendable {
    public var isVisible: Bool
    public var about: String
    public var interests: [SocialInterest]
    /// 18+ ve koşullar onayı verildi mi?
    public var hasConsented: Bool

    public init(isVisible: Bool = false, about: String = "", interests: [SocialInterest] = [], hasConsented: Bool = false) {
        self.isVisible = isVisible
        self.about = about
        self.interests = interests
        self.hasConsented = hasConsented
    }
}

public enum SocialProfileOutcome: Equatable, Sendable {
    case saved
    case consentRequired
    case rejectedContent
    case aboutTooLong
    /// Görünür olmak için kaba konum gerekir.
    case locationRequired
}

// MARK: - Hayvanseverler ve bağlantılar

public enum ConnectionState: Hashable, Sendable {
    case none
    case outgoingPending(requestId: UUID)
    case incomingPending(requestId: UUID)
    case connected(conversationId: UUID)
}

public struct AnimalLover: Identifiable, Hashable, Sendable {
    /// Kullanıcı kimliği.
    public let id: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var about: String
    public var interests: [SocialInterest]
    public var isVerifiedFeeder: Bool
    /// Son 30 günde "mama koydum" sayısı.
    public var fedLast30Days: Int
    public var distanceBand: DistanceBand
    public var sharedInterestCount: Int
    public var connection: ConnectionState

    public init(
        id: UUID,
        displayName: String,
        avatarURL: URL? = nil,
        about: String = "",
        interests: [SocialInterest] = [],
        isVerifiedFeeder: Bool = false,
        fedLast30Days: Int = 0,
        distanceBand: DistanceBand,
        sharedInterestCount: Int = 0,
        connection: ConnectionState = .none
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.about = about
        self.interests = interests
        self.isVerifiedFeeder = isVerifiedFeeder
        self.fedLast30Days = fedLast30Days
        self.distanceBand = distanceBand
        self.sharedInterestCount = sharedInterestCount
        self.connection = connection
    }
}

/// Bana gelen bekleyen bağlantı isteği.
public struct ConnectionRequest: Identifiable, Hashable, Sendable {
    /// İstek kimliği.
    public let id: UUID
    /// Gönderen.
    public var userId: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var about: String
    public var interests: [SocialInterest]
    public var isVerifiedFeeder: Bool
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID,
        userId: UUID,
        displayName: String,
        avatarURL: URL? = nil,
        about: String = "",
        interests: [SocialInterest] = [],
        isVerifiedFeeder: Bool = false,
        note: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.about = about
        self.interests = interests
        self.isVerifiedFeeder = isVerifiedFeeder
        self.note = note
        self.createdAt = createdAt
    }
}

public enum SendRequestOutcome: Equatable, Sendable {
    case sent(requestId: UUID)
    /// Karşı taraf zaten istek atmıştı: bağlantı kuruldu.
    case autoAccepted(conversationId: UUID)
    case consentRequired
    /// Ben ya da karşı taraf görünür değil.
    case notVisible
    case alreadyConnected
    case alreadyPending
    /// Reddedilen istekten sonra 30 gün bekleme.
    case cooldown
    case rejectedContent
    case limitReached(Int)
    case noteTooLong
    case notFound
}

// MARK: - Sohbet

public enum ConversationKind: String, Codable, Sendable {
    case meetup, direct
}

public struct ConversationSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kind: ConversationKind
    /// Buluşma başlığı ya da karşı tarafın adı; hesabı silinmişse "Silinmiş kullanıcı".
    public var title: String
    public var meetupId: UUID?
    public var otherUserId: UUID?
    public var otherAvatarURL: URL?
    public var lastBody: String?
    public var lastAt: Date?
    public var unreadCount: Int
    public var isReadOnly: Bool

    public init(
        id: UUID,
        kind: ConversationKind,
        title: String,
        meetupId: UUID? = nil,
        otherUserId: UUID? = nil,
        otherAvatarURL: URL? = nil,
        lastBody: String? = nil,
        lastAt: Date? = nil,
        unreadCount: Int = 0,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.meetupId = meetupId
        self.otherUserId = otherUserId
        self.otherAvatarURL = otherAvatarURL
        self.lastBody = lastBody
        self.lastAt = lastAt
        self.unreadCount = unreadCount
        self.isReadOnly = isReadOnly
    }
}

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var authorId: UUID
    public var authorName: String
    public var authorAvatarURL: URL?
    public var body: String
    public var createdAt: Date
    /// 3 farklı rapor sonrası incelemede: yalnızca yazarı görür.
    public var isPendingModeration: Bool

    public init(
        id: UUID = UUID(),
        authorId: UUID,
        authorName: String,
        authorAvatarURL: URL? = nil,
        body: String,
        createdAt: Date,
        isPendingModeration: Bool = false
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.body = body
        self.createdAt = createdAt
        self.isPendingModeration = isPendingModeration
    }
}

public enum SendMessageOutcome: Equatable, Sendable {
    case sent(ChatMessage)
    case notMember
    case readOnly
    case rejectedContent
    case rateLimited
    case bodyEmpty
    case bodyTooLong
}
