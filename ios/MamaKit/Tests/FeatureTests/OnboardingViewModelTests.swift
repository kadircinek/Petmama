import XCTest
import MamaCore
import FeatureOnboarding

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testStartsOnFirstIntroPageWithSkip() async {
        let model = OnboardingViewModel()
        XCTAssertEqual(model.step, .intro(0))
        XCTAssertEqual(model.introIndex, 0)
        XCTAssertTrue(model.showsSkip)
        XCTAssertFalse(model.isFinished)
        XCTAssertEqual(OnboardingViewModel.introPageCount, 3)
        XCTAssertEqual(OnboardingViewModel.introPages.map(\.title), [
            "Haritada mama noktalarını gör", "Mama koy, bildir", "Bağışla destek ol",
        ])
    }

    func testAdvanceWalksThroughEveryStep() async {
        let model = OnboardingViewModel()
        var visited: [OnboardingViewModel.Step] = [model.step]
        while !model.isFinished {
            model.advance()
            if !model.isFinished { visited.append(model.step) }
        }
        XCTAssertEqual(visited, [.intro(0), .intro(1), .intro(2), .location, .notifications, .signIn])
        XCTAssertEqual(model.steps, visited)
    }

    func testSkipJumpsFromAnyIntroPageToLocation() async {
        let model = OnboardingViewModel()
        model.advance()
        XCTAssertEqual(model.step, .intro(1))
        model.skipIntro()
        XCTAssertEqual(model.step, .location)
        XCTAssertFalse(model.showsSkip)
        XCTAssertNil(model.introIndex)
    }

    func testPrepareSkipsDecidedPermissionsAndSignIn() async {
        let partial = OnboardingViewModel()
        partial.prepare(locationDecided: true, notificationsDecided: false, signedIn: false)
        partial.skipIntro()
        XCTAssertEqual(partial.step, .notifications)
        partial.notNow()
        XCTAssertEqual(partial.step, .signIn)

        let everythingDone = OnboardingViewModel()
        everythingDone.prepare(locationDecided: true, notificationsDecided: true, signedIn: true)
        XCTAssertEqual(everythingDone.steps, [.intro(0), .intro(1), .intro(2)])
        everythingDone.skipIntro()
        XCTAssertTrue(everythingDone.isFinished)
    }

    func testLocationAndNotificationRequestsRecordResultAndAdvance() async {
        let model = OnboardingViewModel()
        model.skipIntro()
        await model.requestLocation { .authorized }
        XCTAssertEqual(model.locationResult, .authorized)
        XCTAssertEqual(model.step, .notifications)
        XCTAssertFalse(model.isRequesting)

        await model.requestNotifications { false }
        XCTAssertEqual(model.notificationsGranted, false)
        XCTAssertEqual(model.step, .signIn)

        // "Şimdilik gez"
        model.finish()
        XCTAssertTrue(model.isFinished)
    }

    func testNotNowSkipsPermissionWithoutRecording() async {
        let model = OnboardingViewModel()
        model.skipIntro()
        model.notNow()
        XCTAssertEqual(model.step, .notifications)
        XCTAssertNil(model.locationResult)
        model.notNow()
        XCTAssertEqual(model.step, .signIn)
        XCTAssertNil(model.notificationsGranted)
        model.notNow()
        XCTAssertTrue(model.isFinished)
    }

    func testRequestsOutsideTheirStepAreIgnored() async {
        let model = OnboardingViewModel()
        var asked = false
        await model.requestLocation {
            asked = true
            return .authorized
        }
        XCTAssertFalse(asked)
        XCTAssertEqual(model.step, .intro(0))
        model.notNow()
        XCTAssertEqual(model.step, .intro(0), "'Şimdi değil' tanıtım sayfalarında yok")
    }

    func testShowIntroClampsPageIndex() async {
        let model = OnboardingViewModel()
        model.showIntro(page: 5)
        XCTAssertEqual(model.step, .intro(2))
        XCTAssertTrue(model.isLastIntroPage)
        model.showIntro(page: -1)
        XCTAssertEqual(model.step, .intro(0))
        model.skipIntro()
        model.showIntro(page: 1)
        XCTAssertEqual(model.step, .location, "izin adımındayken sayfa kaydırma etkisiz")
    }
}
