#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Harita üstündeki çekilebilir alt panel (D10). Kapalıyken en yakın nokta ve tek dokunuşla "Mama koydum";
/// açıkken ana sayfa içeriği (selamlama, hızlı eylemler, mama gereken noktalar, "Bugün mahallende").
struct MapHomePanel: View {
    let model: MapViewModel
    @Binding var isExpanded: Bool
    let maxExpandedHeight: CGFloat

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                handle
                collapsedContent
                    .padding(.horizontal, 16)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)

            if isExpanded {
                ScrollView {
                    HomePanelContent(model: model)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }
                .frame(maxHeight: maxExpandedHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MamaColor.card)
                .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        )
        .offset(y: dragOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .accessibilityAction(named: isExpanded ? Text("Paneli küçült") : Text("Ana sayfayı aç")) {
            isExpanded.toggle()
        }
    }

    private var handle: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Capsule()
                .fill(MamaColor.stroke)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityLabel(isExpanded ? Text("Paneli küçült") : Text("Ana sayfayı aç"))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, state, _ in
                let height = value.translation.height
                // Açıkken aşağı, kapalıyken yukarı doğru hafif takip.
                state = isExpanded ? max(0, height) : max(-60, min(0, height)) * 0.5
            }
            .onEnded { value in
                let height = value.translation.height
                if height < -40 { isExpanded = true }
                if height > 40 { isExpanded = false }
            }
    }

    // MARK: - Kapalı durum

    @ViewBuilder
    private var collapsedContent: some View {
        if let target = model.quickFeedTarget {
            QuickFeedRow(target: target, now: model.now, isSubmitting: model.isSubmittingQuickFeed, onFeed: quickFeed)
        } else if let nearest = model.nearestSpot {
            NearestSpotRow(spot: nearest) { router.push(.spot(nearest.id)) }
        } else if model.isNeighborhoodEmpty {
            HStack(spacing: 12) {
                Text("Bu sokağın ilk besleyicisi sen ol")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                Spacer(minLength: 8)
                Button("Nokta ekle") { router.present(.addSpot(nil), session: session) }
                    .buttonStyle(.mamaPrimary(systemImage: "plus", fullWidth: false))
            }
        } else if model.userCoordinate == nil {
            HStack(spacing: 12) {
                Text("Konumunu açarsan en yakın noktayı gösteririz.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                Spacer(minLength: 8)
                Button("İzin ver") {
                    Task {
                        await location.requestAuthorization()
                        await model.userLocationChanged(await location.refresh())
                    }
                }
                .buttonStyle(.mamaSecondary(systemImage: "location.fill", fullWidth: false))
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 54)
        }
    }

    /// PRD 6.4: "Mama koydum" tek elle 2 saniyede; giriş yoksa önce giriş, sonra hızlı akış.
    private func quickFeed() {
        guard session.isSignedIn else {
            router.present(.quickFeed, session: session)
            return
        }
        Task {
            let feedback = await model.submitQuickFeed()
            router.showToast(feedback.message, style: feedback.style)
        }
    }
}

private struct QuickFeedRow: View {
    let target: MapViewModel.QuickFeedTarget
    let now: Date
    let isSubmitting: Bool
    let onFeed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(MamaColor.statusFed)
                Text("\(target.spot.title) · \(MamaFormat.distance(target.distanceMeters))")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                StatusBadge(status: target.spot.currentStatus(now: now), hasUrgentNeed: target.spot.hasUrgentNeed, compact: true)
            }
            .accessibilityElement(children: .combine)
            Button(action: onFeed) {
                if isSubmitting {
                    ProgressView().tint(MamaColor.onInk)
                } else {
                    Text("Mama koydum")
                }
            }
            .buttonStyle(.mamaFed)
            .disabled(isSubmitting)
            .accessibilityHint(Text("\(target.spot.title) noktasına mama koyduğunu kaydeder"))
        }
    }
}

private struct NearestSpotRow: View {
    let spot: Spot
    let onDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("En yakın nokta")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                Text(spot.distanceMeters.map { "\(spot.title) · \(MamaFormat.distance($0))" } ?? spot.title)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Detay", action: onDetail)
                .buttonStyle(.mamaSecondary(fullWidth: false))
        }
    }
}
#endif
