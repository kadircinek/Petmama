import Foundation
import XCTest
import MamaCore
@testable import FeatureMap

@MainActor
final class MapViewModelTests: XCTestCase {
    private let wideBounds = GeoBounds(center: .modaKadikoy, latitudeDelta: 0.03, longitudeDelta: 0.03)

    private func makeModel(signedIn: Bool = true) -> (MapViewModel, InMemoryBackend) {
        let (services, backend) = MapSpotsFixture.services(signedIn: signedIn)
        return (MapViewModel(services: services, debounceMilliseconds: 0), backend)
    }

    // MARK: - Kümeleme ve filtre

    func testWideRegionClustersAllVisibleSpots() async {
        let (model, _) = makeModel()
        model.setVisibleBounds(wideBounds)
        await model.loadRegion()

        let spotCount = model.mapSpots.count
        let clusterCount = model.clusters.count
        let clusteredTotal = model.clusters.map(\.count).reduce(0, +)
        XCTAssertEqual(spotCount, 20)
        XCTAssertEqual(clusteredTotal, spotCount)
        XCTAssertLessThan(clusterCount, spotCount, "Geniş bölgede noktalar kümelenmeli")
        XCTAssertFalse(model.isOffline)
    }

    func testStreetLevelShowsSinglePins() async {
        let (model, _) = makeModel()
        model.setVisibleBounds(GeoBounds(center: MapSpotsFixture.coordinate(ofSpot: 1), radiusMeters: 200))
        await model.loadRegion()

        let clusters = model.clusters
        XCTAssertFalse(clusters.isEmpty)
        XCTAssertTrue(clusters.allSatisfy(\.isSingle))
    }

    func testStatusFilterNarrowsPinsAndClusters() async {
        let (model, _) = makeModel()
        model.setVisibleBounds(wideBounds)
        await model.loadRegion()
        await model.applyFilter(SpotFilter(statuses: [.needsFood]))

        let ids = Set(model.mapSpots.map(\.id))
        let clusteredTotal = model.clusters.map(\.count).reduce(0, +)
        XCTAssertEqual(ids, [DemoData.id(2, 6), DemoData.id(2, 11), DemoData.id(2, 16)])
        XCTAssertEqual(clusteredTotal, 3)
        XCTAssertEqual(model.filter.activeCount, 1)
    }

    func testSelectingSinglePinAndZoomingIntoCluster() async {
        let (model, _) = makeModel()
        model.setVisibleBounds(wideBounds)
        await model.loadRegion()

        guard let cluster = model.clusters.first(where: { !$0.isSingle }) else {
            return XCTFail("Geniş bölgede en az bir çoklu küme bekleniyordu")
        }
        let zoomTarget = model.handleAnnotationSelection(cluster.id)
        XCTAssertEqual(zoomTarget?.id, cluster.id)
        XCTAssertNil(model.selectedSpotId)
        let zoom = model.zoomBounds(for: cluster)
        XCTAssertLessThanOrEqual(zoom.latitudeDelta, wideBounds.latitudeDelta / 2)
        XCTAssertTrue(cluster.spots.allSatisfy { zoom.contains($0.coordinate) })

        model.setVisibleBounds(GeoBounds(center: MapSpotsFixture.coordinate(ofSpot: 1), radiusMeters: 200))
        let single = model.handleAnnotationSelection(DemoData.id(2, 1).uuidString)
        XCTAssertNil(single)
        XCTAssertEqual(model.selectedSpot?.title, "Moda Parkı girişi")
    }

    // MARK: - Çevrimdışı

    func testOfflineFallsBackToCachedSpots() async {
        let backend = MapSpotsFixture.backend()
        let cache = InMemorySpotCache()
        let cached = [MapSpotsFixture.spot(1), MapSpotsFixture.spot(6)]
        await cache.store(cached, for: wideBounds)
        let services = MapSpotsFixture.offlineServices(backend: backend, cache: cache)
        let model = MapViewModel(services: services, debounceMilliseconds: 0)

        model.setVisibleBounds(wideBounds)
        await model.loadRegion()

        let ids = Set(model.regionSpots.map(\.id))
        XCTAssertTrue(model.isOffline)
        XCTAssertNil(model.error)
        XCTAssertEqual(ids, Set(cached.map(\.id)))
        XCTAssertEqual(model.clusters.map(\.count).reduce(0, +), 2)
    }

    func testOnlineLoadStoresRegionInCache() async {
        let (services, _) = MapSpotsFixture.services()
        let model = MapViewModel(services: services, debounceMilliseconds: 0)
        model.setVisibleBounds(wideBounds)
        await model.loadRegion()

        let cached = await services.spotCache.cachedSpots(in: wideBounds)
        XCTAssertEqual(cached.count, model.regionSpots.count)
    }

    // MARK: - Alt panel (ana sayfa)

