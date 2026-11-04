import Foundation
import Observation
import MamaCore

/// Açıklama için en az karakter (izolasyonsuz; doğrulama mesajında da kullanılır).
private let minimumNeedDescriptionLength = 10

/// İhtiyaç bildirme formu (FR-I1, FR-I2).
@MainActor
@Observable
public final class CreateNeedViewModel {
    public static let minDescriptionLength = minimumNeedDescriptionLength
    public static let maxPhotos = 3
    public static let nearbyRadiusMeters = 500

    public enum ValidationIssue: Equatable, Sendable {
        case missingType
        case missingTarget
        case descriptionTooShort
        case profanity

        public var message: String {
            switch self {
            case .missingType: return "Önce ne gerektiğini seç."
            case .missingTarget: return "İhtiyacı bir noktaya bağla; gönüllüler yeri böyle bulur."
            case .descriptionTooShort:
                return "Biraz daha anlatır mısın? En az \(minimumNeedDescriptionLength) karakter yeter."
            case .profanity: return MamaError.rejectedContent.userMessage
            }
        }
    }

    public var type: NeedType?
    public var urgency: NeedUrgency = .normal
    /// Açıklama metni (`description` adı `CustomStringConvertible` ile karışmasın diye).
    public var descriptionText = ""
    public private(set) var photos: [NeedPhotoDraft] = []
    public var selectedSpotId: UUID?

    public let presetSpotId: UUID?
    public let animalId: UUID?
    public private(set) var presetSpot: Spot?
    public private(set) var animal: Animal?
    public private(set) var nearbySpots: [Spot] = []
    public private(set) var isLoadingSpots = false

    /// İlk gönderme denemesinden sonra doğrulama mesajları görünür.
    public private(set) var attemptedSubmit = false
    public private(set) var isSubmitting = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(spotId: UUID?, animalId: UUID?, services: AppServices) {
        self.presetSpotId = spotId
        self.selectedSpotId = spotId
        self.animalId = animalId
        self.services = services
    }

    /// Nokta verilmediyse seçici gösterilir.
    public var showsSpotPicker: Bool { presetSpotId == nil }
    /// Hayvana bağlı değilse nokta zorunlu (sunucu: `animal_id is not null or spot_id is not null`).
    public var isSpotRequired: Bool { presetSpotId == nil && animalId == nil }
    /// Acil veteriner ihtiyacında gönderimden sonra veteriner bilgisi açılır (FR-I4).
    public var shouldOpenVetHelp: Bool { type == .vet && urgency == .urgent }

    public var trimmedDescription: String {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validationIssue: ValidationIssue? {
        if type == nil { return .missingType }
        if selectedSpotId == nil && animalId == nil { return .missingTarget }
        if trimmedDescription.count < Self.minDescriptionLength { return .descriptionTooShort }
        if ContentFilter.containsProfanity(descriptionText) { return .profanity }
        return nil
    }

    public func load(near coordinate: Coordinate?) async {
        isLoadingSpots = true
        defer { isLoadingSpots = false }
        if let animalId {
            animal = try? await services.animals.animal(id: animalId)
        }
        if let presetSpotId {
            presetSpot = try? await services.spots.spot(id: presetSpotId)
            return
        }
        guard let coordinate else { return }
        do {
            nearbySpots = try await services.spots.spots(near: coordinate, radiusMeters: Self.nearbyRadiusMeters)
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func toggleSpot(_ id: UUID) {
        selectedSpotId = selectedSpotId == id ? nil : id
    }

    public var canAddPhoto: Bool { photos.count < Self.maxPhotos }

    public func addPhoto(_ data: Data) {
        guard canAddPhoto else { return }
        photos.append(NeedPhotoDraft(data: data))
    }

    public func removePhoto(_ id: UUID) {
        photos.removeAll { $0.id == id }
    }

    public func makeDraft(photoURLs: [URL]) -> NeedDraft? {
        guard let type else { return nil }
        return NeedDraft(
            spotId: selectedSpotId,
            animalId: animalId,
            type: type,
            urgency: urgency,
            description: trimmedDescription,
            photoURLs: photoURLs
        )
    }

    /// Doğrular, fotoğrafları yükler ve ihtiyacı oluşturur. Başarısızsa `nil`.
    public func submit() async -> UUID? {
        guard !isSubmitting else { return nil }
        attemptedSubmit = true
        guard validationIssue == nil else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var urls: [URL] = []
            for photo in photos {
                urls.append(try await services.media.uploadJPEG(photo.data))
            }
            guard let draft = makeDraft(photoURLs: urls) else { return nil }
            let id = try await services.needs.createNeed(draft)
            error = nil
            return id
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }
}
