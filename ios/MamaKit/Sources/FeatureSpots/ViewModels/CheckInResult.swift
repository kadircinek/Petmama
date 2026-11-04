import Foundation
import MamaCore

/// Bir check-in denemesinin kullanıcı arayüzü sonucu. Her `CheckInOutcome` buraya eşlenir (FR-C1…C5, FR-H8).
public enum CheckInResult: Equatable, Sendable {
    case success(kind: CheckInKind, closedNeedCount: Int)
    case tooFar(distanceMeters: Double, maxDistanceMeters: Double)
    case queuedOffline
    case rateLimited
    case spotInactive
    case locationUnavailable
    case failed(MamaError)

    public init(_ outcome: CheckInOutcome, kind: CheckInKind) {
        switch outcome {
        case .success(let receipt): self = .success(kind: kind, closedNeedCount: receipt.closedNeedCount)
        case .tooFar(let distance, let maxDistance): self = .tooFar(distanceMeters: distance, maxDistanceMeters: maxDistance)
        case .queuedOffline: self = .queuedOffline
        case .rateLimited: self = .rateLimited
        case .spotInactive: self = .spotInactive
        }
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Başarı ve çevrimdışı kuyruk: işlem kabul edildi, sheet kapanır. Diğerlerinde kullanıcı sheet'te kalır.
    public var dismissesSheet: Bool {
        switch self {
        case .success, .queuedOffline: return true
        case .tooFar, .rateLimited, .spotInactive, .locationUnavailable, .failed: return false
        }
    }

    public var toastStyle: AppRouter.Toast.Style {
        switch self {
        case .success: return .success
        case .queuedOffline, .rateLimited: return .info
        case .tooFar, .spotInactive, .locationUnavailable, .failed: return .warning
        }
    }

    public var message: String {
        switch self {
        case .success(let kind, let closed):
            switch kind {
            case .fed:
                return closed > 0
                    ? "Teşekkürler! Mama bekleyen noktayı sen kapattın."
                    : "Teşekkürler! Mama koyduğun kaydedildi."
            case .water:
                return closed > 0
                    ? "Teşekkürler! Bekleyen bildirimi sen kapattın."
                    : "Teşekkürler! Su koyduğun kaydedildi."
            case .needFood, .needWater, .broken:
                return "Teşekkürler! Yakındaki gönüllülere haber verdik."
            }
        case .tooFar(let distance, let maxDistance):
            return Self.tooFarMessage(distance: distance, maxDistance: maxDistance)
        case .queuedOffline:
            return "Bağlantı yok, check-in'in sırada; bağlantı gelince gönderilecek."
        case .rateLimited:
            return "Bu noktaya az önce kayıt girdin. Biraz sonra tekrar deneyebilirsin."
        case .spotInactive:
            return "Bu nokta artık aktif görünmüyor. Yakında başka bir nokta olabilir."
        case .locationUnavailable:
            return "Konumunu alamadık. Check-in için noktaya yakın olduğunu doğrulamamız gerekiyor."
        case .failed(let error):
            return error.userMessage
        }
    }

    static func tooFarMessage(distance: Double, maxDistance: Double) -> String {
        "Noktaya biraz daha yaklaşman gerekiyor: \(MamaFormat.distance(distance)) uzaktasın, en fazla \(MamaFormat.distance(maxDistance))."
    }
}

/// Nokta ekranlarındaki küçük eylemlerin (takip, koruyuculuk, "artık yok") toast sonucu.
public struct SpotFeedback: Equatable, Sendable {
    public var message: String
    public var style: AppRouter.Toast.Style
    public var isSuccess: Bool

    public init(message: String, style: AppRouter.Toast.Style = .success, isSuccess: Bool = true) {
        self.message = message
        self.style = style
        self.isSuccess = isSuccess
    }

    init(error: MamaError) {
        self.init(message: error.userMessage, style: .warning, isSuccess: false)
    }
}