    func testQuickFeedTargetIsNearestSpotWithin100m() async {
        let (model, _) = makeModel()
        model.setUserLocation(MapSpotsFixture.coordinate(ofSpot: 1))
        await model.loadHome()

        let target = model.quickFeedTarget
        XCTAssertEqual(target?.spot.id, DemoData.id(2, 1))
        XCTAssertLessThan(target?.distanceMeters ?? .infinity, 1)
        XCTAssertNotNil(model.summary)
        XCTAssertTrue(model.needsFoodSpots.contains { $0.id == DemoData.id(2, 6) })
        XCTAssertFalse(model.isNeighborhoodEmpty)
    }

    func testNoQuickFeedTargetButNearestSpotWhenFartherThan100m() async {
        let (model, _) = makeModel()
        let user = GeoMath.destination(from: MapSpotsFixture.coordinate(ofSpot: 8), meters: 240, bearingDegrees: 0)
        model.setUserLocation(user)
        await model.loadHome()

        XCTAssertNil(model.quickFeedTarget)
        XCTAssertEqual(model.nearestSpot?.id, DemoData.id(2, 8))
        let feedback = await model.submitQuickFeed()
        XCTAssertFalse(feedback.isSuccess)
    }

    func testOneTapQuickFeedMarksSpotFed() async {
        let (model, _) = makeModel()
        model.setUserLocation(MapSpotsFixture.coordinate(ofSpot: 6))
        await model.loadHome()
        model.setVisibleBounds(wideBounds)
        await model.loadRegion()

        let feedback = await model.submitQuickFeed()
        XCTAssertTrue(feedback.isSuccess)
        XCTAssertEqual(feedback.message, "Teşekkürler! Mama bekleyen noktayı sen kapattın.")
        XCTAssertEqual(model.feedSuccessCount, 1)
        let updated = model.regionSpots.first { $0.id == DemoData.id(2, 6) }
        XCTAssertEqual(updated?.currentStatus(now: MapSpotsFixture.now), .fedRecent)
        XCTAssertFalse(model.needsFoodSpots.contains { $0.id == DemoData.id(2, 6) })
    }

    func testEmptyNeighborhood() async {
        let (model, _) = makeModel()
        model.setUserLocation(Coordinate(latitude: 41.2, longitude: 29.6))
        await model.loadHome()

        XCTAssertTrue(model.isNeighborhoodEmpty)
        XCTAssertNil(model.nearestSpot)
    }

    func testQueuedCheckInsFlushAfterReconnect() async {
        let (services, _) = MapSpotsFixture.services()
        let draft = CheckInDraft(spotId: DemoData.id(2, 1), kind: .fed, userCoordinate: MapSpotsFixture.coordinate(ofSpot: 1),
                                 createdAt: MapSpotsFixture.now)
        let pendingStore = InMemoryPendingCheckInStore([draft])
        let backend = MapSpotsFixture.backend()
        let queue = OfflineCheckInQueue(store: pendingStore, repository: backend)
        var withQueue = services
        withQueue.checkIns = queue
        withQueue.checkInQueue = queue
        withQueue.spots = backend
        let model = MapViewModel(services: withQueue, debounceMilliseconds: 0)

        let feedback = await model.flushPendingCheckIns()
        let remaining = await queue.pendingCount()
        XCTAssertEqual(feedback?.isSuccess, true)
        XCTAssertEqual(remaining, 0)
    }

    // MARK: - Liste ve İhtiyaçlar

    func testListUsesFilterDistanceAndSort() async {
        let (model, _) = makeModel()
        model.setUserLocation(MapSpotsFixture.coordinate(ofSpot: 1))
        model.mode = .list
        await model.applyFilter(SpotFilter(maxDistanceKm: 1, sort: .nearest))
        await model.loadList()

        let list = model.filteredListSpots
        XCTAssertEqual(list.first?.id, DemoData.id(2, 1))
        XCTAssertTrue(list.allSatisfy { ($0.distanceMeters ?? 0) <= 1000 })
        let distances = list.compactMap(\.distanceMeters)
        XCTAssertEqual(distances, distances.sorted())
    }

    func testNeedsSegmentSortsUrgentFirstAndClaims() async {
        let (model, _) = makeModel()
        model.setUserLocation(.modaKadikoy)
        model.mode = .needs
        await model.loadNeeds()

        let needs = model.filteredNeeds
        XCTAssertEqual(needs.first?.id, DemoData.id(5, 1), "Acil veteriner ihtiyacı en üstte")
        XCTAssertFalse(needs.contains { $0.status == .resolved })

        guard let neuter = needs.first(where: { $0.id == DemoData.id(5, 2) }) else {
            return XCTFail("Kısırlaştırma ihtiyacı listede olmalı")
        }
        let feedback = await model.claim(neuter)
        XCTAssertTrue(feedback.isSuccess)
        let claimed = model.needs.first { $0.id == neuter.id }
        XCTAssertEqual(claimed?.status, .claimed)
    }

    func testNeedTypeFilterAppliesToNeedsSegment() async {
        let (model, _) = makeModel()
        model.setUserLocation(.modaKadikoy)
        await model.loadNeeds()
        await model.applyFilter(SpotFilter(needTypes: [.shelter]))

        let types = Set(model.filteredNeeds.map(\.type))
        XCTAssertEqual(types, [.shelter])
    }
}
