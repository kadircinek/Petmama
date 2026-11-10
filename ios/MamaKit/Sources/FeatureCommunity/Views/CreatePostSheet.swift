#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Mahalleye yaz". Sheet: `AppSheet.createPost(kind:spotId:)`; kendi `NavigationStack`'ini açar.
public struct CreatePostSheet: View {
    @State private var model: CreatePostViewModel
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var showsDiscardDialog = false

    public init(kind: CommunityPostKind?, spotId: UUID?, services: AppServices) {
        _model = State(initialValue: CreatePostViewModel(kind: kind, spotId: spotId, services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CreatePostKindSection(model: model)
                    if model.kind == .alert {
                        BannerView(
                            String(localized: "Acil bir durum varsa önce 112'yi veya Alo 153'ü ara. Uyarın mahalledeki besleyicilere görünür."),
                            style: .warning,
                            systemImage: "phone.fill"
                        )
                    }
                    CreatePostBodySection(model: model)
                    if model.isCoverRequest {
                        CreatePostCoverDatesSection(model: model)
                    }
                    CreatePostSpotSection(model: model)
                    CreatePostPhotoSection(model: model)
                    privacyFootnote
                    if let problem = model.visibleProblem(near: location.coordinate) {
                        BannerView(problem, style: .warning)
                    }
                    submitButton
                }
                .padding(MamaMetrics.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .mamaBackground()
            .navigationTitle("Mahalleye yaz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { cancel() }
                        .disabled(model.isSubmitting)
                }
            }
            .task { await load() }
            .confirmationDialog("Taslak silinsin mi?", isPresented: $showsDiscardDialog, titleVisibility: .visible) {
                Button("Taslağı sil", role: .destructive) { dismiss() }
                Button("Yazmaya devam et", role: .cancel) {}
            } message: {
                Text("Yazdıkların kaydedilmez.")
            }
        }
        // Boş olmayan taslak aşağı kaydırmayla kaybolmasın; "Vazgeç" önce onay ister.
        .interactiveDismissDisabled(model.hasDraftContent || model.isSubmitting)
    }

    private var privacyFootnote: some View {
        Label {
            Text("Paylaşımın yaklaşık 1 km hassasiyetle mahallene gösterilir; tam konumun saklanmaz.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(MamaFont.footnote)
        .foregroundStyle(MamaColor.textSecondary)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if model.isSubmitting {
                Text("Paylaşılıyor…")
            } else {
                Text("Mahalleyle paylaş")
            }
        }
        .buttonStyle(.mamaPrimary(systemImage: "paperplane.fill"))
        .disabled(model.isSubmitting)
        .padding(.top, 4)
    }

    // MARK: - Eylemler

    private func load() async {
        var coordinate = location.coordinate
        if coordinate == nil { coordinate = await location.refresh() }
        await model.load(near: coordinate)
    }

    private func cancel() {
        if model.hasDraftContent {
            showsDiscardDialog = true
        } else {
            dismiss()
        }
    }

    /// Nokta bağlı değilse kaba konum için taze konum denenir; yoksa form dostça uyarır.
    private func submit() async {
        var coordinate = location.coordinate
        if coordinate == nil, model.selectedSpotId == nil { coordinate = await location.refresh() }
        guard let result = await model.submit(near: coordinate), result.isCreated else { return }
        router.showToast(result.message, style: result.toastStyle)
        dismiss()
    }
}

#Preview("Paylaşım") {
    PreviewEnvironment { services in
        CreatePostSheet(kind: nil, spotId: nil, services: services)
    }
}

#Preview("Yerime bakar mısın?") {
    PreviewEnvironment { services in
        CreatePostSheet(kind: .coverRequest, spotId: DemoData.id(2, 1), services: services)
    }
}

#Preview("Uyarı") {
    PreviewEnvironment { services in
        CreatePostSheet(kind: .alert, spotId: nil, services: services)
    }
}
#endif
