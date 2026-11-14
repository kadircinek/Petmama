#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// Buluşma detayı. Rota: `AppRoute.meetup(id)`. Buluşma noktası herkese açıktır (kişisel konum değil), haritada tek pin.
public struct MeetupDetailScreen: View {
    @State private var model: MeetupDetailViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var showsCancelDialog = false
    @State private var showsLeaveDialog = false
    @State private var participantPendingRemoval: MeetupParticipant?
    @State private var showsRemoveDialog = false
    /// Onay sheet'i katılım için açıldıysa: kapanınca onay verilmişse katılım tamamlanır.
    @State private var joinAfterConsent = false
    @State private var successFeedback = 0
    private let services: AppServices

    public init(meetupId: UUID, services: AppServices) {
        _model = State(initialValue: MeetupDetailViewModel(services: services, meetupId: meetupId))
        self.services = services
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(String(localized: "Buluşma"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session.userId) { await reload() }
            .onChange(of: router.sheet) { old, new in
                guard old != nil, new == nil else { return }
                Task { await sheetClosed() }
            }
            .confirmationDialog("Buluşma iptal edilsin mi?", isPresented: $showsCancelDialog, titleVisibility: .visible) {
                Button("Buluşmayı iptal et", role: .destructive) { cancel() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Katılanlara haber veririz; sohbet yalnızca okunur hale gelir.")
            }
            .confirmationDialog("Buluşmadan ayrılmak istiyor musun?", isPresented: $showsLeaveDialog, titleVisibility: .visible) {
                Button("Ayrıl", role: .destructive) { leave() }
                Button("Vazgeç", role: .cancel) {}
            }
            .confirmationDialog(
                "Bu kişi buluşmadan çıkarılsın mı?",
                isPresented: $showsRemoveDialog,
                titleVisibility: .visible,
                presenting: participantPendingRemoval
            ) { participant in
                Button("Çıkar", role: .destructive) { remove(participant) }
                Button("Vazgeç", role: .cancel) {}
            } message: { _ in
                Text("Çıkarılan kişi bu buluşmaya tekrar katılamaz.")
            }
            .sensoryFeedback(.success, trigger: successFeedback)
    }

    @ViewBuilder
    private var content: some View {
        if session.isRestoring, !session.isSignedIn {
            LoadingView()
        } else if !session.isSignedIn {
            SocialSignInGate(message: String(localized: "Buluşmaları görmek için giriş yap.")) {
                router.present(.signIn, session: session)
            }
        } else if let meetup = model.meetup {
            detail(meetup)
        } else if model.hasLoaded, model.error == nil {
            EmptyStateView(
                systemImage: "person.3",
                title: String(localized: "Bu buluşma artık görünmüyor"),
                message: String(localized: "Silinmiş ya da sana kapalı olabilir.")
            )
        } else if model.hasLoaded {
            EmptyStateView(
                systemImage: "arrow.clockwise",
                title: String(localized: "Buluşmayı açamadık"),
                message: model.error?.userMessage,
                actionTitle: String(localized: "Tekrar dene"),
                action: { Task { await reload() } }
            )
        } else {
            LoadingView()
        }
    }

    private func detail(_ meetup: Meetup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(meetup)
                place(meetup)
                if !meetup.description.isEmpty {
                    SocialFormCard(String(localized: "Ne yapacağız?")) {
                        Text(verbatim: meetup.description)
                            .font(MamaFont.body)
                            .foregroundStyle(MamaColor.textPrimary)
                    }
                }
                if model.isParticipant, !model.participants.isEmpty {
                    participants(meetup)
                }
                if let message = model.message {
                    BannerView(message, style: .warning)
                }
                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                }
                actions(meetup)
                Label {
                    Text("Buluşmalar herkese açık yerlerde yapılır. Ev adresini paylaşma; rahatsız edici bir durumu raporla.")
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .font(MamaFont.footnote)
                .foregroundStyle(MamaColor.textSecondary)
            }
            .padding(MamaMetrics.screenPadding)
        }
        .refreshable { await reload() }
        .toolbar {
            if !model.isOrganizer {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            router.present(.report(.meetup, meetup.id), session: session)
                        } label: {
                            Label("Buluşmayı raporla", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(String(localized: "Diğer seçenekler"))
                }
            }
        }
    }

