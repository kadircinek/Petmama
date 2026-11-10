import Foundation
import Observation
import MamaCore

/// "Nokta bağla" seçeneği: önce kullanıcının koruyucusu olduğu noktalar, sonra yakındakiler.
public struct CommunitySpotOption: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// Sheet bu noktayla açıldı (ör. nokta detayından "Yerime bakar mısın?").
        case preset
        case guarded
        case nearby
    }

    public let spot: Spot
    public let source: Source
    /// Kullanıcının konumundan uzaklık; konum yoksa `nil`.
    public let distanceMeters: Double?

    public var id: UUID { spot.id }
}

/// "Mahalleye yaz" formu: tür, metin, isteğe bağlı fotoğraf ve nokta, "Yerime bakar mısın?" tarihleri.
@MainActor
@Observable
public final class CreatePostViewModel {
    public static let nearbyRadiusMeters = 500
    public static let maxNearbyOptions = 8

    public var kind: CommunityPostKind
    public var bodyText = ""
    public var selectedSpotId: UUID?
    /// "Yerime bakar mısın?" aralığı (İstanbul günü, ikisi de dahil). Yalnızca o türde gönderilir.
    public var coverFrom: Date
    public var coverTo: Date
    public private(set) var photo: CommunityPhotoDraft?

    public let presetSpotId: UUID?
    public private(set) var spotOptions: [CommunitySpotOption] = []
    public private(set) var isLoadingSpots = false
    public private(set) var hasLoadedSpots = false

    /// İlk gönderme denemesinden sonra doğrulama mesajları görünür.
    public private(set) var attemptedSubmit = false
    public private(set) var isSubmitting = false
    /// Sunucunun ya da bağlantının geri çevirdiği son denemenin açıklaması.
    public private(set) var submitProblem: String?

    @ObservationIgnored private let services: AppServices
    /// Yeniden denemede aynı fotoğraf ikinci kez yüklenmesin.
    @ObservationIgnored private var uploadedPhoto: (id: UUID, url: URL)?

