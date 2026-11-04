#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// Nokta ekleme akışı (ekran 16): sorumlu besleme hatırlatması, sonra en fazla 3 adım (FR-N2), mükerrer kontrolü (FR-N3).
public struct AddSpotFlow: View {
    @State private var model: AddSpotFlowViewModel
    @State private var position: MapCameraPosition
    @State private var showsReminderBanner = true
    @AppStorage("mama.addSpot.reminderAcknowledged") private var reminderAcknowledged = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location

    /// Nokta konumunu doğrulamak için yakın kamera.
    static let cameraDistance: CLLocationDistance = 350

    public init(initialCoordinate: Coordinate?, services: AppServices) {
        _model = State(initialValue: AddSpotFlowViewModel(initialCoordinate: initialCoordinate, services: services))
        let start = initialCoordinate ?? .modaKadikoy
        _position = State(initialValue: .camera(MapCamera(centerCoordinate: start.clCoordinate, distance: Self.cameraDistance)))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if reminderAcknowledged {
                    flow
                } else {
                    FeedingReminderView {
                        withAnimation { reminderAcknowledged = true }
                        showsReminderBanner = false
                    }
                }
            }
            .mamaBackground()
            .navigationTitle("Nokta ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .sheet(isPresented: duplicatesBinding) {
                DuplicateSpotSheet(
                    candidates: model.duplicates,
                    isSubmitting: model.isSubmitting,
                    onSelect: openExisting,
                    onForce: { submit(force: true) }
                )
            }
        }
        .interactiveDismissDisabled(model.hasProgress)
        .task {
            if model.adoptUserLocation(await location.refresh()) {
                position = .camera(MapCamera(centerCoordinate: model.coordinate.clCoordinate, distance: Self.cameraDistance))
            }
        }
    }

    private var flow: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ProgressSegments(count: AddSpotFlowViewModel.Step.allCases.count, current: model.step.rawValue)
                Text(model.step.title)
                    .font(MamaFont.title2)
                    .foregroundStyle(MamaColor.textPrimary)
                Text(model.step.subtitle)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)

            switch model.step {
            case .location:
                AddSpotLocationStep(model: model, position: $position, showsReminder: $showsReminderBanner)
            case .details:
                AddSpotDetailsStep(model: model)
            case .extras:
                AddSpotExtrasStep(model: model)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let message = model.errorMessage {
                BannerView(message, style: .warning)
            }
            HStack(spacing: 10) {
                if model.step != .location {
                    Button("Geri") { withAnimation { model.back() } }
                        .buttonStyle(.mamaSecondary(fullWidth: false))
                }
                if model.isLastStep {
                    Button {
                        submit(force: false)
                    } label: {
                        if model.isSubmitting {
                            ProgressView().tint(MamaColor.onInk)
                        } else {
                            Text("Noktayı ekle")
                        }
                    }
                    .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
                    .disabled(!model.canSubmit)
                } else {
                    Button("Devam") { withAnimation { model.next() } }
                        .buttonStyle(.mamaPrimary)
                        .disabled(!model.canGoNext)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var duplicatesBinding: Binding<Bool> {
        Binding(
            get: { !model.duplicates.isEmpty },
            set: { isPresented in if !isPresented { model.dismissDuplicates() } }
        )
    }

    private func submit(force: Bool) {
        Task {
            let result = await model.submit(force: force)
            guard case .created(let id, let pending) = result else { return }
            router.showToast(model.message(for: result), style: pending ? .info : .success)
            dismiss()
            router.push(.spot(id))
        }
    }

    /// "Evet, bu nokta": akışı kapat ve mevcut noktayı aç.
    private func openExisting(_ candidate: DuplicateCandidate) {
        model.dismissDuplicates()
        router.dismissSheet()
        router.push(.spot(candidate.id))
    }
}

extension AddSpotFlowViewModel.Step {
    var title: String {
        switch self {
        case .location: return String(localized: "Konumu doğrula")
        case .details: return String(localized: "Ne tür bir nokta?")
        case .extras: return String(localized: "Fotoğraf ve not")
        }
    }

    var subtitle: String {
        switch self {
        case .location: return String(localized: "Haritayı kaydırarak iğneyi mama kabının olduğu yere getir.")
        case .details: return String(localized: "Tipi ve beslenen hayvanları seç. Ad isteğe bağlı.")
        case .extras: return String(localized: "Hepsi isteğe bağlı. Kimlerin görebileceğini sen seç.")
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        Color.clear.sheet(isPresented: .constant(true)) {
            AddSpotFlow(initialCoordinate: nil, services: services)
        }
    }
}
#endif
