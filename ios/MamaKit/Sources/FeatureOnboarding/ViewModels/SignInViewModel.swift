import Foundation
import Observation
import MamaCore

/// Giriş / kayıt ekranı (ekran 7, FR-P1). Apple ile giriş ve e-posta akışı.
///
/// Apple tarafındaki nonce/SHA256 işi görünüm katmanında yapılır (CryptoKit); bu sınıf yalnızca
/// sonucu `SessionStore`'a iletir, böylece Linux'ta derlenir ve test edilir.
@MainActor
@Observable
public final class SignInViewModel {
    public enum Mode: String, CaseIterable, Sendable, Hashable {
        case signIn, signUp
    }

    public private(set) var mode: Mode = .signIn
    public var email = ""
    public var password = ""
    public var displayName = ""
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    /// Olumlu bilgi (ör. "Şifre sıfırlama bağlantısını gönderdik").
    public private(set) var infoMessage: String?

    @ObservationIgnored private let services: AppServices

    public static let minimumPasswordLength = 8
    public static let maximumDisplayNameLength = 40
    public static let demoEmail = "demo@mamaharitasi.app"
    public static let demoPassword = "demo1234"

    public init(services: AppServices) {
        self.services = services
    }

    // MARK: - Durum

    /// Demo modunda (D7) giriş bilgilerini gösteren ipucu kartı.
    public var showsDemoHint: Bool { services.config.isDemo }

    public var isSignUp: Bool { mode == .signUp }

    /// Buton etkin mi? Ayrıntılı doğrulama gönderimde yapılır ve mesajla gösterilir.
    public var canSubmit: Bool {
        !isWorking && !trimmedEmail.isEmpty && !password.isEmpty && (!isSignUp || !trimmedName.isEmpty)
    }

    /// Formdaki ilk sorun; `nil` = gönderilebilir.
    public var validationIssue: String? {
        if !Self.isValidEmail(email) { return "Geçerli bir e-posta adresi yazar mısın?" }
        if password.count < Self.minimumPasswordLength {
            return "Şifren en az \(Self.minimumPasswordLength) karakter olmalı."
        }
        if isSignUp {
            let name = trimmedName
            if name.isEmpty { return "Sana nasıl hitap edelim? Bir isim yaz." }
            if name.count > Self.maximumDisplayNameLength {
                return "İsim en fazla \(Self.maximumDisplayNameLength) karakter olabilir."
            }
            if ContentFilter.containsProfanity(name) { return MamaError.rejectedContent.userMessage }
        }
        return nil
    }

    // MARK: - Eylemler

    public func switchMode(to mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        clearMessages()
    }

    public func fillDemoCredentials() {
        switchMode(to: .signIn)
        email = Self.demoEmail
        password = Self.demoPassword
        clearMessages()
    }

    /// E-posta ile giriş veya kayıt. Başarılıysa `true`.
    @discardableResult
    public func submit(session: SessionStore) async -> Bool {
        clearMessages()
        if let issue = validationIssue {
            errorMessage = issue
            return false
        }
        isWorking = true
        defer { isWorking = false }
        let succeeded: Bool
        switch mode {
        case .signIn:
            succeeded = await session.signIn(email: trimmedEmail, password: password)
        case .signUp:
            succeeded = await session.signUp(email: trimmedEmail, password: password, displayName: trimmedName)
        }
        finish(succeeded, session: session)
        return succeeded
    }

    /// Apple kimlik bilgisinden gelen token ile giriş (nonce ham haliyle iletilir).
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String, fullName: String?, session: SessionStore) async -> Bool {
        clearMessages()
        isWorking = true
        defer { isWorking = false }
        let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let succeeded = await session.signInWithApple(
            idToken: idToken,
            nonce: nonce,
            fullName: (name?.isEmpty ?? true) ? nil : name
        )
        finish(succeeded, session: session)
        return succeeded
    }

    /// Apple akışı token üretemeden bittiğinde. Kullanıcı vazgeçtiyse mesaj gösterilmez.
    public func appleSignInFailed(canceled: Bool) {
        clearMessages()
        guard !canceled else { return }
        errorMessage = "Apple ile giriş tamamlanamadı. Biraz sonra tekrar dener misin?"
    }

    @discardableResult
    public func sendPasswordReset() async -> Bool {
        clearMessages()
        guard Self.isValidEmail(email) else {
            errorMessage = "Şifre sıfırlama bağlantısı için önce e-posta adresini yaz."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.sendPasswordReset(email: trimmedEmail)
            infoMessage = "Şifre sıfırlama bağlantısını \(trimmedEmail) adresine gönderdik. Gelen kutunu kontrol et."
            return true
        } catch {
            errorMessage = MamaError.classify(error).userMessage
            return false
        }
    }

    public func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: - Yardımcılar

    /// Basit biçim kontrolü; asıl doğrulama sunucuda.
    public static func isValidEmail(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(" "), let at = value.firstIndex(of: "@") else { return false }
        let local = value[..<at]
        let domain = value[value.index(after: at)...]
        return !local.isEmpty
            && !domain.contains("@")
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func finish(_ succeeded: Bool, session: SessionStore) {
        if succeeded {
            password = ""
        } else {
            errorMessage = session.lastError?.userMessage ?? MamaError.server("").userMessage
        }
    }
}
