import Foundation
import Observation
import MamaCore

/// "Bağışım nereye gitti?" çizelgesinin bir adımı (ekran 19).
public struct DonationTraceStep: Identifiable, Hashable, Sendable {
    public let id: Int
    public var title: String
    public var detail: String
    public var systemImage: String
    /// `false` → "v1.1'de" (D13: teslim kanıtı v1.1).
    public var isAvailable: Bool
}

@MainActor
@Observable
public final class DonationTraceViewModel {
    public static let comingSoonLabel = "v1.1'de"

    public private(set) var overview: DonationOverview?
    public private(set) var hasLoaded = false
    @ObservationIgnored private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var steps: [DonationTraceStep] {
        [
            DonationTraceStep(
                id: 1,
                title: "Bağış alındı",
                detail: "Bağışın derneğin kendi sayfasında alınır, makbuzun dernekten e-postayla gelir. Mama Haritası para toplamaz.",
                systemImage: "heart.fill",
                isAvailable: true
            ),
            DonationTraceStep(
                id: 2,
                title: "Toplu mama alımı",
                detail: "Dernek, haftanın bağışlarıyla toptan fiyata kuru mama alır.",
                systemImage: "cart.fill",
                isAvailable: false
            ),
            DonationTraceStep(
                id: 3,
                title: "Noktalara teslim",
                detail: "Doğrulanmış besleyiciler ve dernek gönüllüleri mamayı en çok ihtiyaç olan noktalara bırakır. Her teslim fotoğraf, konum ve kg ile kaydedilir.",
                systemImage: "mappin.and.ellipse",
                isAvailable: false
            ),
            DonationTraceStep(
                id: 4,
                title: "Sana bildirim",
                detail: "“Bağışının da katkı verdiği 40 kg mama Kadıköy'de 12 noktaya ulaştı” gibi bir bildirim alırsın.",
                systemImage: "bell.fill",
                isAvailable: false
            ),
        ]
    }

    /// "Kasım 2026"
    public var monthTitle: String? {
        guard let month = overview?.month else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month)
    }

    public var kilogramsText: String? {
        overview.map { MamaFormat.kilograms($0.kgDistributed, language: .turkish) }
    }

    public var donorCountText: String? {
        guard let count = overview?.donorCount, count > 0 else { return nil }
        return "\(count) bağışçı"
    }

    public func load() async {
        overview = try? await services.donations.overview()
        hasLoaded = true
    }
}
