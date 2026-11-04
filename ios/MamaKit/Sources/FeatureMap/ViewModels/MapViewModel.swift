import Foundation
import Observation
import MamaCore

/// Harita sekmesinin durumu (FR-H1…H8, D10): görünüm modu, filtre, görünür bölgenin noktaları ve kümeleri,
/// çevrimdışı önbellek yedeği, alt paneldeki ana sayfa içeriği ve İhtiyaçlar segmenti.
///
/// Konum gibi ortam değerleri görünümden gelir (`setUserLocation`); VM ortamı okumaz.
@MainActor
@Observable
public final class MapViewModel {
    public enum Mode: String, CaseIterable, Hashable, Sendable {
        case map, list, needs
    }

    /// Alt paneldeki tek dokunuşla "Mama koydum" hedefi (PRD 6.4).
    public struct QuickFeedTarget: Equatable, Sendable {
        public var spot: Spot
        public var distanceMeters: Double
    }

    /// Görünür bölge sorgusunun tamponu: kaydırmada tekrar sorguyu azaltır.
    public static let queryExpansion = 1.4
    /// Ana sayfa içeriği ("en yakın nokta", "mama gereken noktalar") için arama yarıçapı.
    public static let nearbyRadiusMeters = 1500
    /// Konum değişince ana sayfa içeriğini yenileme eşiği.
    static let homeReloadDistance: Double = 75

    public var mode: Mode = .map
    public internal(set) var filter: SpotFilter = .default
    public var selectedSpotId: UUID?
    public internal(set) var userCoordinate: Coordinate?
    public internal(set) var visibleBounds: GeoBounds?

    public internal(set) var regionSpots: [Spot] = []
    public internal(set) var clusters: [SpotCluster] = []
    public internal(set) var listSpots: [Spot] = []
    public internal(set) var needs: [Need] = []
    public internal(set) var followedIds: Set<UUID> = []

    public internal(set) var nearbySpots: [Spot] = []
    public internal(set) var summary: NeighborhoodSummary?
    public internal(set) var hasLoadedNearby = false

    public internal(set) var isOffline = false
    public internal(set) var isLoadingRegion = false
    public internal(set) var isLoadingList = false
    public internal(set) var isLoadingNeeds = false
    public internal(set) var isSubmittingQuickFeed = false
    public internal(set) var claimingNeedId: UUID?
    /// Her başarılı hızlı "Mama koydum"da artar; haptik ve pati animasyonunu tetikler.
    public internal(set) var feedSuccessCount = 0
    public var error: MamaError?

    @ObservationIgnored let services: AppServices
    @ObservationIgnored private let clusterer: SpotClusterer
    @ObservationIgnored private let debounceNanoseconds: UInt64
    @ObservationIgnored private var loadedBounds: GeoBounds?
    @ObservationIgnored private var regionRequest = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored var homeCenter: Coordinate?

    public init(services: AppServices, clusterer: SpotClusterer = SpotClusterer(), debounceMilliseconds: UInt64 = 350) {
        self.services = services
        self.clusterer = clusterer
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
    }

    public var now: Date { services.now() }

    /// Haritada gösterilen noktalar. Filtre uygulanır; mesafe ölçütü haritada görünür bölgeyle belirlendiği
    /// için burada yok sayılır (mesafe Liste ve İhtiyaçlar'da uygulanır).
    public var mapSpots: [Spot] {
        let now = now
        return regionSpots.filter { spot in
            var probe = spot
            probe.distanceMeters = nil
            return filter.matches(probe, followedIds: followedIds, now: now)
        }
    }

    public var selectedSpot: Spot? {
        guard let selectedSpotId else { return nil }
        return regionSpots.first { $0.id == selectedSpotId }
    }

    // MARK: - Konum

    public func setUserLocation(_ coordinate: Coordinate?) {
        guard coordinate != userCoordinate else { return }
        userCoordinate = coordinate
        regionSpots = regionSpots.map { $0.withDistance(from: coordinate) }
    }

    /// Konum değişince çağrılır; anlamlı bir hareket varsa ana sayfa içeriğini yeniler.
    public func userLocationChanged(_ coordinate: Coordinate?) async {
        setUserLocation(coordinate)
        guard let coordinate else { return }
        if let homeCenter, GeoMath.distance(homeCenter, coordinate) < Self.homeReloadDistance { return }
        await loadHome()
    }

