import XCTest
@testable import MamaCore

final class AuthLinkTests: XCTestCase {
    private func parse(_ string: String) -> AuthLink.Kind? {
        AuthLink.parse(URL(string: string)!)
    }

    func testEmailConfirmationLink() {
        XCTAssertEqual(parse("mamaharitasi://auth-callback?code=abc123"), .emailConfirmed)
    }

    func testRecoveryLinkFromOurRedirect() {
        XCTAssertEqual(parse("mamaharitasi://auth-callback?flow=recovery&code=abc123"), .passwordRecovery)
    }

    func testRecoveryLinkImplicitFlow() {
        XCTAssertEqual(parse("mamaharitasi://auth-callback#access_token=x&refresh_token=y&type=recovery"), .passwordRecovery)
    }

    func testExpiredLinkIsFailure() {
        let kind = parse("mamaharitasi://auth-callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")
        XCTAssertEqual(kind, .failed(AuthLink.expiredMessage))
    }

    func testForeignURLsAreIgnored() {
        XCTAssertNil(parse("https://mamaharitasi.app/auth-callback?code=1"))
        XCTAssertNil(parse("mamaharitasi://spot/123"))
    }

    func testRecoveryRedirectAddsFlowParameter() {
        let url = AuthLink.recoveryRedirect(from: AuthLink.callbackURL)
        XCTAssertEqual(url.absoluteString, "mamaharitasi://auth-callback?flow=recovery")
        XCTAssertEqual(AuthLink.parse(url), .passwordRecovery)
    }
}

/// Bağlantıyla oturum açmayı ve şifre güncellemeyi kaydeden sahte kimlik deposu.
actor StubLinkAuth: AuthRepository {
    let user = UserProfile(displayName: "Bağlantılı", createdAt: Date(timeIntervalSince1970: 0))
    private(set) var signedIn = false
    private(set) var completedLinks: [URL] = []
    private(set) var newPasswords: [String] = []

    func currentUserId() async -> UUID? { signedIn ? user.id : nil }
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> UserProfile { user }
    func signIn(email: String, password: String) async throws -> UserProfile { user }
    func signUp(email: String, password: String, displayName: String) async throws -> UserProfile { user }
    func sendPasswordReset(email: String) async throws {}
    func signOut() async throws { signedIn = false }
    func deleteAccount() async throws {}

    func completeAuthLink(_ url: URL) async throws -> UserProfile {
        completedLinks.append(url)
        signedIn = true
        return user
    }

    func updatePassword(_ newPassword: String) async throws {
        guard signedIn else { throw MamaError.notSignedIn }
        newPasswords.append(newPassword)
    }
}

@MainActor
final class SessionAuthLinkTests: XCTestCase {
    private func makeSession() -> (SessionStore, StubLinkAuth) {
        let auth = StubLinkAuth()
        let profiles = AppServices.demo().profiles
        return (SessionStore(auth: auth, profiles: profiles), auth)
    }

    func testConfirmationLinkSignsIn() async {
        let (session, _) = makeSession()
        let handled = await session.handleAuthLink(URL(string: "mamaharitasi://auth-callback?code=abc")!)
        XCTAssertEqual(handled, .emailConfirmed)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertFalse(session.isRecoveringPassword)
    }

    func testRecoveryLinkSignsInAndAsksForNewPassword() async {
        let (session, _) = makeSession()
        let handled = await session.handleAuthLink(URL(string: "mamaharitasi://auth-callback?flow=recovery&code=abc")!)
        XCTAssertEqual(handled, .passwordRecovery)
        XCTAssertTrue(session.isSignedIn)
        XCTAssertTrue(session.isRecoveringPassword)
    }

    func testExpiredLinkSetsErrorWithoutCallingBackend() async {
        let (session, auth) = makeSession()
        let handled = await session.handleAuthLink(URL(string: "mamaharitasi://auth-callback#error=access_denied&error_code=otp_expired")!)
        XCTAssertEqual(handled, .failed(AuthLink.expiredMessage))
        XCTAssertFalse(session.isSignedIn)
        XCTAssertEqual(session.lastError, .invalidInput(AuthLink.expiredMessage))
        let completed = await auth.completedLinks
        XCTAssertTrue(completed.isEmpty)
    }

    func testForeignURLIsNotHandled() async {
        let (session, auth) = makeSession()
        let handled = await session.handleAuthLink(URL(string: "https://ornek.org")!)
        XCTAssertNil(handled)
        let completed = await auth.completedLinks
        XCTAssertTrue(completed.isEmpty)
    }

    func testUpdatePasswordEndsRecovery() async {
        let (session, auth) = makeSession()
        _ = await session.handleAuthLink(URL(string: "mamaharitasi://auth-callback?flow=recovery&code=abc")!)
        let ok = await session.updatePassword("yeniSifre123")
        XCTAssertTrue(ok)
        XCTAssertFalse(session.isRecoveringPassword)
        let passwords = await auth.newPasswords
        XCTAssertEqual(passwords, ["yeniSifre123"])
    }
}
