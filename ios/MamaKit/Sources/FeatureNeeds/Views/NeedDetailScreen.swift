#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// İhtiyaç detayı. Rota: `AppRoute.need(id)`.
public struct NeedDetailScreen: View {
    @State private var model: NeedDetailViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @State private var confirmResolve = false
    @State private var feedback = 0

    public init(needId: UUID, services: AppServices) {
        _model = State(initialValue: NeedDetailViewModel(needId: needId, services: services))
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(model.need?.type.label ?? String(localized: "İhtiyaç"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            router.present(.report(.need, model.needId), session: session)
                        } label: {
                            Label("Raporla", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "Diğer seçenekler"))
                }
            }
            .task { await model.load() }
            .confirmationDialog("Bu ihtiyaç çözüldü mü?", isPresented: $confirmResolve, titleVisibility: .visible) {
                Button("Evet, çözüldü") { resolve() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Çözüldü olarak işaretleyince ihtiyacı açan kişiye haber veririz.")
            }
            .sensoryFeedback(.success, trigger: feedback)
    }

    @ViewBuilder
    private var content: some View {
        if let need = model.need {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NeedPhotoHeader(need: need)
                    chips(need)
                    Text(need.description)
                        .font(MamaFont.body)
                        .foregroundStyle(MamaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    links(need)
                    NeedTimelineView(steps: model.timeline(viewerId: session.userId), now: model.now)
                    actions(need)
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.bottom, 24)
            }
            .refreshable { await model.load() }
        } else if model.hasLoaded {
            EmptyStateView(
                systemImage: "questionmark.circle",
                title: String(localized: "Bu ihtiyacı bulamadık"),
                message: model.error?.userMessage
            )
        } else {
            LoadingView()
        }
    }

    private func chips(_ need: Need) -> some View {
        FlowLayout(spacing: 8) {
            TagChip(need.type.label, systemImage: need.type.systemImage)
            TagChip(
                need.urgency.label,
                systemImage: need.urgency == .urgent ? "exclamationmark.triangle.fill" : "clock",
                style: need.urgency == .urgent && need.status != .resolved ? .danger : .neutral
            )
            TagChip(need.status.label, systemImage: need.status.systemImage, style: statusStyle(need.status))
            TagChip(MamaFormat.relative(need.createdAt, now: model.now), systemImage: "clock.arrow.circlepath")
        }
    }

    @ViewBuilder
    private func links(_ need: Need) -> some View {
        if let animalId = need.animalId {
            NavigationLink(value: AppRoute.animal(animalId)) {
                NeedLinkRow(
                    title: need.animalName ?? String(localized: "Hayvan"),
                    subtitle: String(localized: "Hayvan profili"),
                    systemImage: "pawprint.fill",
                    photoURL: need.animalPhotoURL
                )
            }
            .buttonStyle(.plain)
        }
        if let spotId = need.spotId {
            NavigationLink(value: AppRoute.spot(spotId)) {
                NeedLinkRow(
                    title: need.spotTitle ?? String(localized: "Nokta"),
                    subtitle: need.isLocationExact ? String(localized: "Nokta detayı") : String(localized: "Yaklaşık konum"),
                    systemImage: "mappin.and.ellipse",
                    photoURL: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func actions(_ need: Need) -> some View {
        VStack(spacing: 10) {
            if need.status == .open {
                Button {
                    claim()
                } label: {
                    Text("Ben ilgileniyorum")
                }
                .buttonStyle(.mamaPrimary(systemImage: "hand.raised.fill"))
                .disabled(model.isWorking)
            }
            if model.canResolve(userId: session.userId, isVerifiedFeeder: session.profile?.isVerifiedFeeder ?? false) {
                Button {
                    confirmResolve = true
                } label: {
                    Text("Çözüldü olarak işaretle")
                }
                .buttonStyle(.mamaSecondary(tint: MamaColor.statusFed, systemImage: "checkmark.circle.fill"))
                .disabled(model.isWorking)
            }
            if model.showsVetHelp {
                Button {
                    router.push(.vetHelp(needId: need.id))
                } label: {
                    Text("Acil veteriner bilgisi")
                }
                .buttonStyle(.mamaSecondary(tint: MamaColor.statusUrgent, systemImage: "cross.case.fill"))
            }
        }
    }

    private func statusStyle(_ status: NeedStatus) -> TagChip.Style {
        switch status {
        case .open: return .warning
        case .claimed: return .info
        case .resolved: return .positive
        }
    }

    private func claim() {
        guard session.isSignedIn else {
            router.present(.signIn, session: session)
            return
        }
        Task {
            let result = await model.claim()
            if result == .claimed { feedback += 1 }
            router.showToast(result.message, style: result.toastStyle)
        }
    }

    /// Son kararı sunucu verir; yetki yoksa açıklayıcı mesaj.
    private func resolve() {
        Task {
            let result = await model.resolve()
            if result == .resolved { feedback += 1 }
            router.showToast(result.message, style: result.toastStyle)
        }
    }
}

#Preview("Acil veteriner") {
    PreviewEnvironment { services in
        NeedDetailScreen(needId: DemoData.id(5, 1), services: services)
    }
}

#Preview("Üstlenilmiş") {
    PreviewEnvironment { services in
        NeedDetailScreen(needId: DemoData.id(5, 4), services: services)
    }
}
#endif
