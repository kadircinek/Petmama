import Foundation
import Observation
import MamaCore

/// Nokta detayı (ekran 13, FR-N4): durum, buradaki hayvanlar, son 7 gün çizelgesi, açık ihtiyaçlar, koruyucular,
/// takip, koruyuculuk ve "Bu nokta artık yok" (FR-N6).
@MainActor
@Observable
public final class SpotDetailViewModel {
    /// 7 sütunlu besleme çizelgesinin bir günü.
    public struct TimelineBar: Identifiable, Equatable, Sendable {
        public var id: Date { day }
        public var day: Date
        public var weekday: Weekday
        public var fedCount: Int
        public var needCount: Int
        public var isToday: Bool

        public var label: String { weekday.shortName }
    }

    public let spotId: UUID
    public internal(set) var spot: Spot?
    public internal(set) var animals: [Animal] = []
    public internal(set) var timeline: [FeedingDay] = []
    public internal(set) var needs: [Need] = []
    public internal(set) var guardians: [Guardian] = []
    public internal(set) var isFollowing = false
    public internal(set) var isLoading = false
    public internal(set) var hasLoaded = false
    public internal(set) var isWorking = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var currentUserId: UUID?

    public init(spotId: UUID, services: AppServices) {
        self.spotId = spotId
        self.services = services
    }

    public var now: Date { services.now() }

    public var status: SpotStatus? { spot?.currentStatus(now: now) }

    public var notFound: Bool { hasLoaded && spot == nil && error == nil }

    public var lastFedText: String {
        guard let lastFedAt = spot?.lastFedAt else { return "Henüz mama kaydı yok" }
        return "Son mama: \(MamaFormat.relative(lastFedAt, now: now))"
    }

    public var isGuardian: Bool {
        guard let currentUserId else { return false }
        return guardians.contains { $0.userId == currentUserId }
    }

    /// Kullanıcının koruyucu günleri (koruyucu değilse boş).
    public var mySchedule: Set<Weekday> {
        guard let currentUserId else { return [] }
        return guardians.first { $0.userId == currentUserId }?.schedule ?? []
    }

    public var timelineBars: [TimelineBar] {
        let calendar = Self.istanbulCalendar
        let today = calendar.startOfDay(for: now)
        return timeline.map { day in
            TimelineBar(
                day: day.day,
                weekday: Self.weekday(of: day.day, calendar: calendar),
                fedCount: day.fedCount,
                needCount: day.needCount,
                isToday: calendar.isDate(day.day, inSameDayAs: today)
            )
        }
    }

    public var maxTimelineCount: Int {
        timeline.map(\.fedCount).max() ?? 0
    }

    public var weeklyFedCount: Int {
        timeline.map(\.fedCount).reduce(0, +)
    }

    /// Konum ve oturum görünümden gelir. `userId` koruyucu durumunu belirlemek için.
    public func load(near coordinate: Coordinate?, userId: UUID?) async {
        currentUserId = userId
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let id = spotId
        let spots = services.spots
        let animalRepository = services.animals
        let needRepository = services.needs
        let profiles = services.profiles
        do {
            let loaded = try await spots.spot(id: id)
            spot = loaded?.withDistance(from: coordinate)
            error = nil
            guard loaded != nil else { return }
        } catch {
            self.error = MamaError.classify(error)
            return
        }
        async let animalList = animalRepository.animals(atSpot: id)
        async let days = spots.feedingTimeline(spotId: id, days: 7)
        async let openNeeds = needRepository.needs(spotId: id, animalId: nil, includeResolved: false)
        async let guardianList = spots.guardians(spotId: id)
        async let followed = profiles.followedSpotIds()
        animals = (try? await animalList) ?? animals
        timeline = (try? await days) ?? timeline
        needs = (try? await openNeeds) ?? needs
        guardians = (try? await guardianList) ?? guardians
        isFollowing = ((try? await followed) ?? []).contains(id)
    }

    public func setFollowing(_ following: Bool) async -> SpotFeedback {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.profiles.setFollowing(following, target: .spot, id: spotId)
            isFollowing = following
            return following
                ? SpotFeedback(message: "Noktayı takip ediyorsun. Değişikliklerden haberdar olacaksın.")
                : SpotFeedback(message: "Noktayı takip etmeyi bıraktın.", style: .info)
        } catch {
            return SpotFeedback(error: MamaError.classify(error))
        }
    }

    /// `schedule == nil` koruyuculuktan çıkar.
    public func setGuardian(schedule: Set<Weekday>?, userId: UUID?) async -> SpotFeedback {
        currentUserId = userId ?? currentUserId
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.profiles.setGuardian(spotId: spotId, schedule: schedule)
            guardians = (try? await services.spots.guardians(spotId: spotId)) ?? guardians
            return schedule == nil
                ? SpotFeedback(message: "Koruyuculuktan çıktın. Emeğin için teşekkürler!", style: .info)
                : SpotFeedback(message: "Artık bu noktanın koruyucususun. Teşekkürler!")
        } catch {
            return SpotFeedback(error: MamaError.classify(error))
        }
    }

    /// "Bu nokta artık yok" (FR-N6): 3 farklı kişi bildirince nokta pasife alınır.
    public func reportGone() async -> SpotFeedback {
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await services.spots.reportGone(spotId: spotId)
            if outcome.deactivated {
                spot?.isActive = false
                return SpotFeedback(message: "Teşekkürler! Nokta haritadan kaldırıldı.")
            }
            let needed = InactiveSpotPolicy.distinctReportsToDeactivate
            return SpotFeedback(message: "Teşekkürler! Bildirimin alındı (\(outcome.reportCount)/\(needed)).", style: .info)
        } catch {
            return SpotFeedback(error: MamaError.classify(error))
        }
    }

    // MARK: - Takvim

    static var istanbulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        return calendar
    }

    /// Gregoryen hafta günü (1 = Pazar) → ISO `Weekday` (1 = Pazartesi).
    static func weekday(of date: Date, calendar: Calendar) -> Weekday {
        let gregorian = calendar.component(.weekday, from: date)
        return Weekday(rawValue: (gregorian + 5) % 7 + 1) ?? .monday
    }
}
