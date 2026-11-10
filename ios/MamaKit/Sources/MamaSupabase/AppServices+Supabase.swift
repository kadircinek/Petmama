import Foundation
import MamaCore

extension AppServices {
    /// Gerçek backend'e bağlı servisler. Check-in'ler `AppServices.inMemory` ile aynı şekilde
    /// `OfflineCheckInQueue` üzerinden gider (bağlantı yoksa kuyruğa alınır, FR-H8).
    ///
    /// - Parameters:
    ///   - url: Supabase proje adresi (`https://<ref>.supabase.co`).
    ///   - anonKey: Herkese açık anon/publishable anahtar. Gizli (service_role) anahtar asla istemciye konmaz.
    ///   - spotCache: Çevrimdışı harita önbelleği (ör. `MamaPersistence.SwiftDataStore`).
    ///   - pendingStore: Çevrimdışı check-in kuyruğunun kalıcı deposu.
    ///   - authRedirectURL: Şifre sıfırlama / e-posta doğrulama bağlantılarının döneceği deep link.
    public static func supabase(
        url: URL,
        anonKey: String,
        config: AppConfig,
        spotCache: any SpotCache,
        pendingStore: any PendingCheckInStore,
        authRedirectURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AppServices {
        let backend = SupabaseBackend(url: url, anonKey: anonKey, authRedirectURL: authRedirectURL, now: now)
        return supabase(backend: backend, config: config, spotCache: spotCache, pendingStore: pendingStore, now: now)
    }

    /// Hazır bir `SupabaseBackend` ile (ör. özel `SupabaseClient` yapılandırması).
    public static func supabase(
        backend: SupabaseBackend,
        config: AppConfig,
        spotCache: any SpotCache,
        pendingStore: any PendingCheckInStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> AppServices {
        let queue = OfflineCheckInQueue(store: pendingStore, repository: backend)
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
            spotCache: spotCache,
            checkInQueue: queue,
            config: config,
            now: now
        )
    }
}
