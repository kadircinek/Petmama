import Foundation
import MamaCore

// Alt paneldeki ana sayfa içeriği (D10, ekran 8): en yakın nokta, tek dokunuşla "Mama koydum",
// yakında mama gereken noktalar ve "Bugün mahallende" özeti.
extension MapViewModel {
    /// 100 m içindeki en yakın, konumu kesin, aktif nokta (PRD 6.4).
    public var quickFeedTarget: QuickFeedTarget? {
        CheckInPolicy.quickFeedCandidate(user: userCoordinate, spots: nearbySpots)
            .map { QuickFeedTarget(spot: $0.spot.withDistance(from: userCoordinate), distanceMeters: $0.distance) }
    }

    /// Konum biliniyorsa en yakın nokta ("En yakın nokta: … · 240 m").
    public var nearestSpot: Spot? {
        guard let user = userCoordinate else { return nil }
        return nearbySpots
            .map { $0.withDistance(from: user) }
            .min { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }

    /// "Yakınında mama gereken noktalar" şeridi: turuncu noktalar, en yakın önce.
    public var needsFoodSpots: [Spot] {
        let now = now
        let origin = userCoordinate ?? homeCenter
        return nearbySpots
            .filter { $0.currentStatus(now: now) == .needsFood }
            .map { $0.withDistance(from: origin) }
            .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }

    /// Mahallede hiç nokta yok: "Bu sokağın ilk besleyicisi sen ol" (PRD 6.4).
    public var isNeighborhoodEmpty: Bool {
        hasLoadedNearby && nearbySpots.isEmpty
    }

    public func loadHome() async {
        let center = userCoordinate ?? visibleBounds?.center ?? .modaKadikoy
        homeCenter = center
        let repository = services.spots
        let radius = Self.nearbyRadiusMeters
        do {
            async let nearby = repository.spots(near: center, radiusMeters: radius)
            async let neighborhood = repository.neighborhoodSummary(near: center)
            let (spots, summaryValue) = try await (nearby, neighborhood)
            nearbySpots = spots
            summary = summaryValue
            isOffline = false
        } catch {
            let classified = MamaError.classify(error)
            if classified.isConnectivity {
                let cached = await services.spotCache.cachedSpots(in: GeoBounds(center: center, radiusMeters: Double(radius)))
                nearbySpots = cached
                    .map { $0.withDistance(from: center) }
                    .filter { ($0.distanceMeters ?? .infinity) <= Double(radius) }
                    .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
                summary = nil
                isOffline = true
            } else {
                self.error = classified
            }
        }
        hasLoadedNearby = true
    }

    /// Tek dokunuşla "Mama koydum": 100 m içindeki en yakın noktaya doğrudan check-in (PRD 6.4).
    public func submitQuickFeed() async -> MapFeedback {
        guard let user = userCoordinate, let target = quickFeedTarget else { return .noQuickFeedTarget }
        isSubmittingQuickFeed = true
        defer { isSubmittingQuickFeed = false }
        let draft = CheckInDraft(spotId: target.spot.id, kind: .fed, userCoordinate: user, createdAt: now)
        do {
            let outcome = try await services.checkIns.checkIn(draft)
            switch outcome {
            case .success(let receipt):
                feedSuccessCount += 1
                markFed(spotId: target.spot.id, status: receipt.spotStatus)
            case .queuedOffline:
                // İyimser güncelleme: kuyruktaki check-in gönderilince sunucu da aynı durumu verir.
                feedSuccessCount += 1
                markFed(spotId: target.spot.id, status: .fedRecent)
            case .tooFar, .rateLimited, .spotInactive:
                break
            }
            return MapFeedback.feeding(outcome)
        } catch {
            return MapFeedback(error: MamaError.classify(error))
        }
    }

    /// Çevrimdışı kuyruktaki check-in'leri gönderir (FR-H8). Gönderilen olursa toast metni döner.
    @discardableResult
    public func flushPendingCheckIns() async -> MapFeedback? {
        let outcomes = await services.checkInQueue.flush(now: now)
        let sent = outcomes.filter { outcome in
            if case .success = outcome { return true }
            return false
        }.count
        guard sent > 0 else { return nil }
        await loadRegion(force: true)
        return .flushed(count: sent)
    }

    /// Haritayı, ana sayfa içeriğini ve açık segmenti yeniler (dakikada bir ve sheet kapanınca).
    public func refresh() async {
        await loadRegion(force: true)
        await loadHome()
        switch mode {
        case .map: break
        case .list: await loadList()
        case .needs: await loadNeeds()
        }
    }

    func markFed(spotId: UUID, status: SpotStatus) {
        let fedAt = now
        let update: (Spot) -> Spot = { spot in
            guard spot.id == spotId else { return spot }
            var copy = spot
            copy.lastFedAt = fedAt
            copy.status = status
            return copy
        }
        nearbySpots = nearbySpots.map(update)
        regionSpots = regionSpots.map(update)
        listSpots = listSpots.map(update)
        recluster()
    }
}
