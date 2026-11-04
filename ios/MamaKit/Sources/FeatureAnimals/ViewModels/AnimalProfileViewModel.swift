import Foundation
import Observation
import MamaCore

/// Hayvan profili (ekran 14, FR-A1…A4).
@MainActor
@Observable
public final class AnimalProfileViewModel {
    /// "Bu hayvanı gördüm": kullanıcı bu mesafedeki en yakın bilinen noktayı işaretler (FR-A3).
    public static let markSeenRadiusMeters: Double = 300

    public enum MarkSeenResult: Equatable, Sendable {
        case marked(spotId: UUID, spotTitle: String?)
        case needsLocation
        case noKnownSpot
        case failed(MamaError)

        public var message: String {
            switch self {
            case .marked(_, let title?):
                return "Teşekkürler! Görüldüğü yer güncellendi: \(title)"
            case .marked(_, nil):
                return "Teşekkürler! Görüldüğü yer güncellendi."
            case .needsLocation:
                return "Görüldüğü noktayı bulabilmemiz için konumunu açman gerekiyor."
            case .noKnownSpot:
                return "Bu hayvan henüz bir noktaya bağlı değil."
            case .failed(let error):
                return error.userMessage
            }
        }

        public var toastStyle: AppRouter.Toast.Style {
            switch self {
            case .marked: return .success
            case .needsLocation, .noKnownSpot: return .info
            case .failed: return .warning
            }
        }
    }

    public private(set) var animal: Animal?
    public private(set) var spots: [Spot] = []
    public private(set) var openNeeds: [Need] = []
    public private(set) var isFollowing = false
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var isMarkingSeen = false
    public var error: MamaError?

    public let animalId: UUID
    @ObservationIgnored private let services: AppServices

    public init(animalId: UUID, services: AppServices) {
        self.animalId = animalId
        self.services = services
    }

    public var now: Date { services.now() }

    public func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            animal = try await services.animals.animal(id: animalId)
            guard animal != nil else {
                error = .notFound
                return
            }
            async let spotList = services.animals.spots(forAnimal: animalId)
            async let needList = services.needs.needs(spotId: nil, animalId: animalId, includeResolved: false)
            spots = try await spotList
            openNeeds = try await needList
            error = nil
        } catch {
            self.error = MamaError.classify(error)
        }
        // Takip durumu ikincil bilgi: alınamazsa profil yine gösterilir.
        if let followed = try? await services.profiles.followedAnimals() {
            isFollowing = followed.contains { $0.id == animalId }
        }
    }

    // MARK: - Görünüm metinleri

    public var lastSeenSpot: Spot? {
        guard let id = animal?.lastSeenSpotId else { return nil }
        return spots.first { $0.id == id }
    }

    /// "2 sa önce · Moda Parkı girişi"
    public var lastSeenText: String {
        guard let animal, let seenAt = animal.lastSeenAt else { return "Bilinmiyor" }
        let relative = MamaFormat.relative(seenAt, now: now, language: .turkish)
        guard let title = lastSeenSpot?.title else { return relative }
        return "\(relative) · \(title)"
    }

    /// "Evet · kulak küpesi var" / "Hayır" / "Bilinmiyor"
    public var neuteredText: String {
        guard let animal else { return "Bilinmiyor" }
        let base: String
        switch animal.isNeutered {
        case true?: base = "Evet"
        case false?: base = "Hayır"
        case nil: base = "Bilinmiyor"
        }
        return animal.earTag ? "\(base) · kulak küpesi var" : base
    }

    public var vaccinationText: String {
        let info = animal?.vaccinationInfo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return info.isEmpty ? "Bilinmiyor" : info
    }

    // MARK: - "Bu hayvanı gördüm" (FR-A3)

    /// Kullanıcıya 300 m içindeki en yakın bilinen nokta; yoksa son görüldüğü nokta.
    public static func seenSpotChoice(user: Coordinate, spots: [Spot], lastSeenSpotId: UUID?) -> Spot? {
        if let nearest = GeoMath.nearest(to: user, in: spots, coordinate: \.coordinate),
           nearest.distance <= markSeenRadiusMeters {
            return nearest.item
        }
        guard let lastSeenSpotId else { return nil }
        return spots.first { $0.id == lastSeenSpotId }
    }

    /// Oturum kontrolü görünümde yapılır; burada konum ve nokta seçimi.
    public func markSeen(user: Coordinate?) async -> MarkSeenResult {
        guard let user else { return .needsLocation }
        let lastSeenId = animal?.lastSeenSpotId
        let chosen = Self.seenSpotChoice(user: user, spots: spots, lastSeenSpotId: lastSeenId)
        guard let spotId = chosen?.id ?? lastSeenId else { return .noKnownSpot }

        isMarkingSeen = true
        defer { isMarkingSeen = false }
        do {
            try await services.animals.markSeen(animalId: animalId, spotId: spotId)
            let title = chosen?.title
            await load()
            return .marked(spotId: spotId, spotTitle: title)
        } catch {
            let mama = MamaError.classify(error)
            return .failed(mama)
        }
    }

    // MARK: - Takip

    /// İyimser güncelleme; hata olursa geri alınır.
    public func toggleFollow() async {
        let target = !isFollowing
        isFollowing = target
        do {
            try await services.profiles.setFollowing(target, target: .animal, id: animalId)
        } catch {
            isFollowing = !target
            self.error = MamaError.classify(error)
        }
    }
}
