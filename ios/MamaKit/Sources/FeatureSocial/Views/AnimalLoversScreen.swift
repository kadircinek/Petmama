#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Profil › "Hayvanseverler" (spec 5.2). Rota: `AppRoute.animalLovers`.
/// Varsayılan kapalı: önce sosyal onay, sonra "görünür ol". Kişiler haritada asla pin değildir; yalnızca mesafe aralığı.
public struct AnimalLoversScreen: View {
    @State private var model: AnimalLoversViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var showsProfileEdit = false
    @State private var requestTarget: AnimalLover?
    @State private var sendingId: UUID?
    @State private var respondingId: UUID?
    @State private var withdrawRequestId: UUID?
    @State private var showsWithdrawDialog = false
    private let services: AppServices

    public init(services: AppServices) {
        _model = State(initialValue: AnimalLoversViewModel(services: services))
        self.services = services
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(String(localized: "Hayvanseverler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.profile?.hasConsented == true {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: AppRoute.conversations) {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel(String(localized: "Sohbetler"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsProfileEdit = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .accessibilityLabel(String(localized: "Hayvansever profilim"))
                    }
                }
            }
            .task(id: session.userId) { await reload() }
            .onChange(of: router.sheet) { old, new in
                // Onay sheet'i kapanınca tazele.
                if old != nil, new == nil { Task { await reload() } }
            }
            .sheet(isPresented: $showsProfileEdit, onDismiss: { Task { await reload() } }) {
                SocialProfileEditScreen(services: services)
            }
            .confirmationDialog("İstek geri çekilsin mi?", isPresented: $showsWithdrawDialog, titleVisibility: .visible) {
                Button("İsteği geri çek", role: .destructive) { withdraw() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Karşı tarafa bildirim gitmez. İstersen daha sonra yeniden istek gönderebilirsin.")
            }
            .sheet(item: $requestTarget) { lover in
                ConnectionNoteSheet(lover: lover) { note in
                    send(to: lover, note: note)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if session.isRestoring, !session.isSignedIn {
            LoadingView()
        } else if !session.isSignedIn {
            SocialSignInGate(message: String(localized: "Çevrendeki besleyicilerle tanışmak için giriş yap.")) {
                router.present(.signIn, session: session)
            }
        } else if !model.hasLoaded {
            LoadingView()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let error = model.error {
                        BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                    }
                    if let message = model.message {
                        BannerView(message, style: .info)
                    }
                    if model.profile?.hasConsented != true {
                        SocialConsentPrompt(
                            title: String(localized: "Çevrendeki besleyicilerle tanış"),
                            message: String(localized: "Birlikte besleyebileceğin, kısırlaştırmada ya da veteriner taşımada el ele verebileceğin komşuları bul.")
                        ) {
                            router.present(.socialConsent, session: session)
                        }
                    } else {
                        requestsRow
                        if model.isVisible {
                            visibleList
                        } else {
                            becomeVisibleCard
                        }
                    }
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .refreshable { await reload() }
        }
    }

    @ViewBuilder
    private var requestsRow: some View {
        if !model.incoming.isEmpty {
            NavigationLink(value: AppRoute.connectionRequests) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MamaColor.tilePeach))
                        .accessibilityHidden(true)
                    let count = model.incoming.count
                    Text("\(count) tanışma isteği seni bekliyor")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(MamaColor.textSecondary)
                }
                .mamaCard(padding: 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var becomeVisibleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hayvanseverler'de görün")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Listeyi yalnızca kendini gösterenler görebilir. Görünür olunca adın, kısa tanıtımın ve ilgi alanların 10 km içindeki hayvanseverlere görünür.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
            Label {
                Text("Kesin konumun hiçbir zaman görünmez ve haritada gösterilmezsin; yalnızca \"1 km'den yakın\", \"1–3 km\" gibi bir aralık görünür.")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(MamaFont.footnote)
            .foregroundStyle(MamaColor.textSecondary)
            Button {
                showsProfileEdit = true
            } label: {
                Text("Profilimi hazırla")
            }
            .buttonStyle(.mamaPrimary(systemImage: "person.crop.circle.badge.checkmark"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    @ViewBuilder
    private var visibleList: some View {
        interestFilter
        if model.lovers.isEmpty {
            EmptyStateView(
                mascot: .duo,
                mood: .neutral,
                title: model.interestFilter == nil
                    ? String(localized: "Yakında görünür hayvansever yok")
                    : String(localized: "Bu ilgi alanında kimse yok"),
                message: String(localized: "Mahallendeki besleyicilere uygulamayı anlat; buluşmalara katılarak da tanışabilirsin.")
            )
        } else {
            ForEach(model.lovers) { lover in
                AnimalLoverCard(
                    lover: lover,
                    myInterests: Set(model.profile?.interests ?? []),
                    isSending: sendingId == lover.id,
                    isDisabled: sendingId != nil || respondingId != nil,
                    onRequest: { requestTarget = lover },
                    onWithdraw: { requestId in
                        withdrawRequestId = requestId
                        showsWithdrawDialog = true
                    },
                    onRespond: { requestId, accept in respond(requestId, accept: accept) },
                    onOpenChat: { router.push(.conversation($0)) }
                )
            }
        }
    }

    private var interestFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SelectableChip(String(localized: "Tümü"), isSelected: model.interestFilter == nil) {
                    Task { await model.setInterestFilter(nil) }
                }
                ForEach(SocialInterest.allCases, id: \.self) { interest in
                    SelectableChip(interest.label, systemImage: interest.systemImage, isSelected: model.interestFilter == interest) {
                        Task { await model.setInterestFilter(model.interestFilter == interest ? nil : interest) }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Eylemler

    private func reload() async {
        guard session.isSignedIn else { return }
        await model.load(at: location.coordinate)
    }

    /// Demo'da senaryolu kabul ~3 sn sürer; bu sürede buton ilerleme gösterir ve kilitlidir.
    private func send(to lover: AnimalLover, note: String?) {
        guard sendingId == nil else { return }
        sendingId = lover.id
        Task {
            let outcome = await model.sendRequest(to: lover.id, note: note)
            sendingId = nil
            if case .consentRequired = outcome { router.present(.socialConsent, session: session) }
        }
    }

    private func withdraw() {
        guard let requestId = withdrawRequestId else { return }
        withdrawRequestId = nil
        Task {
            if await model.withdraw(requestId: requestId) {
                router.showToast(String(localized: "İsteğin geri çekildi."), style: .info)
            }
        }
    }

    private func respond(_ requestId: UUID, accept: Bool) {
        guard respondingId == nil, let request = model.incoming.first(where: { $0.id == requestId }) else { return }
        respondingId = requestId
        Task {
            let conversationId = await model.respond(request, accept: accept)
            respondingId = nil
            if let conversationId { router.push(.conversation(conversationId)) }
        }
    }
}

/// İstekle birlikte isteğe bağlı kısa not (0–200).
struct ConnectionNoteSheet: View {
    let lover: AnimalLover
    let onSend: (String?) -> Void
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(lover.displayName) ile tanış")
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
                Text("İstersen kısa bir not ekle: hangi noktada besliyorsun, nasıl yardımlaşabilirsiniz?")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                TextField(String(localized: "Ör. Moda Parkı'ndaki kedilerin su kaplarını birlikte takip edelim mi?"), text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .font(MamaFont.body)
                    .socialFieldBackground()
                CharacterCounter(count: SocialPolicy.length(trimmed), limit: SocialPolicy.maxNote)
                Button {
                    onSend(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                } label: {
                    Text("İstek gönder")
                }
                .buttonStyle(.mamaPrimary(systemImage: "hand.wave.fill"))
                .disabled(SocialPolicy.length(trimmed) > SocialPolicy.maxNote)
                Spacer(minLength: 0)
            }
            .padding(MamaMetrics.screenPadding)
            .mamaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PreviewEnvironment { services in
        AnimalLoversScreen(services: services)
    }
}
#endif