    // MARK: - Bölümler

    private func header(_ meetup: Meetup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: meetup.title)
                .font(MamaFont.title2)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                MeetupStatusChips(meetup: meetup, now: services.now())
                TagChip(participantsText(meetup), systemImage: "person.2.fill")
            }
            InfoRow(systemImage: "calendar", title: String(localized: "Ne zaman"), value: MeetupFormat.when(meetup, now: services.now()))
            InfoRow(systemImage: "clock", title: String(localized: "Süre"), value: durationText(meetup))
            HStack(spacing: 10) {
                AvatarView(name: meetup.organizerName, url: meetup.organizerAvatarURL, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: meetup.organizerName)
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                    Text("Düzenleyen")
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                if meetup.organizerIsVerified {
                    TagChip(String(localized: "Doğrulanmış besleyici"), systemImage: "checkmark.seal.fill", style: .positive)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    private func place(_ meetup: Meetup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: meetup.coordinate.clCoordinate,
                latitudinalMeters: 600,
                longitudinalMeters: 600
            ))) {
                Marker(meetup.placeName, systemImage: "person.3.fill", coordinate: meetup.coordinate.clCoordinate)
                    .tint(MamaColor.ink)
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
            .accessibilityLabel(String(localized: "Buluşma noktası haritası"))
            Label {
                Text(verbatim: meetup.placeName)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(MamaFont.headline)
            .foregroundStyle(MamaColor.textPrimary)
            if let distance = meetup.distanceMeters {
                Text("Sana \(MamaFormat.distance(distance)) uzaklıkta")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            if let spotId = meetup.spotId {
                NavigationLink(value: AppRoute.spot(spotId)) {
                    HStack {
                        Label {
                            Text(verbatim: meetup.spotTitle ?? String(localized: "Bağlı mama noktası"))
                        } icon: {
                            Image(systemName: "pawprint.fill")
                        }
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                    .frame(minHeight: MamaMetrics.minTapSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    private func participants(_ meetup: Meetup) -> some View {
        SocialFormCard(String(localized: "Katılanlar")) {
            ForEach(model.participants) { participant in
                HStack(spacing: 10) {
                    AvatarView(name: participant.displayName, url: participant.avatarURL, size: 36)
                    Text(verbatim: participant.displayName)
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                    if participant.isVerifiedFeeder {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(MamaColor.statusFed)
                            .accessibilityLabel(String(localized: "Doğrulanmış besleyici"))
                    }
                    Spacer(minLength: 0)
                    if participant.isOrganizer {
                        TagChip(String(localized: "Düzenleyen"), style: .info)
                    } else if model.isOrganizer, meetup.status == .active, !isEnded(meetup) {
                        Button {
                            participantPendingRemoval = participant
                            showsRemoveDialog = true
                        } label: {
                            Text("Çıkar")
                                .font(MamaFont.subheadline.weight(.semibold))
                                .foregroundStyle(MamaColor.statusUrgent)
                                .frame(minHeight: MamaMetrics.minTapSize)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        .accessibilityLabel(String(localized: "\(participant.displayName) kişisini çıkar"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ meetup: Meetup) -> some View {
        VStack(spacing: 10) {
            if meetup.status == .cancelled {
                BannerView(String(localized: "Bu buluşma iptal edildi."), style: .warning, systemImage: "xmark.circle.fill")
            } else if isEnded(meetup) {
                BannerView(String(localized: "Bu buluşma sona erdi. Emeğine sağlık!"), style: .info, systemImage: "clock.badge.checkmark")
            } else if meetup.viewerRole == .removed {
                BannerView(String(localized: "Düzenleyen seni bu buluşmadan çıkardı, tekrar katılamazsın."), style: .warning)
            }
            if model.canChat, let conversationId = meetup.conversationId {
                Button {
                    router.push(.conversation(conversationId))
                } label: {
                    Text("Sohbete git")
                }
                .buttonStyle(.mamaPrimary(systemImage: "bubble.left.and.bubble.right.fill"))
            }
            if model.canJoin {
                Button(action: join) {
                    if model.isBusy {
                        Text("Katılım kaydediliyor…")
                    } else {
                        Text("Katıl")
                    }
                }
                .buttonStyle(.mamaPrimary(systemImage: "person.badge.plus"))
                .disabled(model.isBusy)
            } else if meetup.viewerRole == .none, meetup.status == .active, !isEnded(meetup), model.isFull {
                Button {} label: { Text("Buluşma doldu") }
                    .buttonStyle(.mamaSecondary(systemImage: "person.fill.xmark"))
                    .disabled(true)
            }
            if meetup.viewerRole == .participant, meetup.status == .active, !isEnded(meetup) {
                Button {
                    showsLeaveDialog = true
                } label: {
                    Text("Buluşmadan ayrıl")
                }
                .buttonStyle(.mamaSecondary(systemImage: "rectangle.portrait.and.arrow.right"))
                .disabled(model.isBusy)
            }
            if model.isOrganizer, meetup.status == .active, !isEnded(meetup) {
                Button {
                    showsCancelDialog = true
                } label: {
                    Text("Buluşmayı iptal et")
                }
                .buttonStyle(.mamaSecondary(tint: MamaColor.statusUrgent, systemImage: "xmark.circle"))
                .disabled(model.isBusy)
            }
        }
    }

    // MARK: - Yardımcılar

    private func isEnded(_ meetup: Meetup) -> Bool { meetup.endsAt <= services.now() }

    private func participantsText(_ meetup: Meetup) -> String {
        if let limit = meetup.capacity {
            return String(localized: "\(meetup.participantCount)/\(limit) kişi")
        }
        return String(localized: "\(meetup.participantCount) kişi")
    }

    private func durationText(_ meetup: Meetup) -> String {
        let minutes = Int(meetup.endsAt.timeIntervalSince(meetup.startsAt) / 60)
        return CreateMeetupSheet.durationLabel(minutes)
    }

    // MARK: - Eylemler

    private func reload() async {
        guard session.isSignedIn else { return }
        await model.load(near: location.coordinate)
    }

    private func sheetClosed() async {
        if joinAfterConsent {
            joinAfterConsent = false
            if await !SocialGate.needsConsent(services) {
                await performJoin()
                return
            }
        }
        await reload()
    }

    /// Onay yoksa önce onay ekranı; onay verilince katılım kendiliğinden tamamlanır.
    private func join() {
        Task {
            if await SocialGate.needsConsent(services) {
                joinAfterConsent = true
                router.present(.socialConsent, session: session)
            } else {
                await performJoin()
            }
        }
    }

    private func performJoin() async {
        guard let outcome = await model.join() else { return }
        switch outcome {
        case .joined:
            successFeedback += 1
            router.showToast("Buluşmaya katıldın! Sohbette diğer besleyicilerle konuşabilirsin.")
        case .consentRequired:
            joinAfterConsent = true
            router.present(.socialConsent, session: session)
        default:
            break  // Mesaj ekranda gösterilir.
        }
    }

    private func leave() {
        Task {
            if await model.leave() {
                router.showToast("Buluşmadan ayrıldın.", style: .info)
            }
        }
    }

    private func remove(_ participant: MeetupParticipant) {
        Task {
            if await model.remove(participant.id) {
                router.showToast("Kişi buluşmadan çıkarıldı.", style: .info)
            }
        }
    }

    private func cancel() {
        Task {
            if await model.cancel() {
                router.showToast("Buluşma iptal edildi. Katılanlara haber verdik.", style: .info)
            }
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        MeetupDetailScreen(meetupId: DemoData.id(8, 1), services: services)
    }
}
#endif
