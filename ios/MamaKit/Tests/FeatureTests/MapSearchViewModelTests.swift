import Foundation
import XCTest
import MamaCore
@testable import FeatureMap

@MainActor
final class SearchViewModelTests: XCTestCase {
    private lazy var defaults: UserDefaults = makeDefaults()

    /// Her test kendi UserDefaults alanını kullanır; test bitince silinir.
    private func makeDefaults() -> UserDefaults {
        let name = "mama.search.tests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name) ?? UserDefaults()
    }

    private func makeModel() -> SearchViewModel {
        SearchViewModel(services: MapSpotsFixture.services().services, defaults: defaults)
    }

    func testTextSearchReturnsNearestFirst() async {
        let model = makeModel()
        model.query = "moda"
        await model.search(near: .modaKadikoy)

        let results = model.results
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.title.lowercased().contains("moda") || ($0.note ?? "").lowercased().contains("moda") })
        let distances = results.compactMap(\.distanceMeters)
        XCTAssertEqual(distances, distances.sorted())
        XCTAssertTrue(model.hasSearched)
        XCTAssertFalse(model.showsSuggestions)
    }

    func testRecentSearchesPersistDedupeAndCapAtEight() async {
        let model = makeModel()
        for index in 1...10 { model.record("Sokak \(index)") }
        model.record("sokak 5")

        XCTAssertEqual(model.recentSearches.count, SearchViewModel.recentLimit)
        XCTAssertEqual(model.recentSearches.first, "sokak 5")
        XCTAssertEqual(model.recentSearches.filter { $0.lowercased() == "sokak 5" }.count, 1)

        let reloaded = makeModel()
        XCTAssertEqual(reloaded.recentSearches, model.recentSearches)

        reloaded.removeRecent("sokak 5")
        XCTAssertFalse(reloaded.recentSearches.contains("sokak 5"))
        reloaded.clearRecents()
        XCTAssertTrue(makeModel().recentSearches.isEmpty)
    }

    func testCommitIgnoresBlankQuery() async {
        let model = makeModel()
        model.query = "   "
        model.commitCurrentQuery()
        XCTAssertTrue(model.recentSearches.isEmpty)
    }

    func testPopularNeedsFoodShowsOnlyOrangeSpots() async {
        let model = makeModel()
        await model.runPopular(.needsFood, near: .modaKadikoy)

        let ids = Set(model.results.map(\.id))
        XCTAssertEqual(model.activePopular, .needsFood)
        XCTAssertEqual(ids, [DemoData.id(2, 6), DemoData.id(2, 11), DemoData.id(2, 16)])
        XCTAssertFalse(model.showsSuggestions)

        // Ekrana geri dönünce boş metinle arama popüler sonuçları silmemeli.
        await model.search(near: .modaKadikoy)
        XCTAssertEqual(model.results.count, 3)

        model.clearPopular()
        XCTAssertTrue(model.showsSuggestions)
    }

    func testPopularCatHousesShowsShelters() async {
        let model = makeModel()
        await model.runPopular(.catHouses, near: .modaKadikoy)

        let results = model.results
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.type == .shelter && $0.species.matches(.cat) })
    }

    func testPopularModaParkRunsTextSearchAndRecordsIt() async {
        let model = makeModel()
        await model.runPopular(.modaPark, near: .modaKadikoy)

        XCTAssertEqual(model.query, "Moda Parkı")
        XCTAssertEqual(model.results.first?.id, DemoData.id(2, 1))
        XCTAssertEqual(model.recentSearches.first, "Moda Parkı")
    }

    func testOfflineSearchSurfacesError() async {
        let services = MapSpotsFixture.offlineServices(backend: MapSpotsFixture.backend())
        let model = SearchViewModel(services: services, defaults: defaults)
        model.query = "moda"
        await model.search(near: nil)
        XCTAssertEqual(model.error, .offline)
    }
}
