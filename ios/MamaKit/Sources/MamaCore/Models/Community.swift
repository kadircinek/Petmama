import Foundation

// Mahalle (topluluk): besleyicilerin birbiriyle etkileşime girdiği sayfa (D17).
// Özel mesaj yok; her şey mahalleye açık, raporlanabilir ve engellenebilir.

/// Mahalle paylaşımının türü.
public enum CommunityPostKind: String, Codable, CaseIterable, Sendable, Hashable {
    /// Serbest paylaşım: "Pamuk bugün çok neşeliydi."
    case note
    /// Soru veya tavsiye isteği.
    case question
    /// "Yerime bakar mısın?": tatile çıkan besleyici noktasını emanet eder (PRD persona Ayşe).
    case coverRequest = "cover_request"
    /// Mama veya malzeme paylaşımı: "Elimde fazla mama var."
    case supply
    /// Mahalleye uyarı: "Bu sokakta şüpheli mama görüldü."
    case alert
}

public struct CommunityPost: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: CommunityPostKind
    public var body: String
    public var photoURL: URL?
    public var authorId: UUID
    public var authorName: String
    public var authorAvatarURL: URL?
    public var authorIsVerified: Bool
    /// Bağlı nokta. Nokta izleyene görünür değilse sunucu `nil` döner.
    public var spotId: UUID?
    public var spotTitle: String?
    public var animalId: UUID?
    public var animalName: String?
    /// "Yerime bakar mısın?" tarih aralığı (İstanbul günü, ikisi de dahil).
    public var coverFrom: Date?
    public var coverTo: Date?
    public var volunteerCount: Int
    public var viewerVolunteered: Bool
    public var pawCount: Int
    public var viewerPawed: Bool
    public var commentCount: Int
    /// İzleyicinin konumundan paylaşımın kaba konumuna (≈1 km hassasiyet).
    public var distanceMeters: Double?
    /// İnceleme bekliyor: yalnızca yazarına görünür.
    public var isPendingModeration: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: CommunityPostKind,
        body: String,
        photoURL: URL? = nil,
        authorId: UUID,
        authorName: String,
        authorAvatarURL: URL? = nil,
        authorIsVerified: Bool = false,
        spotId: UUID? = nil,
        spotTitle: String? = nil,
        animalId: UUID? = nil,
        animalName: String? = nil,
        coverFrom: Date? = nil,
        coverTo: Date? = nil,
        volunteerCount: Int = 0,
        viewerVolunteered: Bool = false,
        pawCount: Int = 0,
        viewerPawed: Bool = false,
        commentCount: Int = 0,
        distanceMeters: Double? = nil,
        isPendingModeration: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.body = body
        self.photoURL = photoURL
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.authorIsVerified = authorIsVerified
        self.spotId = spotId
        self.spotTitle = spotTitle
        self.animalId = animalId
        self.animalName = animalName
        self.coverFrom = coverFrom
        self.coverTo = coverTo
        self.volunteerCount = volunteerCount
        self.viewerVolunteered = viewerVolunteered
        self.pawCount = pawCount
        self.viewerPawed = viewerPawed
        self.commentCount = commentCount
        self.distanceMeters = distanceMeters
        self.isPendingModeration = isPendingModeration
        self.createdAt = createdAt
    }
}

public struct CommunityComment: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var postId: UUID
    public var body: String
    public var authorId: UUID
    public var authorName: String
    public var authorAvatarURL: URL?
    public var authorIsVerified: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        postId: UUID,
        body: String,
        authorId: UUID,
        authorName: String,
        authorAvatarURL: URL? = nil,
        authorIsVerified: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.body = body
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.authorIsVerified = authorIsVerified
        self.createdAt = createdAt
    }
}

/// "Ben bakarım" diyen gönüllü.
public struct CommunityVolunteer: Identifiable, Hashable, Codable, Sendable {
    public var userId: UUID
    public var displayName: String
    public var avatarURL: URL?
    public var isVerifiedFeeder: Bool

    public var id: UUID { userId }

    public init(userId: UUID, displayName: String, avatarURL: URL? = nil, isVerifiedFeeder: Bool = false) {
        self.userId = userId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isVerifiedFeeder = isVerifiedFeeder
    }
}

public struct CommunityPostDraft: Hashable, Codable, Sendable {
    public var kind: CommunityPostKind
    public var body: String
    public var photoURL: URL?
    public var spotId: UUID?
    public var animalId: UUID?
    /// Nokta bağlı değilse zorunlu. Sunucu yalnızca ≈1 km'ye yuvarlanmış halini saklar.
    public var coordinate: Coordinate?
    public var coverFrom: Date?
    public var coverTo: Date?

    public init(
        kind: CommunityPostKind = .note,
        body: String = "",
        photoURL: URL? = nil,
        spotId: UUID? = nil,
        animalId: UUID? = nil,
        coordinate: Coordinate? = nil,
        coverFrom: Date? = nil,
        coverTo: Date? = nil
    ) {
        self.kind = kind
        self.body = body
        self.photoURL = photoURL
        self.spotId = spotId
        self.animalId = animalId
        self.coordinate = coordinate
        self.coverFrom = coverFrom
        self.coverTo = coverTo
    }
}

