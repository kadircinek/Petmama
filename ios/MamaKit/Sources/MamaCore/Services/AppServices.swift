import Foundation

/// Bu derlemenin APNs ortamı (`aps-environment` entitlement'ı). Sunucu her token'ı kendi ortamına gönderir.
public enum APNsEnvironment: String, Hashable, Sendable {
    /// Xcode'dan kurulan Debug derlemeleri.
    case sandbox
    /// TestFlight ve App Store.
    case production
}

/// Uygulama yapılandırması (Info.plist / xcconfig'den okunur).
public struct AppConfig: Hashable, Sendable {
    public var isDemo: Bool
    public var donation: DonationConfig
    /// Uygulama içi ve App Store sayfasında görünen iletişim (PRD 9.2).
    public var supportEmail: String
    public var privacyPolicyURL: URL?
    public var termsURL: URL?
    public var kvkkNoticeURL: URL?
    public var apnsEnvironment: APNsEnvironment

    public init(
        isDemo: Bool,
        donation: DonationConfig = .placeholder,
        supportEmail: String = "destek@mamaharitasi.app",
        privacyPolicyURL: URL? = nil,
        termsURL: URL? = nil,
        kvkkNoticeURL: URL? = nil,
        apnsEnvironment: APNsEnvironment = .production
    ) {
        self.isDemo = isDemo
        self.donation = donation
        self.supportEmail = supportEmail
        self.privacyPolicyURL = privacyPolicyURL
        self.termsURL = termsURL
        self.kvkkNoticeURL = kvkkNoticeURL
        self.apnsEnvironment = apnsEnvironment
    }
}

/// Bağımlılık kabı. ViewModel'ler bunu init'te alır; SwiftUI ortamına da konur.
public struct AppServices: Sendable {
    public var auth: any AuthRepository
    public var spots: any SpotRepository
    public var checkIns: any CheckInRepository
    public var animals: any AnimalRepository
    public var needs: any NeedRepository
    public var profiles: any ProfileRepository
    public var notifications: any NotificationRepository
    public var moderation: any ModerationRepository
    public var donations: any DonationRepository
    public var community: any CommunityRepository
    public var media: any MediaUploader
    public var spotCache: any SpotCache
    public var checkInQueue: OfflineCheckInQueue
    public var config: AppConfig
    public var now: @Sendable () -> Date

    public init(
        auth: any AuthRepository,
        spots: any SpotRepository,
        checkIns: any CheckInRepository,
        animals: any AnimalRepository,
        needs: any NeedRepository,
        profiles: any ProfileRepository,
        notifications: any NotificationRepository,
        moderation: any ModerationRepository,
        donations: any DonationRepository,
        community: any CommunityRepository,
        media: any MediaUploader,
        spotCache: any SpotCache,
        checkInQueue: OfflineCheckInQueue,
        config: AppConfig,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.auth = auth
        self.spots = spots
        self.checkIns = checkIns
        self.animals = animals
        self.needs = needs
        self.profiles = profiles
        self.notifications = notifications
        self.moderation = moderation
        self.donations = donations
        self.community = community
        self.media = media
        self.spotCache = spotCache
        self.checkInQueue = checkInQueue
        self.config = config
        self.now = now
    }

    /// Kadıköy demo verisiyle bellek içi servisler (D7). `signedIn` true ise demo kullanıcıyla oturum açık başlar.
    public static func demo(signedIn: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) -> AppServices {
        let backend = InMemoryBackend(seed: DemoData.make(now: now()), signedIn: signedIn, now: now)
        return AppServices.inMemory(backend, now: now)
    }

    public static func inMemory(_ backend: InMemoryBackend, config: AppConfig? = nil, now: @escaping @Sendable () -> Date = { Date() }) -> AppServices {
        let queue = OfflineCheckInQueue(store: InMemoryPendingCheckInStore(), repository: backend)
        return AppServices(
            auth: backend,
            spots: backend,
            checkIns: queue,
            animals: backend,
            needs: backend,
            profiles: backend,
            notifications: backend,
            moderation: backend,
            donations: backend,
            community: backend,
            media: backend,
            spotCache: InMemorySpotCache(),
            checkInQueue: queue,
            config: config ?? AppConfig(
                isDemo: true,
                donation: DonationConfig(
                    partnerName: "Ortak dernek (demo)",
                    donationURL: URL(string: "https://example.org/bagis"),
                    usdToTry: 41.5
                )
            ),
            now: now
        )
    }
}
