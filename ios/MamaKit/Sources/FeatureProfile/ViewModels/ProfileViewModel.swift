import Foundation
import Observation
import MamaCore

/// Profil sekmesi (ekran 20, FR-P2/P4): istatistik şeridi, doğrulanmış besleyici ilerlemesi, rozetler.
@MainActor
@Observable
public final class ProfileViewModel {
    public struct Stat: Identifiable, Hashable, Sendable {
        public let value: String
        public let label: String
        public var id: String { label }
    }

    /// v1.1 rozetleri (D13): MVP'de kilitli ve "yakında" olarak gösterilir.
    public struct Badge: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let systemImage: String
        public let detail: String
    }

    public static let upcomingBadges: [Badge] = [
        Badge(id: "first_feed", title: "İlk mama", systemImage: "pawprint.fill", detail: "İlk \"Mama koydum\"un"),
        Badge(id: "streak_7", title: "7 gün seri", systemImage: "flame.fill", detail: "7 gün üst üste besleme"),
        Badge(id: "winter_hero", title: "Kış kahramanı", systemImage: "snowflake", detail: "Soğuk günlerde düzenli besleme"),
        Badge(id: "need_solver", title: "İhtiyaç çözücü", systemImage: "hands.sparkles.fill", detail: "İhtiyaç kapatmaya yardım"),
        Badge(id: "neighborhood_guardian", title: "Mahalle koruyucusu", systemImage: "shield.lefthalf.filled", detail: "Noktalarına düzenli bakım"),
    ]

    public private(set) var stats: ProfileStats = .zero
    public private(set) var hasLoadedStats = false
    public private(set) var unreadNotificationCount = 0
    public private(set) var isLoading = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    /// Oturum kapalıysa yalnızca sıfırlar. Açıksa istatistik, okunmamış bildirim sayısı ve güncel profil.
    public func load(session: SessionStore) async {
        guard let userId = session.userId else {
            stats = .zero
            hasLoadedStats = false
            unreadNotificationCount = 0
            error = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await services.profiles.stats(userId: userId)
            hasLoadedStats = true
            error = nil
            // Güven puanı / doğrulanmış rozeti check-in'lerle değişmiş olabilir.
            if let fresh = try await services.profiles.profile(id: userId), session.userId == userId {
                session.update(fresh)
            }
        } catch {
            self.error = MamaError.classify(error)
        }
        // Bildirim rozeti alınamazsa profil yine de gösterilir.
        if let items = try? await services.notifications.notifications() {
            unreadNotificationCount = items.filter { !$0.isRead }.count
        }
    }

    // MARK: - Doğrulanmış besleyici (FR-P4)

    /// Sunucu bayrağı veya son 30 gündeki doğrulanmış check-in sayısı yeterliyse.
    public func isVerified(_ profile: UserProfile) -> Bool {
        profile.isVerifiedFeeder
            || TrustPolicy.qualifiesAsVerifiedFeeder(verifiedCheckInsLast30Days: stats.verifiedCheckInsLast30Days)
    }

    public var remainingForVerification: Int {
        TrustPolicy.remainingForVerification(verifiedCheckInsLast30Days: stats.verifiedCheckInsLast30Days)
    }

    /// 0…1 arası ilerleme.
    public var verificationProgress: Double {
        let goal = Double(TrustPolicy.verifiedFeederCheckIns)
        return min(1, max(0, Double(stats.verifiedCheckInsLast30Days) / goal))
    }

    public var verificationMessage: String {
        "Doğrulanmış besleyici rozetine \(remainingForVerification) check-in kaldı"
    }

    public var verificationHint: String {
        "Son \(TrustPolicy.verifiedFeederWindowDays) günde konumu doğrulanmış \(TrustPolicy.verifiedFeederCheckIns) check-in ile rozet kendiliğinden gelir."
    }

    // MARK: - İstatistik şeridi (FR-P2)

    public var statItems: [Stat] {
        [
            Stat(value: "\(stats.fedSpotCount)", label: "Beslediğin nokta"),
            Stat(value: "\(stats.checkInCount)", label: "Check-in"),
            Stat(value: "\(stats.resolvedNeedCount)", label: "Kapatılan ihtiyaç"),
        ]
    }

    /// Bildirim satırındaki rozet: 99'dan fazlası "99+".
    public var unreadBadgeText: String? {
        guard unreadNotificationCount > 0 else { return nil }
        return unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)"
    }
}
