import Foundation
import MamaCore

/// Harita sekmesindeki bir eylemin kullanıcıya gösterilecek sonucu (toast metni + stil).
public struct MapFeedback: Equatable, Sendable {
    public var message: String
    public var style: AppRouter.Toast.Style
    public var isSuccess: Bool

    public init(message: String, style: AppRouter.Toast.Style, isSuccess: Bool) {
        self.message = message
        self.style = style
        self.isSuccess = isSuccess
    }

    init(error: MamaError) {
        self.init(message: error.userMessage, style: .warning, isSuccess: false)
    }

    /// Tek dokunuşla "Mama koydum" sonucunun metni (FR-C2, FR-C5, FR-H8).
    static func feeding(_ outcome: CheckInOutcome) -> MapFeedback {
        switch outcome {
        case .success(let receipt):
            if receipt.closedNeedCount > 0 {
                return MapFeedback(message: "Teşekkürler! Mama bekleyen noktayı sen kapattın.", style: .success, isSuccess: true)
            }
            return MapFeedback(message: "Teşekkürler! Mama koyduğun kaydedildi.", style: .success, isSuccess: true)
        case .tooFar(let distance, let maxDistance):
            return MapFeedback(
                message: "Noktaya biraz daha yaklaşman gerekiyor: \(MamaFormat.distance(distance)) uzaktasın, en fazla \(MamaFormat.distance(maxDistance)).",
                style: .warning,
                isSuccess: false
            )
        case .queuedOffline:
            return MapFeedback(message: "Bağlantı yok, check-in'in sırada; bağlantı gelince gönderilecek.", style: .info, isSuccess: true)
        case .rateLimited:
            return MapFeedback(message: "Bu noktaya az önce mama koyduğunu kaydettik. Biraz sonra tekrar deneyebilirsin.", style: .info, isSuccess: false)
        case .spotInactive:
            return MapFeedback(message: "Bu nokta artık aktif görünmüyor.", style: .warning, isSuccess: false)
        }
    }

    static func claim(_ outcome: ClaimOutcome) -> MapFeedback {
        switch outcome {
        case .ok:
            return MapFeedback(message: "Teşekkürler! İlgilendiğini herkes görecek.", style: .success, isSuccess: true)
        case .alreadyClaimed:
            return MapFeedback(message: "Bu ihtiyaçla başka bir gönüllü ilgileniyor.", style: .info, isSuccess: false)
        case .resolved:
            return MapFeedback(message: "Bu ihtiyaç çoktan çözülmüş. Yine de teşekkürler!", style: .info, isSuccess: false)
        }
    }

    static func flushed(count: Int) -> MapFeedback {
        MapFeedback(message: "Sıradaki \(count) check-in gönderildi. Teşekkürler!", style: .success, isSuccess: true)
    }

    static let noQuickFeedTarget = MapFeedback(
        message: "100 m içinde bir nokta bulamadık. İstersen yeni bir nokta ekleyebilirsin.",
        style: .info,
        isSuccess: false
    )
}
