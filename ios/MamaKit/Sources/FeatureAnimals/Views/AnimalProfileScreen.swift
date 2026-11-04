#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Hayvan profili (ekran 14, FR-A1…A4). Rota: `AppRoute.animal(id)`.
public struct AnimalProfileScreen: View {
    @State private var model: AnimalProfileViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var seenFeedback = 0

    public init(animalId: UUID, services: AppServices) {
        _model = State(initialValue: AnimalProfileViewModel(animalId: animalId, services: services))
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(model.animal?.displayName ?? String(localized: "Hayvan profili"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { await model.load() }
            .onChange(of: router.sheet) { old, new in
                // "İhtiyaç bildir" sheet'i kapanınca açık ihtiyaçları tazele.
                if old != nil, new == nil { Task { await model.load() } }
            }
            .sensoryFeedback(.success, trigger: seenFeedback)
    }

    @ViewBuilder
    private var content: some View {
        if let animal = model.animal {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AnimalPhotoHeader(animal: animal)
                    titleBlock(animal)
                    if let warning = animal.warning {
                        AnimalWarningBanner(warning: warning)
                    }
                    if let error = model.error {
                        BannerView(error.userMessage, style: .warning)
                    }
                    seenButton
                    if !animal.temperamentTags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(String(localized: "Karakteri"))
                            TemperamentTiles(tags: animal.temperamentTags)
                        }
                    }
                    if let about = animal.about, !about.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(String(localized: "Hakkında"))
                            Text(about)
                                .font(MamaFont.body)
                                .foregroundStyle(MamaColor.textPrimary)
                        }
                    }
                    infoCard
                    spotsSection
                    needsSection
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.bottom, 24)
            }
            .refreshable { await model.load() }
        } else if model.hasLoaded {
            EmptyStateView(
                systemImage: "pawprint",
                title: String(localized: "Bu hayvanı bulamadık"),
                message: model.error?.userMessage
            )
        } else {
            LoadingView(String(localized: "Profil yükleniyor"))
        }
    }

    // MARK: - Bölümler

    private func titleBlock(_ animal: Animal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(animal.displayName)
                    .font(MamaFont.largeTitle)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(2)
                TagChip(sexLabel(animal.sex), style: animal.sex == .unknown ? .neutral : .info)
                Spacer(minLength: 0)
            }
            Text(subtitle(animal))
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var seenButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                markSeen()
            } label: {
                HStack(spacing: 8) {
                    if model.isMarkingSeen { ProgressView() }
                    Text("Bu hayvanı gördüm")
                }
            }
            .buttonStyle(.mamaSecondary(tint: MamaColor.statusFed, systemImage: "eye.fill"))
            .disabled(model.isMarkingSeen)
            Text("Yakınındaki noktasını işaretleriz; konumun kaydedilmez.")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 14) {
            InfoRow(systemImage: "scissors", title: String(localized: "Kısırlaştırma"), value: model.neuteredText)
            Divider()
            InfoRow(systemImage: "syringe.fill", title: String(localized: "Aşı bilgisi"), value: model.vaccinationText)
            Divider()
            InfoRow(systemImage: "eye.fill", title: String(localized: "Son görülme"), value: model.lastSeenText)
        }
        .mamaCard()
    }

    private var spotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Görüldüğü noktalar"))
            if model.spots.isEmpty {
                Text("Henüz bir noktaya bağlı değil.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            ForEach(model.spots) { spot in
                NavigationLink(value: AppRoute.spot(spot.id)) {
                    SpotCardView(spot: spot, now: model.now)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var needsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Açık ihtiyaçlar"))
            if model.openNeeds.isEmpty {
                Text("Şu an açık ihtiyacı yok.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            ForEach(model.openNeeds) { need in
                NeedCardView(need: need, now: model.now, onDetail: { router.push(.need(need.id)) })
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let animal = model.animal {
            Button(String(localized: "İhtiyaç bildir")) {
                router.present(.createNeed(spotId: animal.lastSeenSpotId, animalId: animal.id), session: session)
            }
            .buttonStyle(.mamaPrimary(systemImage: "plus"))
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.animal != nil {
                Button {
                    toggleFollow()
                } label: {
                    Image(systemName: model.isFollowing ? "heart.fill" : "heart")
                }
                .accessibilityLabel(model.isFollowing ? String(localized: "Takibi bırak") : String(localized: "Takip et"))

                Menu {
                    Button {
                        router.present(.report(.animal, model.animalId), session: session)
                    } label: {
                        Label("Raporla", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "Diğer seçenekler"))
            }
        }
    }

    // MARK: - Eylemler

    /// FR-A3: giriş + konum gerekir; nokta seçimi ViewModel'de.
    private func markSeen() {
        guard session.isSignedIn else {
            router.present(.signIn, session: session)
            return
        }
        Task {
            if location.authorization == .notDetermined {
                await location.requestAuthorization()
            }
            let coordinate = await location.refresh()
            let result = await model.markSeen(user: coordinate)
            if case .marked = result { seenFeedback += 1 }
            router.showToast(result.message, style: result.toastStyle)
        }
    }

    private func toggleFollow() {
        guard session.isSignedIn else {
            router.present(.signIn, session: session)
            return
        }
        Task {
            await model.toggleFollow()
            if model.isFollowing, model.error == nil {
                router.showToast(String(localized: "Takip ediyorsun. Yeni ihtiyaçlarını sana haber vereceğiz."))
            }
        }
    }

    // MARK: - Metinler

    private func sexLabel(_ sex: AnimalSex) -> String {
        sex == .unknown ? String(localized: "Cinsiyet bilinmiyor") : sex.label
    }

    /// "Kedi · Yetişkin · Sarman"
    private func subtitle(_ animal: Animal) -> String {
        var parts = [animal.species.label]
        if animal.ageEstimate != .unknown { parts.append(animal.ageEstimate.label) }
        if let pattern = animal.colorPattern?.trimmingCharacters(in: .whitespaces), !pattern.isEmpty {
            parts.append(pattern)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Tarçın") {
    PreviewEnvironment { services in
        AnimalProfileScreen(animalId: DemoData.id(4, 2), services: services)
    }
}

#Preview("Kont — uyarılı") {
    PreviewEnvironment { services in
        AnimalProfileScreen(animalId: DemoData.id(4, 6), services: services)
    }
}
#endif
