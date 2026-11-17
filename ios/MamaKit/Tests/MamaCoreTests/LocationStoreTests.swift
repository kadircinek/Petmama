import XCTest
@testable import MamaCore

/// iOS, sürekli konum takibi açıkken `requestLocation`'a cevap vermeyebilir; kullanıcı yerinde
/// durduğunda yeni konum da gelmez. `LocationStore.refresh` böyle bir sürücüde asla takılmamalı.
@MainActor
private final class HangingLocationDriver: LocationDriver {
    var authorization: LocationAuthorization = .authorized
    var onUpdate: ((Coordinate) -> Void)?

    func requestAuthorization() async -> LocationAuthorization { authorization }
    func currentLocation() async -> Coordinate? {
        // Hiç dönmeyen istek (iptal edilene kadar).
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 50_000_000) }
        return nil
    }
    func startUpdating() {}
    func stopUpdating() {}
}

@MainActor
final class LocationStoreTests: XCTestCase {
    func testRefreshDoesNotHangWhenDriverNeverAnswers() async {
        let driver = HangingLocationDriver()
        let store = LocationStore(driver: driver, refreshTimeout: .milliseconds(200))
        driver.onUpdate?(.modaKadikoy)  // takipten gelmiş son konum

        let started = Date()
        let result = await store.refresh()

        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "refresh zaman aşımında dönmeli")
        XCTAssertEqual(result, .modaKadikoy, "taze konum gelmezse bilinen son konum kullanılır")
    }

    func testRefreshReturnsNilWithoutAnyKnownLocation() async {
        let store = LocationStore(driver: HangingLocationDriver(), refreshTimeout: .milliseconds(100))
        let result = await store.refresh()
        XCTAssertNil(result)
    }
}
