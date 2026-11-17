#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Tek vaka (Faz 3.1): içerik önizlemesi, raporlar, sahibinin geçmişi ve kararlar.
/// Rota: `AppRoute.moderationCase(target:id:)`. Her karar onay diyaloğuyla; not isteğe bağlı.
public struct ModerationCaseScreen: View {
    @State private var model: ModerationCaseViewModel
    @State private var pendingDecision: ModerationDecision?
    @State private var pendingSuspension: SuspensionLength?
    @State private var showsUnsuspendDialog = false
    @State private var successFeedback = 0
    @Environment(AppRouter.self) private var router

    public init(target: ReportTarget, targetId: UUID, services: AppServices) {
        _model = State(initialValue: ModerationCaseViewModel(target: target, targetId: targetId, services: services))
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(String(localized: "Rapor"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .confirmationDialog(
                decisionDialogTitle,
                isPresented: Binding(get: { pendingDecision != nil }, set: { if !$0 { pendingDecision = nil } }),
                titleVisibility: .visible,
                presenting: pendingDecision
            ) { decision in
                switch decision {
                case .approve:
                    Button("Uygun, yayında kalsın") { run { await model.decide(.approve) } }
                case .remove:
                    Button("Kaldır", role: .destructive) { run { await model.decide(.remove) } }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { decision in
                switch decision {
                case .approve: Text("İçerik yayında kalır (gizlendiyse geri açılır), açık raporlar kapanır.")
                case .remove: Text(removeMessage)
                }
            }
            .confirmationDialog(
                String(localized: "Kullanıcı uzaklaştırılsın mı?"),
                isPresented: Binding(get: { pendingSuspension != nil }, set: { if !$0 { pendingSuspension = nil } }),
                titleVisibility: .visible,
                presenting: pendingSuspension
            ) { length in
                Button(String(localized: "\(length.label) uzaklaştır"), role: .destructive) { run { await model.suspend(length) } }
                Button("Vazgeç", role: .cancel) {}
            } message: { _ in
                Text("Uzaklaştırılan kişi uygulamayı okumaya devam eder ama hiçbir şey yazamaz: nokta, check-in, paylaşım, yorum, mesaj, buluşma, istek.")
            }
            .confirmationDialog(
                String(localized: "Uzaklaştırma kaldırılsın mı?"),
                isPresented: $showsUnsuspendDialog,
                titleVisibility: .visible
            ) {
                Button("Uzaklaştırmayı kaldır") { run { await model.unsuspend() } }
                Button("Vazgeç", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: successFeedback)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            LoadingView()
        } else if let detail = model.detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = model.message {
                        BannerView(message, style: .success)
                    }
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    ModerationPreviewCard(item: detail.moderationCase)
                    if model.canDecide {
                        decisionSection
                    } else if let decision = detail.moderationCase.decision {
                        decidedSection(decision, at: detail.moderationCase.decidedAt)
                    }
                    if let owner = detail.owner {
                        ownerSection(owner)
                    }
                    reportsSection(detail.reports)
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .refreshable { await model.load() }
        } else {
            EmptyStateView(
                systemImage: model.error == nil ? "tray" : "exclamationmark.triangle",
                title: model.error == nil ? String(localized: "Bu rapor artık yok") : String(localized: "Rapor yüklenemedi"),
                message: model.error?.userMessage
            )
        }
    }

    // MARK: - Karar

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Karar"))
            VStack(alignment: .leading, spacing: 6) {
                TextField(String(localized: "Kısa not (isteğe bağlı)"), text: $model.note, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                        .fill(MamaColor.cardSecondary))
                Text(model.isNoteTooLong
                     ? String(localized: "Not en fazla 500 karakter olabilir.")
                     : String(localized: "Not yalnızca karar kaydında görünür, kullanıcıya gitmez."))
                    .font(MamaFont.caption)
                    .foregroundStyle(model.isNoteTooLong ? MamaColor.statusUrgent : MamaColor.textSecondary)
            }
            Button { pendingDecision = .approve } label: { Text("Uygun, yayında kalsın") }
                .buttonStyle(.mamaPrimary(accent: MamaColor.statusFed, systemImage: "checkmark"))
            Button { pendingDecision = .remove } label: { Text("Kaldır") }
                .buttonStyle(.mamaSecondary(tint: MamaColor.statusUrgent, systemImage: "trash"))
        }
        .disabled(model.isBusy || model.isNoteTooLong)
        .mamaCard()
    }

    private func decidedSection(_ decision: ModerationDecision, at date: Date?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: decision == .remove ? "trash.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(decision == .remove ? MamaColor.statusUrgent : MamaColor.statusFed)
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.label)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                if let date {
                    Text(verbatim: MamaFormat.relative(date))
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .mamaCard()
    }

    // MARK: - Sahip

    private func ownerSection(_ owner: ModerationOwnerHistory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(model.target == .user ? String(localized: "Raporlanan kullanıcı") : String(localized: "İçerik sahibi"))
            HStack(spacing: 12) {
                AvatarView(name: owner.displayName ?? "?", url: nil, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: owner.displayName ?? String(localized: "Silinmiş kullanıcı"))
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    if owner.isModerator {
                        TagChip(String(localized: "Moderatör"), systemImage: "checkmark.shield.fill", style: .info)
                    }
                }
                Spacer(minLength: 0)
            }
            InfoRow(systemImage: "trash", title: String(localized: "Son 90 günde kaldırılan"), value: "\(owner.removedCount90d)")
            InfoRow(systemImage: "hand.raised", title: String(localized: "Son 90 günde uzaklaştırma"), value: "\(owner.suspensionCount90d)")
            if let text = model.ownerSuspensionText {
                BannerView(String(localized: "Şu an uzaklaştırılmış: \(text)"), style: .warning, systemImage: "hand.raised.fill")
                Button { showsUnsuspendDialog = true } label: { Text("Uzaklaştırmayı kaldır") }
                    .buttonStyle(.mamaSecondary(systemImage: "arrow.uturn.backward"))
                    .disabled(model.isBusy)
            } else if model.canSuspend {
                Menu {
                    ForEach(SuspensionLength.allCases, id: \.self) { length in
                        Button(length.label) { pendingSuspension = length }
                    }
                } label: {
                    Label(String(localized: "Kullanıcıyı uzaklaştır"), systemImage: "hand.raised.fill")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.statusUrgent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().strokeBorder(MamaColor.statusUrgent.opacity(0.5), lineWidth: 1.5))
                }
                .disabled(model.isBusy || model.isNoteTooLong)
            }
        }
        .mamaCard()
    }

    // MARK: - Raporlar

    private func reportsSection(_ reports: [ModerationReportEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(String(localized: "Raporlar"))
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TagChip(report.reason.label, systemImage: "flag.fill", style: report.status == .open ? .warning : .neutral)
                        Spacer(minLength: 0)
                        Text(verbatim: MamaFormat.relative(report.createdAt))
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                    if let details = report.details, !details.isEmpty {
                        Text(verbatim: details)
                            .font(MamaFont.subheadline)
                            .foregroundStyle(MamaColor.textPrimary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill").accessibilityHidden(true)
                        Text(verbatim: report.reporterName ?? String(localized: "Silinmiş kullanıcı"))
                        Text(verbatim: "·")
                        Text(statusLabel(report.status))
                    }
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                    .fill(MamaColor.card))
            }
        }
    }

    private func statusLabel(_ status: ModerationReportStatus) -> String {
        switch status {
        case .open: return String(localized: "Açık")
        case .actioned: return String(localized: "İşleme alındı")
        case .dismissed: return String(localized: "Reddedildi")
        }
    }

    // MARK: - Yardımcılar

    private var decisionDialogTitle: String {
        switch pendingDecision {
        case .remove: return String(localized: "İçerik kaldırılsın mı?")
        default: return String(localized: "İçerik yayında kalsın mı?")
        }
    }

    private var removeMessage: String {
        switch model.target {
        case .meetup: return String(localized: "Buluşma iptal edilir, katılanlara haber verilir. Açık raporlar kapanır.")
        case .need, .animal: return String(localized: "Kayıt kalıcı olarak silinir. Açık raporlar kapanır.")
        case .checkin, .photo: return String(localized: "Fotoğraf kaldırılır. Açık raporlar kapanır.")
        case .user: return String(localized: "Kullanıcı raporunda içerik yoktur: yalnızca raporlar kapanır. Uzaklaştırma ayrı bir karardır.")
        default: return String(localized: "İçerik herkesten gizlenir, yazarı da göremez. Açık raporlar kapanır.")
        }
    }

    private func run(_ work: @escaping () async -> Bool) {
        Task {
            if await work() { successFeedback += 1 }
        }
    }
}

