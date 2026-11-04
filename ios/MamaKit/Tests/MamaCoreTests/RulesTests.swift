import XCTest
@testable import MamaCore

final class SpotStatusRulesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshWithinTwelveHours() {
        let fed = now.addingTimeInterval(-(12 * 3600 - 60))
        XCTAssertEqual(SpotStatusRules.status(lastFedAt: fed, hasOpenFoodRequest: false, now: now), .fedRecent)
    }

    func testStaleBetweenTwelveAndTwentyFourHours() {
        XCTAssertEqual(SpotStatusRules.status(lastFedAt: now.addingTimeInterval(-12 * 3600), hasOpenFoodRequest: false, now: now), .fedStale)
        XCTAssertEqual(SpotStatusRules.status(lastFedAt: now.addingTimeInterval(-(24 * 3600 - 1)), hasOpenFoodRequest: false, now: now), .fedStale)
    }

    func testUnknownAfterTwentyFourHoursOrNever() {
        XCTAssertEqual(SpotStatusRules.status(lastFedAt: now.addingTimeInterval(-24 * 3600), hasOpenFoodRequest: false, now: now), .unknown)
        XCTAssertEqual(SpotStatusRules.status(lastFedAt: nil, hasOpenFoodRequest: false, now: now), .unknown)
    }

    func testOpenRequestWinsOverFreshFeeding() {
        XCTAssertEqual(SpotStatusRules.status(lastFedAt: now, hasOpenFoodRequest: true, now: now), .needsFood)
    }

    func testCachedSpotAgesOffline() {
        let spot = Spot(coordinate: .modaKadikoy, type: .food, species: .cat, title: "x", status: .fedRecent, lastFedAt: now.addingTimeInterval(-13 * 3600))
        XCTAssertEqual(spot.currentStatus(now: now), .fedStale)
        var needs = spot
        needs.status = .needsFood
        XCTAssertEqual(needs.currentStatus(now: now.addingTimeInterval(86_400 * 3)), .needsFood)
    }
}

final class CheckInPolicyTests: XCTestCase {
    let spot = Spot(coordinate: .modaKadikoy, type: .food, species: .cat, title: "Moda")

    func testFeedRequiresHundredMeters() {
        let near = GeoMath.offset(.modaKadikoy, north: 95, east: 0)
        let far = GeoMath.offset(.modaKadikoy, north: 105, east: 0)
        guard case .allowed = CheckInPolicy.precheck(kind: .fed, user: near, spot: spot) else { return XCTFail("95 m izinli olmalı") }
        guard case .tooFar(_, let max) = CheckInPolicy.precheck(kind: .fed, user: far, spot: spot) else { return XCTFail("105 m reddedilmeli") }
        XCTAssertEqual(max, 100)
    }

    func testRequestAllowsThreeHundredMeters() {
        let user = GeoMath.offset(.modaKadikoy, north: 0, east: 290)
        guard case .allowed = CheckInPolicy.precheck(kind: .needFood, user: user, spot: spot) else { return XCTFail() }
        let far = GeoMath.offset(.modaKadikoy, north: 0, east: 310)
        guard case .tooFar = CheckInPolicy.precheck(kind: .broken, user: far, spot: spot) else { return XCTFail() }
    }

    func testFuzzedSpotDefersToServer() {
        var fuzzed = spot
        fuzzed.isLocationExact = false
        XCTAssertEqual(CheckInPolicy.precheck(kind: .fed, user: .modaKadikoy, spot: fuzzed), .deferToServer)
        XCTAssertEqual(CheckInPolicy.precheck(kind: .fed, user: nil, spot: spot), .locationUnavailable)
    }

