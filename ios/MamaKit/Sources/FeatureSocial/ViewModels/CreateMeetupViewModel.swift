import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class CreateMeetupViewModel {
    public var title = ""
    public var description = ""
    public var startsAt: Date
    public var durationMinutes = SocialPolicy.defaultDurationMinutes
    public var placeName = ""
    public var coordinate: Coordinate
    public var spotId: UUID?
    public var capacityEnabled = false
    public var capacity = 10
    public private(set) var isSubmitting = false
    /// Sunucu tarafı reddin mesajı (istemci ön kontrolü `validationIssue`'da).
    public private(set) var message: String?
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices, coordinate: Coordinate = .modaKadikoy) {
        self.services = services
        self.coordinate = coordinate
        self.startsAt = services.now().addingTimeInterval(86_400)
    }

    public var draft: MeetupDraft {
        MeetupDraft(
            title: title, description: description, startsAt: startsAt, durationMinutes: durationMinutes,
            placeName: placeName, coordinate: coordinate, spotId: spotId, capacity: capacityEnabled ? capacity : nil
        )
    }

    /// İstemci tarafı ön doğrulama (SocialPolicy); sorun yoksa `nil`.
    public var validationIssue: String? {
        SocialPolicy.validate(draft, now: services.now()).map(SocialMessages.message(for:))
    }

    /// Nokta cihaz konumuna 50 m'den yakınsa `true`: arayüz "evine çok yakın" onayı ister. Konum yoksa `false`.
    public func isNearDevice(_ device: Coordinate?) -> Bool {
        guard let device else { return false }
        return SocialPolicy.isNearDevice(point: coordinate, device: device)
    }

    public var canSubmit: Bool { validationIssue == nil && !isSubmitting }

    /// Doğrulama geçmezse sunucuya gidilmez ve `nil` döner.
    public func submit() async -> CreateMeetupOutcome? {
        guard !isSubmitting else { return nil }
        message = validationIssue
        guard message == nil else { return nil }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            let outcome = try await services.social.createMeetup(draft)
            message = SocialMessages.message(for: outcome)
            return outcome
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }
}
