#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Paylaşım detayı: tam kart, "Bakacaklar", yorumlar ve altta yorum kutusu. Rota: `AppRoute.post(id)`.
public struct PostDetailScreen: View {
    @State private var model: PostDetailViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool
    @State private var showsDeletePostDialog = false
    @State private var commentPendingDelete: CommunityComment?
    @State private var showsDeleteCommentDialog = false
    @State private var successFeedback = 0
    /// Yeni gönderilen yorum: liste ona kaydırılır.
    @State private var scrollTarget: UUID?

    public init(postId: UUID, services: AppServices) {
        _model = State(initialValue: PostDetailViewModel(postId: postId, services: services))
    }

    public var body: some View {
        content
            .mamaBackground()
            .navigationTitle(model.post?.kind.label ?? String(localized: "Paylaşım"))
            .navigationBarTitleDisplayMode(.inline)
            // İlk açılış ve giriş/çıkış.
            .task(id: session.userId) { await reload() }
            .onChange(of: router.sheet) { old, new in
                // Rapor/engelleme veya giriş sheet'i kapanınca tazele (engellenen kişinin yorumları gizlenir).
                if old != nil, new == nil { Task { await reload() } }
            }
            .confirmationDialog("Paylaşımın silinsin mi?", isPresented: $showsDeletePostDialog, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { deletePost() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Yorumlar ve patiler de silinir. Bu işlem geri alınamaz.")
            }
            .sensoryFeedback(.success, trigger: successFeedback)
    }

    @ViewBuilder
    private var content: some View {
        if session.isRestoring, !session.isSignedIn {
            // Bildirimden açılışta oturum geri yüklenirken giriş daveti bir an görünüp kaybolmasın.
            LoadingView()
        } else if !session.isSignedIn || model.requiresSignIn {
            CommunitySignInGate { router.present(.signIn, session: session) }
        } else if let post = model.post {
            thread(post)
        } else if model.isNotFound {
            EmptyStateView(
                systemImage: "text.bubble",
                title: String(localized: "Bu paylaşım artık yok"),
                message: String(localized: "Silinmiş ya da incelemeye alınmış olabilir.")
            )
        } else if model.hasLoaded {
            EmptyStateView(
                systemImage: "arrow.clockwise",
                title: String(localized: "Paylaşımı açamadık"),
                message: model.error?.userMessage,
                actionTitle: String(localized: "Tekrar dene"),
                action: { Task { await reload() } }
            )
        } else {
            LoadingView()
        }
    }

    private func thread(_ post: CommunityPost) -> some View {
        ScrollViewReader { proxy in
            threadContent(post)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .bottom) }
                    scrollTarget = nil
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PostCommentComposer(model: model, isFocused: $composerFocused, onSend: send)
        }
        .confirmationDialog(
            "Yorum silinsin mi?",
            isPresented: $showsDeleteCommentDialog,
            titleVisibility: .visible,
            presenting: commentPendingDelete
        ) { comment in
            Button("Sil", role: .destructive) { delete(comment) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Bu işlem geri alınamaz.")
        }
    }

    private func threadContent(_ post: CommunityPost) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                }
                CommunityPostCard(
                    post: post,
                    now: model.now,
                    viewerId: session.userId,
                    layout: .detail,
                    isCoverOpen: model.isCoverOpen,
                    isBusy: model.isWorking,
                    onPaw: paw,
                    onVolunteer: volunteer,
                    onComment: { composerFocused = true },
                    onDelete: { showsDeletePostDialog = true }
                )
                if post.kind == .coverRequest {
                    PostVolunteersSection(volunteers: model.volunteers)
                }
                PostCommentsSection(
                    comments: model.comments,
                    now: model.now,
                    viewerId: session.userId,
                    canDelete: { model.canDeleteComment($0, userId: session.userId) },
                    onDelete: askToDelete
                )
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await reload() }
    }

    // MARK: - Eylemler

    private func reload() async {
        await model.load(near: location.coordinate, signedIn: session.isSignedIn)
    }

    /// Başarılıysa klavye kapanır ve liste yeni yoruma kayar; sorun olursa kutunun üstünde açıklaması görünür.
    private func send() {
        Task {
            guard case .sent(let commentId)? = await model.sendComment(near: location.coordinate) else { return }
            successFeedback += 1
            composerFocused = false
            scrollTarget = commentId
        }
    }

    /// İyimser pati; yalnızca sorun olursa haber verilir.
    private func paw() {
        Task {
            guard let message = await model.togglePaw()?.message else { return }
            router.showToast(message, style: .warning)
        }
    }

    private func volunteer() {
        Task {
            guard let result = await model.toggleVolunteer() else { return }
            if case .volunteered = result { successFeedback += 1 }
            router.showToast(result.message, style: result.toastStyle)
        }
    }

    private func askToDelete(_ comment: CommunityComment) {
        commentPendingDelete = comment
        showsDeleteCommentDialog = true
    }

    private func delete(_ comment: CommunityComment) {
        Task {
            guard let result = await model.deleteComment(comment.id) else { return }
            router.showToast(result.message(for: .comment), style: result.toastStyle)
        }
    }

    /// Kendi paylaşımını silince akışa dönülür.
    private func deletePost() {
        Task {
            guard let result = await model.deletePost() else { return }
            router.showToast(result.message(for: .post), style: result.toastStyle)
            if result == .deleted { dismiss() }
        }
    }
}

#Preview("Soru ve yorumlar") {
    PreviewEnvironment { services in
        PostDetailScreen(postId: DemoData.id(6, 3), services: services)
    }
}

#Preview("Yerime bakar mısın?") {
    PreviewEnvironment { services in
        PostDetailScreen(postId: DemoData.id(6, 1), services: services)
    }
}

#Preview("Bulunamadı") {
    PreviewEnvironment { services in
        PostDetailScreen(postId: DemoData.id(6, 99), services: services)
    }
}
#endif