    func testQuickFeedPicksNearestWithinHundredMeters() {
        let a = Spot(coordinate: GeoMath.offset(.modaKadikoy, north: 80, east: 0), type: .food, species: .cat, title: "A")
        let b = Spot(coordinate: GeoMath.offset(.modaKadikoy, north: 30, east: 0), type: .food, species: .cat, title: "B")
        let c = Spot(coordinate: GeoMath.offset(.modaKadikoy, north: 150, east: 0), type: .food, species: .cat, title: "C")
        XCTAssertEqual(CheckInPolicy.quickFeedCandidate(user: .modaKadikoy, spots: [a, b, c])?.spot.title, "B")
        XCTAssertNil(CheckInPolicy.quickFeedCandidate(user: .modaKadikoy, spots: [c]))
    }
}

final class GeoTests: XCTestCase {
    func testHaversineMatchesKnownDistance() {
        // Moda iskele → Kadıköy iskele ≈ 1,6 km
        let moda = Coordinate(latitude: 40.98200, longitude: 29.02310)
        let kadikoy = Coordinate(latitude: 40.99260, longitude: 29.02380)
        XCTAssertEqual(GeoMath.distance(moda, kadikoy), 1180, accuracy: 20)
    }

    func testOffsetRoundTrip() {
        let moved = GeoMath.offset(.modaKadikoy, north: 100, east: 0)
        XCTAssertEqual(GeoMath.distance(.modaKadikoy, moved), 100, accuracy: 1)
    }

    func testFuzzIsDeterministicAndWithinRange() {
        for index in 0..<200 {
            let id = DemoData.id(9, index)
            let a = LocationFuzzer.fuzz(.modaKadikoy, seed: id)
            let b = LocationFuzzer.fuzz(.modaKadikoy, seed: id)
            XCTAssertEqual(a, b)
            let d = GeoMath.distance(.modaKadikoy, a)
            XCTAssertGreaterThanOrEqual(d, 49)
            XCTAssertLessThanOrEqual(d, 101)
        }
    }

    func testBoundsContainment() {
        let bounds = GeoBounds(center: .modaKadikoy, radiusMeters: 500)
        XCTAssertTrue(bounds.contains(GeoMath.offset(.modaKadikoy, north: 400, east: -400)))
        XCTAssertFalse(bounds.contains(GeoMath.offset(.modaKadikoy, north: 600, east: 0)))
        XCTAssertTrue(bounds.expanded(by: 2).contains(bounds))
    }
}

final class ClustererTests: XCTestCase {
    func spot(_ north: Double, _ east: Double, status: SpotStatus = .fedRecent) -> Spot {
        Spot(coordinate: GeoMath.offset(.modaKadikoy, north: north, east: east), type: .food, species: .cat, title: "s", status: status)
    }

    func testNoClusteringAtStreetLevel() {
        let spots = (0..<5).map { spot(Double($0) * 10, 0) }
        let bounds = GeoBounds(center: .modaKadikoy, latitudeDelta: 0.002, longitudeDelta: 0.002)
        XCTAssertEqual(SpotClusterer().clusters(for: spots, in: bounds).count, 5)
    }

    func testClustersAtCityLevelAndCountsNeedsFood() {
        let spots = [spot(0, 0, status: .needsFood), spot(5, 5, status: .needsFood), spot(10, 0), spot(3000, 3000)]
        let bounds = GeoBounds(center: .modaKadikoy, latitudeDelta: 0.1, longitudeDelta: 0.1)
        let clusters = SpotClusterer().clusters(for: spots, in: bounds)
        XCTAssertLessThan(clusters.count, spots.count)
        XCTAssertEqual(clusters.map(\.count).reduce(0, +), 4)
        let big = clusters.max { $0.count < $1.count }!
        XCTAssertEqual(big.needsFoodCount, 2)
    }

    func testOnlyVisibleSpotsAreClustered() {
        let bounds = GeoBounds(center: .modaKadikoy, latitudeDelta: 0.002, longitudeDelta: 0.002)
        XCTAssertTrue(SpotClusterer().clusters(for: [spot(5000, 0)], in: bounds).isEmpty)
    }
}

