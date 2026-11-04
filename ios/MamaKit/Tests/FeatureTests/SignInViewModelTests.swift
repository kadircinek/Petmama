import XCTest
import MamaCore
import FeatureOnboarding

private let signInNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
final class SignInViewModelTests: XCTestCase {
    private func makeEnvironment(signedIn: Bool = false, config: AppConfig? = nil) -> (SignInViewModel, SessionStore, AppServices) {
        let now = signInNow
        let backend = InMemoryBackend(seed: DemoData.make(now: now), signedIn: signedIn, now: { now })
        let services = AppServices.inMemory(backend, config: config, now: { now })
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        return (SignInViewModel(services: services), session, services)
    }

    func testEmailValidation() async {
        XCTAssertTrue(SignInViewModel.isValidEmail("demo@mamaharitasi.app"))
        XCTAssertTrue(SignInViewModel.isValidEmail("  ayse.k@moda.org.tr "))
        XCTAssertFalse(SignInViewModel.isValidEmail(""))
        XCTAssertFalse(SignInViewModel.isValidEmail("ayse"))
        XCTAssertFalse(SignInViewModel.isValidEmail("@moda.org"))
        XCTAssertFalse(SignInViewModel.isValidEmail("ayse@moda"))
        XCTAssertFalse(SignInViewModel.isValidEmail("ayse@@moda.org"))
        XCTAssertFalse(SignInViewModel.isValidEmail("ay se@moda.org"))
    }

    func testValidationBlocksSubmitWithoutCallingBackend() async {
        let (model, session, _) = makeEnvironment()
        model.email = "demo"
        model.password = "demo1234"
        let invalidEmail = await model.submit(session: session)
        XCTAssertFalse(invalidEmail)
        XCTAssertEqual(model.errorMessage, "Geçerli bir e-posta adresi yazar mısın?")

        model.email = SignInViewModel.demoEmail
        model.password = "kisa"
        let shortPassword = await model.submit(session: session)
        XCTAssertFalse(shortPassword)
        XCTAssertEqual(model.errorMessage, "Şifren en az 8 karakter olmalı.")
        XCTAssertNil(session.lastError, "doğrulama hatasında sunucuya gidilmez")
        XCTAssertFalse(session.isSignedIn)
    }

    func testWrongDemoPasswordShowsFriendlyError() async {
        let (model, session, _) = makeEnvironment()
        model.email = SignInViewModel.demoEmail
        model.password = "yanlis-sifre"
        let succeeded = await model.submit(session: session)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.errorMessage, MamaError.invalidCredentials.userMessage)
        XCTAssertFalse(session.isSignedIn)
        XCTAssertFalse(model.isWorking)
    }

    func testDemoCredentialsSignIn() async {
        let (model, session, _) = makeEnvironment()
        model.fillDemoCredentials()
        XCTAssertEqual(model.email, "demo@mamaharitasi.app")
        XCTAssertEqual(model.password, "demo1234")
        XCTAssertTrue(model.canSubmit)
        let succeeded = await model.submit(session: session)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(session.userId, DemoData.meId)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.password, "", "başarılı girişten sonra şifre bellekte tutulmaz")
    }

    func testSignUpValidation() async {
        let (model, session, _) = makeEnvironment()
        model.switchMode(to: .signUp)
        model.email = "yeni@mamaharitasi.app"
        model.password = "guvenli123"
        XCTAssertFalse(model.canSubmit, "kayıtta isim zorunlu")
        let withoutName = await model.submit(session: session)
        XCTAssertFalse(withoutName)
        XCTAssertEqual(model.errorMessage, "Sana nasıl hitap edelim? Bir isim yaz.")

        model.displayName = "siktir git"
        let profane = await model.submit(session: session)
        XCTAssertFalse(profane)
        XCTAssertEqual(model.errorMessage, MamaError.rejectedContent.userMessage)

        model.displayName = String(repeating: "a", count: SignInViewModel.maximumDisplayNameLength + 1)
        XCTAssertEqual(model.validationIssue, "İsim en fazla 40 karakter olabilir.")
    }

    func testSignUpWithExistingEmailFails() async {
        let (model, session, _) = makeEnvironment()
        model.switchMode(to: .signUp)
        model.displayName = "Deniz"
        model.email = SignInViewModel.demoEmail
        model.password = "baskasifre1"
        let succeeded = await model.submit(session: session)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.errorMessage, MamaError.emailAlreadyInUse.userMessage)
    }

    func testSignUpCreatesAccount() async {
        let (model, session, _) = makeEnvironment()
        model.switchMode(to: .signUp)
        model.displayName = "  Deniz  "
        model.email = " deniz@moda.org "
        model.password = "guvenli123"
        let succeeded = await model.submit(session: session)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(session.profile?.displayName, "Deniz")
        XCTAssertNotEqual(session.userId, DemoData.meId)
    }

    func testDemoHintOnlyInDemoMode() async {
        let (demo, _, _) = makeEnvironment()
        XCTAssertTrue(demo.showsDemoHint)
        let (production, _, _) = makeEnvironment(config: AppConfig(isDemo: false))
        XCTAssertFalse(production.showsDemoHint)
    }

    func testPasswordResetNeedsEmail() async {
        let (model, _, _) = makeEnvironment()
        let withoutEmail = await model.sendPasswordReset()
        XCTAssertFalse(withoutEmail)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.infoMessage)

        model.email = "ayse@moda.org"
        let sent = await model.sendPasswordReset()
        XCTAssertTrue(sent)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.infoMessage?.contains("ayse@moda.org"), true)
    }

    func testAppleSignInSignsInDemoUserWithTrimmedName() async {
        let (model, session, _) = makeEnvironment()
        let succeeded = await model.signInWithApple(idToken: "token", nonce: "raw-nonce", fullName: "  Ece Yılmaz ", session: session)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(session.userId, DemoData.meId)
        XCTAssertEqual(session.profile?.displayName, "Ece Yılmaz")
    }

    func testAppleCancellationShowsNoErrorButFailureDoes() async {
        let (model, _, _) = makeEnvironment()
        model.appleSignInFailed(canceled: true)
        XCTAssertNil(model.errorMessage)
        model.appleSignInFailed(canceled: false)
        XCTAssertNotNil(model.errorMessage)
    }

    func testSwitchingModeClearsMessages() async {
        let (model, session, _) = makeEnvironment()
        _ = await model.submit(session: session)
        XCTAssertNotNil(model.errorMessage)
        model.switchMode(to: .signUp)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.isSignUp)
    }
}
