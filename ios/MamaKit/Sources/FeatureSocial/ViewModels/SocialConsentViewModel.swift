import Foundation
import Observation
import MamaCore

/// 18+ ve koşullar onayı (iki kutu).
@MainActor
@Observable
public final class SocialConsentViewModel {
    public var adultConfirmed = false
    public var termsAccepted = false
    public private(set) var isSubmitting = false
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var canSubmit: Bool { adultConfirmed && termsAccepted && !isSubmitting }

    /// Onay verildiyse `true`.
    public func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            _ = try await services.social.giveSocialConsent()
            return true
        } catch {
            self.error = MamaError.classify(error)
            return false
        }
    }
}
