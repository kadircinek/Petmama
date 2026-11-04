import Foundation
import Observation
import MamaCore

/// Nokta ekleme akışı (ekran 16, FR-N2 en fazla 3 adım, FR-N3 mükerrer önleme, PRD 9.3/9.4).
///
/// 1) Konumu doğrula (harita ortasındaki iğne) → 2) tip, tür, isteğe bağlı ad → 3) isteğe bağlı fotoğraf, not, görünürlük.
@MainActor
@Observable
public final class AddSpotFlowViewModel {
    public enum Step: Int, CaseIterable, Sendable {
        case location, details, extras
    }

    public enum SubmitResult: Equatable, Sendable {
        case created(id: UUID, pendingModeration: Bool)
        case duplicate([DuplicateCandidate])
        case limitReached(Int)
        case rejectedContent
        case failed(MamaError)
    }

    public static let titleLimit = 60
    public static let noteLimit = 280

    public var step: Step = .location
    public internal(set) var coordinate: Coordinate
    public var type: SpotType = .food
    public var species: SpotSpecies = .cat
    public var title = ""
    public var note = ""
    public var visibility: SpotVisibility = .public
    public internal(set) var photoData: Data?

    public internal(set) var duplicates: [DuplicateCandidate] = []
    public internal(set) var isSubmitting = false
    public internal(set) var lastResult: SubmitResult?
    public internal(set) var photoUploadFailed = false

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var hasExplicitLocation: Bool
    @ObservationIgnored private var uploadedPhotoURL: URL?

    /// `initialCoordinate` haritada uzun basmadan gelir (FR-H6); yoksa kullanıcı konumuyla başlanır.
    public init(initialCoordinate: Coordinate?, services: AppServices) {
        self.services = services
        self.coordinate = initialCoordinate ?? .modaKadikoy
        self.hasExplicitLocation = initialCoordinate != nil
    }

    public var isLastStep: Bool { step == .extras }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Anında geri bildirim için istemci tarafı küfür kontrolü (sunucu da kontrol eder, PRD 9.2).
    public var titleWarning: String? {
        if trimmedTitle.count > Self.titleLimit { return "Ad en fazla \(Self.titleLimit) karakter olabilir." }
        if ContentFilter.containsProfanity(trimmedTitle) { return "Adda uygunsuz bir ifade var gibi görünüyor." }
        return nil
    }

    public var noteWarning: String? {
        if trimmedNote.count > Self.noteLimit { return "Not en fazla \(Self.noteLimit) karakter olabilir." }
        if ContentFilter.containsProfanity(trimmedNote) { return "Notta uygunsuz bir ifade var gibi görünüyor." }
        return nil
    }

    public var canGoNext: Bool {
        switch step {
        case .location: return coordinate.isValid
        case .details: return titleWarning == nil
        case .extras: return false
        }
    }

    public var canSubmit: Bool {
        coordinate.isValid && titleWarning == nil && noteWarning == nil && !isSubmitting
    }

    /// Kullanıcı bir şey girdiyse sheet kaydırılarak yanlışlıkla kapanmasın.
    public var hasProgress: Bool {
        step != .location || !trimmedTitle.isEmpty || !trimmedNote.isEmpty || photoData != nil
    }

    /// Başlangıç koordinatı verilmediyse ve kullanıcı haritayı henüz kaydırmadıysa kullanıcı konumuna geçer.
    /// Konum değiştiyse `true` döner (görünüm kamerayı taşır).
    @discardableResult
    public func adoptUserLocation(_ user: Coordinate?) -> Bool {
        guard !hasExplicitLocation, let user, user.isValid else { return false }
        hasExplicitLocation = true
        coordinate = user
        return true
    }

    /// Harita ortasındaki iğnenin yeni konumu.
    public func moveCoordinate(to newValue: Coordinate) {
        guard newValue.isValid else { return }
        hasExplicitLocation = true
        coordinate = newValue
    }

    public func next() {
        guard canGoNext, let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    public func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// İsteğe bağlı fotoğraf (adım 3). Değişirse önceki yükleme geçersiz olur.
    public func setPhoto(_ data: Data?) {
        guard data != photoData else { return }
        photoData = data
        uploadedPhotoURL = nil
    }

    public func dismissDuplicates() {
        duplicates = []
    }

    @discardableResult
    public func submit(force: Bool = false) async -> SubmitResult {
        if ContentFilter.containsProfanity(trimmedTitle) || ContentFilter.containsProfanity(trimmedNote) {
            return finish(.rejectedContent)
        }
        isSubmitting = true
        defer { isSubmitting = false }
        photoUploadFailed = false
        if let photoData, uploadedPhotoURL == nil {
            do {
                uploadedPhotoURL = try await services.media.uploadJPEG(photoData)
            } catch {
                photoUploadFailed = true
            }
        }
        let draft = SpotDraft(
            coordinate: coordinate,
            type: type,
            species: species,
            title: String(trimmedTitle.prefix(Self.titleLimit)),
            note: trimmedNote.isEmpty ? nil : String(trimmedNote.prefix(Self.noteLimit)),
            photoURL: uploadedPhotoURL,
            visibility: visibility,
            force: force
        )
        do {
            switch try await services.spots.createSpot(draft) {
            case .created(let id, let pending):
                duplicates = []
                return finish(.created(id: id, pendingModeration: pending))
            case .duplicate(let candidates):
                duplicates = candidates
                return finish(.duplicate(candidates))
            case .limitReached(let limit):
                return finish(.limitReached(limit))
            case .rejectedContent:
                return finish(.rejectedContent)
            }
        } catch {
            return finish(.failed(MamaError.classify(error)))
        }
    }

    /// Sonucun kullanıcı metni.
    public func message(for result: SubmitResult) -> String {
        switch result {
        case .created(_, let pending):
            return pending
                ? "Noktan kısa bir incelemeden sonra haritada görünecek."
                : "Teşekkürler! Noktan haritaya eklendi."
        case .duplicate:
            return "Bu nokta zaten var mı?"
        case .limitReached(let limit):
            return "Bugün en fazla \(limit) nokta ekleyebilirsin. Yarın yine bekleriz!"
        case .rejectedContent:
            return MamaError.rejectedContent.userMessage
        case .failed(let error):
            return error.userMessage
        }
    }

    /// Adımda gösterilecek hata bandı (oluşturma ve mükerrer dışındaki sonuçlar).
    public var errorMessage: String? {
        switch lastResult {
        case .none, .created, .duplicate: return nil
        case .some(let result): return message(for: result)
        }
    }

    private func finish(_ result: SubmitResult) -> SubmitResult {
        lastResult = result
        return result
    }
}
