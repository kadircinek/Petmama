#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Akış" bölümü: haftalık özet, tür filtresi ve paylaşım kartları. Tümü giriş gerektirir (D17).
struct CommunityFeedView: View {
    let model: CommunityFeedViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location
    @State private var postPendingDelete: CommunityPost?
    @State private var showsDeleteDialog = false
    /// Detayı açılan paylaşım; dönüşte kartı tazelenir (pati, yorum sayısı).
    @State private var lastOpenedPostId: UUID?
    @State private var volunteerFeedback = 0

    var body: some View {
        content
            // İlk açılış, giriş/çıkış ve detaydan dönüş. Kaydırma konumu bozulmasın diye açılmış kartlar korunur.
            .task(id: session.userId) {
                await reload(keepingDepth: true)
                await refreshOpenedPost()
            }
            .onChange(of: router.sheet) { old, new in
                // Yeni paylaşım, rapor/engelleme veya giriş sheet'i kapanınca akışı tazele.
                if old != nil, new == nil { Task { await reload(keepingDepth: true) } }
            }
            .onChange(of: location.coordinate == nil) { _, isNil in
                if !isNil { Task { await reload() } }
            }
            .sensoryFeedback(.success, trigger: volunteerFeedback)
    }

    @ViewBuilder
    private var content: some View {
        if session.isRestoring, !session.isSignedIn {
            // Açılışta oturum geri yüklenirken giriş daveti bir an görünüp kaybolmasın.
            LoadingView()
        } else if !session.isSignedIn || model.requiresSignIn {
            CommunitySignInGate { router.present(.signIn, session: session) }
        } else {
            feed
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let summary = model.summary {
                    CommunitySummaryCard(summary: summary) { select(.coverRequest) }
                        .padding(.horizontal, MamaMetrics.screenPadding)
                }
                CommunityKindFilterBar(selected: model.selectedKind) { select($0) }
                if let error = model.error {
                    BannerView(error.userMessage, style: error.isConnectivity ? .warning : .error)
                        .padding(.horizontal, MamaMetrics.screenPadding)
                }
                list
            }
            .padding(.top, 8)
            // Yüzen "Mahalleye yaz" butonu son kartın üstünü örtmesin.
            .padding(.bottom, 96)
        }
        .refreshable { await reload() }
        .overlay(alignment: .bottom) { composeButton }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: compose) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(String(localized: "Mahalleye yaz"))
            }
        }
        .confirmationDialog(
            "Paylaşımın silinsin mi?",
            isPresented: $showsDeleteDialog,
            titleVisibility: .visible,
            presenting: postPendingDelete
        ) { post in
            Button("Sil", role: .destructive) { delete(post) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Yorumlar ve patiler de silinir. Bu işlem geri alınamaz.")
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.showsLoadingPlaceholder {
            LoadingView(String(localized: "Mahalle yükleniyor"))
                .frame(height: 240)
        } else if model.isEmpty {
            CommunityEmptyState(isFiltered: model.hasActiveFilter, onCompose: compose, onClearFilter: { select(nil) })
        } else if model.posts.isEmpty {
            // Yüklenemedi (üstte hata bandı var): "henüz paylaşım yok" demek yanıltıcı olur.
            Button {
                Task { await reload() }
            } label: {
                Text("Tekrar dene")
            }
            .buttonStyle(.mamaSecondary(systemImage: "arrow.clockwise", fullWidth: false))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        } else {
            ForEach(model.posts) { post in
                CommunityPostCard(
                    post: post,
                    now: model.now,
                    viewerId: session.userId,
                    showsDistance: model.hasViewerLocation,
                    isCoverOpen: model.isCoverOpen(post),
                    isBusy: model.busyPostIds.contains(post.id),
                    onPaw: { paw(post) },
                    onVolunteer: { volunteer(post) },
                    onComment: { open(post) },
                    onDelete: { askToDelete(post) }
                )
                .padding(.horizontal, MamaMetrics.screenPadding)
                .onAppear { loadMoreIfNeeded(after: post) }
            }
            listFooter
        }
    }

    /// Sonraki sayfa yüklenirken gösterge; otomatik yükleme kaçarsa elle "Daha fazla göster".
    @ViewBuilder
    private var listFooter: some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: MamaMetrics.minTapSize)
        } else if model.canLoadMore {
            MamaTextButton(String(localized: "Daha fazla göster")) {
                Task { await model.loadMore(near: location.coordinate) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var composeButton: some View {
        if !model.posts.isEmpty {
            Button(action: compose) {
                Text("Mahalleye yaz")
            }
            .buttonStyle(.mamaPrimary(systemImage: "square.and.pencil", fullWidth: false))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Yükleme

    private func reload(keepingDepth: Bool = false) async {
        await model.load(near: location.coordinate, signedIn: session.isSignedIn, keepingDepth: keepingDepth)
    }

    private func refreshOpenedPost() async {
        guard let postId = lastOpenedPostId else { return }
        lastOpenedPostId = nil
        await model.refreshPost(postId, near: location.coordinate)
    }

    private func loadMoreIfNeeded(after post: CommunityPost) {
        guard post.id == model.posts.last?.id, model.canLoadMore else { return }
        Task { await model.loadMoreIfNeeded(after: post, near: location.coordinate) }
    }

    private func select(_ kind: CommunityPostKind?) {
        Task { await model.selectKind(kind, near: location.coordinate) }
    }

    // MARK: - Eylemler

    private func compose() {
        router.present(.createPost(kind: nil, spotId: nil), session: session)
    }

    private func open(_ post: CommunityPost) {
        lastOpenedPostId = post.id
        router.push(.post(post.id))
    }

    /// İyimser pati; yalnızca sorun olursa haber verilir.
    private func paw(_ post: CommunityPost) {
        Task {
            guard let message = await model.togglePaw(post.id)?.message else { return }
            router.showToast(message, style: .warning)
        }
    }

    private func volunteer(_ post: CommunityPost) {
        Task {
            guard let result = await model.toggleVolunteer(post.id) else { return }
            if case .volunteered = result { volunteerFeedback += 1 }
            router.showToast(result.message, style: result.toastStyle)
        }
    }

    private func askToDelete(_ post: CommunityPost) {
        postPendingDelete = post
        showsDeleteDialog = true
    }

    private func delete(_ post: CommunityPost) {
        Task {
            guard let result = await model.deletePost(post.id) else { return }
            router.showToast(result.message(for: .post), style: result.toastStyle)
        }
    }
}
#endif
