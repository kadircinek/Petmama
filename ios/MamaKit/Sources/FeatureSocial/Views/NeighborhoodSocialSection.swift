#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Mahalle › Akış'ın en üstü (spec 2026-11-16): "Şu an turda" kartları ve "Mahalledeki hayvanseverler" şeridi.
/// AppFeature, `CommunityTabScreen`'e enjekte eder (feature modülleri birbirini import etmez). Giriş yoksa hiçbir şey
/// göstermez (Akış zaten giriş ister).
public struct NeighborhoodSocialSection: View {
    @State private var model: NeighborhoodSocialViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var selectedLoverId: UUID?
    @State private var tourPendingEnd: Meetup?
    @State private var showsEndDialog = false
    @State private var showsProfileEdit = false
    private let services: AppServices
    /// Akış aşağı çekilince artar: başlık da yeniden yüklenir.
    private let refreshToken: Int

    public init(services: AppServices, refreshToken: Int = 0) {
        _model = State(initialValue: NeighborhoodSocialViewModel(services: services))
        self.services = services
        self.refreshToken = refreshToken
    }

    public var body: some View {
        Group {
            if session.isSignedIn {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    if let message = model.message {
                        BannerView(message, style: .info)
                    }
                    // Kalan süre dakikada bir yenilenir; biten tur yeniden yükleme beklemeden düşer.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        tours(at: context.date)
                    }
                    strip
                }
            }
        }
        .task(id: session.userId) { await reload() }
        .onChange(of: refreshToken) { _, _ in Task { await reload() } }
        .onChange(of: router.sheet) { old, new in
            // Onay / tur başlatma / giriş sheet'i kapanınca tazele.
            if old != nil, new == nil { Task { await reload() } }
        }
        .onChange(of: location.coordinate == nil) { _, isNil in
            if !isNil { Task { await reload() } }
        }
        .sheet(isPresented: $showsProfileEdit, onDismiss: { Task { await reload() } }) {
            SocialProfileEditScreen(services: services)
        }
        .sheet(item: loverBinding) { lover in
            NeighborhoodLoverSheet(model: model, loverId: lover.id) { conversationId in
                selectedLoverId = nil
                router.push(.conversation(conversationId))
            } onConsentRequired: {
                selectedLoverId = nil
                router.present(.socialConsent, session: session)
            }
        }
        .confirmationDialog("Tur bitirilsin mi?", isPresented: $showsEndDialog, titleVisibility: .visible, presenting: tourPendingEnd) { tour in
            Button("Turu bitir", role: .destructive) { end(tour) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Katılanlara haber veririz; sohbet yalnızca okunur hale gelir.")
        }
    }

    // MARK: - Şu an turda

    @ViewBuilder
    private func tours(at date: Date) -> some View {
        let visible = model.visibleTours(at: date)
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if model.hasMoreTours(at: date) {
                    SectionHeader(String(localized: "Şu an turda"), actionTitle: String(localized: "Tümünü gör")) {
                        router.communitySection = .meetups
                    }
                } else {
                    SectionHeader(String(localized: "Şu an turda"))
                }
                tourCards(visible, at: date)
            }
        }
    }

    private func tourCards(_ visible: [Meetup], at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visible) { tour in
                TourNowCard(
                    tour: tour,
                    remainingMinutes: model.remainingMinutes(tour, at: date),
                    isMember: model.isMember(tour),
                    busyAction: model.busyMeetupId == tour.id ? model.busyAction : nil,
                    isDisabled: model.busyMeetupId != nil,
                    onOpen: { router.push(.meetup(tour.id)) },
                    onJoin: { join(tour) },
                    onMessage: { message(tour) },
                    onEnd: {
                        tourPendingEnd = tour
                        showsEndDialog = true
                    }
                )
            }
        }
    }

    // MARK: - Hayvanseverler şeridi

    @ViewBuilder
    private var strip: some View {
        switch model.stripState {
        case .loading, .unavailable:
            EmptyView()
        case .needsConsent:
            NeighborhoodLoversInvite(
                message: String(localized: "Bugün kim besledi, kim şu an turda gör; komşu besleyicilerle tanış. Önce kısa bir onay gerekiyor."),
                buttonTitle: String(localized: "Tanışmaya başla")
            ) {
                router.present(.socialConsent, session: session)
            }
        case .needsVisibility:
            NeighborhoodLoversInvite(
                message: String(localized: "Listeyi yalnızca kendini gösterenler görebilir. Görünür olunca sen de mahallendeki hayvanseverler arasında yer alırsın; kesin konumun asla görünmez."),
                buttonTitle: String(localized: "Görünür ol")
            ) {
                showsProfileEdit = true
            }
        case .lovers:
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(String(localized: "Mahalledeki hayvanseverler"), actionTitle: String(localized: "Tümünü gör")) {
                    router.push(.animalLovers)
                }
                if model.lovers.isEmpty {
                    Text("Yakında görünür hayvansever yok. Buluşmalara katılarak da tanışabilirsin.")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.lovers) { lover in
                                LoverChip(lover: lover) { selectedLoverId = lover.id }
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    private var loverBinding: Binding<AnimalLover?> {
        Binding(
            get: { selectedLoverId.flatMap { model.lover(id: $0) } },
            set: { selectedLoverId = $0?.id }
        )
    }

    // MARK: - Eylemler

    private func reload() async {
        guard session.isSignedIn else { return }
        await model.load(at: location.coordinate)
    }

    private func join(_ tour: Meetup) {
        Task {
            let outcome = await model.join(tour)
            if model.lastActionNeedsConsent {
                router.present(.socialConsent, session: session)
            } else if case .joined = outcome {
                router.showToast(String(localized: "Tura katıldın. Sohbetten haberleşebilirsiniz."))
            }
        }
    }

    private func message(_ tour: Meetup) {
        Task {
            if let conversationId = await model.messageTour(tour) {
                router.push(.conversation(conversationId))
            } else if model.lastActionNeedsConsent {
                router.present(.socialConsent, session: session)
            }
        }
    }

    private func end(_ tour: Meetup) {
        tourPendingEnd = nil
        Task {
            if await model.endTour(tour) {
                router.showToast(String(localized: "Turun bitti. Teşekkürler!"), style: .info)
            }
        }
    }
}

/// "Şu an turda" kartı: düzenleyen, nokta, kalan süre, katılımcı sayısı ve eylemler.
struct TourNowCard: View {
    let tour: Meetup
    let remainingMinutes: Int
    let isMember: Bool
    let busyAction: NeighborhoodSocialViewModel.TourAction?
    let isDisabled: Bool
    let onOpen: () -> Void
    let onJoin: () -> Void
    let onMessage: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    AvatarView(name: tour.organizerName, url: tour.organizerAvatarURL, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(organizerLine)
                            .font(MamaFont.headline)
                            .foregroundStyle(MamaColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        Label {
                            Text(verbatim: tour.placeName)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                        .lineLimit(1)
                        FlowLayout(spacing: 6) {
                            TourBadge()
                            TagChip(remainingText, systemImage: "clock.fill", style: .info)
                            TagChip(participantsText, systemImage: "person.2.fill")
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(MamaColor.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    @ViewBuilder
    private var actions: some View {
        if isMember {
            HStack(spacing: 10) {
                Button(action: onMessage) { Text("Sohbete git") }
                    .buttonStyle(.mamaPrimary(systemImage: "bubble.left.and.bubble.right.fill"))
                if tour.viewerRole == .organizer {
                    Button(action: onEnd) { Text("Turu bitir") }
                        .buttonStyle(.mamaSecondary(tint: MamaColor.statusUrgent, systemImage: "flag.checkered", fullWidth: false))
                }
            }
            .disabled(isDisabled)
        } else {
            HStack(spacing: 10) {
                Button(action: onJoin) {
                    if busyAction == .join {
                        ProgressView().tint(MamaColor.onInk)
                    } else {
                        Text("Katıl")
                    }
                }
                .buttonStyle(.mamaPrimary(systemImage: "figure.walk"))
                Button(action: onMessage) {
                    if busyAction == .message {
                        ProgressView()
                    } else {
                        Text("Mesaj at")
                    }
                }
                .buttonStyle(.mamaSecondary(systemImage: "bubble.left.fill"))
            }
            .disabled(isDisabled)
        }
    }

    private var organizerLine: String {
        if tour.viewerRole == .organizer { return String(localized: "Sen şu an turdasın") }
        return String(localized: "\(tour.organizerName) şu an turda")
    }

    private var remainingText: String {
        let minutes = remainingMinutes
        return String(localized: "\(minutes) dk kaldı")
    }

    private var participantsText: String {
        String(localized: "\(tour.participantCount) kişi")
    }
}

/// Şeritteki kişi: fotoğraf/baş harf, ad, mesafe bandı ve "Turda" / "Bugün besledi" rozeti.
struct LoverChip: View {
    let lover: AnimalLover
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                AvatarView(name: lover.displayName, url: lover.avatarURL, size: 56)
                    .overlay(alignment: .bottomTrailing) {
                        if lover.isOnTour || lover.fedToday {
                            Image(systemName: lover.isOnTour ? "figure.walk.circle.fill" : "pawprint.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(MamaColor.statusFed)
                                .background(Circle().fill(MamaColor.card))
                                .accessibilityHidden(true)
                        }
                    }
                Text(verbatim: lover.displayName)
                    .font(MamaFont.subheadline.weight(.semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(1)
                Text(verbatim: lover.distanceBand.label)
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(1)
                if lover.isOnTour {
                    TagChip(String(localized: "Turda"), style: .positive)
                } else if lover.fedToday {
                    TagChip(String(localized: "Bugün besledi"), style: .info)
                }
            }
            .frame(width: 116)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous).fill(MamaColor.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Onay yok ya da görünür değil: şerit yerine davet kartı.
struct NeighborhoodLoversInvite: View {
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MamaColor.tileMint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mahallendeki hayvanseverleri gör")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text(verbatim: message)
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: action) { Text(verbatim: buttonTitle) }
                .buttonStyle(.mamaPrimary(systemImage: "person.crop.circle.badge.checkmark"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }
}

/// Şeritte dokunulan kişinin kartı (Hayvanseverler'deki `AnimalLoverCard` ile aynı eylemler).
struct NeighborhoodLoverSheet: View {
    let model: NeighborhoodSocialViewModel
    let loverId: UUID
    let onOpenChat: (UUID) -> Void
    let onConsentRequired: () -> Void
    @State private var showsNote = false
    @State private var isSending = false
    @State private var isResponding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let message = model.personMessage {
                        BannerView(message, style: .info)
                    }
                    if let lover = model.lover(id: loverId) {
                        if lover.isOnTour || lover.fedToday {
                            FlowLayout(spacing: 6) {
                                if lover.isOnTour { TagChip(String(localized: "Şu an turda"), systemImage: "figure.walk", style: .positive) }
                                if lover.fedToday { TagChip(String(localized: "Bugün besledi"), systemImage: "pawprint.fill", style: .info) }
                            }
                        }
                        AnimalLoverCard(
                            lover: lover,
                            myInterests: Set(model.profile?.interests ?? []),
                            isSending: isSending,
                            isDisabled: isSending || isResponding,
                            onRequest: { showsNote = true },
                            onWithdraw: { requestId in
                                Task { await model.withdraw(requestId: requestId) }
                            },
                            onRespond: { requestId, accept in respond(requestId, accept: accept) },
                            onOpenChat: onOpenChat
                        )
                        .sheet(isPresented: $showsNote) {
                            ConnectionNoteSheet(lover: lover) { note in send(to: lover, note: note) }
                        }
                    }
                }
                .padding(MamaMetrics.screenPadding)
            }
            .mamaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send(to lover: AnimalLover, note: String?) {
        guard !isSending else { return }
        isSending = true
        Task {
            let outcome = await model.sendRequest(to: lover.id, note: note)
            isSending = false
            if case .consentRequired = outcome { onConsentRequired() }
        }
    }

    private func respond(_ requestId: UUID, accept: Bool) {
        guard !isResponding else { return }
        isResponding = true
        Task {
            let conversationId = await model.respond(requestId: requestId, accept: accept)
            isResponding = false
            if let conversationId { onOpenChat(conversationId) }
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        ScrollView {
            NeighborhoodSocialSection(services: services)
                .padding()
        }
    }
}
#endif
