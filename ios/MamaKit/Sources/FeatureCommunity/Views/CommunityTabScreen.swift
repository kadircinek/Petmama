#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Mahalle" sekmesinin kökü (D17): besleyicilerin birbiriyle etkileştiği sayfa. `NavigationStack`'i AppFeature sağlar.
///
/// "Akış" bölümü paylaşımları gösterir ve giriş gerektirir; "Buluşmalar" (Tanışma) ve "İhtiyaçlar" bölümleri
/// dışarıdan verilen listelerdir (feature modülleri birbirini import etmediği için AppFeature enjekte eder).
public struct CommunityTabScreen<MeetupsContent: View, NeedsContent: View>: View {
    @State private var model: CommunityFeedViewModel
    @Environment(AppRouter.self) private var router
    private let meetups: () -> MeetupsContent
    private let needs: () -> NeedsContent

    public init(
        services: AppServices,
        @ViewBuilder meetups: @escaping () -> MeetupsContent,
        @ViewBuilder needs: @escaping () -> NeedsContent
    ) {
        _model = State(initialValue: CommunityFeedViewModel(services: services))
        self.meetups = meetups
        self.needs = needs
    }

    public var body: some View {
        VStack(spacing: 0) {
            PillSegmentedControl(
                selection: sectionBinding,
                options: [
                    (value: CommunitySection.feed, title: String(localized: "Akış")),
                    (value: CommunitySection.meetups, title: String(localized: "Buluşmalar")),
                    (value: CommunitySection.needs, title: String(localized: "İhtiyaçlar")),
                ]
            )
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 8)

            switch router.communitySection {
            case .feed:
                CommunityFeedView(model: model)
            case .meetups:
                meetups()
            case .needs:
                needs()
            }
        }
        .mamaBackground()
        .navigationTitle("Mahalle")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `router.communitySection` için Binding (yerel `@Bindable` `@Sendable` kapanışlarda yakalanmasın diye elle).
    private var sectionBinding: Binding<CommunitySection> {
        Binding(
            get: { router.communitySection },
            set: { router.communitySection = $0 }
        )
    }
}

#Preview("Akış") {
    PreviewEnvironment { services in
        CommunityTabScreen(services: services) {
            Text("Buluşmalar")
        } needs: {
            Text("İhtiyaçlar")
        }
    }
}

#Preview("Giriş yok") {
    PreviewEnvironment(signedIn: false) { services in
        CommunityTabScreen(services: services) {
            Text("Buluşmalar")
        } needs: {
            Text("İhtiyaçlar")
        }
    }
}
#endif
