#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// Nokta detayı (ekran 13, FR-N4, FR-N6, FR-H7).
public struct SpotDetailScreen: View {
    @State private var model: SpotDetailViewModel
    @State private var showsGuardianEditor = false
    @State private var showsGoneConfirmation = false

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location

    public init(spotId: UUID, services: AppServices) {
        _model = State(initialValue: SpotDetailViewModel(spotId: spotId, services: services))
    }

    public var body: some View {
        Group {
            if let spot = model.spot {
                content(spot)
            } else if model.notFound {
                EmptyStateView(
                    systemImage: "mappin.slash",
                    title: String(localized: "Bu nokta artık görünmüyor"),
                    message: String(localized: "Kaldırılmış ya da pasife alınmış olabilir.")
                )
            } else if let error = model.error {
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: String(localized: "Nokta yüklenemedi"),
                    message: error.userMessage,
                    actionTitle: String(localized: "Tekrar dene")
                ) {
                    Task { await load() }
                }
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mamaBackground()
        .navigationTitle(model.spot?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await load() }
        .onChange(of: router.sheet) { oldValue, newValue in
            // Check-in, hayvan veya ihtiyaç sheet'i kapanınca tazele.
            if oldValue != nil, newValue == nil { Task { await load() } }
        }
        .confirmationDialog(
            String(localized: "Bu nokta artık yok mu?"),
            isPresented: $showsGoneConfirmation,
            titleVisibility: .visible
        ) {
            Button("Evet, artık yok", role: .destructive) {
                Task { await perform { await model.reportGone() } }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("3 farklı kişi bildirirse nokta haritadan kaldırılır.")
        }
        .sheet(isPresented: $showsGuardianEditor) {
            GuardianScheduleSheet(initial: model.mySchedule, isGuardian: model.isGuardian) { schedule in
                Task { await perform { await model.setGuardian(schedule: schedule, userId: session.userId) } }
            }
        }
    }

    private func content(_ spot: Spot) -> some View {
        let status = spot.currentStatus(now: model.now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SpotHeroHeader(spot: spot, status: status)
                VStack(alignment: .leading, spacing: 26) {
                    SpotSummaryBlock(spot: spot, status: status, lastFedText: model.lastFedText)
                    checkInButtons(spot)
                    SpotAnimalsSection(spotId: spot.id, animals: model.animals)
                    FeedingTimelineSection(bars: model.timelineBars, maxCount: model.maxTimelineCount, weeklyCount: model.weeklyFedCount)
                    SpotNeedsSection(spotId: spot.id, needs: model.needs, now: model.now)
                    SpotGuardiansSection(guardians: model.guardians, isGuardian: model.isGuardian) {
                        requireSignIn { showsGuardianEditor = true }
                    }
                    FeedingGuideLink()
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .refreshable { await load() }
    }

    private func checkInButtons(_ spot: Spot) -> some View {
        VStack(spacing: 10) {
            Button("Mama koydum") {
                router.present(.checkIn(spotId: spot.id, kind: .fed), session: session)
            }
            .buttonStyle(.mamaFed)
            Button("Mama gerekli") {
                router.present(.checkIn(spotId: spot.id, kind: .needFood), session: session)
            }
            .buttonStyle(.mamaNeedsFood)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.spot != nil {
                Button {
                    requireSignIn {
                        Task { await perform { await model.setFollowing(!model.isFollowing) } }
                    }
                } label: {
                    Image(systemName: model.isFollowing ? "heart.fill" : "heart")
                }
                .disabled(model.isWorking)
                .accessibilityLabel(model.isFollowing ? Text("Takibi bırak") : Text("Noktayı takip et"))

                Menu {
                    Button {
                        openWalkingDirections()
                    } label: {
                        Label("Yol tarifi", systemImage: "figure.walk")
                    }
                    Button {
                        router.present(.report(.spot, model.spotId), session: session)
                    } label: {
                        Label("Raporla", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        requireSignIn { showsGoneConfirmation = true }
                    } label: {
                        Label("Bu nokta artık yok", systemImage: "mappin.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("Diğer işlemler"))
            }
        }
    }

    // MARK: - Davranış

    private func load() async {
        await model.load(near: location.coordinate, userId: session.userId)
    }

    private func perform(_ action: () async -> SpotFeedback) async {
        let feedback = await action()
        router.showToast(feedback.message, style: feedback.style)
    }

    private func requireSignIn(_ action: () -> Void) {
        if session.isSignedIn {
            action()
        } else {
            router.present(.signIn, session: session)
        }
    }

    /// Yürüme rotası Apple Haritalar'a devredilir; uygulama içinde navigasyon yok (FR-H7).
    private func openWalkingDirections() {
        guard let spot = model.spot else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.coordinate.clCoordinate))
        item.name = spot.title
        _ = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

#Preview {
    PreviewEnvironment { services in
        SpotDetailScreen(spotId: DemoData.id(2, 1), services: services)
    }
}
#endif
