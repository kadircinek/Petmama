#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Profil" sekmesinin kökü (ekran 20, FR-P2/P4).
public struct ProfileTabScreen: View {
    @State private var model: ProfileViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    public init(services: AppServices) {
        _model = State(initialValue: ProfileViewModel(services: services))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let profile = session.profile {
                    signedIn(profile)
                } else {
                    signedOut
                }
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.vertical, 12)
        }
        .mamaBackground()
        .navigationTitle(String(localized: "Profil"))
        .task(id: session.userId) { await model.load(session: session) }
        .refreshable { await model.load(session: session) }
    }

    // MARK: - Oturum açık

    @ViewBuilder
    private func signedIn(_ profile: UserProfile) -> some View {
        header(profile)
        if let error = model.error {
            BannerView(error.userMessage, style: .warning)
        }
        if !model.isVerified(profile), model.hasLoadedStats {
            verificationProgress
        }
        StatsStrip(model.statItems.map { StatsStrip.Item(value: $0.value, label: $0.label) })
        badges
        MenuCard {
            NavigationLink(value: AppRoute.following) {
                MenuRow(title: String(localized: "Takip ettiklerim"), systemImage: "heart.fill", tint: MamaColor.tilePeach)
            }
            MenuDivider()
            NavigationLink(value: AppRoute.notifications) {
                MenuRow(
                    title: String(localized: "Bildirimler"),
                    systemImage: "bell.fill",
                    tint: MamaColor.tileBlue,
                    badge: model.unreadBadgeText
                )
            }
            MenuDivider()
            NavigationLink(value: AppRoute.settings) {
                MenuRow(title: String(localized: "Ayarlar"), systemImage: "gearshape.fill", tint: MamaColor.tileLavender)
            }
            MenuDivider()
            Button {
                router.present(.editProfile, session: session)
            } label: {
                MenuRow(title: String(localized: "Profili düzenle"), systemImage: "pencil", tint: MamaColor.tileMint)
            }
        }
        .buttonStyle(.plain)
    }

    private func header(_ profile: UserProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            AvatarView(name: profile.displayName, url: profile.avatarURL, size: 84)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName)
                    .font(MamaFont.title2)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(2)
                if let neighborhood = profile.neighborhood, !neighborhood.isEmpty {
                    Label(neighborhood, systemImage: "mappin.and.ellipse")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                if model.isVerified(profile) {
                    TagChip(String(localized: "Doğrulanmış besleyici"), systemImage: "checkmark.seal.fill", style: .positive)
                }
            }
            Spacer(minLength: 0)
            Button {
                router.present(.editProfile, session: session)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.mamaCircle)
            .accessibilityLabel(String(localized: "Profili düzenle"))
        }
        .mamaCard()
    }

    private var verificationProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.verificationMessage, systemImage: "checkmark.seal")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
            ProgressView(value: model.verificationProgress)
                .tint(MamaColor.statusFed)
                .accessibilityLabel(String(localized: "Doğrulanmış besleyici ilerlemesi"))
            Text(model.verificationHint)
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
        }
        .mamaCard()
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(String(localized: "Rozetler"))
                TagChip(String(localized: "yakında"), systemImage: "sparkles", style: .info)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                ForEach(ProfileViewModel.upcomingBadges) { badge in
                    LockedBadgeView(badge: badge)
                }
            }
            .mamaCard()
        }
    }

    // MARK: - Oturum kapalı

    @ViewBuilder
    private var signedOut: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(MamaColor.ink)
                .frame(width: 88, height: 88)
                .background(Circle().fill(MamaColor.mint))
                .accessibilityHidden(true)
            Text("Giriş yap, beslediğin noktaları takip et")
                .font(MamaFont.title3)
                .foregroundStyle(MamaColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Check-in'lerin, takip ettiğin noktalar ve hayvanlar, doğrulanmış besleyici rozetin burada görünür.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Giriş yap")) {
                router.present(.signIn, session: session)
            }
            .buttonStyle(.mamaPrimary)
        }
        .frame(maxWidth: .infinity)
        .mamaCard(padding: 20)

        MenuCard {
            NavigationLink(value: AppRoute.settings) {
                MenuRow(title: String(localized: "Ayarlar"), systemImage: "gearshape.fill", tint: MamaColor.tileLavender)
            }
            MenuDivider()
            NavigationLink(value: AppRoute.feedingGuide) {
                MenuRow(title: String(localized: "Sorumlu besleme rehberi"), systemImage: "book.fill", tint: MamaColor.tileMint)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Oturum açık") {
    PreviewEnvironment { services in ProfileTabScreen(services: services) }
}

#Preview("Oturum kapalı") {
    PreviewEnvironment(signedIn: false) { services in ProfileTabScreen(services: services) }
}
#endif
