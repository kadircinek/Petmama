import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class ConversationsViewModel {
    public private(set) var items: [ConversationSummary] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var totalUnread: Int { items.reduce(0) { $0 + $1.unreadCount } }
    public var isEmpty: Bool { hasLoaded && !isLoading && error == nil && items.isEmpty }

    public func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            items = try await services.social.conversations()
        } catch {
            self.error = MamaError.classify(error)
        }
    }
}

extension ConversationSummary {
    /// Görünen başlık. Karşı tarafın hesabı silinmiş bire bir sohbette sunucunun Türkçe sabiti yerine yerelleştirilmiş metin.
    public var displayTitle: String {
        if kind == .direct, otherUserId == nil { return String(localized: "Silinmiş kullanıcı") }
        return title
    }
}
