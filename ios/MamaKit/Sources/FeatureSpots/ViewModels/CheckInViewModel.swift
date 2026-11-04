import Foundation
import Observation
import MamaCore

/// "Mama koydum" / "Mama gerekli" check-in'i (FR-C1…C5).
///
/// Akış: noktayı yükle → taze konumla ön kontrol (`CheckInPolicy.precheck`) → isteğe bağlı fotoğrafı yükle →
/// `services.checkIns` (çevrimdışı kuyruk dahil) → sonucu `CheckInResult`'a eşle.
@MainActor
@Observable
public final class CheckInViewModel {
    /// Ön kontrol mesajının tonu (görünüm renge çevirir).
    public enum Tone: Equatable, Sendable {
        case ok, info, warning
    }

    public let spotId: UUID
    public let initialKind: CheckInKind
    public var kind: CheckInKind
    public var amount: FoodAmount?
    public var photoData: Data?

    public internal(set) var spot: Spot?
    public internal(set) var userCoordinate: Coordinate?
    public internal(set) var isLoading = false
    public internal(set) var isSubmitting = false
    public internal(set) var result: CheckInResult?
    /// Fotoğraf yüklenemedi; check-in fotoğrafsız gönderildi.
    public internal(set) var photoUploadFailed = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices

    public init(spotId: UUID, kind: CheckInKind, services: AppServices) {
        self.spotId = spotId
        self.initialKind = kind
        self.kind = kind
        self.services = services
    }

    /// "Mama gerekli" akışı mı (mama bitti / su bitti / kap kırık seçimi)?
    public var isRequestFlow: Bool { initialKind.isRequest }

    public var availableKinds: [CheckInKind] {
        isRequestFlow ? CheckInKind.requestKinds : [.fed, .water]
    }

    /// Miktar yalnızca "Mama koydum" için sorulur (FR-C2).
    public var asksAmount: Bool { kind == .fed }

    /// Fotoğraf yalnızca besleme check-in'lerinde (fotoğraflı check-in daha çok puan kazandırır).
    public var allowsPhoto: Bool { !kind.isRequest }

    public var precheck: CheckInPolicy.Precheck? {
        guard let spot else { return nil }
        return CheckInPolicy.precheck(kind: kind, user: userCoordinate, spot: spot)
    }

    public var precheckMessage: String? {
        switch precheck {
        case .none:
            return nil
        case .allowed(let distance):
            return "Konumun uygun: noktaya \(MamaFormat.distance(distance)) uzaktasın."
        case .tooFar(let distance, let maxDistance):
            return CheckInResult.tooFarMessage(distance: distance, maxDistance: maxDistance)
        case .deferToServer:
            return "Bu noktanın konumu yaklaşık gösteriliyor; mesafeyi gönderirken biz kontrol edeceğiz."
        case .locationUnavailable:
            return "Konumunu alamadık. Check-in için noktaya yakın olduğunu doğrulamamız gerekiyor."
        }
    }

    public var precheckTone: Tone {
        switch precheck {
        case .allowed: return .ok
        case .none, .deferToServer: return .info
        case .tooFar, .locationUnavailable: return .warning
        }
    }

    public var isTooFar: Bool {
        if case .tooFar = precheck { return true }
        return false
    }

    public var canSubmit: Bool {
        guard spot != nil, !isSubmitting else { return false }
        switch precheck {
        case .allowed, .deferToServer: return true
        case .tooFar, .locationUnavailable, .none: return false
        }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            spot = try await services.spots.spot(id: spotId)
            if spot == nil { error = .notFound }
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func updateLocation(_ coordinate: Coordinate?) {
        if let coordinate { userCoordinate = coordinate }
    }

    public func toggleAmount(_ value: FoodAmount) {
        amount = amount == value ? nil : value
    }

    @discardableResult
    public func submit(user: Coordinate?) async -> CheckInResult {
        updateLocation(user)
        guard let spot else { return finish(.failed(error ?? .notFound)) }
        guard let coordinate = userCoordinate else { return finish(.locationUnavailable) }
        if case .tooFar(let distance, let maxDistance) = CheckInPolicy.precheck(kind: kind, user: coordinate, spot: spot) {
            return finish(.tooFar(distanceMeters: distance, maxDistanceMeters: maxDistance))
        }

        isSubmitting = true
        defer { isSubmitting = false }
        photoUploadFailed = false
        var photoURL: URL?
        if allowsPhoto, let photoData {
            do {
                photoURL = try await services.media.uploadJPEG(photoData)
            } catch {
                photoUploadFailed = true
            }
        }
        let draft = CheckInDraft(
            spotId: spot.id,
            kind: kind,
            amount: asksAmount ? amount : nil,
            photoURL: photoURL,
            userCoordinate: coordinate,
            createdAt: services.now()
        )
        do {
            let outcome = try await services.checkIns.checkIn(draft)
            return finish(CheckInResult(outcome, kind: kind))
        } catch {
            return finish(.failed(MamaError.classify(error)))
        }
    }

    private func finish(_ result: CheckInResult) -> CheckInResult {
        self.result = result
        return result
    }
}
