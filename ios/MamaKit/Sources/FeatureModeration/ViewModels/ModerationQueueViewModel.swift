import Foundation
import Observation
import MamaCore

/// Moderasyon kuyruğu (Faz 3.1): hedefe göre gruplanmış raporlar. Sekmeler: Açık (varsayılan) / Kapananlar (son 30 gün).
/// Rota: `AppRoute.moderation`. Moderatörlük sunucuda doğrulanır; moderatör olmayana kuyruk boş döner.
@MainActor
@Observable
public final class ModerationQueueViewModel {
    public enum Tab: String, CaseIterable, Hashable, Sendable {
        case open, closed
    }

    public static let pageSize = 50

    public private(set) var tab: Tab = .open
    public private(set) var cases: [ModerationCase] = []
    /// Açık vaka sayısı (sekme başlığı ve Profil rozeti ile aynı).
    public private(set) var openCount = 0
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var isEmpty: Bool { hasLoaded && cases.isEmpty }

    public var emptyTitle: String {
        switch tab {
        case .open: return "Bekleyen rapor yok"
        case .closed: return "Son \(ModerationPolicy.closedWindowDays) günde kapanan rapor yok"
        }
    }

    public var emptyMessage: String {
        switch tab {
        case .open: return "Yeni bir rapor geldiğinde burada görünür. Raporlara 24 saat içinde bakmaya çalış."
        case .closed: return "Verdiğin kararlar burada listelenir."
        }
    }

    public func select(_ tab: Tab) async {
        guard tab != self.tab else { return }
        self.tab = tab
        cases = []
        hasLoaded = false
        await load()
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        let requested = tab
        do {
            let loaded = try await services.moderator.moderationQueue(closed: requested == .closed, limit: Self.pageSize)
            guard requested == tab else { return }
            cases = loaded
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
        if let count = try? await services.moderator.openCaseCount() {
            openCount = count
        }
    }
}
