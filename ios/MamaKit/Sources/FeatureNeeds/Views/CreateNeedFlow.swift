#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// İhtiyaç bildirme akışı. Sheet: `AppSheet.createNeed(spotId:animalId:)`; kendi `NavigationStack`'ini açar.
public struct CreateNeedFlow: View {
    @State private var model: CreateNeedViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss

    public init(spotId: UUID?, animalId: UUID?, services: AppServices) {
        _model = State(initialValue: CreateNeedViewModel(spotId: spotId, animalId: animalId, services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contextChips
                    NeedTypeGridSection(model: model)
                    NeedUrgencySection(model: model)
                    NeedDescriptionSection(model: model)
                    NeedPhotosSection(model: model)
                    if model.showsSpotPicker {
                        NeedSpotSection(model: model)
                    }
                    if model.shouldOpenVetHelp {
                        BannerView(
                            String(localized: "Mama Haritası tıbbi tavsiye vermez. Paylaştıktan sonra en yakın veteriner kliniklerini göstereceğiz."),
                            style: .warning,
                            systemImage: "cross.case.fill"
                        )
                    }
                    if model.attemptedSubmit, let issue = model.validationIssue {
                        BannerView(issue.message, style: .warning)
                    }
                    submitButton
                }
                .padding(MamaMetrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .mamaBackground()
            .navigationTitle("İhtiyaç bildir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .task { await load() }
            .alert("Paylaşamadık", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(model.error?.userMessage ?? "")
            }
            .interactiveDismissDisabled(model.isSubmitting)
        }
    }

    /// Hangi hayvan / nokta için açıldığı.
    @ViewBuilder
    private var contextChips: some View {
        if model.animal != nil || model.presetSpot != nil {
            FlowLayout(spacing: 8) {
                if let animal = model.animal {
                    TagChip(String(localized: "\(animal.displayName) için"), systemImage: animal.species.systemImage, style: .info)
                }
                if let spot = model.presetSpot {
                    TagChip(spot.title, systemImage: "mappin.and.ellipse")
                }
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if model.isSubmitting {
                Text("Paylaşılıyor…")
            } else {
                Text("İhtiyacı paylaş")
            }
        }
        .buttonStyle(.mamaPrimary(systemImage: "paperplane.fill"))
        .disabled(model.isSubmitting)
        .padding(.top, 4)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.error != nil },
            set: { isPresented in if !isPresented { model.error = nil } }
        )
    }

    private func load() async {
        var coordinate = location.coordinate
        if coordinate == nil, model.showsSpotPicker { coordinate = await location.refresh() }
        await model.load(near: coordinate)
    }

    private func submit() async {
        guard let id = await model.submit() else { return }
        router.showToast(String(localized: "Teşekkürler! İhtiyaç paylaşıldı, yakındaki gönüllüler görecek."))
        if model.shouldOpenVetHelp {
            // Acil veteriner: sheet kapanır, İhtiyaçlar sekmesinde veteriner bilgisi açılır (FR-I4).
            dismiss()
            router.open(.vetHelp(needId: id), in: .community)
        } else {
            dismiss()
        }
    }
}

#Preview("Noktadan") {
    PreviewEnvironment { services in
        CreateNeedFlow(spotId: DemoData.id(2, 1), animalId: DemoData.id(4, 2), services: services)
    }
}

#Preview("Nokta seçerek") {
    PreviewEnvironment { services in
        CreateNeedFlow(spotId: nil, animalId: nil, services: services)
    }
}
#endif
