#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "İhtiyaçlar" sekmesinin kökü (ekran 17, FR-I1…I5). `NavigationStack`'i AppFeature sağlar.
public struct NeedsTabScreen: View {
    @State private var model: NeedsListViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var claimFeedback = 0

    public init(services: AppServices) {
        _model = State(initialValue: NeedsListViewModel(services: services))
    }

    public var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                NeedTypeFilterBar(
                    selected: model.selectedTypes,
                    onToggle: { model.toggleType($0) },
                    onClear: { model.clearTypes() }
                )
                Toggle(isOn: $model.includeResolved) {
                    Text("Çözülenleri göster")
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                }
                .tint(MamaColor.statusFed)
                .padding(.horizontal, MamaMetrics.screenPadding)

                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                        .padding(.horizontal, MamaMetrics.screenPadding)
                }
                list
            }
            .padding(.vertical, 8)
        }
        .mamaBackground()
        .navigationTitle("İhtiyaçlar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.createNeed(spotId: nil, animalId: nil), session: session)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "İhtiyaç bildir"))
            }
        }
        // İlk açılış ve "Çözülenleri göster" değişince yeniden yükler.
        .task(id: model.includeResolved) { await reload() }
        .refreshable { await reload() }
        .onChange(of: router.sheet) { old, new in
            // Yeni ihtiyaç veya giriş sheet'i kapanınca listeyi tazele.
            if old != nil, new == nil { Task { await reload() } }
        }
        .onChange(of: location.coordinate == nil) { _, isNil in
            if !isNil { Task { await reload() } }
        }
        .sensoryFeedback(.success, trigger: claimFeedback)
    }

    @ViewBuilder
    private var list: some View {
        if !model.hasLoaded {
            LoadingView(String(localized: "İhtiyaçlar yükleniyor"))
                .frame(height: 240)
        } else if model.isEmpty {
            EmptyStateView(
                systemImage: "checkmark.seal.fill",
                title: String(localized: "Yakınında açık ihtiyaç yok. Harika!"),
                message: model.hasActiveFilter
                    ? String(localized: "Filtreleri temizleyip tekrar bakabilirsin.")
                    : String(localized: "Bir ihtiyaç görürsen buradan paylaşabilirsin."),
                actionTitle: String(localized: "İhtiyaç bildir"),
                action: { router.present(.createNeed(spotId: nil, animalId: nil), session: session) }
            )
        } else {
            ForEach(model.visibleNeeds) { need in
                NeedCardView(
                    need: need,
                    now: model.now,
                    onClaim: { claim(need) },
                    onDetail: { router.push(.need(need.id)) }
                )
                .disabled(model.claimingId == need.id)
                .padding(.horizontal, MamaMetrics.screenPadding)
            }
        }
    }

    private func reload() async {
        await model.load(near: location.coordinate)
    }

    /// FR-I3. Giriş yoksa önce giriş ekranı.
    private func claim(_ need: Need) {
        guard session.isSignedIn else {
            router.present(.signIn, session: session)
            return
        }
        Task {
            let result = await model.claim(need.id, near: location.coordinate)
            if result == .claimed { claimFeedback += 1 }
            router.showToast(result.message, style: result.toastStyle)
        }
    }
}

/// Yatay ihtiyaç tipi filtresi.
struct NeedTypeFilterBar: View {
    let selected: Set<NeedType>
    let onToggle: (NeedType) -> Void
    let onClear: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SelectableChip(String(localized: "Tümü"), isSelected: selected.isEmpty, action: onClear)
                ForEach(NeedType.allCases, id: \.self) { type in
                    SelectableChip(type.label, systemImage: type.systemImage, isSelected: selected.contains(type)) {
                        onToggle(type)
                    }
                }
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        NeedsTabScreen(services: services)
    }
}

#Preview("Giriş yok") {
    PreviewEnvironment(signedIn: false) { services in
        NeedsTabScreen(services: services)
    }
}
#endif