    public init(kind: CommunityPostKind?, spotId: UUID?, services: AppServices) {
        self.kind = kind ?? .note
        self.presetSpotId = spotId
        self.selectedSpotId = spotId
        self.services = services
        // Varsayılan: yarın başlayıp ertesi gün biten iki günlük aralık.
        let calendar = CommunityFormat.istanbulCalendar
        let today = calendar.startOfDay(for: services.now())
        self.coverFrom = Self.noon(of: calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        self.coverTo = Self.noon(of: calendar.date(byAdding: .day, value: 2, to: today) ?? today)
    }

    // MARK: - Metin

    public var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var remainingCharacters: Int { CommunityPolicy.maxBodyLength - trimmedBody.count }
    public var isOverLimit: Bool { remainingCharacters < 0 }

    /// Kapatmadan önce onay gerektiren taslak var mı?
    public var hasDraftContent: Bool { !trimmedBody.isEmpty || photo != nil }

    // MARK: - Nokta

    public var isCoverRequest: Bool { kind == .coverRequest }
    /// "Yerime bakar mısın?" için nokta zorunlu; diğer türlerde isteğe bağlı.
    public var isSpotRequired: Bool { isCoverRequest }

    public var selectedSpot: CommunitySpotOption? {
        spotOptions.first { $0.id == selectedSpotId }
    }

    public func toggleSpot(_ id: UUID) {
        selectedSpotId = selectedSpotId == id ? nil : id
    }

    /// Nokta seçeneklerini yükler: (varsa) açılıştaki nokta, koruyucusu olunan noktalar, 500 m içindekiler.
    public func load(near coordinate: Coordinate?) async {
        isLoadingSpots = true
        defer {
            isLoadingSpots = false
            hasLoadedSpots = true
        }
        var options: [CommunitySpotOption] = []
        var seen: Set<UUID> = []

        if let presetSpotId {
            do {
                if let spot = try await services.spots.spot(id: presetSpotId) {
                    seen.insert(spot.id)
                    options.append(option(spot, source: .preset, from: coordinate))
                } else if selectedSpotId == presetSpotId {
                    // Nokta artık görünmüyor: bağlamadan devam edilir.
                    selectedSpotId = nil
                }
            } catch {
                // Bağlantı sorunu: seçim korunur, son kararı sunucu verir.
            }
        }

        let guardedIds = (try? await services.profiles.guardedSpotIds()) ?? []
        var guarded: [CommunitySpotOption] = []
        for id in guardedIds where !seen.contains(id) {
            if let spot = try? await services.spots.spot(id: id) {
                seen.insert(spot.id)
                guarded.append(option(spot, source: .guarded, from: coordinate))
            }
        }
        options.append(contentsOf: guarded.sorted(by: Self.isCloser))

        if let coordinate {
            let nearby = (try? await services.spots.spots(near: coordinate, radiusMeters: Self.nearbyRadiusMeters)) ?? []
            let fresh = nearby.filter { !seen.contains($0.id) }.prefix(Self.maxNearbyOptions)
            options.append(contentsOf: fresh.map { option($0, source: .nearby, from: coordinate) })
        }
        spotOptions = options
    }

    // MARK: - Fotoğraf

    public func setPhoto(_ data: Data) {
        photo = CommunityPhotoDraft(data: data)
    }

    public func removePhoto() {
        photo = nil
    }

    // MARK: - Tarihler

    /// Bugün (İstanbul) ve sonrası seçilebilir.
    public var earliestCoverStart: Date {
        CommunityFormat.istanbulCalendar.startOfDay(for: services.now())
    }

    /// Bitiş için geçerli aralık: başlangıç günü … başlangıç + `maxCoverDays`.
    public var coverToRange: ClosedRange<Date> {
        let calendar = CommunityFormat.istanbulCalendar
        let start = calendar.startOfDay(for: coverFrom)
        let lastDay = calendar.date(byAdding: .day, value: CommunityPolicy.maxCoverDays, to: start) ?? start
        return start...lastDay.addingTimeInterval(86_399)
    }

    /// Başlangıç değişince bitişi geçerli aralığa çeker (bitiş ≥ başlangıç, en fazla `maxCoverDays` gün).
    public func normalizeCoverDates() {
        if coverFrom < earliestCoverStart { coverFrom = Self.noon(of: earliestCoverStart) }
        let range = coverToRange
        if coverTo < range.lowerBound {
            coverTo = Self.noon(of: range.lowerBound)
        } else if coverTo > range.upperBound {
            coverTo = Self.noon(of: range.upperBound)
        }
    }

    // MARK: - Gönderme

    /// `coordinate` yalnızca nokta bağlı değilken gönderilir; sunucu ≈1 km'ye yuvarlanmış halini saklar.
    public func makeDraft(near coordinate: Coordinate?, photoURL: URL? = nil) -> CommunityPostDraft {
        CommunityPostDraft(
            kind: kind,
            body: trimmedBody,
            photoURL: photoURL,
            spotId: selectedSpotId,
            coordinate: selectedSpotId == nil ? coordinate : nil,
            coverFrom: isCoverRequest ? Self.noon(of: coverFrom) : nil,
            coverTo: isCoverRequest ? Self.noon(of: coverTo) : nil
        )
    }

    /// Gönderimden önce dostça ön kontrol (asıl karar sunucuda).
    public func validationError(near coordinate: Coordinate?) -> CommunityValidationError? {
        CommunityPolicy.validate(makeDraft(near: coordinate), now: services.now())
    }

    /// Formda gösterilecek uyarı: ilk denemeden sonra canlı ön kontrol, yoksa son denemenin sonucu.
    public func visibleProblem(near coordinate: Coordinate?) -> String? {
        guard attemptedSubmit else { return nil }
        return validationError(near: coordinate)?.userMessage ?? submitProblem
    }

    /// Doğrular, (varsa) fotoğrafı yükler ve paylaşımı oluşturur. `nil` = zaten gönderiliyor.
    public func submit(near coordinate: Coordinate?) async -> CreatePostResult? {
        guard !isSubmitting else { return nil }
        attemptedSubmit = true
        submitProblem = nil
        if let invalid = validationError(near: coordinate) { return .invalid(invalid) }

        isSubmitting = true
        defer { isSubmitting = false }
        let result: CreatePostResult
        do {
            let photoURL = try await uploadPhotoIfNeeded()
            result = CreatePostResult(try await services.community.createPost(makeDraft(near: coordinate, photoURL: photoURL)))
        } catch {
            result = .failed(MamaError.classify(error))
        }
        if !result.isCreated { submitProblem = result.message }
        return result
    }

    // MARK: - Yardımcılar

    private func uploadPhotoIfNeeded() async throws -> URL? {
        guard let photo else { return nil }
        if let uploadedPhoto, uploadedPhoto.id == photo.id { return uploadedPhoto.url }
        let url = try await services.media.uploadJPEG(photo.data)
        uploadedPhoto = (photo.id, url)
        return url
    }

    private func option(_ spot: Spot, source: CommunitySpotOption.Source, from coordinate: Coordinate?) -> CommunitySpotOption {
        let distance = spot.distanceMeters ?? coordinate.map { GeoMath.distance($0, spot.coordinate) }
        return CommunitySpotOption(spot: spot, source: source, distanceMeters: distance)
    }

    private static func isCloser(_ lhs: CommunitySpotOption, _ rhs: CommunitySpotOption) -> Bool {
        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (a?, b?) where a != b: return a < b
        default: return lhs.spot.title.localizedCompare(rhs.spot.title) == .orderedAscending
        }
    }

    /// Günün öğlesi (İstanbul): gün bilgisi saat dilimi dönüşümlerinde kaymasın.
    private static func noon(of date: Date) -> Date {
        CommunityFormat.istanbulCalendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
    }
}
