import Foundation
import Observation
import MamaCore

/// Arama ekranı (ekran 12): son aramalar (son 8, UserDefaults), popüler aramalar ve sonuçlar.
@MainActor
@Observable
public final class SearchViewModel {
    /// Popüler aramalar. "Moda Parkı" metin araması; diğer ikisi yakındaki noktaları süzer.
    public enum PopularSearch: String, CaseIterable, Hashable, Sendable {
        case modaPark
        case catHouses
        case needsFood

        public var title: String {
            switch self {
            case .modaPark: return "Moda Parkı"
            case .catHouses: return "Kedi evleri"
            case .needsFood: return "Mama gerekli"
            }
        }

        public var systemImage: String {
            switch self {
            case .modaPark: return "tree.fill"
            case .catHouses: return "house.fill"
            case .needsFood: return "exclamationmark.circle.fill"
            }
        }
    }

    public static let recentLimit = 8
    public static let recentsKey = "mama.search.recent"
    public static let nearbyRadiusMeters = 3000

    public var query = ""
    public internal(set) var results: [Spot] = []
    public internal(set) var recentSearches: [String]
    public internal(set) var activePopular: PopularSearch?
    public internal(set) var isSearching = false
    public internal(set) var hasSearched = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastSearchedText: String?

    public init(services: AppServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        self.recentSearches = Array((defaults.stringArray(forKey: Self.recentsKey) ?? []).prefix(Self.recentLimit))
    }

    public var now: Date { services.now() }

    public var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Arama kutusu boş ve popüler bir arama seçili değilken öneriler gösterilir.
    public var showsSuggestions: Bool {
        trimmedQuery.isEmpty && activePopular == nil
    }

    /// Metin araması (yazarken gecikmeli çağrılır).
    public func search(near center: Coordinate?) async {
        let text = trimmedQuery
        guard !text.isEmpty else {
            if activePopular == nil {
                results = []
                hasSearched = false
                lastSearchedText = nil
            }
            return
        }
        if activePopular == nil, hasSearched, text == lastSearchedText { return }
        activePopular = nil
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await services.spots.search(query: text, near: center)
            guard text == trimmedQuery else { return }
            results = found
            hasSearched = true
            lastSearchedText = text
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func runPopular(_ popular: PopularSearch, near center: Coordinate?) async {
        switch popular {
        case .modaPark:
            query = popular.title
            await search(near: center)
            record(popular.title)
        case .catHouses, .needsFood:
            activePopular = popular
            isSearching = true
            defer { isSearching = false }
            let origin = center ?? .modaKadikoy
            do {
                let nearby = try await services.spots.spots(near: origin, radiusMeters: Self.nearbyRadiusMeters)
                guard activePopular == popular else { return }
                results = Self.matches(nearby, for: popular, now: now)
                hasSearched = true
                error = nil
            } catch {
                self.error = MamaError.classify(error)
            }
        }
    }

    public func clearPopular() {
        activePopular = nil
        results = []
        hasSearched = false
        lastSearchedText = nil
    }

    /// Arama gönderildiğinde veya bir sonuç açıldığında metni son aramalara ekler.
    public func commitCurrentQuery() {
        record(trimmedQuery)
    }

    public func record(_ term: String) {
        let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let key = Self.normalized(cleaned)
        var updated = recentSearches.filter { Self.normalized($0) != key }
        updated.insert(cleaned, at: 0)
        recentSearches = Array(updated.prefix(Self.recentLimit))
        defaults.set(recentSearches, forKey: Self.recentsKey)
    }

    public func removeRecent(_ term: String) {
        recentSearches.removeAll { $0 == term }
        defaults.set(recentSearches, forKey: Self.recentsKey)
    }

    public func clearRecents() {
        recentSearches = []
        defaults.removeObject(forKey: Self.recentsKey)
    }

    static func matches(_ spots: [Spot], for popular: PopularSearch, now: Date) -> [Spot] {
        switch popular {
        case .modaPark:
            return spots
        case .catHouses:
            return spots.filter { $0.type == .shelter && $0.species.matches(.cat) }
        case .needsFood:
            return spots.filter { $0.currentStatus(now: now) == .needsFood }
        }
    }

    private static func normalized(_ term: String) -> String {
        term.lowercased(with: Locale(identifier: "tr_TR"))
    }
}
