#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Hayvan ekleme akışı (FR-A1, FR-A2). Sheet: `AppSheet.createAnimal(spotId:)`; kendi `NavigationStack`'ini açar.
public struct AddAnimalFlow: View {
    @State private var model: AddAnimalViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss

    public init(spotId: UUID?, services: AppServices) {
        _model = State(initialValue: AddAnimalViewModel(spotId: spotId, services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mahallendeki dostu tanıt. Bildiklerini yaz, bilmediklerini boş bırak.")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                    AnimalIdentitySection(model: model)
                    AnimalHealthSection(model: model)
                    AnimalTemperamentSection(model: model)
                    AnimalPhotosSection(model: model)
                    AnimalSpotSection(model: model)
                    if let message = model.validationMessage {
                        BannerView(message, style: .warning)
                    }
                    submitButton
                }
                .padding(MamaMetrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .mamaBackground()
            .navigationTitle("Hayvan ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .task { await loadSpots() }
            .alert("Kaydedemedik", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(model.error?.userMessage ?? "")
            }
            .interactiveDismissDisabled(model.isSubmitting)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if model.isSubmitting {
                Text("Kaydediliyor…")
            } else {
                Text("Hayvanı ekle")
            }
        }
        .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
        .disabled(!model.canSubmit)
        .padding(.top, 4)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.error != nil },
            set: { isPresented in if !isPresented { model.error = nil } }
        )
    }

    private func loadSpots() async {
        var coordinate = location.coordinate
        if coordinate == nil { coordinate = await location.refresh() }
        await model.loadSpots(near: coordinate)
    }

    private func submit() async {
        guard let animal = await model.submit() else { return }
        router.showToast(String(localized: "Teşekkürler! \(animal.displayName) mahallenin defterine eklendi."))
        dismiss()
        router.push(.animal(animal.id))
    }
}

#Preview("Noktadan") {
    PreviewEnvironment { services in
        AddAnimalFlow(spotId: DemoData.id(2, 1), services: services)
    }
}

#Preview("Yakındaki noktalar") {
    PreviewEnvironment { services in
        AddAnimalFlow(spotId: nil, services: services)
    }
}
#endif
