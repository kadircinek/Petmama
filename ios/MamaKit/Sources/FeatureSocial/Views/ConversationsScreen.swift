#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Profil › "Sohbetler": buluşma ve bire bir sohbetler birlikte, son mesaja göre. Rota: `AppRoute.conversations`.
public struct ConversationsScreen: View {
    @State private var model: ConversationsViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    private let services: AppServices

    public init(services: AppServices) {
        _model = State(initialValue: ConversationsViewModel(services: services))
        self.services = services
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(String(localized: "Sohbetler"))
            .navigationBarTitleDisplayMode(.inline)
            // Sohbetten dönünce okunmamış sayıları tazelensin.
            .onAppear { Task { await reload() } }
    }

    @ViewBuilder
    private var content: some View {
        if !session.isSignedIn {
            SocialSignInGate(message: String(localized: "Sohbetlerini görmek için giriş yap.")) {
                router.present(.signIn, session: session)
            }
        } else if !model.hasLoaded {
            LoadingView()
        } else if model.isEmpty {
            EmptyStateView(
                mascot: .duo,
                mood: .happy,
                title: String(localized: "Henüz sohbet yok"),
                message: String(localized: "Bir buluşmaya katıl ya da Hayvanseverler'de biriyle tanış; sohbetlerin burada toplanır."),
                actionTitle: String(localized: "Hayvanseverler"),
                action: { router.push(.animalLovers) }
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    ForEach(model.items) { item in
                        NavigationLink(value: AppRoute.conversation(item.id)) {
                            ConversationRow(item: item, now: services.now())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        guard session.isSignedIn else { return }
        await model.load()
    }
}

private struct ConversationRow: View {
    let item: ConversationSummary
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: item.title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .lineLimit(1)
                    if item.isReadOnly {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                            .accessibilityLabel(String(localized: "Yalnızca okunabilir"))
                    }
                    Spacer(minLength: 0)
                    if let lastAt = item.lastAt {
                        Text(verbatim: MamaFormat.relative(lastAt, now: now))
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(verbatim: item.lastBody ?? String(localized: "Henüz mesaj yok. İlk merhabayı sen yaz!"))
                        .font(MamaFont.subheadline)
                        .foregroundStyle(item.unreadCount > 0 ? MamaColor.textPrimary : MamaColor.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if item.unreadCount > 0 {
                        Text(verbatim: item.unreadCount > 99 ? "99+" : "\(item.unreadCount)")
                            .font(MamaFont.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MamaColor.statusUrgent))
                            .accessibilityLabel(String(localized: "\(item.unreadCount) okunmamış mesaj"))
                    }
                }
            }
        }
        .mamaCard(padding: 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        switch item.kind {
        case .direct:
            AvatarView(name: item.title, url: item.otherAvatarURL, size: 48)
        case .meetup:
            Image(systemName: "person.3.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(MamaColor.tileBlue))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        ConversationsScreen(services: services)
    }
}
#endif