final class PolicyTests: XCTestCase {
    func istanbul(_ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: 30))!
    }

    func testQuietHoursWrapMidnight() {
        XCTAssertTrue(NotificationPolicy.isQuietHour(istanbul(23)))
        XCTAssertTrue(NotificationPolicy.isQuietHour(istanbul(2)))
        XCTAssertTrue(NotificationPolicy.isQuietHour(istanbul(6)))
        XCTAssertFalse(NotificationPolicy.isQuietHour(istanbul(7)))
        XCTAssertFalse(NotificationPolicy.isQuietHour(istanbul(21)))
        XCTAssertTrue(NotificationPolicy.isQuietHour(istanbul(13), startHour: 12, endHour: 14))
    }

    func testDailyPushCap() {
        let noon = istanbul(12)
        XCTAssertTrue(NotificationPolicy.canSendNeedFoodPush(sentToday: 2, at: noon, preferences: .default))
        XCTAssertFalse(NotificationPolicy.canSendNeedFoodPush(sentToday: 3, at: noon, preferences: .default))
        XCTAssertFalse(NotificationPolicy.canSendNeedFoodPush(sentToday: 0, at: istanbul(23), preferences: .default))
    }

    func testTrustPolicy() {
        XCTAssertEqual(TrustPolicy.dailySpotLimit(isVerifiedFeeder: false), 5)
        XCTAssertEqual(TrustPolicy.dailySpotLimit(isVerifiedFeeder: true), 30)
        XCTAssertTrue(TrustPolicy.requiresModeration(trustScore: 4))
        XCTAssertFalse(TrustPolicy.requiresModeration(trustScore: 5))
        XCTAssertTrue(TrustPolicy.qualifiesAsVerifiedFeeder(verifiedCheckInsLast30Days: 20))
        XCTAssertEqual(TrustPolicy.remainingForVerification(verifiedCheckInsLast30Days: 14), 6)
    }

    func testProfanityFilterTurkish() {
        XCTAssertTrue(ContentFilter.containsProfanity("Siktir git"))
        XCTAssertFalse(ContentFilter.containsProfanity("Apartmanın arka bahçesi, çitin yanı"))
        XCTAssertFalse(ContentFilter.containsProfanity("Göztepe parkı")) // "göt" kökü kelime başında değil
        XCTAssertTrue(ContentFilter.containsProfanity("aq"))
    }

    func testInactiveAfterThreeReports() {
        XCTAssertFalse(InactiveSpotPolicy.shouldDeactivate(distinctReporterCount: 2))
        XCTAssertTrue(InactiveSpotPolicy.shouldDeactivate(distinctReporterCount: 3))
    }
}

