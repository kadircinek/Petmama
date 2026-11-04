import Foundation
import Observation
import MamaCore

/// Ayarlar (ekran 23): bildirim tercihleri, engellenen kullanıcılar, çıkış ve hesap silme (FR-P3).
@MainActor
@Observable
public final class SettingsViewModel {
    public struct BlockedUser: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let displayName: String
    }

    /// Görünüm bağlanır; değişiklikler `savePreferences()` ile gönderilir.
    public var preferences: NotificationPreferences = .default
    /// Sunucudaki son hali. `nil` = henüz yüklenmedi (veya oturum kapalı).
    public private(set) var savedPreferences: NotificationPreferences?
    public private(set) var blockedUsers: [BlockedUser] = []
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var isDeletingAccount = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public static let radiusOptions = NotificationPreferences.radiusOptions
    public static let hourOptions = Array(0..<24)
    public static let dailyLimitNote =
        "Günde en fazla \(NotificationPolicy.maxNeedFoodPushesPerDay) \"mama gerekli\" bildirimi gönderilir."
    public static let deleteAccountExplanation =
        "Profilin, takip ettiklerin, bildirimlerin ve cihaz kayıtların kalıcı olarak silinir. Eklediğin noktalar ve hayvan profilleri topluluk için kalır ama artık seninle ilişkilendirilmez. Bu işlem geri alınamaz."

    public init(services: AppServices) {
        self.services = services
    }

    public var supportEmail: String { services.config.supportEmail }
    public var hasLoadedPreferences: Bool { savedPreferences != nil }
    public var hasUnsavedChanges: Bool { savedPreferences.map { $0 != preferences } ?? false }

    public func load(isSignedIn: Bool) async {
        guard isSignedIn else {
            preferences = .default
            savedPreferences = nil
            blockedUsers = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await services.notifications.preferences()
            preferences = loaded
            savedPreferences = loaded
            blockedUsers = try await loadBlockedUsers()
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    /// Değişiklik varsa gönderir. Hata olursa son kaydedilen hale döner.
    @discardableResult
    public func savePreferences() async -> Bool {
        guard let saved = savedPreferences, preferences != saved else { return false }
        let pending = preferences
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.notifications.updatePreferences(pending)
            savedPreferences = pending
            return true
        } catch {
            self.error = MamaError.classify(error)
            preferences = saved
            return false
        }
    }

    public func unblock(_ user: BlockedUser) async {
        do {
            try await services.moderation.unblock(userId: user.id)
            blockedUsers.removeAll { $0.id == user.id }
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func signOut(session: SessionStore) async {
        await session.signOut()
        reset()
    }

    /// Hesabı siler (FR-P3). Başarılıysa oturum kapanır; topluluk verisi anonim kalır (PRD 9.5).
    @discardableResult
    public func deleteAccount(session: SessionStore) async -> Bool {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        session.clearError()
        let deleted = await session.deleteAccount()
        if deleted {
            reset()
        } else {
            error = session.lastError ?? .server("delete-account")
        }
        return deleted
    }

    // MARK: - Biçimlendirme

    /// "500 m", "1 km", "2 km", "5 km"
    public static func radiusLabel(_ meters: Int) -> String {
        guard meters >= 1000 else { return "\(meters) m" }
        if meters % 1000 == 0 { return "\(meters / 1000) km" }
        return String(format: "%.1f km", Double(meters) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// "22:00"
    public static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", ((hour % 24) + 24) % 24)
    }

    /// "22:00–07:00 arası bildirim gönderilmez." Başlangıç = bitiş ise sessiz saat kapalı.
    public var quietHoursSummary: String {
        guard preferences.quietStartHour != preferences.quietEndHour else {
            return "Sessiz saat kapalı."
        }
        return "\(Self.hourLabel(preferences.quietStartHour))–\(Self.hourLabel(preferences.quietEndHour)) arası bildirim gönderilmez."
    }

    // MARK: - Yardımcılar

    private func loadBlockedUsers() async throws -> [BlockedUser] {
        let ids = try await services.moderation.blockedUserIds()
        var users: [BlockedUser] = []
        for id in ids {
            let name = (try? await services.profiles.profile(id: id))?.displayName
            users.append(BlockedUser(id: id, displayName: name ?? "Kullanıcı"))
        }
        return users.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    private func reset() {
        preferences = .default
        savedPreferences = nil
        blockedUsers = []
        error = nil
    }
}
