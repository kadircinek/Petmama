import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class MeetupDetailViewModel {
    public let meetupId: UUID
    public private(set) var meetup: Meetup?
    public private(set) var participants: [MeetupParticipant] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isBusy = false
    /// Son eylemin kullanıcıya gösterilecek mesajı.
    public private(set) var message: String?
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var origin: Coordinate?

    public init(services: AppServices, meetupId: UUID) {
        self.services = services
        self.meetupId = meetupId
    }

    public var isFull: Bool { meetup?.isFull ?? false }
    public var isOrganizer: Bool { meetup?.viewerRole == .organizer }
    public var isParticipant: Bool { meetup?.viewerRole == .participant || isOrganizer }
    /// Sohbet yalnızca düzenleyen ve katılımcılar için açılır.
    public var canChat: Bool { isParticipant && meetup?.conversationId != nil }
    public var canJoin: Bool {
        guard let meetup else { return false }
        return meetup.status == .active && meetup.endsAt > services.now()
            && (meetup.viewerRole == .none) && !meetup.isFull
    }

    public func load(near coordinate: Coordinate? = nil) async {
        if let coordinate { origin = coordinate }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        await refresh()
    }

    public func join() async -> JoinMeetupOutcome? {
        await act { [services, meetupId] in
            let outcome = try await services.social.joinMeetup(id: meetupId)
            return (outcome, SocialMessages.message(for: outcome))
        }
    }

    /// Düzenleyen ayrılamaz (iptal eder). `true` = ayrıldı.
    @discardableResult
    public func leave() async -> Bool {
        await act { [services, meetupId] in
            let done = try await services.social.leaveMeetup(id: meetupId)
            return (done, done ? nil : "Düzenleyen buluşmadan ayrılamaz, yalnızca iptal edebilir.")
        } ?? false
    }

    @discardableResult
    public func remove(_ userId: UUID) async -> Bool {
        await act { [services, meetupId] in
            let done = try await services.social.removeParticipant(meetupId: meetupId, userId: userId)
            return (done, done ? nil : "Bu kişi çıkarılamadı.")
        } ?? false
    }

    @discardableResult
    public func cancel() async -> Bool {
        await act { [services, meetupId] in
            let done = try await services.social.cancelMeetup(id: meetupId)
            return (done, done ? nil : "Bu buluşma iptal edilemedi.")
        } ?? false
    }

    private func act<T>(_ work: () async throws -> (T, String?)) async -> T? {
        guard !isBusy else { return nil }
        isBusy = true
        message = nil
        error = nil
        defer { isBusy = false }
        do {
            let (result, text) = try await work()
            message = text
            await refresh()
            return result
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    private func refresh() async {
        do {
            meetup = try await services.social.meetup(id: meetupId, near: origin)
            participants = meetup == nil ? [] : try await services.social.meetupParticipants(meetupId: meetupId)
        } catch {
            self.error = MamaError.classify(error)
        }
    }
}
