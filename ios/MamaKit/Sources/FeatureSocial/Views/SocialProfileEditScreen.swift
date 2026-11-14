#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Hayvansever profili: görünürlük, hakkında (0–300) ve ilgi etiketleri. Kendi `NavigationStack`'iyle sheet olarak açılır.
public struct SocialProfileEditScreen: View {
    @State private var model: SocialProfileEditViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss

    public init(services: AppServices) {
        _model = State(initialValue: SocialProfileEditViewModel(services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    visibilitySection
                    aboutSection
                    interestsSection
                    if let message = model.message {
                        BannerView(message, style: .warning)
                    }
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        if model.isSaving {
                            Text("Kaydediliyor…")
                        } else {
                            Text("Kaydet")
                        }
                    }
                    .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
                    .disabled(model.isSaving || model.aboutRemaining < 0)
                }
                .padding(MamaMetrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .mamaBackground()
            .navigationTitle("Hayvansever profilim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                        .disabled(model.isSaving)
                }
            }
            .task { await model.load() }
        }
    }

    private var visibilitySection: some View {
        SocialFormCard(String(localized: "Görünürlük")) {
            Toggle(isOn: $model.isVisible) {
                Text("Hayvanseverler'de görün")
                    .font(MamaFont.bodyEmphasized)
            }
            .tint(MamaColor.statusFed)
            Label {
                Text("Konumun yaklaşık 1 km'ye yuvarlanır; başkaları yalnızca mesafe aralığını görür, haritada gösterilmezsin. Kapattığında listeden hemen çıkarsın, mevcut sohbetlerin sürer.")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(MamaFont.footnote)
            .foregroundStyle(MamaColor.textSecondary)
        }
    }

    private var aboutSection: some View {
        SocialFormCard(String(localized: "Hakkında"), subtitle: String(localized: "Nerede, hangi hayvanlara bakıyorsun? Nasıl yardımcı olabilirsin?")) {
            TextField(String(localized: "Ör. Moda sahilindeki kedileri besliyorum, kısırlaştırma randevularına yardım ederim."), text: $model.about, axis: .vertical)
                .lineLimit(3...8)
                .font(MamaFont.body)
                .socialFieldBackground()
            CharacterCounter(count: model.about.count, limit: SocialPolicy.maxAbout)
        }
    }

    private var interestsSection: some View {
        SocialFormCard(String(localized: "İlgi alanların"), subtitle: String(localized: "Ortak ilgi alanı olanlar listede önce görünür.")) {
            FlowLayout(spacing: 8) {
                ForEach(SocialInterest.allCases, id: \.self) { interest in
                    SelectableChip(interest.label, systemImage: interest.systemImage, isSelected: model.interests.contains(interest)) {
                        model.toggle(interest)
                    }
                }
            }
        }
    }

    private func save() async {
        var coordinate = location.coordinate
        if coordinate == nil, model.isVisible { coordinate = await location.refresh() }
        guard let outcome = await model.save(at: coordinate), outcome == .saved else { return }
        if model.isVisible {
            router.showToast("Profilin kaydedildi; artık hayvanseverler seni görebilir.")
        } else {
            router.showToast("Profilin kaydedildi.")
        }
        dismiss()
    }
}

#Preview {
    PreviewEnvironment { services in
        SocialProfileEditScreen(services: services)
    }
}
#endif
