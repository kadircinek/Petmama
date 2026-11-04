import XCTest
import MamaCore
@testable import FeatureDonate

@MainActor
final class DonationTraceViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeServices() -> AppServices {
        let fixed = now
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: false, now: { fixed })
        return AppServices.inMemory(backend, now: { fixed })
    }

    func testStepsMarkDeliveryAsComingInV11() async {
        let model = DonationTraceViewModel(services: makeServices())
        let steps = model.steps
        XCTAssertEqual(steps.map(\.title), ["Bağış alındı", "Toplu mama alımı", "Noktalara teslim", "Sana bildirim"])
        XCTAssertEqual(steps.map(\.isAvailable), [true, false, false, false])
        XCTAssertTrue(steps[3].detail.contains("40 kg mama Kadıköy'de 12 noktaya ulaştı"))
        XCTAssertEqual(DonationTraceViewModel.comingSoonLabel, "v1.1'de")
    }

    func testLoadsCurrentMonthOverview() async {
        let model = DonationTraceViewModel(services: makeServices())
        XCTAssertNil(model.kilogramsText)
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.kilogramsText, "412 kg")
        XCTAssertEqual(model.donorCountText, "37 bağışçı")
        XCTAssertNotNil(model.monthTitle)
    }
}
