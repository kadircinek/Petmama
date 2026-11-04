import Foundation
import Observation
import MamaCore

/// Bildirimler (ekran 22): "Bugün" / "Daha önce". Gün sınırı İstanbul saatine göre.
@MainActor
@Observable
public final class NotificationsViewModel {
    public enum SectionKind: String, Sendable, Hashable, CaseIterable {
        case today, earlier

        public var title: String {
            switch self {
            case .today: return "Bugün"
            case .earlier: return "Daha önce"
            }
        }
    }

    public struct Section: Identifiable, Hashable, Sendable {
        public let kind: SectionKind
        public let items: [AppNotification]

        public var id: SectionKind { kind }
        public var title: String { kind.title }
    }

    public private(set) var items: [AppNotification] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var sections: [Section] { Self.group(items, now: services.now()) }

    public var unreadCount: Int { items.filter { !$0.isRead }.count }
    public var hasUnread: Bool { unreadCount > 0 }
    public var isEmpty: Bool { items.isEmpty }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await services.notifications.notifications()
            hasLoaded = true
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    /// Satıra dokunuldu: okundu işaretler, açılacak rotayı döner.
    @discardableResult
    public func open(_ notification: AppNotification) async -> AppRoute? {
        if !notification.isRead {
            await markRead([notification.id])
        }
        return Self.route(for: notification)
    }

    public func markAllRead() async {
        let ids = items.filter { !$0.isRead }.map(\.id)
        guard !ids.isEmpty else { return }
        await markRead(ids)
    }

    public func relativeTime(for notification: AppNotification) -> String {
        MamaFormat.relative(notification.createdAt, now: services.now())
    }

    // MARK: - Saf kurallar

    /// Bugün = İstanbul saatiyle bu gece yarısından sonra. Her bölüm yeniden eskiye sıralıdır; boş bölüm yok.
    public static func group(
        _ items: [AppNotification],
        now: Date,
        timeZone: TimeZone = NotificationPolicy.timeZone
    ) -> [Section] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        let sections = [
            Section(kind: .today, items: sorted.filter { $0.createdAt >= startOfToday }),
            Section(kind: .earlier, items: sorted.filter { $0.createdAt < startOfToday }),
        ]
        return sections.filter { !$0.items.isEmpty }
    }

    /// İhtiyaç bildirimi ihtiyaca, nokta bildirimi noktaya, teslim bildirimi "Bağışım nereye gitti?" ekranına.
    public static func route(for notification: AppNotification) -> AppRoute? {
        if let needId = notification.needId { return .need(needId) }
        if let spotId = notification.spotId { return .spot(spotId) }
        if notification.kind == .donationDelivered { return .donationTrace }
        return nil
    }

    // MARK: - Yardımcılar

    private func markRead(_ ids: [UUID]) async {
        do {
            try await services.notifications.markRead(ids: ids)
            let readAt = services.now()
            let set = Set(ids)
            items = items.map { item in
                guard set.contains(item.id), item.readAt == nil else { return item }
                var copy = item
                copy.readAt = readAt
                return copy
            }
        } catch {
            self.error = MamaError.classify(error)
        }
    }
}