final class FilterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func make(_ title: String, species: SpotSpecies, fedHoursAgo: Double?, distance: Double, urgent: Bool = false, needsFood: Bool = false) -> Spot {
        Spot(coordinate: .modaKadikoy, type: .food, species: species, title: title,
             status: needsFood ? .needsFood : .unknown,
             lastFedAt: fedHoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
             hasUrgentNeed: urgent, distanceMeters: distance)
    }

    func testSpeciesFilterMatchesBoth() {
        let spots = [make("kedi", species: .cat, fedHoursAgo: 1, distance: 10),
                     make("köpek", species: .dog, fedHoursAgo: 1, distance: 20),
                     make("ikisi", species: .both, fedHoursAgo: 1, distance: 30)]
        let filter = SpotFilter(species: [.dog])
        XCTAssertEqual(filter.apply(to: spots, now: now).map(\.title), ["köpek", "ikisi"])
    }

    func testDistanceAndSort() {
        let spots = [make("yakın-tok", species: .cat, fedHoursAgo: 1, distance: 100),
                     make("uzak", species: .cat, fedHoursAgo: 2, distance: 4000),
                     make("aç", species: .cat, fedHoursAgo: 30, distance: 500),
                     make("hiç", species: .cat, fedHoursAgo: nil, distance: 800)]
        XCTAssertEqual(SpotFilter(maxDistanceKm: 3).apply(to: spots, now: now).map(\.title), ["yakın-tok", "aç", "hiç"])
        XCTAssertEqual(SpotFilter(maxDistanceKm: 3, sort: .longestUnfed).apply(to: spots, now: now).map(\.title), ["hiç", "aç", "yakın-tok"])
    }

    func testUrgentSortAndStatusFilter() {
        let spots = [make("normal", species: .cat, fedHoursAgo: 1, distance: 10),
                     make("acil", species: .cat, fedHoursAgo: 1, distance: 900, urgent: true),
                     make("mama", species: .cat, fedHoursAgo: 1, distance: 50, needsFood: true)]
        XCTAssertEqual(SpotFilter(sort: .urgent).apply(to: spots, now: now).map(\.title), ["acil", "mama", "normal"])
        XCTAssertEqual(SpotFilter(statuses: [.needsFood]).apply(to: spots, now: now).map(\.title), ["mama"])
    }

    func testOnlyFollowed() {
        let a = make("a", species: .cat, fedHoursAgo: 1, distance: 10)
        let b = make("b", species: .cat, fedHoursAgo: 1, distance: 20)
        XCTAssertEqual(SpotFilter(onlyFollowed: true).apply(to: [a, b], followedIds: [b.id], now: now).map(\.title), ["b"])
    }

    func testNeedSortingUrgentFirstThenDistance() {
        let needs = [
            Need(type: .shelter, description: "a", distanceMeters: 50),
            Need(type: .vet, urgency: .urgent, description: "b", distanceMeters: 900),
            Need(type: .water, status: .claimed, description: "c", distanceMeters: 10),
            Need(type: .meds, description: "d", distanceMeters: 20),
        ]
        XCTAssertEqual(NeedSorting.sorted(needs).map(\.description), ["b", "d", "a", "c"])
    }

    func testDistanceClamp() {
        XCTAssertEqual(SpotFilter(maxDistanceKm: 50).maxDistanceKm, 10)
        XCTAssertEqual(SpotFilter(maxDistanceKm: 0.2).maxDistanceKm, 1)
    }
}

final class FormattingTests: XCTestCase {
    func testDistance() {
        XCTAssertEqual(MamaFormat.distance(42, language: .turkish), "40 m")
        XCTAssertEqual(MamaFormat.distance(1234, language: .turkish), "1,2 km")
        XCTAssertEqual(MamaFormat.distance(1234, language: .english), "1.2 km")
    }

    func testRelative() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(MamaFormat.relative(now.addingTimeInterval(-20), now: now, language: .turkish), "az önce")
        XCTAssertEqual(MamaFormat.relative(now.addingTimeInterval(-5 * 60), now: now, language: .turkish), "5 dk önce")
        XCTAssertEqual(MamaFormat.relative(now.addingTimeInterval(-3 * 3600), now: now, language: .turkish), "3 sa önce")
        XCTAssertEqual(MamaFormat.relative(now.addingTimeInterval(-50 * 3600), now: now, language: .english), "2d ago")
    }

    func testMoneyAndKg() {
        XCTAssertEqual(MamaFormat.usd(5, language: .turkish), "5 USD")
        XCTAssertEqual(MamaFormat.kilograms(1234, language: .turkish), "1.234 kg")
    }

    func testDonationLinkCarriesUTMAndRef() throws {
        let config = DonationConfig(partnerName: "Dernek", donationURL: URL(string: "https://example.org/bagis?lang=tr"), usdToTry: 41.5)
        let url = try XCTUnwrap(config.link(for: .cat, quantity: 2, refCode: "ABC123"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["lang"], "tr")
        XCTAssertEqual(dict["utm_source"], "mamaharitasi")
        XCTAssertEqual(dict["package"], "cat_5")
        XCTAssertEqual(dict["qty"], "2")
        XCTAssertEqual(dict["ref"], "ABC123")
        XCTAssertEqual(config.tryAmount(for: .dog, quantity: 1), 291)
        XCTAssertNil(DonationConfig.placeholder.link(for: .cat, quantity: 1, refCode: "x"))
    }
}
