import Foundation
import Observation
import MamaCore

/// Formda seçilmiş, henüz yüklenmemiş fotoğraf.
public struct AnimalPhotoDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let data: Data

    public init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }
}

/// Kısırlık seçimi: `Bool?` yerine üç durumlu seçim (segment kontrol için).
public enum NeuteredChoice: String, CaseIterable, Hashable, Sendable {
    case unknown, yes, no

    public var label: String {
        switch self {
        case .unknown: return "Bilinmiyor"
        case .yes: return "Evet"
        case .no: return "Hayır"
        }
    }

    public var value: Bool? {
        switch self {
        case .unknown: return nil
        case .yes: return true
        case .no: return false
        }
    }
}

/// Hayvan ekleme formu (FR-A1, FR-A2).
@MainActor
@Observable
public final class AddAnimalViewModel {
    public static let maxPhotos = 3
    public static let nearbyRadiusMeters = 300

    public var species: AnimalSpecies = .cat
    public var name = ""
    public var colorPattern = ""
    public var sex: AnimalSex = .unknown
    public var ageEstimate: AgeEstimate = .unknown
    public var neutered: NeuteredChoice = .unknown
    public var earTag = false
    public var vaccinationInfo = ""
    public private(set) var temperamentTags: Set<TemperamentTag> = []
    public var warning: AnimalWarning?
    public var about = ""
    public private(set) var photos: [AnimalPhotoDraft] = []

    /// Seçili nokta. `preselectedSpotId` verildiyse başlangıçta odur.
    public var selectedSpotId: UUID?
    public let preselectedSpotId: UUID?
    public private(set) var preselectedSpot: Spot?
    public private(set) var nearbySpots: [Spot] = []
    public private(set) var isLoadingSpots = false

    public private(set) var isSubmitting = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(spotId: UUID?, services: AppServices) {
        self.preselectedSpotId = spotId
        self.selectedSpotId = spotId
        self.services = services
    }

    // MARK: - Noktalar

    /// Nokta verilmediyse yakındaki noktaları listeler (300 m).
    public func loadSpots(near coordinate: Coordinate?) async {
        isLoadingSpots = true
        defer { isLoadingSpots = false }
        if let preselectedSpotId {
            preselectedSpot = try? await services.spots.spot(id: preselectedSpotId)
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

    // MARK: - Etiketler ve fotoğraflar

    public func toggleTemperament(_ tag: TemperamentTag) {
        if temperamentTags.contains(tag) { temperamentTags.remove(tag) } else { temperamentTags.insert(tag) }
    }

    public var canAddPhoto: Bool { photos.count < Self.maxPhotos }

    public func addPhoto(_ data: Data) {
        guard canAddPhoto else { return }
        photos.append(AnimalPhotoDraft(data: data))
    }

    public func removePhoto(_ id: UUID) {
        photos.removeAll { $0.id == id }
    }

    // MARK: - Doğrulama ve gönderim

    /// Sunucudan önce anında geri bildirim (PRD 9.2). `nil` = sorun yok.
    public var validationMessage: String? {
        let texts = [name, colorPattern, vaccinationInfo, about]
        if texts.contains(where: ContentFilter.containsProfanity) {
            return MamaError.rejectedContent.userMessage
        }
        return nil
    }

    public var canSubmit: Bool { !isSubmitting && validationMessage == nil }

    public func makeDraft(photoURLs: [URL]) -> AnimalDraft {
        AnimalDraft(
            species: species,
            name: Self.cleaned(name),
            colorPattern: Self.cleaned(colorPattern),
            sex: sex,
            ageEstimate: ageEstimate,
            isNeutered: neutered.value,
            earTag: earTag,
            vaccinationInfo: Self.cleaned(vaccinationInfo),
            temperamentTags: TemperamentTag.allCases.filter(temperamentTags.contains),
            warning: warning,
            about: Self.cleaned(about),
            photoURLs: photoURLs,
            spotId: selectedSpotId
        )
    }

    /// Fotoğrafları yükler ve hayvanı oluşturur. Başarısızsa `error` dolar ve `nil` döner.
    public func submit() async -> Animal? {
        guard !isSubmitting else { return nil }
        if let message = validationMessage {
            error = .invalidInput(message)
            return nil
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var urls: [URL] = []
            for photo in photos {
                urls.append(try await services.media.uploadJPEG(photo.data))
            }
            let animal = try await services.animals.createAnimal(makeDraft(photoURLs: urls))
            error = nil
            return animal
        } catch {
            self.error = MamaError.classify(error)
            return nil
        }
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
