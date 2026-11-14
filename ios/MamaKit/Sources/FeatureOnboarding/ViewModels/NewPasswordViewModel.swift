import Foundation
import Observation
import MamaCore

/// Şifre sıfırlama bağlantısından sonra açılan "Yeni şifre" ekranı.
@MainActor
@Observable
public final class NewPasswordViewModel {
    public var password = ""
    public var confirmation = ""
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    public init() {}

    public var canSubmit: Bool { !isWorking && !password.isEmpty && !confirmation.isEmpty }

    /// Formdaki ilk sorun; `nil` = gönderilebilir.
    public var validationIssue: String? {
        if password.count < SignInViewModel.minimumPasswordLength {
            return "Şifren en az \(SignInViewModel.minimumPasswordLength) karakter olmalı."
        }
        if password != confirmation { return "İki şifre aynı değil." }
        return nil
    }

    @discardableResult
    public func submit(session: SessionStore) async -> Bool {
        if let issue = validationIssue {
            errorMessage = issue
            return false
        }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        guard await session.updatePassword(password) else {
            errorMessage = (session.lastError ?? .server("update-password")).userMessage
            return false
        }
        return true
    }
}
