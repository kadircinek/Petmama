import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class AnimalLoversViewModel {
    public private(set) var lovers: [AnimalLover] = []
    public private(set) var incoming: [ConnectionRequest] = []
    public private(set) var interestFilter: SocialInterest?
    /// `nil` ya da `isVisible == false`: arayüz "kendini görünür yap" durumunu gösterir.
    public private(set) var profile: SocialProfile?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var message: String?
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var lastSentCell: Coordinate?

    public init(
        services: AppServices,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.services = services
        self.sleep = sleep
    }

    public var isVisible: Bool { profile?.isVisible ?? false }

    public func load(at coordinate: Coordinate?) async {
        isLoading = true
        error = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            profile = try await services.social.socialProfile()
            try await refreshLocation(coordinate)
            try await reloadLists()
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func setInterestFilter(_ interest: SocialInterest?) async {
        interestFilter = interest
        do { try await reloadLists() } catch { self.error = MamaError.classify(error) }
    }

    public func sendRequest(to userId: UUID, note: String? = nil) async -> SendRequestOutcome? {
        message = nil
        error = nil
        do {
            let outcome = try await services.social.sendConnectionRequest(to: userId, note: note)
            message = SocialMessages.message(for: outcome)
            switch outcome {
            case .sent:
                try await reloadLists()
                if services.config.isDemo {
                    // Senaryolu demo kullanıcısı isteği kısa süre sonra kabul eder.
                    await sleep(InMemoryBackend.demoResponseDelay)
                    try await reloadLists()
                }
            case .autoAccepted:
                try await reloadLists()
            default:
                break
            }
            return outcome
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    /// Kabulde bire bir sohbetin kimliği.
    @discardableResult
    public func respond(_ request: ConnectionRequest, accept: Bool) async -> UUID? {
        error = nil
        do {
            let conversationId = try await services.social.respondToConnection(requestId: request.id, accept: accept)
            try await reloadLists()
            return conversationId
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    /// Bekleyen (gönderdiğim) isteği geri çeker. `true` = geri çekildi.
    @discardableResult
    public func withdraw(requestId: UUID) async -> Bool {
        message = nil
        error = nil
        do {
            try await services.social.withdrawConnectionRequest(id: requestId)
            try await reloadLists()
            return true
        } catch {
            self.error = MamaError.classify(error)
            return false
        }
    }

    /// Görünürse ve kaba konum hücresi değiştiyse (≈1 km) sunucudaki konumu tazeler.
    private func refreshLocation(_ coordinate: Coordinate?) async throws {
        guard let profile, profile.isVisible, let coordinate else { return }
        let cell = SocialPolicy.roundedCell(coordinate)
        guard cell != lastSentCell else { return }
        let outcome = try await services.social.updateSocialProfile(
            isVisible: true, about: profile.about, interests: profile.interests, at: coordinate
        )
        if outcome == .saved { lastSentCell = cell }
    }

    private func reloadLists() async throws {
        async let people = isVisible ? services.social.animalLovers(interest: interestFilter) : []
        async let requests = services.social.incomingConnectionRequests()
        (lovers, incoming) = try await (people, requests)
    }
}
