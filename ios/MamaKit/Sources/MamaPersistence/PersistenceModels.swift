#if canImport(SwiftData)
import Foundation
import SwiftData

// SwiftData kayıtları (iOS 17). Domain modelleri JSON olarak saklanır; sorgulanan alanlar
// (konum, kimlik, zaman) ayrı sütunlardır. Şema değişirse önbellek atılıp yeniden doldurulabilir:
// içerik yalnızca sunucudaki verinin kopyası (kuyruk hariç).

/// Önbellekteki bir besleme noktası (FR-H8).
@Model
final class CachedSpotRecord {
    @Attribute(.unique) var spotId: UUID
    var latitude: Double
    var longitude: Double
    /// Kayda yazılma zamanı; kapasite aşılınca en eskiler atılır.
    var updatedAt: Date
    /// `JSONEncoder.mama` ile kodlanmış `Spot`.
    var payload: Data

    init(spotId: UUID, latitude: Double, longitude: Double, updatedAt: Date, payload: Data) {
        self.spotId = spotId
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

/// Çevrimdışı kuyruktaki bir check-in.
@Model
final class PendingCheckInRecord {
    @Attribute(.unique) var draftId: UUID
    var createdAt: Date
    /// Kuyruk sırası (FIFO).
    var position: Int
    /// `JSONEncoder.mama` ile kodlanmış `CheckInDraft`.
    var payload: Data

    init(draftId: UUID, createdAt: Date, position: Int, payload: Data) {
        self.draftId = draftId
        self.createdAt = createdAt
        self.position = position
        self.payload = payload
    }
}

/// Anahtar/değer: son harita bölgesi vb.
@Model
final class CacheMetadataRecord {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }
}
#endif
