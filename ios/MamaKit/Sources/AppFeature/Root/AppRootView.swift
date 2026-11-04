#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign
import FeatureDonate
import FeatureMap
import FeatureNeeds
import FeatureOnboarding
import FeatureProfile

/// Uygulamanın kök görünümü: açılış → ilk kullanım akışı → sekmeler.
public struct AppRootView: View {
    @State private var model: AppModel
    @State private var connectivity = ConnectivityMonitor()
    @State private var showSplash = true
    @AppStorage("mama.onboardingCompleted") private var onboardingCompleted = false
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else if !onboardingCompleted {
                OnboardingFlow(services: model.services) {
                    withAnimation(.easeInOut) { onboardingCompleted = true }
                }
                .transition(.opacity)
            } else {
                MainTabView(services: model.services)
                    .transition(.opacity)
            }
        }
        .environment(\.services, model.services)
        .environment(model.session)
        .environment(model.router)
        .environment(model.location)
        .tint(MamaColor.ink)
        .task {
            connectivity.onReconnect = { Task { await model.flushOfflineQueue() } }
            connectivity.start()
            await model.start()
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await model.location.refresh()
                    await model.flushOfflineQueue()
                }
            }
        }
        .onChange(of: model.session.isSignedIn) { _, _ in
            Task { await model.signedInStateChanged() }
        }
        .task(id: notifyCenterKey) {
            await model.updateNotifyCenterIfNeeded(model.location.coordinate)
        }
    }

    /// Konum ~300 m'lik ızgarada değişince tetiklenir (D8).
    private var notifyCenterKey: String {
        guard let c = model.location.coordinate else { return "none-\(model.session.isSignedIn)" }
        return String(format: "%.3f,%.3f,%d", c.latitude, c.longitude, model.session.isSignedIn ? 1 : 0)
    }
}

/// Beş sekmeli ana görünüm. Sistem tab bar'ı gizli; yerine `MamaTabBar`.
struct MainTabView: View {
    let services: AppServices
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            TabStack(tab: .map, services: services) { MapTabScreen(services: services) }
                .tag(AppTab.map)
                .toolbar(.hidden, for: .tabBar)
            TabStack(tab: .needs, services: services) { NeedsTabScreen(services: services) }
                .tag(AppTab.needs)
                .toolbar(.hidden, for: .tabBar)
            TabStack(tab: .donate, services: services) { DonateTabScreen(services: services) }
                .tag(AppTab.donate)
                .toolbar(.hidden, for: .tabBar)
            TabStack(tab: .profile, services: services) { ProfileTabScreen(services: services) }
                .tag(AppTab.profile)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MamaTabBar(selected: router.selectedTab) { tab in
                router.select(tab)
            }
        }
        .sheet(item: $router.sheet) { sheet in
            SheetDestination(sheet: sheet, services: services)
        }
        .mamaToast($router.toast)
    }
}
#endif