    // MARK: - Görünür bölge

    /// Kameranın görünür bölgesini ayarlar ve kümeleri hemen yeniden hesaplar (sorgu yapmaz).
    public func setVisibleBounds(_ bounds: GeoBounds) {
        visibleBounds = bounds
        recluster()
    }

    /// İlk açılışta, kamera henüz değişim bildirmeden önce yaklaşık bölgeyi verir.
    public func seedVisibleBoundsIfNeeded(_ bounds: GeoBounds) {
        guard visibleBounds == nil else { return }
        setVisibleBounds(bounds)
    }

    /// `.onMapCameraChange(frequency: .onEnd)` buraya bağlanır: kümeleri günceller, sorguyu geciktirerek yapar.
    public func cameraDidChange(to bounds: GeoBounds) {
        setVisibleBounds(bounds)
        debounceTask?.cancel()
        let delay = debounceNanoseconds
        debounceTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            await self?.loadRegion()
        }
    }

    /// Görünür bölgenin noktalarını yükler. Bağlantı yoksa son görülen noktaları önbellekten gösterir (FR-H8).
    public func loadRegion(force: Bool = false) async {
        guard let bounds = visibleBounds else { return }
        if !force, !isOffline, let loadedBounds, loadedBounds.contains(bounds) { return }
        let query = bounds.expanded(by: Self.queryExpansion)
        regionRequest += 1
        let request = regionRequest
        isLoadingRegion = true
        defer { if request == regionRequest { isLoadingRegion = false } }
        do {
            let fetched = try await services.spots.spots(in: query)
            await services.spotCache.store(fetched, for: query)
            guard request == regionRequest else { return }
            regionSpots = fetched.map { $0.withDistance(from: userCoordinate) }
            loadedBounds = query
            isOffline = false
        } catch {
            let classified = MamaError.classify(error)
            guard request == regionRequest else { return }
            if classified.isConnectivity {
                let cached = await services.spotCache.cachedSpots(in: query)
                regionSpots = cached.map { $0.withDistance(from: userCoordinate) }
                loadedBounds = nil
                isOffline = true
            } else {
                self.error = classified
            }
        }
        recluster()
    }

    func recluster() {
        guard let bounds = visibleBounds else {
            clusters = []
            return
        }
        let visible = mapSpots
        clusters = clusterer.clusters(for: visible, in: bounds)
        if let selectedSpotId, !visible.contains(where: { $0.id == selectedSpotId }) {
            self.selectedSpotId = nil
        }
    }

    // MARK: - Seçim

    /// Harita seçimini işler. Tekil pinde noktayı seçer; kümede yakınlaştırılacak kümeyi döner ve seçimi temizler.
    @discardableResult
    public func handleAnnotationSelection(_ id: String?) -> SpotCluster? {
        guard let id else {
            selectedSpotId = nil
            return nil
        }
        guard let cluster = clusters.first(where: { $0.id == id }) else { return nil }
        if cluster.isSingle, let spot = cluster.spots.first {
            selectedSpotId = spot.id
            return nil
        }
        selectedSpotId = nil
        return cluster
    }

    /// Küme dokunuşunda gidilecek bölge: üyeleri kapsar, mevcut görünümün en fazla yarısı kadardır.
    public func zoomBounds(for cluster: SpotCluster) -> GeoBounds {
        let lats = cluster.spots.map(\.coordinate.latitude)
        let lngs = cluster.spots.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else {
            return GeoBounds(center: cluster.coordinate, radiusMeters: 200)
        }
        let tight = GeoBounds(minLatitude: minLat, minLongitude: minLng, maxLatitude: maxLat, maxLongitude: maxLng)
        let currentLat = visibleBounds?.latitudeDelta ?? 0.02
        let currentLng = visibleBounds?.longitudeDelta ?? 0.02
        let minimumSpan = 0.0025
        let latDelta = min(max(tight.latitudeDelta * 1.6, minimumSpan), currentLat / 2)
        let lngDelta = min(max(tight.longitudeDelta * 1.6, minimumSpan), currentLng / 2)
        return GeoBounds(center: tight.center, latitudeDelta: latDelta, longitudeDelta: lngDelta)
    }
}
