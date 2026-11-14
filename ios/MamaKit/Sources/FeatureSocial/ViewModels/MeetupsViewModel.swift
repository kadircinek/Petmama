import Foundation
import Observation
import MamaCore

/// Yakındaki buluşmalar. Liste onaydan bağımsız yüklenir; katılmak/oluşturmak için onay gerekir.
@MainActor
@Observable
public final class MeetupsViewModel {
    public private(set) var meetups: [Meetup] = []
    public private(set) var needsConsent = false
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var now: Date { services.now() }
    public var isEmpty: Bool { hasLoaded && !isLoading && error == nil && meetups.isEmpty }

    public func load(near coordinate: Coordinate) async {
        isLoading = true
        error = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            async let list = services.social.meetups(near: coordinate, radiusMeters: SocialPolicy.radiusMeters)
            async let profile = try? await services.social.socialProfile()
            let (loaded, mine) = try await (list, profile)
            meetups = loaded
            // Profil okunamazsa liste yine de gösterilir; onay verilmemiş sayılır.
            needsConsent = !((mine ?? nil)?.hasConsented ?? false)
        } catch {
            self.error = MamaError.classify(error)
        }
    }
}
