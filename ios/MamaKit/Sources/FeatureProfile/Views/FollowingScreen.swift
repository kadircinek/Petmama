#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Takip ettiklerim (ekran 21): Tümü / Yakında / Son. Kaydırarak veya basılı tutarak takibi bırak.
public struct FollowingScreen: View {
    @State private var model: FollowingViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location

    public init(services: AppServices) {
        _model = State(initialValue: FollowingViewModel(services: services))
    }

    public var body: some View {
        List {
            PillSegmentedControl(
                selection: $model.segment,
                options: FollowingViewModel.Segment.allCases.map { (value: $0, title: title(for: $0)) }
            )
            .plainRow()

            if let error = model.error {
                BannerView(error.userMessage, style: .warning).plainRow()
            }
            content
        }
        .listStyle(.plain)
        .mamaBackground()
        .navigationTitle(String(localized: "Takip ettiklerim"))
        .task(id: session.userId) { await model.load(near: location.coordinate) }
        .refreshable { await model.load(near: location.coordinate) }
        .onChange(of: location.coordinate) { _, coordinate in model.updateOrigin(coordinate) }
    }

    @ViewBuilder
    private var content: some View {
        if !session.isSignedIn {
            EmptyStateView(
                mascot: .cat,
                title: String(localized: "Takip etmek için giriş yap"),
                message: String(localized: "Beslediğin noktaları ve sevdiğin hayvanları takip et, haberleri buraya gelsin."),
                actionTitle: String(localized: "Giriş yap"),
                action: { router.present(.signIn, session: session) }
            )
            .plainRow()
        } else if model.isLoading && !model.hasLoaded {
            LoadingView().frame(height: 240).plainRow()
        } else if model.hasLoaded && model.isEmpty {
            EmptyStateView(
                mascot: .cat,
                title: String(localized: "Henüz takip ettiğin bir şey yok"),
                message: String(localized: "Bir noktanın ya da hayvanın sayfasındaki kalbe dokun; yeni mama ve ihtiyaç haberleri burada toplansın.")
            )
            .plainRow()
        } else if model.needsLocationForSegment {
            EmptyStateView(
                systemImage: "location.slash",
                title: String(localized: "Konumun kapalı"),
                message: String(localized: "Yakındaki takip ettiklerini görmek için konum iznini açabilirsin.")
            )
            .plainRow()
        } else if model.isSegmentEmpty {
            EmptyStateView(
                systemImage: "mappin.slash",
                title: String(localized: "1 km içinde takip ettiğin bir şey yok"),
                message: String(localized: "\"Tümü\" sekmesinden hepsini görebilirsin.")
            )
            .plainRow()
        } else {
            lists
        }
    }

    @ViewBuilder
    private var lists: some View {
        if !model.visibleSpots.isEmpty {
            Section {
                ForEach(model.visibleSpots) { spot in
                    Button {
                        router.push(.spot(spot.id))
                    } label: {
                        SpotCardView(spot: spot, now: model.now)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        unfollowButton { await model.unfollow(spot: spot) }
                    }
                    .contextMenu {
                        unfollowButton { await model.unfollow(spot: spot) }
                    }
                }
            } header: {
                sectionHeader(String(localized: "Noktalar"), count: model.visibleSpots.count)
            }
        }
        if !model.visibleAnimals.isEmpty {
            Section {
                ForEach(model.visibleAnimals) { item in
                    Button {
                        router.push(.animal(item.animal.id))
                    } label: {
                        FollowedAnimalRow(item: item, now: model.now)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        unfollowButton { await model.unfollow(animal: item.animal) }
                    }
                    .contextMenu {
                        unfollowButton { await model.unfollow(animal: item.animal) }
                    }
                }
            } header: {
                sectionHeader(String(localized: "Hayvanlar"), count: model.visibleAnimals.count)
            }
        }
    }

    private func unfollowButton(_ action: @escaping () async -> Void) -> some View {
        Button(role: .destructive) {
            Task { await action() }
        } label: {
            Label(String(localized: "Takibi bırak"), systemImage: "heart.slash.fill")
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(MamaFont.headline)
            .foregroundStyle(MamaColor.textPrimary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func title(for segment: FollowingViewModel.Segment) -> String {
        switch segment {
        case .all: return String(localized: "Tümü")
        case .nearby: return String(localized: "Yakında")
        case .recent: return String(localized: "Son")
        }
    }
}

extension View {
    /// Düz liste satırı: zemin ve ayraç yok, kart görünümü korunur.
    func plainRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: MamaMetrics.screenPadding, bottom: 6, trailing: MamaMetrics.screenPadding))
    }
}

#Preview {
    PreviewEnvironment { services in FollowingScreen(services: services) }
}
#endif
