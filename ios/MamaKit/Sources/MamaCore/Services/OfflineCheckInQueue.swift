import Foundation

/// Çevrimdışı check-in kuyruğu (FR-H8).
///
/// `CheckInRepository` olarak davranır: önce sunucuya gönderir, bağlantı hatasında kuyruğa alır ve
/// `.queuedOffline` döner. `flush()` bağlantı gelince (uygulama öne gelince, ağ değişince) çağrılır.
public actor OfflineCheckInQueue: CheckInRepository {
    /// 12 saatten eski check-in'ler gönderilmez: "mama koydum" bilgisi bayatlamıştır.
    public static let maxAge: TimeInterval = 12 * 3600

    private let store: any PendingCheckInStore
    private let repository: any CheckInRepository
    private var isFlushing = false
    /// O anki oturumun kullanıcısı. Kuyruğa giren taslaklar bununla işaretlenir; `flush` yalnızca
    /// bu kullanıcının taslaklarını gönderir. `nil` (oturum yok) iken hiçbir şey gönderilmez.
    public private(set) var owner: UUID?

    public init(store: any PendingCheckInStore, repository: any CheckInRepository) {
        self.store = store
        self.repository = repository
    }

    public func checkIn(_ draft: CheckInDraft) async throws -> CheckInOutcome {
        var draft = draft
        if draft.userId == nil { draft.userId = owner }
        do {
            return try await repository.checkIn(draft)
        } catch {
            let classified = MamaError.classify(error)
            guard classified.isConnectivity else { throw classified }
            var pending = await store.load()
            if !pending.contains(where: { $0.id == draft.id }) {
                pending.append(draft)
                await store.save(pending)
            }
            return .queuedOffline
        }
    }

    public func pendingCount() async -> Int {
        await store.load().count
    }

    public func pendingDrafts() async -> [CheckInDraft] {
        await store.load()
    }

    /// Oturum değişince çağrılır (giriş, çıkış, açılışta oturum geri yükleme).
    public func setOwner(_ userId: UUID?) {
        owner = userId
    }

    /// Çıkışta ve hesap silmede: bekleyen taslaklar bir sonraki hesaba geçmesin.
    public func clear() async {
        await store.save([])
    }

    /// Kuyruktakileri sırayla gönderir. Bağlantı yine koparsa kalanları korur.
    @discardableResult
    public func flush(now: Date = Date()) async -> [CheckInOutcome] {
        guard !isFlushing, let owner else { return [] }
        isFlushing = true
        defer { isFlushing = false }

        // Bayat olanlar ve başka hesaba ait (ya da sahipsiz, eski sürümden kalma) taslaklar atılır.
        var remaining = await store.load().filter {
            now.timeIntervalSince($0.createdAt) <= Self.maxAge && $0.userId == owner
        }
        var outcomes: [CheckInOutcome] = []
        while let next = remaining.first {
            do {
                outcomes.append(try await repository.checkIn(next))
                remaining.removeFirst()
            } catch {
                if MamaError.classify(error).isConnectivity { break }
                // Kalıcı hata (ör. nokta silinmiş): kuyruğu tıkamasın.
                remaining.removeFirst()
            }
        }
        await store.save(remaining)
        return outcomes
    }
}

public actor InMemoryPendingCheckInStore: PendingCheckInStore {
    private var drafts: [CheckInDraft]

    public init(_ drafts: [CheckInDraft] = []) {
        self.drafts = drafts
    }

    public func load() async -> [CheckInDraft] { drafts }
    public func save(_ drafts: [CheckInDraft]) async { self.drafts = drafts }
}

/// JSON dosyasına yazan basit kalıcı depo. SwiftData kullanılamayan ortamlarda yedek.
public actor FilePendingCheckInStore: PendingCheckInStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() async -> [CheckInDraft] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.mama.decode([CheckInDraft].self, from: data)) ?? []
    }

    public func save(_ drafts: [CheckInDraft]) async {
        guard let data = try? JSONEncoder.mama.encode(drafts) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

public actor InMemorySpotCache: SpotCache {
    private var spotsById: [UUID: Spot] = [:]
    private var bounds: GeoBounds?
    private let capacity: Int

    public init(capacity: Int = 2000) {
        self.capacity = capacity
    }

    public func store(_ spots: [Spot], for bounds: GeoBounds) async {
        for spot in spots { spotsById[spot.id] = spot }
        if spotsById.count > capacity {
            // En eski beslenenleri at.
            let sorted = spotsById.values.sorted { ($0.lastFedAt ?? .distantPast) > ($1.lastFedAt ?? .distantPast) }
            spotsById = Dictionary(uniqueKeysWithValues: sorted.prefix(capacity).map { ($0.id, $0) })
        }
        self.bounds = bounds
    }

    public func cachedSpots(in bounds: GeoBounds) async -> [Spot] {
        spotsById.values.filter { bounds.contains($0.coordinate) }
    }

    public func lastBounds() async -> GeoBounds? { bounds }
}

extension JSONEncoder {
    public static var mama: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var mama: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
