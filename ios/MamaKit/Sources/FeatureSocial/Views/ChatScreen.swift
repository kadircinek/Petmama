#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Sohbet (buluşma grubu ya da bire bir). Rota: `AppRoute.conversation(id)`.
/// Açıkken canlı güncellenir (Realtime, yoksa 5 sn'de bir). Her mesaj uzun basınca raporlanabilir.
public struct ChatScreen: View {
    @State private var model: ChatViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool
    @State private var showsBlockDialog = false
    @State private var showsRemoveDialog = false
    @State private var isActing = false
    /// Mesajın menüsünden engellenecek kişi.
    @State private var authorPendingBlock: ChatMessage?
    @State private var showsAuthorBlockDialog = false
    private let services: AppServices

    public init(conversationId: UUID, services: AppServices) {
        _model = State(initialValue: ChatViewModel(services: services, conversationId: conversationId))
        self.services = services
    }

    public var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .mamaBackground()
            .navigationTitle(model.title.isEmpty ? String(localized: "Sohbet") : model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarMenu }
            .task { await model.start() }
            .onDisappear { model.stop() }
            .confirmationDialog("Bu kişi engellensin mi?", isPresented: $showsBlockDialog, titleVisibility: .visible) {
                Button("Engelle", role: .destructive) { block() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Sohbetiniz kapanır ve birbirinizi listelerde görmezsiniz. Engeli Ayarlar'dan kaldırabilirsin.")
            }
            .confirmationDialog(
                "Bu kişi engellensin mi?",
                isPresented: $showsAuthorBlockDialog,
                titleVisibility: .visible,
                presenting: authorPendingBlock
            ) { message in
                Button("Engelle", role: .destructive) { blockAuthor(of: message) }
                Button("Vazgeç", role: .cancel) {}
            } message: { _ in
                Text("Birbirinizin mesajlarını görmezsiniz ve listelerde karşılaşmazsınız. Engeli Ayarlar'dan kaldırabilirsin.")
            }
            .confirmationDialog("Bağlantı kaldırılsın mı?", isPresented: $showsRemoveDialog, titleVisibility: .visible) {
                Button("Bağlantıyı kaldır", role: .destructive) { removeConnection() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Bu sohbet kapanır. İstersen daha sonra yeniden tanışma isteği gönderebilirsin.")
            }
    }

    // MARK: - Mesajlar

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if model.canLoadOlder {
                        MamaTextButton(String(localized: "Daha eski mesajlar")) {
                            Task { await model.loadOlder() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if model.messages.isEmpty {
                        Text("Henüz mesaj yok. Hangi noktada besliyorsunuz, nasıl yardımlaşabilirsiniz? İlk merhabayı sen yaz!")
                            .font(MamaFont.subheadline)
                            .foregroundStyle(MamaColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    ForEach(model.messages) { message in
                        ChatBubble(
                            message: message,
                            isMine: message.authorId == session.userId,
                            showsAuthor: model.summary?.kind != .direct,
                            now: services.now()
                        )
                        .id(message.id)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.body
                            } label: {
                                Label("Kopyala", systemImage: "doc.on.doc")
                            }
                            if message.authorId != session.userId {
                                Button(role: .destructive) {
                                    router.present(.report(.chatMessage, message.id), session: session)
                                } label: {
                                    Label("Raporla", systemImage: "flag")
                                }
                                Button(role: .destructive) {
                                    authorPendingBlock = message
                                    showsAuthorBlockDialog = true
                                } label: {
                                    Label("Engelle", systemImage: "hand.raised.fill")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    // MARK: - Alt çubuk

    @ViewBuilder
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.message {
                BannerView(message, style: .warning)
            }
            if let error = model.error {
                BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
            }
            if model.isReadOnly {
                BannerView(
                    String(localized: "Bu sohbet artık yalnızca okunabiliyor. Mesajlar 30 gün sonra silinir."),
                    style: .info,
                    systemImage: "lock.fill"
                )
            } else {
                composer
            }
        }
        .padding(.horizontal, MamaMetrics.screenPadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var composer: some View {
        @Bindable var model = model
        HStack(alignment: .bottom, spacing: 10) {
            TextField(String(localized: "Mesaj yaz…"), text: $model.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($composerFocused)
                .font(MamaFont.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: MamaMetrics.minTapSize)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MamaColor.card))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MamaColor.stroke, lineWidth: 1))
            Button {
                Task { await model.send() }
            } label: {
                Group {
                    if model.isSending {
                        ProgressView().tint(MamaColor.onInk)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }
                }
                .foregroundStyle(MamaColor.onInk)
                .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
                .background(Circle().fill(MamaColor.ink))
                .opacity(model.canSend || model.isSending ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
            .accessibilityLabel(String(localized: "Gönder"))
        }
        if model.draft.count > SocialPolicy.maxMessage - 100 {
            CharacterCounter(count: model.draft.count, limit: SocialPolicy.maxMessage)
        }
    }

    // MARK: - Başlık menüsü

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        if let summary = model.summary {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    switch summary.kind {
                    case .meetup:
                        if let meetupId = summary.meetupId {
                            Button {
                                router.push(.meetup(meetupId))
                            } label: {
                                Label("Buluşmayı göster", systemImage: "person.3")
                            }
                        }
                    case .direct:
                        if summary.otherUserId != nil {
                            Button(role: .destructive) {
                                showsRemoveDialog = true
                            } label: {
                                Label("Bağlantıyı kaldır", systemImage: "person.crop.circle.badge.minus")
                            }
                            Button(role: .destructive) {
                                showsBlockDialog = true
                            } label: {
                                Label("Engelle", systemImage: "hand.raised.fill")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isActing)
                .accessibilityLabel(String(localized: "Diğer seçenekler"))
            }
        }
    }

    // MARK: - Eylemler

    private func block() {
        guard let userId = model.summary?.otherUserId else { return }
        act {
            try await services.moderation.block(userId: userId)
            router.showToast(String(localized: "Kişi engellendi."), style: .info)
        }
    }

    /// Grup sohbetinde engellenenin mesajları gizlenir, sohbette kalınır; bire bir sohbet kapanır.
    private func blockAuthor(of message: ChatMessage) {
        guard !isActing else { return }
        if model.summary?.kind == .direct {
            act {
                try await services.moderation.block(userId: message.authorId)
                router.showToast(String(localized: "Kişi engellendi."), style: .info)
            }
            return
        }
        isActing = true
        Task {
            defer { isActing = false }
            do {
                try await services.moderation.block(userId: message.authorId)
                router.showToast(String(localized: "Kişi engellendi; mesajlarını artık görmeyeceksin."), style: .info)
                await model.restart()
            } catch {
                router.showToast(MamaError.classify(error).userMessage, style: .warning)
            }
        }
    }

    private func removeConnection() {
        guard let userId = model.summary?.otherUserId else { return }
        act {
            try await services.social.removeConnection(userId: userId)
            router.showToast(String(localized: "Bağlantı kaldırıldı."), style: .info)
        }
    }

    /// Başarılıysa sohbetten çıkılır; hata olursa ekranda kalınır.
    private func act(_ work: @escaping @MainActor () async throws -> Void) {
        guard !isActing else { return }
        isActing = true
        Task {
            defer { isActing = false }
            do {
                try await work()
                model.stop()
                dismiss()
            } catch {
                router.showToast(MamaError.classify(error).userMessage, style: .warning)
            }
        }
    }
}

/// Mesaj balonu. Kendi mesajların sağda koyu; incelemedeki mesaj yalnızca yazarına görünür.
private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let showsAuthor: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 48) }
            if !isMine, showsAuthor {
                AvatarView(name: message.authorName, url: message.authorAvatarURL, size: 28)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if !isMine, showsAuthor {
                    Text(verbatim: message.authorName)
                        .font(MamaFont.caption.weight(.semibold))
                        .foregroundStyle(MamaColor.textSecondary)
                }
                Text(verbatim: message.body)
                    .font(MamaFont.body)
                    .foregroundStyle(isMine ? MamaColor.onInk : MamaColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isMine ? MamaColor.ink : MamaColor.card)
                    )
                    .opacity(message.isPendingModeration ? 0.6 : 1)
                HStack(spacing: 4) {
                    if message.isPendingModeration {
                        Image(systemName: "eye.slash")
                        Text("İncelemede; yalnızca sen görüyorsun")
                    }
                    Text(verbatim: MamaFormat.relative(message.createdAt, now: now))
                }
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PreviewEnvironment { services in
        ChatScreen(conversationId: DemoData.id(9, 1), services: services)
    }
}
#endif
