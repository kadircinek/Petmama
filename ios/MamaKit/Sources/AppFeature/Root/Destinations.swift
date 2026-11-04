#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign
import FeatureAnimals
import FeatureDonate
import FeatureMap
import FeatureNeeds
import FeatureOnboarding
import FeatureProfile
import FeatureSpots

/// `AppRoute` → ekran. Feature modülleri birbirini tanımaz; eşleme burada yapılır.
struct RouteDestination: View {
    let route: AppRoute
    let services: AppServices

    var body: some View {
        switch route {
        case .spot(let id):
            SpotDetailScreen(spotId: id, services: services)
        case .animal(let id):
            AnimalProfileScreen(animalId: id, services: services)
        case .need(let id):
            NeedDetailScreen(needId: id, services: services)
        case .following:
            FollowingScreen(services: services)
        case .notifications:
            NotificationsScreen(services: services)
        case .settings:
            SettingsScreen(services: services)
        case .search:
            SearchScreen(services: services)
        case .donationTrace:
            DonationTraceScreen(services: services)
        case .feedingGuide:
            FeedingGuideScreen()
        case .vetHelp(let needId):
            VetHelpScreen(needId: needId, services: services)
        case .privacy:
            PrivacyScreen(services: services)
        }
    }
}

/// `AppSheet` → modal içerik.
struct SheetDestination: View {
    let sheet: AppSheet
    let services: AppServices
    @Environment(AppRouter.self) private var router

    var body: some View {
        switch sheet {
        case .addMenu:
            AddMenuSheet(services: services)
        case .addSpot(let coordinate):
            AddSpotFlow(initialCoordinate: coordinate, services: services)
        case .checkIn(let spotId, let kind):
            CheckInSheet(spotId: spotId, kind: kind, services: services)
        case .quickFeed:
            QuickFeedSheet(services: services)
        case .createNeed(let spotId, let animalId):
            CreateNeedFlow(spotId: spotId, animalId: animalId, services: services)
        case .createAnimal(let spotId):
            AddAnimalFlow(spotId: spotId, services: services)
        case .report(let target, let id):
            ReportSheet(target: target, targetId: id, services: services)
        case .signIn:
            SignInScreen(services: services) { success in
                router.signInFinished(success: success)
            }
        case .editProfile:
            EditProfileSheet(services: services)
        }
    }
}

/// Her sekmenin kendi gezinme yığını; yol `AppRouter`'da tutulur (bildirimden derin bağlantı için).
struct TabStack<Root: View>: View {
    let tab: AppTab
    let services: AppServices
    @ViewBuilder let root: () -> Root
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack(path: Binding(
            get: { router.path(for: tab) },
            set: { router.setPath($0, for: tab) }
        )) {
            root()
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestination(route: route, services: services)
                }
        }
    }
}
#endif
