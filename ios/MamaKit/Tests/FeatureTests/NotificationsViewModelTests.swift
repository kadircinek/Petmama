import XCTest
import MamaCore
import FeatureProfile

/// Sabit bildirim listesi dönen sahte depo.
private actor StubNotificationRepository: NotificationRepository {
    private(set) var items: [AppNotification]
    private(set) var markedIds: [UUID] = []

    init(items: [AppNotification]) { self.items = items }

    func notifications() async throws -> [AppNotification] { items }
    func markRead(ids: [UUID]) async throws { markedIds.append(contentsOf: ids) }
    func preferences() async throws -> NotificationPreferences { .default }
    func updatePreferences(_ preferences: NotificationPreferences) async throws {}
    func registerDeviceToken(_ token: String) async throws {}
    func updateNotifyCenter(_ coordinate: Coordinate) async throws {}
}

@MainActor
final class NotificationsViewModelTests: XCTestCase {
    private func istanbul(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func item(_ title: String, at date: Date, kind: NotificationKind = .needFoodNearby, read: Bool = false) -> AppNotification {
        AppNotification(kind: kind, title: title, body: "", spotId: DemoData.id(2, 1), readAt: read ? date : nil, createdAt: date)
    }

    func testGroupingUsesIstanbulMidnight() async {
        // İstanbul'da 4 Kasım 00:30 = UTC 3 Kasım 21:30.
        let now = istanbul(4, 0, 30)
        let items = [
            item("dün gece", at: istanbul(3, 23, 50)),
            item("bu gece", at: istanbul(4, 0, 10)),
            item("dün sabah", at: istanbul(3, 10, 0)),
            item("az önce", at: istanbul(4, 0, 20)),
        ]
        let sections = NotificationsViewModel.group(items, now: now)
        XCTAssertEqual(sections.map(\.kind), [.today, .earlier])
        XCTAssertEqual(sections.map(\.title), ["Bugün", "Daha önce"])
        XCTAssertEqual(sections[0].items.map(\.title), ["az önce", "bu gece"])
        XCTAssertEqual(sections[1].items.map(\.title), ["dün gece", "dün sabah"])

        // Aynı anlar UTC'ye göre gruplansaydı hepsi "bugün" olurdu.
        let utc = NotificationsViewModel.group(items, now: now, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(utc.map(\.kind), [.today])
        XCTAssertEqual(utc[0].items.count, 4)
    }

    func testEmptySectionsAreOmitted() async {
        let now = istanbul(4, 12, 0)
        XCTAssertTrue(NotificationsViewModel.group([], now: now).isEmpty)
        let onlyOld = NotificationsViewModel.group([item("eski", at: istanbul(1, 9, 0))], now: now)
        XCTAssertEqual(onlyOld.map(\.kind), [.earlier])
    }

    func testViewModelGroupsWithServicesClockAndMarksAllRead() async {
        let now = istanbul(4, 0, 30)
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { now })
        var services = AppServices.inMemory(backend, now: { now })
        let stub = StubNotificationRepository(items: [
            item("bugün okunmamış", at: istanbul(4, 0, 5)),
            item("dün okunmuş", at: istanbul(3, 23, 59), read: true),
            item("dün okunmamış", at: istanbul(3, 8, 0), kind: .thanksFed),
        ])
        services.notifications = stub
        let model = NotificationsViewModel(services: services)
        await model.load()

        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.sections.map(\.kind), [.today, .earlier])
        XCTAssertEqual(model.sections[0].items.map(\.title), ["bugün okunmamış"])
        XCTAssertEqual(model.unreadCount, 2)
        XCTAssertEqual(model.relativeTime(for: model.sections[0].items[0]), MamaFormat.relative(istanbul(4, 0, 5), now: now))

        await model.markAllRead()
        XCTAssertEqual(model.unreadCount, 0)
        XCTAssertFalse(model.hasUnread)
        let marked = await stub.markedIds
        XCTAssertEqual(marked.count, 2, "yalnızca okunmamışlar gönderilir")
    }

    func testOpeningNotificationMarksReadAndRoutesToSpot() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: true, now: { now })
        let services = AppServices.inMemory(backend, now: { now })
        // Emre "mama gerekli" der → demo kullanıcı bildirim alır.
        let spotId = DemoData.id(2, 1)
        let raw = await backend.rawSpot(spotId)
        let spot = try XCTUnwrap(raw)
        await backend.setCurrentUser(DemoData.emreId)
        _ = try await backend.checkIn(CheckInDraft(spotId: spotId, kind: .needFood, userCoordinate: GeoMath.offset(spot.coordinate, north: 30, east: 0)))
        await backend.setCurrentUser(DemoData.meId)

        let model = NotificationsViewModel(services: services)
        await model.load()
        XCTAssertEqual(model.sections.map(\.kind), [.today])
        let notification = try XCTUnwrap(model.items.first)
        XCTAssertEqual(notification.kind, .needFoodNearby)
        XCTAssertEqual(model.unreadCount, 1)

        let route = await model.open(notification)
        XCTAssertEqual(route, .spot(spotId))
        XCTAssertEqual(model.unreadCount, 0)
        let stored = await backend.notifications(for: DemoData.meId)
        XCTAssertEqual(stored.first?.isRead, true)
    }

    func testRoutes() async {
        let needId = DemoData.id(5, 1)
        let spotId = DemoData.id(2, 7)
        let resolved = AppNotification(kind: .needResolved, title: "", body: "", spotId: spotId, needId: needId)
        let spotOnly = AppNotification(kind: .followedSpotChanged, title: "", body: "", spotId: spotId)
        let donation = AppNotification(kind: .donationDelivered, title: "", body: "")
        let bare = AppNotification(kind: .thanksFed, title: "", body: "")
        XCTAssertEqual(NotificationsViewModel.route(for: resolved), .need(needId))
        XCTAssertEqual(NotificationsViewModel.route(for: spotOnly), .spot(spotId))
        XCTAssertEqual(NotificationsViewModel.route(for: donation), .donationTrace)
        XCTAssertNil(NotificationsViewModel.route(for: bare))
    }
}
