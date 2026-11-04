#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// "Harita" sekmesinin kökü (ekran 8–11, D10). AppFeature bunu bir `NavigationStack` içine koyar.
public struct MapTabScreen: View {
    @State private var model: MapViewModel
    @State private var position: MapCameraPosition = MapCameraDefaults.street(.modaKadikoy)
    @State private var hasCenteredOnUser = false
    @State private var isPanelExpanded = false
    @State private var showsFilter = false
    @State private var showsLegend = false

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location

    /// Görünürken haritayı tazeleme aralığı.
    private static let refreshInterval: UInt64 = 60_000_000_000

    public init(services: AppServices) {
        _model = State(initialValue: MapViewModel(services: services))
    }

    public var body: some View {
        // `$model.x` doğrudan @State Binding'inden; yerel @Bindable, @Sendable kapanışlarda (.task/Task) yakalanmasın.
        ZStack {
            mapLayer
            switch model.mode {
            case .map:
                EmptyView()
            case .list:
                SpotListContent(model: model)
                    .background(MamaBackground())
            case .needs:
                NeedsListContent(model: model)
                    .background(MamaBackground())
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            MapTopBar(
                mode: $model.mode,
                activeFilterCount: model.filter.activeCount,
                onSearch: { router.push(.search) },
                onFilter: { showsFilter = true },
                onLegend: { showsLegend = true }
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background {
                if model.mode != .map {
                    MamaColor.backgroundTop.ignoresSafeArea(edges: .top)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsFilter) {
            MapFilterSheet(filter: model.filter, canFilterFollowed: session.isSignedIn) { newFilter in
                Task { await model.applyFilter(newFilter) }
            }
        }
        .sheet(isPresented: $showsLegend) { legendSheet }
        .task { await start() }
        .task { await refreshPeriodically() }
        .task(id: model.mode) { await model.loadCurrentMode() }
        .onChange(of: location.coordinate) { _, newValue in
            if let newValue, !hasCenteredOnUser { centerOnce(on: newValue) }
            Task { await model.userLocationChanged(newValue) }
        }
        .onChange(of: model.isOffline) { wasOffline, isOffline in
            guard wasOffline, !isOffline, session.isSignedIn else { return }
            Task { await flushQueue() }
        }
        .onChange(of: router.sheet) { oldValue, newValue in
            // Check-in veya nokta ekleme kapanınca pin renklerini tazele.
            if oldValue != nil, newValue == nil { Task { await model.refresh() } }
        }
    }

    // MARK: - Harita katmanı

    private var mapLayer: some View {
        ZStack {
            SpotMapView(model: model, position: $position) { coordinate in
                router.present(.addSpot(coordinate), session: session)
            }
            .ignoresSafeArea(edges: .top)

            GeometryReader { proxy in
                VStack(spacing: 10) {
                    if model.isOffline {
                        BannerView(String(localized: "Çevrimdışı: son görülen noktalar gösteriliyor"), style: .warning, systemImage: "wifi.slash")
                            .background(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius).fill(MamaColor.card))
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Button {
                            Task { await centerOnUser() }
                        } label: {
                            Image(systemName: "location.fill")
                        }
                        .buttonStyle(.mamaCircle)
                        .accessibilityLabel(Text("Konumum"))
                    }
                    bottomCard(maxPanelHeight: proxy.size.height * 0.55)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }

            PawBurstView(trigger: model.feedSuccessCount)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.selectedSpotId)
        .sensoryFeedback(.success, trigger: model.feedSuccessCount)
        .opacity(model.mode == .map ? 1 : 0)
        .allowsHitTesting(model.mode == .map)
        .accessibilityHidden(model.mode != .map)
    }

    @ViewBuilder
    private func bottomCard(maxPanelHeight: CGFloat) -> some View {
        if let spot = model.selectedSpot {
            SelectedSpotCard(
                spot: spot,
                now: model.now,
                onFed: { router.present(.checkIn(spotId: spot.id, kind: .fed), session: session) },
                onDetail: { router.push(.spot(spot.id)) },
                onClose: { model.selectedSpotId = nil }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            MapHomePanel(model: model, isExpanded: $isPanelExpanded, maxExpandedHeight: maxPanelHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var legendSheet: some View {
        NavigationStack {
            ScrollView {
                StatusLegend()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .mamaBackground()
            .navigationTitle("Renklerin anlamı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { showsLegend = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Davranış

    private func start() async {
        let user = await location.refresh() ?? location.coordinate
        if let user { centerOnce(on: user) }
        model.setUserLocation(user)
        model.seedVisibleBoundsIfNeeded(MapCameraDefaults.approximateBounds(around: user ?? .modaKadikoy))
        if session.isSignedIn {
            await flushQueue()
            await model.loadFollowed()
        }
        await model.loadRegion()
        await model.loadHome()
    }

    private func refreshPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.refreshInterval)
            guard !Task.isCancelled else { break }
            await model.refresh()
        }
    }

    private func flushQueue() async {
        if let feedback = await model.flushPendingCheckIns() {
            router.showToast(feedback.message, style: feedback.style)
        }
    }

    /// İlk konumda bir kez sokak seviyesine odaklanır (FR-H1); sonra kullanıcının kaydırmasına karışmaz.
    private func centerOnce(on coordinate: Coordinate) {
        guard !hasCenteredOnUser else { return }
        hasCenteredOnUser = true
        position = MapCameraDefaults.street(coordinate)
    }

    private func centerOnUser() async {
        if location.authorization == .notDetermined {
            await location.requestAuthorization()
        }
        guard let user = await location.refresh() else {
            if location.authorization == .denied {
                router.showToast(String(localized: "Konum izni kapalı. Ayarlar'dan açabilirsin."), style: .info)
            }
            return
        }
        hasCenteredOnUser = true
        withAnimation(.easeInOut(duration: 0.4)) {
            position = MapCameraDefaults.street(user)
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        MapTabScreen(services: services)
    }
}
#endif