/// İçerik önizlemesi. Sohbet mesajında yalnızca raporlanan mesaj görünür.
struct ModerationPreviewCard: View {
    let item: ModerationCase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TagChip(item.target.label, systemImage: item.target.systemImage, style: .info)
                ModerationStateChip(state: item.contentState)
                Spacer(minLength: 0)
            }
            if item.photoURL != nil {
                AsyncPhoto(url: item.photoURL, placeholderSystemImage: item.target.systemImage)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
            }
            if let title = item.displayTitle {
                Text(verbatim: title)
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            if let body = item.displayBody {
                Text(verbatim: body)
                    .font(MamaFont.body)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            if item.target == .chatMessage {
                Text("Yalnızca raporlanan mesaj gösterilir; sohbetin geri kalanı gizli kalır.")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            if let owner = item.ownerName, item.target != .user {
                Label(owner, systemImage: "person.fill")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            FlowLayout(spacing: 6) {
                TagChip(String(localized: "\(item.reportCount) rapor"), systemImage: "flag.fill", style: .warning)
                ForEach(item.reasons, id: \.self) { reason in
                    TagChip(reason.label)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }
}

#Preview {
    PreviewEnvironment { services in
        ModerationCaseScreen(target: .post, targetId: DemoData.moderationPostId, services: services)
    }
}
#endif
