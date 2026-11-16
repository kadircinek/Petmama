import Foundation
import Observation
import MamaCore

/// Mahalle › Akış'ın üstü (spec 2026-11-16): "Şu an turda" kartları ve "Mahalledeki hayvanseverler" şeridi.
///
/// Turlar sosyal onay olmadan da listelenir (buluşmalar gibi); şerit yalnızca onay vermiş ve görünür olan
/// izleyiciye gösterilir (kendini göstermeyen başkalarını göremez — Tanışma 5.5/1), yoksa davet kartı.
@MainActor
@Observable
public final class NeighborhoodSocialViewModel {
    public enum StripState: Equatable, Sendable {
        case loading
        /// Profil okunamadı (bağlantı/sunucu hatası): yanlış bir onay daveti yerine şerit hiç gösterilmez.
        case unavailable
        /// Sosyal onay yok: "Mahallendeki hayvanseverleri gör" → onay.
        case needsConsent
        /// Onay var ama Hayvanseverler'de görünür değil → görünür ol.
        case needsVisibility
        case lovers
    }

    /// Şeritte gösterilen en fazla kişi ("Tümünü gör" → Hayvanseverler).
    public static let stripLimit = 12
    /// "Şu an turda" bölümünde en fazla kart ("Tümünü gör" → Buluşmalar).
    public static let maxTourCards = 3

    public enum TourAction: Equatable, Sendable { case join, message, end }

    public private(set) var tours: [Meetup] = []
    public private(set) var lovers: [AnimalLover] = []
    public private(set) var profile: SocialProfile?
    public private(set) var hasLoaded = false
    /// Katıl / Mesaj at / Turu bitir sürerken o turun kimliği ve hangi eylem olduğu.
    public private(set) var busyMeetupId: UUID?
    public private(set) var busyAction: TourAction?
    /// Son tur eyleminin mesajı (Mahalle bandında).
    public private(set) var message: String?
    /// Şeritteki kişi kartı eylemlerinin mesajı (yalnızca kişi sheet'inde).
    public private(set) var personMessage: String?
    /// Son eylem sosyal onay istediği için yapılamadı: arayüz onay ekranını açar.
    public private(set) var lastActionNeedsConsent = false
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var origin: Coordinate = .modaKadikoy
    @ObservationIgnored private var lastSentCell: Coordinate?
    @ObservationIgnored private var profileLoadFailed = false

    public init(services: AppServices) {
        self.services = services
    }

    public var now: Date { services.now() }

    public var stripState: StripState {
        guard hasLoaded else { return .loading }
        if profile == nil, profileLoadFailed { return .unavailable }
        guard profile?.hasConsented == true else { return .needsConsent }
        guard profile?.isVisible == true else { return .needsVisibility }
        return .lovers
    }

    public func isMember(_ tour: Meetup) -> Bool {
        tour.viewerRole == .organizer || tour.viewerRole == .participant
    }

    /// Kalan dakika (yukarı yuvarlanır); bitmişse 0.
    public func remainingMinutes(_ tour: Meetup) -> Int {
        remainingMinutes(tour, at: now)
    }

    public func remainingMinutes(_ tour: Meetup, at date: Date) -> Int {
        let seconds = tour.endsAt.timeIntervalSince(date)
        return seconds > 0 ? Int((seconds / 60).rounded(.up)) : 0
    }

    /// Çizim anındaki turlar: bitenler (yeniden yükleme beklemeden) düşer, en fazla `maxTourCards`.
    public func visibleTours(at date: Date) -> [Meetup] {
        Array(activeTours(at: date).prefix(Self.maxTourCards))
    }

    /// Kart sınırını aşan aktif tur var mı ("Tümünü gör").
    public func hasMoreTours(at date: Date) -> Bool {
        activeTours(at: date).count > Self.maxTourCards
    }

    private func activeTours(at date: Date) -> [Meetup] {
        tours.filter { $0.status == .active && $0.startsAt <= date && $0.endsAt > date }
    }

    public func lover(id: UUID) -> AnimalLover? {
        lovers.first { $0.id == id }
    }

