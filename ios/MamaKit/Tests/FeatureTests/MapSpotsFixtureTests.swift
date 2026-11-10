import Foundation
import XCTest
import MamaCore

/// FeatureMap ve FeatureSpots testleri için ortak kurulum: sabit zaman, Kadıköy demo verisi ve
/// bağlantı hatası atan küçük repository taslakları.
enum MapSpotsFixture {
    /// 2026-11-04 10:00 İstanbul (07:00 UTC).
    static let now = Date(timeIntervalSince1970: 1_793_775_600)

    static func backend(signedIn: Bool = true) -> InMemoryBackend {
        InMemoryBackend(seed: DemoData.make(now: now), signedIn: signedIn, now: { now })
    }

    static func services(signedIn: Bool = true) -> (services: AppServices, backend: InMemoryBackend) {
        let backend = backend(signedIn: signedIn)
        return (AppServices.inMemory(backend, now: { now }), backend)
    }

    /// Elle kurulan servisler: noktalar ve/veya check-in'ler bağlantı hatası atar.
    static func offlineServices(
        backend: InMemoryBackend,
        cache: any SpotCache = InMemorySpotCache(),
        offlineSpots: Bool = true,
        offlineCheckIns: Bool = false
    ) -> AppServices {
        let checkInRepository: any CheckInRepository = offlineCheckIns ? OfflineCheckIns() : backend
        let queue = OfflineCheckInQueue(store: InMemoryPendingCheckInStore(), repository: checkInRepository)
        return AppServices(
            auth: backend,
            spots: offlineSpots ? OfflineSpots() : backend,
            checkIns: queue,
            animals: backend,
            needs: backend,
            profiles: backend,
            notifications: backend,
            moderation: backend,
            donations: backend,
            community: backend,
            media: backend,
            spotCache: cache,
            checkInQueue: queue,
            config: AppConfig(isDemo: true),
            now: { now }
        )
    }

    /// Demo noktası (1 tabanlı sıra, `DemoData.id(2, n)`).
    static func spot(_ index: Int) -> Spot {
        DemoData.make(now: now).spots[index - 1]
    }

    static func coordinate(ofSpot index: Int) -> Coordinate {
        spot(index).coordinate
    }

    struct OfflineSpots: SpotRepository {
        private func offline<T>() throws -> T { throw URLError(.notConnectedToInternet) }

        func spots(in bounds: GeoBounds) async throws -> [Spot] { try offline() }
        func spots(near center: Coordinate, radiusMeters: Int) async throws -> [Spot] { try offline() }
        func spot(id: UUID) async throws -> Spot? { try offline() }
        func search(query: String, near center: Coordinate?) async throws -> [Spot] { try offline() }
        func feedingTimeline(spotId: UUID, days: Int) async throws -> [FeedingDay] { try offline() }
        func guardians(spotId: UUID) async throws -> [Guardian] { try offline() }
        func duplicates(near coordinate: Coordinate) async throws -> [DuplicateCandidate] { try offline() }
        func createSpot(_ draft: SpotDraft) async throws -> CreateSpotOutcome { try offline() }
        func reportGone(spotId: UUID) async throws -> GoneReportOutcome { try offline() }
        func neighborhoodSummary(near center: Coordinate) async throws -> NeighborhoodSummary { try offline() }
    }

    struct OfflineCheckIns: CheckInRepository {
        func checkIn(_ draft: CheckInDraft) async throws -> CheckInOutcome {
            throw URLError(.notConnectedToInternet)
        }
    }
}

final class MapSpotsFixtureTests: XCTestCase {
    func testOfflineStubsClassifyAsConnectivity() async {
        do {
            _ = try await MapSpotsFixture.OfflineSpots().spots(in: GeoBounds(center: .modaKadikoy, radiusMeters: 100))
            XCTFail("Bağlantı hatası bekleniyordu")
        } catch {
            XCTAssertEqual(MamaError.classify(error), .offline)
        }
    }
}
