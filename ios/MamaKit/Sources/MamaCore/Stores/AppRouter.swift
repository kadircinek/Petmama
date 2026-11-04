import Foundation
import Observation

/// Değer tabanlı gezinme hedefleri. Feature modülleri birbirini import etmez; rotayı `AppFeature` çözer.
public enum AppRoute: Hashable, Sendable {
    case spot(UUID)
    case animal(UUID)
    case need(UUID)
    case following
    case notifications
    case settings
    case search
    case donationTrace
    case feedingGuide
    case vetHelp(needId: UUID?)
    case privacy
}

/// Modallar (sheet). Birden fazla feature'dan açılabilenler burada.
public enum AppSheet: Identifiable, Hashable, Sendable {
    /// Orta "+ Ekle" menüsü (ekran 15).
    case addMenu
    /// Nokta ekleme akışı (ekran 16). Koordinat verilirse (haritada uzun basma, FR-H6) oradan başlar.
    case addSpot(Coordinate?)
    case checkIn(spotId: UUID, kind: CheckInKind)
    /// Ana sayfadaki tek dokunuşla "Mama koydum": 100 m içindeki en yakın nokta (PRD 6.4).
    case quickFeed
    case createNeed(spotId: UUID?, animalId: UUID?)
    case createAnimal(spotId: UUID?)
    case report(ReportTarget, UUID)
    case signIn
    case editProfile

    public var id: String {
        switch self {
        case .addMenu: return "addMenu"
        case .addSpot(let c): return "addSpot-\(c?.description ?? "here")"
        case .checkIn(let id, let kind): return "checkIn-\(id)-\(kind.rawValue)"
        case .quickFeed: return "quickFeed"
        case .createNeed(let s, let a): return "createNeed-\(s?.uuidString ?? "")-\(a?.uuidString ?? "")"
        case .createAnimal(let s): return "createAnimal-\(s?.uuidString ?? "")"
        case .report(let t, let id): return "report-\(t.rawValue)-\(id)"
        case .signIn: return "signIn"
        case .editProfile: return "editProfile"
        }
    }

    /// Oturum gerektiren modallar (FR-P1).
    public var requiresSignIn: Bool {
        switch self {
        case .addMenu, .signIn: return false
        case .addSpot, .checkIn, .quickFeed, .createNeed, .createAnimal, .report, .editProfile: return true
        }
    }
}

/// Tab bar: Harita · İhtiyaçlar · + Ekle · Bağış · Profil (PRD 6.2).
public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case map, needs, add, donate, profile
}

@MainActor
@Observable
public final class AppRouter {
    public var selectedTab: AppTab = .map
    public var paths: [AppTab: [AppRoute]] = [:]
    public var sheet: AppSheet?
    /// Giriş sonrası açılacak modal.
    public private(set) var pendingSheetAfterSignIn: AppSheet?
    /// Kısa süreli bilgi bandı ("Teşekkürler! Mama koyduğun kaydedildi.").
    public var toast: Toast?

    public init() {}

    public struct Toast: Identifiable, Hashable, Sendable {
        public enum Style: Hashable, Sendable { case success, info, warning }
        public let id = UUID()
        public var message: String
        public var style: Style

        public init(_ message: String, style: Style = .success) {
            self.message = message
            self.style = style
        }
    }

    public func path(for tab: AppTab) -> [AppRoute] {
        paths[tab] ?? []
    }

    public func setPath(_ path: [AppRoute], for tab: AppTab) {
        paths[tab] = path
    }

    public func push(_ route: AppRoute) {
        paths[selectedTab, default: []].append(route)
    }

    public func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    /// Orta "+" sekmesi seçilmez; menüyü açar.
    public func select(_ tab: AppTab) {
        if tab == .add {
            present(.addMenu, session: nil)
            return
        }
        if tab == selectedTab {
            popToRoot(tab)
        }
        selectedTab = tab
    }

    /// Oturum gerektiren modal için önce giriş ekranını gösterir, sonra asıl modalı açar.
    public func present(_ sheet: AppSheet, session: SessionStore?) {
        if sheet.requiresSignIn, let session, !session.isSignedIn {
            pendingSheetAfterSignIn = sheet
            self.sheet = .signIn
        } else {
            self.sheet = sheet
        }
    }

    public func dismissSheet() {
        sheet = nil
    }

    /// Giriş ekranı kapanınca çağrılır.
    public func signInFinished(success: Bool) {
        let next = success ? pendingSheetAfterSignIn : nil
        pendingSheetAfterSignIn = nil
        sheet = next
    }

    public func showToast(_ message: String, style: Toast.Style = .success) {
        toast = Toast(message, style: style)
    }

    /// Push bildirimi veya derin bağlantıdan gelen hedef.
    public func open(_ route: AppRoute, in tab: AppTab = .map) {
        sheet = nil
        selectedTab = tab
        paths[tab] = [route]
    }
}
