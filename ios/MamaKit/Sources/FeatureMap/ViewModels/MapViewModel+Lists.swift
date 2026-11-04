import Foundation
import MamaCore

// Liste ve İhtiyaçlar segmentleri (FR-H4, FR-H5, ekran 10, 11, 17).
extension MapViewModel {
    /// Liste ve İhtiyaçlar sorgusunun merkezi: kullanıcı konumu, yoksa harita merkezi, yoksa Moda.
    var searchCenter: Coordinate {
        userCoordinate ?? visibleBounds?.center ?? .modaKadikoy
    }

    var searchRadiusMeters: Int {
        Int((filter.maxDistanceKm * 1000).rounded())
    }

    public var filteredListSpots: [Spot] {
        filter.apply(to: listSpots, followedIds: followedIds, now: now)
    }

    public var filteredNeeds: [Need] {
        filter.apply(to: needs)
    }

    public func applyFilter(_ newFilter: SpotFilter) async {
        let radiusChanged = newFilter.maxDistanceKm != filter.maxDistanceKm
        filter = newFilter
        if newFilter.onlyFollowed { await loadFollowed() }
        recluster()
        if radiusChanged, mode != .map { await loadCurrentMode() }
    }

    public func resetFilter() async {
        await applyFilter(.default)
    }

    public func loadCurrentMode() async {
        switch mode {
        case .map: await loadRegion()
        case .list: await loadList()
        case .needs: await loadNeeds()
        }
    }

    public func loadFollowed() async {
        if let ids = try? await services.profiles.followedSpotIds() {
            followedIds = ids
            recluster()
        }
    }

    public func loadList() async {
        let center = searchCenter
        let radius = searchRadiusMeters
        isLoadingList = true
        defer { isLoadingList = false }
        do {
            let fetched = try await services.spots.spots(near: center, radiusMeters: radius)
            await services.spotCache.store(fetched, for: GeoBounds(center: center, radiusMeters: Double(radius)))
            listSpots = fetched
            isOffline = false
        } catch {
            let classified = MamaError.classify(error)
            if classified.isConnectivity {
                let cached = await services.spotCache.cachedSpots(in: GeoBounds(center: center, radiusMeters: Double(radius)))
                listSpots = cached
                    .map { $0.withDistance(from: center) }
                    .filter { ($0.distanceMeters ?? .infinity) <= Double(radius) }
                isOffline = true
            } else {
                self.error = classified
            }
        }
    }

    public func loadNeeds() async {
        isLoadingNeeds = true
        defer { isLoadingNeeds = false }
        do {
            needs = try await services.needs.needs(near: searchCenter, radiusMeters: searchRadiusMeters, includeResolved: false)
        } catch {
            let classified = MamaError.classify(error)
            if classified.isConnectivity {
                isOffline = true
            } else {
                self.error = classified
            }
        }
    }

    /// "Ben ilgileniyorum" (FR-I2). Giriş kontrolü görünümde yapılır.
    public func claim(_ need: Need) async -> MapFeedback {
        claimingNeedId = need.id
        defer { claimingNeedId = nil }
        do {
            let outcome = try await services.needs.claim(needId: need.id)
            await loadNeeds()
            return MapFeedback.claim(outcome)
        } catch {
            return MapFeedback(error: MamaError.classify(error))
        }
    }
}