/// Sunucunun `invalid` yanıtındaki `reason` değerleri; istemci ön kontrolü de aynılarını üretir.
public enum CommunityValidationError: String, Error, Hashable, Sendable {
    case bodyEmpty = "body_empty"
    case bodyTooLong = "body_too_long"
    case coverNeedsSpot = "cover_needs_spot"
    case coverDates = "cover_dates"
    case spotNotFound = "spot_not_found"
    /// İstemci tarafı: nokta bağlı değil ve konum yok.
    case locationMissing = "location_missing"

    public var userMessage: String {
        switch self {
        case .bodyEmpty: return "Birkaç kelime yazar mısın?"
        case .bodyTooLong: return "Metin biraz uzun oldu. En fazla \(CommunityPolicy.maxBodyLength) karakter olabilir."
        case .coverNeedsSpot: return "Hangi noktaya bakılacağını seçer misin?"
        case .coverDates: return "Tarihleri kontrol eder misin? En fazla \(CommunityPolicy.maxCoverDays) günlük bir aralık seçebilirsin."
        case .spotNotFound: return "Seçtiğin nokta artık görünmüyor."
        case .locationMissing: return "Mahalleni bulabilmemiz için konum izni gerekiyor ya da bir nokta seçebilirsin."
        }
    }
}

public enum CreatePostOutcome: Hashable, Sendable {
    case created(id: UUID, pendingModeration: Bool)
    case rejectedContent
    case limitReached(limit: Int)
    case invalid(CommunityValidationError)
}

public enum CommentOutcome: Hashable, Sendable {
    case created(id: UUID)
    case rejectedContent
    case limitReached(limit: Int)
    case invalid(CommunityValidationError)
    case postNotFound
}

public struct PawToggleResult: Hashable, Sendable {
    public var pawed: Bool
    public var pawCount: Int

    public init(pawed: Bool, pawCount: Int) {
        self.pawed = pawed
        self.pawCount = pawCount
    }
}

public enum CoverVolunteerOutcome: Hashable, Sendable {
    case ok(volunteered: Bool, volunteerCount: Int)
    case notCoverRequest
    case ownPost
    /// Tarih aralığı geçmişte kaldı.
    case closed
    case postNotFound
}

/// "Bu hafta mahallende" kartı. `fedSpotDays7d` ürünün kuzey yıldızı metriği: beslenmiş nokta-gün.
public struct CommunitySummary: Hashable, Codable, Sendable {
    public var fedSpotDays7d: Int
    public var activeFeeders7d: Int
    public var openCoverRequests: Int
    public var posts7d: Int

    public init(fedSpotDays7d: Int, activeFeeders7d: Int, openCoverRequests: Int, posts7d: Int) {
        self.fedSpotDays7d = fedSpotDays7d
        self.activeFeeders7d = activeFeeders7d
        self.openCoverRequests = openCoverRequests
        self.posts7d = posts7d
    }

    public static let empty = CommunitySummary(fedSpotDays7d: 0, activeFeeders7d: 0, openCoverRequests: 0, posts7d: 0)
}

/// Mahalle kuralları. Sunucudaki karşılıkları: docs/backend-contract.md → Mahalle → Kurallar.
public enum CommunityPolicy {
    public static let maxBodyLength = 600
    public static let maxCommentLength = 300
    public static let dailyPostLimit = 10
    public static let dailyCommentLimit = 60
    public static let maxCoverDays = 30
    public static let feedRadiusMeters = 3000
    public static let pageSize = 30
    /// Bu kadar farklı kullanıcı raporlarsa içerik incelemeye alınır.
    public static let reportsToAutoHide = 3

    static var istanbulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        return calendar
    }

    /// Gönderimden önce dostça uyarı için ön kontrol; asıl karar sunucuda.
    public static func validate(_ draft: CommunityPostDraft, now: Date) -> CommunityValidationError? {
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return .bodyEmpty }
        if body.count > maxBodyLength { return .bodyTooLong }
        if draft.kind == .coverRequest {
            guard draft.spotId != nil else { return .coverNeedsSpot }
            guard let from = draft.coverFrom, let to = draft.coverTo else { return .coverDates }
            let calendar = istanbulCalendar
            let today = calendar.startOfDay(for: now)
            let fromDay = calendar.startOfDay(for: from)
            let toDay = calendar.startOfDay(for: to)
            guard fromDay >= today, toDay >= fromDay else { return .coverDates }
            let span = calendar.dateComponents([.day], from: fromDay, to: toDay).day ?? 0
            if span > maxCoverDays { return .coverDates }
        } else if draft.spotId == nil, draft.coordinate == nil {
            return .locationMissing
        }
        return nil
    }

    public static func validateComment(_ text: String) -> CommunityValidationError? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return .bodyEmpty }
        if body.count > maxCommentLength { return .bodyTooLong }
        return nil
    }

    /// "Yerime bakar mısın?" isteği hâlâ gönüllü kabul ediyor mu? (bitiş günü dahil)
    public static func isCoverOpen(_ post: CommunityPost, now: Date) -> Bool {
        guard post.kind == .coverRequest, let to = post.coverTo else { return false }
        let calendar = istanbulCalendar
        return calendar.startOfDay(for: to) >= calendar.startOfDay(for: now)
    }

    /// Paylaşımın kaba konumu: 2 ondalığa yuvarlanır (≈1,1 km).
    public static func cell(for coordinate: Coordinate) -> Coordinate {
        Coordinate(
            latitude: (coordinate.latitude * 100).rounded() / 100,
            longitude: (coordinate.longitude * 100).rounded() / 100
        )
    }
}
