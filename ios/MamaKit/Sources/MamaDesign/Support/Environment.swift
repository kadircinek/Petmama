#if canImport(UIKit)
import CoreLocation
import SwiftUI
import MamaCore

// SwiftUI ortamında servis kabı. Gözlemlenebilir store'lar (SessionStore, AppRouter, LocationStore)
// `.environment(store)` ile konur ve `@Environment(SessionStore.self)` ile okunur.

private struct ServicesKey: EnvironmentKey {
    static let defaultValue: AppServices = .demo()
}

extension EnvironmentValues {
    public var services: AppServices {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }
}

extension Coordinate {
    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Önizlemeler için hazır ortam: demo servisler, oturum açık, Moda konumu.
///
///     #Preview { PreviewEnvironment { services in SpotDetailScreen(spotId: DemoData.id(2, 1), services: services) } }
public struct PreviewEnvironment<Content: View>: View {
    @State private var session: SessionStore
    @State private var router = AppRouter()
    @State private var location: LocationStore
    private let services: AppServices
    private let content: (AppServices) -> Content

    public init(signedIn: Bool = true, @ViewBuilder content: @escaping (AppServices) -> Content) {
        let services = AppServices.demo(signedIn: signedIn)
        self.services = services
        let profile = signedIn ? UserProfile(id: DemoData.meId, displayName: "Sen", neighborhood: "Moda") : nil
        self._session = State(initialValue: SessionStore(auth: services.auth, profiles: services.profiles, profile: profile))
        self._location = State(initialValue: LocationStore(driver: StaticLocationDriver()))
        self.content = content
    }

    public var body: some View {
        NavigationStack {
            content(services)
        }
            .environment(\.services, services)
            .environment(session)
            .environment(router)
            .environment(location)
            .task { location.start() }
    }
}
#endif
