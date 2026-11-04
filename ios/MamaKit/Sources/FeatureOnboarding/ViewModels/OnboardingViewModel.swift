import Foundation
import Observation
import MamaCore

/// İlk kullanım akışı (ekran 2–7): 3 tanıtım sayfası → konum izni → bildirim izni → giriş.
///
/// "Atla" tanıtım sayfalarını geçer; izin ekranlarındaki "Şimdi değil" yalnızca o adımı geçer.
/// Zaten karar verilmiş izinler ve açık oturum `prepare` ile atlanır.
@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Step: Hashable, Sendable {
        case intro(Int)
        case location
        case notifications
        case signIn

        public var isIntro: Bool {
            if case .intro = self { return true }
            return false
        }
    }

    public struct IntroPage: Identifiable, Hashable, Sendable {
        public enum Tint: Sendable, Hashable { case mint, blue, peach }

        public let id: Int
        public let title: String
        public let message: String
        /// Büyük ana sembol ve etrafındaki küçük semboller (SF Symbols).
        public let symbol: String
        public let accentSymbols: [String]
        public let tint: Tint
    }

    public static let introPages: [IntroPage] = [
        IntroPage(
            id: 0,
            title: "Haritada mama noktalarını gör",
            message: "Mahallendeki mama ve su noktaları tek haritada. Yeşil yakın zamanda mama konduğunu, turuncu mama beklediğini gösterir.",
            symbol: "map.fill",
            accentSymbols: ["pawprint.fill", "mappin.circle.fill", "drop.fill"],
            tint: .mint
        ),
        IntroPage(
            id: 1,
            title: "Mama koy, bildir",
            message: "Mama koyduğunda tek dokunuşla haber ver. Kap boşsa \"mama gerekli\" de; yakındaki gönüllüler haberdar olsun.",
            symbol: "pawprint.fill",
            accentSymbols: ["cat.fill", "dog.fill", "checkmark.circle.fill"],
            tint: .peach
        ),
        IntroPage(
            id: 2,
            title: "Bağışla destek ol",
            message: "Ortak derneğe yaptığın bağış, mama olarak en çok ihtiyaç olan noktalara ulaşır. Nereye gittiğini de görürsün.",
            symbol: "heart.fill",
            accentSymbols: ["gift.fill", "cat.fill", "dog.fill"],
            tint: .blue
        ),
    ]

    public static var introPageCount: Int { introPages.count }

    public private(set) var step: Step = .intro(0)
    public private(set) var isFinished = false
    public private(set) var isRequesting = false
    /// İzin ekranlarının sonucu. `nil` = sorulmadı veya "Şimdi değil".
    public private(set) var locationResult: LocationAuthorization?
    public private(set) var notificationsGranted: Bool?

    private var skipsLocation = false
    private var skipsNotifications = false
    private var skipsSignIn = false

    public init() {}

    /// Ekran açılınca çağrılır: zaten verilmiş kararlar ve açık oturum için ilgili adımlar atlanır.
    public func prepare(locationDecided: Bool, notificationsDecided: Bool, signedIn: Bool) {
        skipsLocation = locationDecided
        skipsNotifications = notificationsDecided
        skipsSignIn = signedIn
    }

    // MARK: - Durum

    /// Akışın bu oturumda göstereceği adımlar.
    public var steps: [Step] { Self.canonicalOrder.filter(isIncluded) }

    public var introIndex: Int? {
        if case .intro(let index) = step { return index }
        return nil
    }

    /// Sağ üstteki "Atla" yalnızca tanıtım sayfalarında.
    public var showsSkip: Bool { step.isIntro }

    public var isLastIntroPage: Bool { introIndex == Self.introPageCount - 1 }

    // MARK: - Geçişler

    public func advance() {
        guard let index = Self.canonicalOrder.firstIndex(of: step) else {
            finish()
            return
        }
        if let next = Self.canonicalOrder[(index + 1)...].first(where: isIncluded) {
            step = next
        } else {
            finish()
        }
    }

    /// "Atla": tanıtımı geç, ilk izin/giriş adımına git.
    public func skipIntro() {
        if let next = Self.canonicalOrder.first(where: { !$0.isIntro && isIncluded($0) }) {
            step = next
        } else {
            finish()
        }
    }

    /// Sayfa kaydırma ile tanıtım sayfası değişimi.
    public func showIntro(page: Int) {
        guard step.isIntro else { return }
        step = .intro(min(max(page, 0), Self.introPageCount - 1))
    }

    /// "Konuma izin ver". İstek görünümden gelir (`LocationStore.requestAuthorization`).
    public func requestLocation(_ request: () async -> LocationAuthorization) async {
        guard step == .location, !isRequesting else { return }
        isRequesting = true
        locationResult = await request()
        isRequesting = false
        advance()
    }

    /// "Bildirimlere izin ver". İstek görünümden gelir (`UNUserNotificationCenter`).
    public func requestNotifications(_ request: () async -> Bool) async {
        guard step == .notifications, !isRequesting else { return }
        isRequesting = true
        notificationsGranted = await request()
        isRequesting = false
        advance()
    }

    /// İzin ekranlarında "Şimdi değil".
    public func notNow() {
        guard !step.isIntro else { return }
        advance()
    }

    /// Giriş yapıldı veya "Şimdilik gez" (FR-P1: hesapsız gezinmek serbest).
    public func finish() {
        isFinished = true
    }

    // MARK: - Yardımcılar

    private static let canonicalOrder: [Step] =
        (0..<introPageCount).map(Step.intro) + [.location, .notifications, .signIn]

    private func isIncluded(_ step: Step) -> Bool {
        switch step {
        case .intro: return true
        case .location: return !skipsLocation
        case .notifications: return !skipsNotifications
        case .signIn: return !skipsSignIn
        }
    }
}
