#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Mama turuna çıkıyorum". Sheet: `AppSheet.startTour(spotId:)`. Sosyal onay yoksa ilk adım onay ekranıdır.
/// Tur başlayınca turun grup sohbeti açılır.
public struct StartTourSheet: View {
    @State private var model: StartTourViewModel
    @State private var consent: SocialConsentViewModel
    @State private var step: Step = .checking
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss
    private let services: AppServices
    private let spotId: UUID?

    private enum Step { case checking, consent, form }

    public init(spotId: UUID?, services: AppServices) {
        _model = State(initialValue: StartTourViewModel(services: services))
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
            .navigationTitle("Mama turuna çıkıyorum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .disabled(model.isSubmitting)
                }
            }
            .task { await prepare() }
        }
        .interactiveDismissDisabled(model.isSubmitting)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BannerView(
                    String(localized: "Tur seçtiğin herkese açık mama noktasında hemen başlar. Komşular katılıp sana yazabilir; senin konumun paylaşılmaz."),
                    style: .info,
                    systemImage: "figure.walk"
                )
                spotSection
                durationSection
                if let message = model.message {
                    BannerView(message, style: .warning)
                }
                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                }
                Button {
                    Task { await submit() }
                } label: {
                    if model.isSubmitting {
                        Text("Başlatılıyor…")
                    } else {
                        Text("Tura çık")
                    }
                }
                .buttonStyle(.mamaPrimary(systemImage: "figure.walk"))
                .disabled(!model.canSubmit)
                .padding(.top, 4)
            }
            .padding(MamaMetrics.screenPadding)
        }
    }

    private var spotSection: some View {
        SocialFormCard(String(localized: "Hangi noktadasın?"), subtitle: String(localized: "Yalnızca herkese açık noktalar listelenir.")) {
            if model.isLoading, model.spots.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: MamaMetrics.minTapSize)
            } else if model.spots.isEmpty {
                Text("Yakında herkese açık bir mama noktası yok. Haritadan bir nokta ekleyebilirsin.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(model.spots) { spot in
                    spotRow(spot)
                }
            }
        }
    }

    private func spotRow(_ spot: Spot) -> some View {
        let selected = model.selectedSpotId == spot.id
        return Button {
            model.selectedSpotId = spot.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? MamaColor.statusFed : MamaColor.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: spot.title)
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let distance = spot.distanceMeters {
                        Text(verbatim: MamaFormat.distance(distance))
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: MamaMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var durationSection: some View {
        SocialFormCard(String(localized: "Ne kadar sürecek?")) {
            Picker(selection: $model.durationMinutes) {
                ForEach(StartTourViewModel.durationOptions, id: \.self) { minutes in
                    Text(verbatim: Self.durationLabel(minutes)).tag(minutes)
                }
            } label: {
                Text("Süre")
            }
            .pickerStyle(.segmented)
        }
    }

    /// "1 saat", "1,5 saat", "2 saat".
    static func durationLabel(_ minutes: Int) -> String {
        if minutes == 60 { return String(localized: "1 saat") }
        if minutes % 60 == 0 { return String(localized: "\(minutes / 60) saat") }
        return String(localized: "\(minutes / 60),5 saat")
    }

    // MARK: - Eylemler

    private func prepare() async {
        guard step == .checking else { return }
        var center = location.coordinate
        if center == nil { center = await location.refresh() }
        await model.load(near: center ?? .modaKadikoy, preselected: spotId)
        step = await SocialGate.needsConsent(services) ? .consent : .form
    }

    private func openPrivacy() {
        dismiss()
        router.push(.privacy)
    }

    private func submit() async {
        guard let outcome = await model.submit() else { return }
        switch outcome {
        case .started(_, let conversationId):
            router.showToast(String(localized: "Turun başladı! Gelenlerle sohbette buluşun."))
            router.communitySection = .feed
            router.open(.conversation(conversationId), in: .community)
        case .consentRequired:
            withAnimation { step = .consent }
        default:
            break  // Mesaj formda gösterilir.
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        StartTourSheet(spotId: nil, services: services)
    }
}
#endif
