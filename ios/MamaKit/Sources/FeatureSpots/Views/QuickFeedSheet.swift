#if canImport(UIKit)
import SwiftUI
import UIKit
import MamaCore
import MamaDesign

/// Tek dokunuşla "Mama koydum" (PRD 6.4): 100 m içindeki en yakın noktayı seçer, büyük bir onay kartı gösterir.
public struct QuickFeedSheet: View {
    @State private var model: QuickFeedViewModel
    @State private var successTrigger = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location

    public init(services: AppServices) {
        _model = State(initialValue: QuickFeedViewModel(services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.state {
                    case .locating:
                        LoadingView(String(localized: "En yakın noktayı arıyoruz…"))
                            .frame(minHeight: 220)
                    case .needsLocation:
                        locationPrompt
                    case .candidate(let spot, let distance):
                        candidateCard(spot: spot, distance: distance)
                    case .noneNearby(let spots):
                        noneNearby(spots)
                    case .failed(let error):
                        EmptyStateView(
                            systemImage: "wifi.slash",
                            title: String(localized: "Noktalar yüklenemedi"),
                            message: error.userMessage,
                            actionTitle: String(localized: "Tekrar dene")
                        ) {
                            Task { await locate() }
                        }
                    }
                }
                .padding(20)
            }
            .mamaBackground()
            .navigationTitle("Mama koy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .overlay { PawBurstView(trigger: successTrigger) }
        }
        .sensoryFeedback(.success, trigger: successTrigger)
        .presentationDetents([.medium, .large])
        .task { await locate() }
    }

    private func candidateCard(spot: Spot, distance: Double) -> some View {
        let status = spot.currentStatus(now: model.now)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AsyncPhoto(url: spot.photoURL, placeholderSystemImage: spot.type.systemImage, placeholderTint: status.color)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(spot.title) · \(MamaFormat.distance(distance))")
                        .font(MamaFont.title3)
                        .foregroundStyle(MamaColor.textPrimary)
                    StatusBadge(status: status, hasUrgentNeed: spot.hasUrgentNeed)
                }
            }
            .accessibilityElement(children: .combine)
            Text("Bu noktaya mama koyduğunu kaydedelim mi?")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
            Button {
                submit()
            } label: {
                if model.isSubmitting {
                    ProgressView().tint(MamaColor.onInk)
                } else {
                    Text("Mama koydum")
                }
            }
            .buttonStyle(.mamaFed)
            .disabled(model.isSubmitting)
            if let result = model.result, !result.dismissesSheet {
                BannerView(result.message, style: .warning)
            }
        }
        .mamaCard(padding: 20)
    }

    private func noneNearby(_ spots: [Spot]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("100 m içinde bir nokta bulamadık")
                .font(MamaFont.title3)
                .foregroundStyle(MamaColor.textPrimary)
            Text("Mama koyduğun yer haritada yoksa yeni bir nokta olarak ekleyebilirsin.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
            if !spots.isEmpty {
                SectionHeader(String(localized: "En yakın noktalar"))
                ForEach(spots) { spot in
                    Button {
                        router.dismissSheet()
                        router.push(.spot(spot.id))
                    } label: {
                        SpotCardView(spot: spot, now: model.now)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Yeni nokta ekle") {
                router.present(.addSpot(nil), session: session)
            }
            .buttonStyle(.mamaPrimary(systemImage: "plus"))
        }
    }

    @ViewBuilder
    private var locationPrompt: some View {
        let denied = location.authorization == .denied
        EmptyStateView(
            systemImage: "location.slash",
            title: String(localized: "Konumunu bilmemiz gerekiyor"),
            message: denied
                ? String(localized: "Konum izni kapalı. En yakın noktayı bulmak için Ayarlar'dan açabilirsin.")
                : String(localized: "En yakın noktayı bulup tek dokunuşla kaydetmek için konumuna bir kez bakarız."),
            actionTitle: denied ? String(localized: "Ayarları aç") : String(localized: "Konuma izin ver")
        ) {
            if denied {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } else {
                Task { await locate() }
            }
        }
    }

    private func locate() async {
        if location.authorization == .notDetermined {
            await location.requestAuthorization()
        }
        await model.locate(user: await location.refresh())
    }

    private func submit() {
        Task {
            let result = await model.submit()
            guard result.dismissesSheet else { return }
            if result.isSuccess { successTrigger += 1 }
            router.showToast(result.message, style: result.toastStyle)
            try? await Task.sleep(nanoseconds: result.isSuccess ? 900_000_000 : 300_000_000)
            dismiss()
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        Color.clear.sheet(isPresented: .constant(true)) {
            QuickFeedSheet(services: services)
        }
    }
}
#endif
