#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Mahalle" sekmesinin kökü (D17): besleyicilerin birbiriyle etkileştiği sayfa. `NavigationStack`'i AppFeature sağlar.
///
/// "Akış" bölümü paylaşımları gösterir ve giriş gerektirir; "İhtiyaçlar" bölümü dışarıdan verilen ihtiyaç
/// listesidir (feature modülleri birbirini import etmediği için AppFeature enjekte eder).
public struct CommunityTabScreen<NeedsContent: View>: View {
    @State private var model: CommunityFeedViewModel
    @Environment(AppRouter.self) private var router
    private let needs: () -> NeedsContent

    public init(services: AppServices, @ViewBuilder needs: @escaping () -> NeedsContent) {
        _model = State(initialValue: CommunityFeedViewModel(services: services))
        self.needs = needs
    }

    public var body: some View {
        VStack(spacing: 0) {
            PillSegmentedControl(
                selection: sectionBinding,
                options: [
                    (value: CommunitySection.feed, title: String(localized: "Akış")),
                    (value: CommunitySection.needs, title: String(localized: "İhtiyaçlar")),
                ]
            )
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 8)

            switch router.communitySection {
            case .feed:
                CommunityFeedView(model: model)
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
            Text("İhtiyaçlar")
        }
    }
}

#Preview("Giriş yok") {
    PreviewEnvironment(signedIn: false) { services in
        CommunityTabScreen(services: services) {
            Text("İhtiyaçlar")
        }
    }
}
#endif
