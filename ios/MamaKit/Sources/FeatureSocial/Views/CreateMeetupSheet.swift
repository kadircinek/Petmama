#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// "Buluşma aç". Sheet: `AppSheet.createMeetup(spotId:)`. Sosyal onay yoksa ilk adım onay ekranıdır.
public struct CreateMeetupSheet: View {
    @State private var model: CreateMeetupViewModel
    @State private var consent: SocialConsentViewModel
    @State private var step: Step = .checking
    @State private var position: MapCameraPosition = .automatic
    @State private var showsDiscardDialog = false
    @State private var showsNearHomeDialog = false
    /// "Evet, burası herkese açık" denildi; nokta değişince sıfırlanır.
    @State private var nearHomeConfirmed = false
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss
    private let services: AppServices
    private let spotId: UUID?

    private enum Step { case checking, consent, form }

    static let durationOptions = [30, 60, 90, 120, 180, 240, 300, 360, 420, 480]

    public init(spotId: UUID?, services: AppServices) {
        _model = State(initialValue: CreateMeetupViewModel(services: services))
        _consent = State(initialValue: SocialConsentViewModel(services: services))
        self.services = services
        self.spotId = spotId
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .checking:
                    LoadingView()
                case .consent:
                    ScrollView {
                        SocialConsentContent(
                            model: consent,
                            config: services.config,
                            onConsented: { withAnimation { step = .form } },
                            onOpenLegalFallback: openPrivacy
                        )
                        .padding(MamaMetrics.screenPadding)
                    }
                case .form:
                    form
                }
            }
            .mamaBackground()
            .navigationTitle("Buluşma aç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { close() }
                        .disabled(model.isSubmitting)
                }
            }
            .task { await prepare() }
            .confirmationDialog(
                "Buluşma noktası evine çok yakın görünüyor. Herkese açık bir yer seçtiğinden emin misin?",
                isPresented: $showsNearHomeDialog,
                titleVisibility: .visible
            ) {
                Button("Evet, burası herkese açık") {
                    nearHomeConfirmed = true
                    Task { await submit() }
                }
                // Rolsüz: iOS 26 açılır kutusunda iptal rolündeki buton gizlenir; seçenek görünür kalsın.
                Button("Noktayı değiştir") {}
            }
            .onChange(of: model.coordinate) { _, _ in nearHomeConfirmed = false }
            .confirmationDialog("Taslak silinsin mi?", isPresented: $showsDiscardDialog, titleVisibility: .visible) {
                Button("Taslağı sil", role: .destructive) { dismiss() }
                Button("Yazmaya devam et", role: .cancel) {}
            } message: {
                Text("Yazdıkların kaydedilmez.")
            }
        }
        .interactiveDismissDisabled(hasDraft || model.isSubmitting)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BannerView(
                    String(localized: "Buluşma noktası herkese açık bir yer olmalı: park girişi, iskele, meydan. Ev adresi paylaşma."),
                    style: .info,
                    systemImage: "person.3.fill"
                )
                titleSection
                timeSection
                placeSection
                capacitySection
                if let message = model.message {
                    BannerView(message, style: .warning)
                }
                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                }
                submitButton
            }
            .padding(MamaMetrics.screenPadding)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var titleSection: some View {
        SocialFormCard(String(localized: "Ne yapacağız?")) {
            TextField(String(localized: "Ör. Moda Parkı mama turu"), text: $model.title)
                .font(MamaFont.body)
                .socialFieldBackground()
            CharacterCounter(count: model.title.count, limit: SocialPolicy.titleLength.upperBound)
            TextField(
                String(localized: "Açıklama (isteğe bağlı): ne getirelim, kimler katılabilir?"),
                text: $model.description,
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(MamaFont.body)
            .socialFieldBackground()
            CharacterCounter(count: model.description.count, limit: SocialPolicy.maxDescription)
        }
    }

    private var timeSection: some View {
        SocialFormCard(String(localized: "Ne zaman?"), subtitle: String(localized: "En erken 1 saat, en geç 60 gün sonrası.")) {
            DatePicker(String(localized: "Başlangıç"), selection: $model.startsAt, in: startRange)
            HStack {
                Text("Süre")
                Spacer(minLength: 8)
                Picker(selection: $model.durationMinutes) {
                    ForEach(Self.durationOptions, id: \.self) { minutes in
                        Text(verbatim: Self.durationLabel(minutes)).tag(minutes)
                    }
                } label: {
                    Text("Süre")
                }
                .labelsHidden()
            }
        }
        .font(MamaFont.subheadline)
        .environment(\.timeZone, TimeZone(identifier: "Europe/Istanbul") ?? .current)
    }

    private var placeSection: some View {
        SocialFormCard(String(localized: "Nerede?"), subtitle: String(localized: "Haritayı kaydırarak iğneyi buluşma noktasına getir.")) {
            Map(position: $position) {
                UserAnnotation()
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                model.coordinate = Coordinate(context.region.center)
            }
            .overlay {
                Image(systemName: "mappin")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(MamaColor.ink)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    .offset(y: -18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
            .accessibilityLabel(String(localized: "Buluşma noktası seçme haritası"))
            TextField(String(localized: "Yer adı, ör. Moda İskelesi önü"), text: $model.placeName)
                .font(MamaFont.body)
                .socialFieldBackground()
        }
    }

    private var capacitySection: some View {
        SocialFormCard(String(localized: "Kişi sınırı")) {
            Toggle(String(localized: "Kişi sınırı koy"), isOn: $model.capacityEnabled)
                .tint(MamaColor.statusFed)
            if model.capacityEnabled {
                let limit = model.capacity
                Stepper(value: $model.capacity, in: SocialPolicy.capacity) {
                    Text("Seninle birlikte en fazla \(limit) kişi")
                }
            }
        }
        .font(MamaFont.subheadline)
    }

    private var submitButton: some View {
        Button {
            // Varsayılan nokta cihazın konumu (çoğu zaman ev): 50 m içindeyse önce onay iste.
            if model.validationIssue == nil, !nearHomeConfirmed, model.isNearDevice(location.coordinate) {
                showsNearHomeDialog = true
            } else {
                Task { await submit() }
            }
        } label: {
            if model.isSubmitting {
                Text("Paylaşılıyor…")
            } else {
                Text("Buluşmayı paylaş")
            }
        }
        .buttonStyle(.mamaPrimary(systemImage: "paperplane.fill"))
        .disabled(model.isSubmitting)
        .padding(.top, 4)
    }

    // MARK: - Yardımcılar

    private var startRange: ClosedRange<Date> {
        let now = services.now()
        return now.addingTimeInterval(SocialPolicy.minLeadTime)...now.addingTimeInterval(TimeInterval(SocialPolicy.maxLeadDays) * 86_400)
    }

    private var hasDraft: Bool {
        step == .form && (!model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !model.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// "30 dk", "2 saat", "2,5 saat".
    static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return String(localized: "\(minutes) dk") }
        let hours = minutes / 60
        if minutes == 60 { return String(localized: "1 saat") }
        if minutes % 60 == 0 { return String(localized: "\(hours) saat") }
        return String(localized: "\(hours),5 saat")
    }

    // MARK: - Eylemler

    private func prepare() async {
        guard step == .checking else { return }
        var center = location.coordinate
        if center == nil { center = await location.refresh() }
        if let spotId, let spot = try? await services.spots.spot(id: spotId) {
            center = spot.coordinate
            model.spotId = spotId
            if model.placeName.isEmpty { model.placeName = String(spot.title.prefix(SocialPolicy.placeNameLength.upperBound)) }
        }
        let coordinate = center ?? .modaKadikoy
        model.coordinate = coordinate
        position = .region(MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        step = await SocialGate.needsConsent(services) ? .consent : .form
    }

    private func close() {
        if hasDraft {
            showsDiscardDialog = true
        } else {
            dismiss()
        }
    }

    private func openPrivacy() {
        dismiss()
        router.push(.privacy)
    }

    private func submit() async {
        guard let outcome = await model.submit() else { return }
        switch outcome {
        case .created(let meetupId, _):
            router.showToast(String(localized: "Buluşman paylaşıldı. Katılanlarla sohbette konuşabilirsin."))
            router.communitySection = .meetups
            router.open(.meetup(meetupId), in: .community)
        case .consentRequired:
            withAnimation { step = .consent }
        default:
            break  // Mesaj formda gösterilir.
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        CreateMeetupSheet(spotId: nil, services: services)
    }
}
#endif
