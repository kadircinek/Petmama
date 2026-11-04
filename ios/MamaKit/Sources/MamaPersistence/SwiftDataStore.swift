#if canImport(SwiftData)
import Foundation
import MamaCore
import SwiftData

/// SwiftData tabanlı çevrimdışı depo: harita önbelleği (`SpotCache`, FR-H8) ve check-in kuyruğu
/// (`PendingCheckInStore`). Kendi arka plan `ModelContext`'i olan bir `ModelActor`'dür
/// (`@ModelActor` makrosunun ürettiği kodun açık hali).
///
/// ```swift
/// let store = try SwiftDataStore.make()
/// let services = AppServices.supabase(url: …, anonKey: …, config: …, spotCache: store, pendingStore: store)
/// ```
public actor SwiftDataStore: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer

    private let capacity: Int
    private let now: @Sendable () -> Date
    private static let lastBoundsKey = "lastBounds"

    /// - Parameter capacity: Önbellekte tutulacak en fazla nokta; aşılınca en eski yazılanlar atılır.
    public init(modelContainer: ModelContainer, capacity: Int = 2000, now: @escaping @Sendable () -> Date = { Date() }) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.capacity = max(1, capacity)
        self.now = now
    }

    /// Diskteki (veya `inMemory` ise bellekteki) varsayılan depo.
    public static func make(inMemory: Bool = false, capacity: Int = 2000) throws -> SwiftDataStore {
        SwiftDataStore(modelContainer: try makeContainer(inMemory: inMemory), capacity: capacity)
    }

    /// Önbellek şeması. Disk deposu açılamazsa (ör. uyumsuz eski şema) dosyalar silinip yeniden oluşturulur:
    /// içerik sunucudan yeniden dolar, yalnızca gönderilmemiş check-in'ler kaybolur.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([CachedSpotRecord.self, PendingCheckInRecord.self, CacheMetadataRecord.self])
        let configuration = ModelConfiguration(
            "MamaCache",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard !inMemory else { throw error }
            let storeURL = configuration.url
            let directory = storeURL.deletingLastPathComponent()
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(storeURL.lastPathComponent + suffix))
            }
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    // MARK: - Metadata

    private func metadataRecord(_ wantedKey: String) -> CacheMetadataRecord? {
        var descriptor = FetchDescriptor<CacheMetadataRecord>(
            predicate: #Predicate<CacheMetadataRecord> { $0.key == wantedKey }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func setMetadata(_ wantedKey: String, payload: Data) {
        if let record = metadataRecord(wantedKey) {
            record.payload = payload
        } else {
            modelContext.insert(CacheMetadataRecord(key: wantedKey, payload: payload))
        }
    }
}

// MARK: - SpotCache

extension SwiftDataStore: SpotCache {
    public func store(_ spots: [Spot], for bounds: GeoBounds) async {
        let context = modelContext
        let encoder = JSONEncoder.mama
        let timestamp = now()

        let existing = (try? context.fetch(FetchDescriptor<CachedSpotRecord>())) ?? []
        var recordsById: [UUID: CachedSpotRecord] = [:]
        for record in existing { recordsById[record.spotId] = record }

        for spot in spots {
            guard let payload = try? encoder.encode(spot) else { continue }
            if let record = recordsById[spot.id] {
                record.latitude = spot.coordinate.latitude
                record.longitude = spot.coordinate.longitude
                record.updatedAt = timestamp
                record.payload = payload
            } else {
                let record = CachedSpotRecord(
                    spotId: spot.id,
                    latitude: spot.coordinate.latitude,
                    longitude: spot.coordinate.longitude,
                    updatedAt: timestamp,
                    payload: payload
                )
                context.insert(record)
                recordsById[spot.id] = record
            }
        }

        if recordsById.count > capacity {
            let oldestFirst = recordsById.values.sorted { $0.updatedAt < $1.updatedAt }
            for record in oldestFirst.prefix(recordsById.count - capacity) {
                context.delete(record)
            }
        }

        if let boundsData = try? encoder.encode(bounds) {
            setMetadata(Self.lastBoundsKey, payload: boundsData)
        }
        try? context.save()
    }

    public func cachedSpots(in bounds: GeoBounds) async -> [Spot] {
        let minLat = bounds.minLatitude
        let maxLat = bounds.maxLatitude
        let minLng = bounds.minLongitude
        let maxLng = bounds.maxLongitude
        let descriptor = FetchDescriptor<CachedSpotRecord>(
            predicate: #Predicate<CachedSpotRecord> { record in
                record.latitude >= minLat && record.latitude <= maxLat
                    && record.longitude >= minLng && record.longitude <= maxLng
            }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        let decoder = JSONDecoder.mama
        return records.compactMap { try? decoder.decode(Spot.self, from: $0.payload) }
    }

    public func lastBounds() async -> GeoBounds? {
        guard let record = metadataRecord(Self.lastBoundsKey) else { return nil }
        return try? JSONDecoder.mama.decode(GeoBounds.self, from: record.payload)
    }
}

// MARK: - PendingCheckInStore

extension SwiftDataStore: PendingCheckInStore {
    public func load() async -> [CheckInDraft] {
        let descriptor = FetchDescriptor<PendingCheckInRecord>(
            sortBy: [SortDescriptor(\PendingCheckInRecord.position), SortDescriptor(\PendingCheckInRecord.createdAt)]
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        let decoder = JSONDecoder.mama
        return records.compactMap { try? decoder.decode(CheckInDraft.self, from: $0.payload) }
    }

    /// Kuyruğun tamamını verilen sırayla değiştirir. Benzersiz `draftId` çakışmasın diye kayıtlar yerinde güncellenir.
    public func save(_ drafts: [CheckInDraft]) async {
        let context = modelContext
        let encoder = JSONEncoder.mama
        let existing = (try? context.fetch(FetchDescriptor<PendingCheckInRecord>())) ?? []
        var recordsById: [UUID: PendingCheckInRecord] = [:]
        for record in existing { recordsById[record.draftId] = record }

        var kept = Set<UUID>()
        for (position, draft) in drafts.enumerated() {
            guard !kept.contains(draft.id), let payload = try? encoder.encode(draft) else { continue }
            kept.insert(draft.id)
            if let record = recordsById[draft.id] {
                record.position = position
                record.createdAt = draft.createdAt
                record.payload = payload
            } else {
                context.insert(PendingCheckInRecord(
                    draftId: draft.id,
                    createdAt: draft.createdAt,
                    position: position,
                    payload: payload
                ))
            }
        }
        for record in existing where !kept.contains(record.draftId) {
            context.delete(record)
        }
        try? context.save()
    }
}
#endif
