#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Moderasyon kuyruğu (Faz 3.1). Rota: `AppRoute.moderation`. Profil'de yalnızca moderatöre görünür.
public struct ModerationQueueScreen: View {
    @State private var model: ModerationQueueViewModel
    @Environment(AppRouter.self) private var router

    public init(services: AppServices) {
        _model = State(initialValue: ModerationQueueViewModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 12) {
            PillSegmentedControl(
                selection: Binding(get: { model.tab }, set: { tab in Task { await model.select(tab) } }),
                options: [
                    (value: ModerationQueueViewModel.Tab.open, title: openTitle),
                    (value: ModerationQueueViewModel.Tab.closed, title: String(localized: "Kapananlar")),
                ]
            )
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 8)
            content
        }
        .mamaBackground()
        .navigationTitle(String(localized: "Moderasyon"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // Detaydan karar verip dönünce listeyi tazele.
        .onChange(of: router.path(for: router.selectedTab).count) { old, new in
            if new < old { Task { await model.load() } }
        }
    }

    private var openTitle: String {
        model.openCount > 0 ? String(localized: "Açık (\(model.openCount))") : String(localized: "Açık")
    }

    private var emptyTitle: String {
        switch model.tab {
        case .open: return String(localized: "Bekleyen rapor yok")
        case .closed: return String(localized: "Son 30 günde kapanan rapor yok")
        }
    }

    private var emptyMessage: String {
        switch model.tab {
        case .open: return String(localized: "Yeni bir rapor geldiğinde burada görünür. Raporlara 24 saat içinde bakmaya çalış.")
        case .closed: return String(localized: "Verdiğin kararlar burada listelenir.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            LoadingView()
        } else if model.isEmpty {
            EmptyStateView(
                systemImage: model.tab == .open ? "checkmark.shield.fill" : "tray.fill",
                title: model.error == nil ? emptyTitle : String(localized: "Raporlar yüklenemedi"),
                message: model.error?.userMessage ?? emptyMessage
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    if model.tab == .open {
                        Text("En çok raporlanan ve en eski önce. Raporlara 24 saat içinde bakmaya çalış.")
                            .font(MamaFont.footnote)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                    ForEach(model.cases) { item in
                        NavigationLink(value: AppRoute.moderationCase(target: item.target, id: item.targetId)) {
                            ModerationCaseCard(item: item, now: Date())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.bottom, 16)
            }
            .refreshable { await model.load() }
        }
    }
}

/// Kuyruk satırı: hedef türü, durum, kısa önizleme, sahip, rapor sayısı ve nedenler.
struct ModerationCaseCard: View {
    let item: ModerationCase
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TagChip(item.target.label, systemImage: item.target.systemImage, style: .info)
                ModerationStateChip(state: item.contentState)
                Spacer(minLength: 0)
                Text(verbatim: MamaFormat.relative(item.lastReportedAt, now: now))
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            HStack(alignment: .top, spacing: 12) {
                if item.photoURL != nil {
                    AsyncPhoto(url: item.photoURL, placeholderSystemImage: item.target.systemImage)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let title = item.displayTitle {
                        Text(verbatim: title)
                            .font(MamaFont.headline)
                            .foregroundStyle(MamaColor.textPrimary)
                            .lineLimit(2)
                    }
                    if let body = item.displayBody {
                        Text(verbatim: body)
                            .font(MamaFont.subheadline)
                            .foregroundStyle(MamaColor.textSecondary)
                            .lineLimit(3)
                    }
                    if let owner = item.ownerName, item.target != .user {
                        Label(owner, systemImage: "person.fill")
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            FlowLayout(spacing: 6) {
                TagChip(String(localized: "\(item.reportCount) rapor"), systemImage: "flag.fill", style: .warning)
                ForEach(item.reasons, id: \.self) { reason in
                    TagChip(reason.label)
                }
                if let decision = item.decision {
                    TagChip(decision.label, systemImage: decision == .remove ? "trash.fill" : "checkmark",
                            style: decision == .remove ? .danger : .positive)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
        .accessibilityElement(children: .combine)
    }
}

struct ModerationStateChip: View {
    let state: ModerationContentState

    var body: some View {
        switch state {
        case .live: TagChip(String(localized: "Yayında"), systemImage: "eye.fill", style: .positive)
        case .pending: TagChip(String(localized: "İncelemede"), systemImage: "eye.slash.fill", style: .warning)
        case .removed: TagChip(String(localized: "Kaldırıldı"), systemImage: "trash.fill", style: .danger)
        case .gone: TagChip(String(localized: "Silinmiş"), systemImage: "xmark.circle", style: .neutral)
        }
    }
}

extension ModerationDecision {
    var label: String {
        switch self {
        case .approve: return String(localized: "Uygun bulundu")
        case .remove: return String(localized: "Kaldırıldı")
        }
    }
}

extension SuspensionLength {
    var label: String {
        switch self {
        case .week: return String(localized: "7 gün")
        case .month: return String(localized: "30 gün")
        case .indefinite: return String(localized: "Süresiz")
        }
    }
}

extension ModerationCase {
    /// Sunucu ihtiyaç ve paylaşımda tür anahtarı döner; yerelleştirilmiş etikete çevrilir.
    var displayTitle: String? {
        switch target {
        case .need: return title.flatMap(NeedType.init(rawValue:))?.label ?? title
        case .post: return title.flatMap(CommunityPostKind.init(rawValue:))?.label ?? title
        default: return title
        }
    }

    var displayBody: String? {
        switch target {
        case .checkin, .photo: return body.flatMap(CheckInKind.init(rawValue:))?.label ?? body
        default: return body
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        ModerationQueueScreen(services: services)
    }
}
#endif