    public func load(at coordinate: Coordinate?) async {
        if let coordinate { origin = coordinate }
        error = nil
        defer { hasLoaded = true }
        do {
            do {
                profile = try await services.social.socialProfile()
                profileLoadFailed = false
            } catch {
                profileLoadFailed = true
                throw error
            }
            try await refreshLocation(coordinate)
            try await reload()
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    // MARK: Turlar

    /// Tura katılır; sonuç mesajı `message`'da.
    public func join(_ tour: Meetup) async -> JoinMeetupOutcome? {
        await act(on: tour, .join) { [services] in
            try await services.social.joinMeetup(id: tour.id)
        }
    }

    /// "Mesaj at" / "Sohbete git": üye değilse önce katılır, sonra turun grup sohbetinin kimliğini döner.
    public func messageTour(_ tour: Meetup) async -> UUID? {
        if isMember(tour), let conversationId = tour.conversationId { return conversationId }
        let outcome = await act(on: tour, .message) { [services] in
            try await services.social.joinMeetup(id: tour.id)
        }
        guard case .joined(let conversationId) = outcome else { return nil }
        return conversationId
    }

    /// "Turu bitir" (yalnızca düzenleyen; buluşma iptaliyle aynı).
    public func endTour(_ tour: Meetup) async -> Bool {
        let done = await act(on: tour, .end) { [services] () async throws -> Bool in
            try await services.social.cancelMeetup(id: tour.id)
        }
        if done == false { message = SocialMessages.cancelFailed }
        return done ?? false
    }

    private func act<T>(on tour: Meetup, _ action: TourAction, _ work: () async throws -> T) async -> T? {
        guard busyMeetupId == nil else { return nil }
        busyMeetupId = tour.id
        busyAction = action
        message = nil
        error = nil
        lastActionNeedsConsent = false
        defer { busyMeetupId = nil; busyAction = nil }
        do {
            let result = try await work()
            if let outcome = result as? JoinMeetupOutcome {
                message = SocialMessages.message(for: outcome)
                lastActionNeedsConsent = outcome == .consentRequired
            }
            try await reload()
            return result
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    // MARK: Şerit (AnimalLoverCard eylemleri)

    public func sendRequest(to userId: UUID, note: String?) async -> SendRequestOutcome? {
        personMessage = nil
        error = nil
        do {
            let outcome = try await services.social.sendConnectionRequest(to: userId, note: note)
            personMessage = SocialMessages.message(for: outcome)
            lastActionNeedsConsent = outcome == .consentRequired
            try await reloadLovers()
            return outcome
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    @discardableResult
    public func withdraw(requestId: UUID) async -> Bool {
        personMessage = nil
        error = nil
        do {
            try await services.social.withdrawConnectionRequest(id: requestId)
            try await reloadLovers()
            return true
        } catch {
            self.error = MamaError.classify(error)
            return false
        }
    }

    /// Kabulde bire bir sohbetin kimliği.
    @discardableResult
    public func respond(requestId: UUID, accept: Bool) async -> UUID? {
        error = nil
        do {
            let conversationId = try await services.social.respondToConnection(requestId: requestId, accept: accept)
            try await reloadLovers()
            return conversationId
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    /// Hayvanseverler ekranındaki gibi: görünürse ve kaba konum hücresi değiştiyse sunucudaki konumu tazeler.
    private func refreshLocation(_ coordinate: Coordinate?) async throws {
        guard let profile, profile.isVisible, profile.hasConsented, let coordinate else { return }
        let cell = SocialPolicy.roundedCell(coordinate)
        guard cell != lastSentCell else { return }
        let outcome = try await services.social.updateSocialProfile(
            isVisible: true, about: profile.about, interests: profile.interests, at: coordinate
        )
        if outcome == .saved { lastSentCell = cell }
    }

    private func reload() async throws {
        async let nearby = services.social.meetups(near: origin, radiusMeters: SocialPolicy.radiusMeters)
        async let people = loadLovers()
        let (meetups, loadedLovers) = try await (nearby, people)
        let current = now
        tours = meetups
            .filter { $0.isTour && $0.status == .active && $0.startsAt <= current && $0.endsAt > current }
            .sorted { Self.tourRank($0) < Self.tourRank($1) }
        lovers = loadedLovers
    }

    private func reloadLovers() async throws {
        lovers = try await loadLovers()
    }

    private func loadLovers() async throws -> [AnimalLover] {
        guard profile?.hasConsented == true, profile?.isVisible == true else { return [] }
        return Array(try await services.social.animalLovers(interest: nil).prefix(Self.stripLimit))
    }

    /// Kendi turum → katıldığım → yakından uzağa (sunucu sırası korunur).
    private static func tourRank(_ tour: Meetup) -> (Int, Double) {
        let role: Int
        switch tour.viewerRole {
        case .organizer: role = 0
        case .participant: role = 1
        case .removed, .none: role = 2
        }
        return (role, tour.distanceMeters ?? .infinity)
    }
}

/// "Mama turuna çıkıyorum": nokta (yalnızca herkese açık, yakından uzağa) ve süre (60/90/120 dk) seçimi.
@MainActor
@Observable
public final class StartTourViewModel {
    public static let durationOptions = SocialPolicy.tourDurations
    /// Listelenen en fazla nokta.
    public static let maxSpots = 8
    /// Nokta arama yarıçapı.
    public static let searchRadiusMeters = 3000

    public private(set) var spots: [Spot] = []
    public var selectedSpotId: UUID?
    public var durationMinutes = SocialPolicy.defaultTourDuration
    public private(set) var isLoading = false
    public private(set) var isSubmitting = false
    public private(set) var message: String?
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var selectedSpot: Spot? { spots.first { $0.id == selectedSpotId } }
    public var canSubmit: Bool { selectedSpotId != nil && !isSubmitting }

    /// `preselected` (nokta detayından) herkese açıksa listenin başına konur ve seçilir; değilse en yakın nokta seçilir.
    public func load(near coordinate: Coordinate, preselected: UUID?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            var list = try await services.spots.spots(near: coordinate, radiusMeters: Self.searchRadiusMeters)
                .filter(Self.isEligible)
                .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
            list = Array(list.prefix(Self.maxSpots))
            if let preselected {
                list.removeAll { $0.id == preselected }
                if let spot = try await services.spots.spot(id: preselected), Self.isEligible(spot) {
                    list.insert(spot, at: 0)
                }
            }
            spots = list
            if selectedSpotId == nil || !list.contains(where: { $0.id == selectedSpotId }) {
                selectedSpotId = list.first?.id
            }
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    /// Nokta seçilmemişse sunucuya gidilmez ve `nil` döner.
    public func submit() async -> StartTourOutcome? {
        guard let spotId = selectedSpotId, !isSubmitting else { return nil }
        isSubmitting = true
        message = nil
        error = nil
        defer { isSubmitting = false }
        do {
            let outcome = try await services.social.startFeedingTour(spotId: spotId, durationMinutes: durationMinutes)
            message = SocialMessages.message(for: outcome)
            return outcome
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    private static func isEligible(_ spot: Spot) -> Bool {
        spot.visibility == .public && spot.isActive
    }
}
