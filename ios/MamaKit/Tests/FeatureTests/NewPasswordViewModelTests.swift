import XCTest
import MamaCore
import FeatureOnboarding

@MainActor
final class NewPasswordViewModelTests: XCTestCase {
    private func makeSignedInSession() async -> SessionStore {
        let services = AppServices.demo()
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        _ = await session.signIn(email: SignInViewModel.demoEmail, password: SignInViewModel.demoPassword)
        return session
    }

    func testShortPasswordIsRejected() async {
        let session = await makeSignedInSession()
        let model = NewPasswordViewModel()
        model.password = "kisa"
        model.confirmation = "kisa"
        let ok = await model.submit(session: session)
        XCTAssertFalse(ok)
        XCTAssertEqual(model.errorMessage, "Şifren en az 8 karakter olmalı.")
    }

    func testMismatchedConfirmationIsRejected() async {
        let session = await makeSignedInSession()
        let model = NewPasswordViewModel()
        model.password = "yeniSifre123"
        model.confirmation = "yeniSifre124"
        let ok = await model.submit(session: session)
        XCTAssertFalse(ok)
        XCTAssertEqual(model.errorMessage, "İki şifre aynı değil.")
    }

    func testValidPasswordIsSavedAndUsableForSignIn() async {
        let session = await makeSignedInSession()
        let model = NewPasswordViewModel()
        model.password = "yeniSifre123"
        model.confirmation = "yeniSifre123"
        let ok = await model.submit(session: session)
        XCTAssertTrue(ok)
        XCTAssertNil(model.errorMessage)

        await session.signOut()
        let reSignIn = await session.signIn(email: SignInViewModel.demoEmail, password: "yeniSifre123")
        XCTAssertTrue(reSignIn, "yeni şifreyle giriş yapılabilmeli")
    }
}
