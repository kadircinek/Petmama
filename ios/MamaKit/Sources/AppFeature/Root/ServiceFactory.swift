import Foundation
import MamaCore
import MamaSupabase
#if canImport(SwiftData)
import MamaPersistence
#endif

/// Yapılandırmaya göre servisleri kurar: Supabase + SwiftData önbelleği, ya da demo modu (D7).
enum ServiceFactory {
    static func make(_ configuration: AppConfiguration) -> AppServices {
        guard configuration.usesSupabase, let url = configuration.supabaseURL, let key = configuration.supabaseAnonKey else {
            return demo(configuration.app)
        }

        let spotCache: any SpotCache
        let pendingStore: any PendingCheckInStore
        #if canImport(SwiftData)
        if let store = try? SwiftDataStore.make() {
            spotCache = store
            pendingStore = store
        } else {
            spotCache = InMemorySpotCache()
            pendingStore = FilePendingCheckInStore(url: fallbackQueueURL)
        }
        #else
        spotCache = InMemorySpotCache()
        pendingStore = FilePendingCheckInStore(url: fallbackQueueURL)
        #endif

        var services = AppServices.supabase(
            url: url,
            anonKey: key,
            config: configuration.app,
            spotCache: spotCache,
            pendingStore: pendingStore
        )
        #if canImport(ImageIO)
        // Yüklemeden önce EXIF/GPS temizle ve 1600 px'e küçült (PRD 7.1). Uploader da yapıyor; çift güvence.
        services.media = SanitizingMediaUploader(base: services.media)
        #endif
        return services
    }

    static func demo(_ config: AppConfig) -> AppServices {
        let backend = InMemoryBackend(seed: DemoData.make(), signedIn: false)
        var services = AppServices.inMemory(backend, config: config)
        #if canImport(ImageIO)
        services.media = SanitizingMediaUploader(base: services.media)
        #endif
        return services
    }

    private static var fallbackQueueURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MamaHaritasi/pending-checkins.json")
    }
}
