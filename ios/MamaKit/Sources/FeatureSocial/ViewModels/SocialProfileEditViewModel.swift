import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class SocialProfileEditViewModel {
    public var isVisible = false
    public var about = ""
    public var interests: [SocialInterest] = []
    public private(set) var hasConsented = false
    public private(set) var isSaving = false
    public private(set) var message: String?
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var aboutRemaining: Int { SocialPolicy.maxAbout - SocialPolicy.length(about) }

    public func load() async {
        do {
            let profile = try await services.social.socialProfile()
            hasConsented = profile?.hasConsented ?? false
            isVisible = profile?.isVisible ?? false
            about = profile?.about ?? ""
            interests = profile?.interests ?? []
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func toggle(_ interest: SocialInterest) {
        if let index = interests.firstIndex(of: interest) { interests.remove(at: index) } else { interests.append(interest) }
    }

    public func save(at coordinate: Coordinate?) async -> SocialProfileOutcome? {
        guard !isSaving else { return nil }
        isSaving = true
        message = nil
        error = nil
        defer { isSaving = false }
        do {
            let outcome = try await services.social.updateSocialProfile(
                isVisible: isVisible, about: about, interests: interests, at: coordinate
            )
            message = SocialMessages.message(for: outcome)
            return outcome
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }
}
