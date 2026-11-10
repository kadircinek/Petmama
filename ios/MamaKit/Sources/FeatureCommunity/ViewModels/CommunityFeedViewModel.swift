import Foundation
import Observation
import MamaCore

/// Mahalle akışı: yakındaki paylaşımlar, haftalık özet, pati ve "Ben bakarım" (D17).
/// Akışın tamamı giriş gerektirir; oturum yoksa `requiresSignIn` açılır ve sunucuya gidilmez.
@MainActor
@Observable
public final class CommunityFeedViewModel {
    /// Sunucudaki `max_rows` üst sınırı (docs/backend-contract.md → `community_feed`).
    public nonisolated static let maxServerRows = 50

    public private(set) var posts: [CommunityPost] = []
    public private(set) var summary: CommunitySummary?
    /// `nil` = tüm türler.
    public private(set) var selectedKind: CommunityPostKind?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var hasLoaded = false
    /// Son sayfa doluydu; devamı olabilir.
    public private(set) var canLoadMore = false
    /// Oturum yok: paylaşımlar yerine giriş daveti gösterilir.
    public private(set) var requiresSignIn = false
    /// Son yükleme gerçek konumla yapıldı (değilse mesafe gösterilmez).
    public private(set) var hasViewerLocation = false
    /// "Ben bakarım" veya silme isteği süren paylaşımlar.
    public private(set) var busyPostIds: Set<UUID> = []
    public var error: MamaError?

    public let pageSize: Int
    /// Tek istekte tazelenebilecek en fazla paylaşım.
    public let maxRowsPerRequest: Int
    @ObservationIgnored private let services: AppServices
    /// Art arda yüklemelerde (filtre, sheet kapanışı) yalnızca en son isteğin sonucu yazılır.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pawsInFlight: Set<UUID> = []

    public init(
        services: AppServices,
        pageSize: Int = CommunityPolicy.pageSize,
        maxRowsPerRequest: Int = CommunityFeedViewModel.maxServerRows
    ) {
        self.services = services
        let cap = min(max(maxRowsPerRequest, 1), Self.maxServerRows)
        self.maxRowsPerRequest = cap
        self.pageSize = min(max(pageSize, 1), cap)
    }

    public var now: Date { services.now() }
    public var hasActiveFilter: Bool { selectedKind != nil }
    /// Gösterilecek kart yokken yükleme sürüyor (ilk açılış, filtre değişimi).
    public var showsLoadingPlaceholder: Bool { !hasLoaded || (isLoading && posts.isEmpty) }
    /// Gerçekten boş: yüklendi, hata yok, paylaşım yok. (Yüklenemediyse boş durum değil hata gösterilir.)
    public var isEmpty: Bool { hasLoaded && !isLoading && !requiresSignIn && error == nil && posts.isEmpty }

    // MARK: - Yükleme

    /// İlk sayfayı ve özeti yükler.
    ///
    /// `keepingDepth` (sheet kapanışı, detaydan dönüş): kaydırma konumu bozulmasın diye o ana kadar açılmış
    /// paylaşımlar korunur. Tek isteğe sığan baş kısım sunucudan tazelenir; daha eski kartlar olduğu gibi kalır.
    public func load(near coordinate: Coordinate?, signedIn: Bool = true, keepingDepth: Bool = false) async {
        generation += 1
        let token = generation
        guard signedIn else {
            showSignInGate()
            return
        }
        if requiresSignIn {
            // Giriş yapıldı: davet yerine yükleniyor durumu görünsün.
            requiresSignIn = false
            hasLoaded = false
        }
        isLoading = true
        defer { if token == generation { isLoading = false } }

        let center = coordinate ?? .modaKadikoy
        let limit = keepingDepth ? min(max(posts.count, pageSize), maxRowsPerRequest) : pageSize
        let community = services.community
        async let summaryResult = try? await community.summary(near: center, radiusMeters: CommunityPolicy.feedRadiusMeters)
        do {
            let page = try await community.feed(
                near: center,
                radiusMeters: CommunityPolicy.feedRadiusMeters,
                kind: selectedKind,
                before: nil,
                limit: limit
            )
            let freshSummary = await summaryResult
            guard token == generation else { return }
            let tail = keepingDepth && page.count >= limit ? olderPosts(than: page) : []
            posts = page + tail
            if tail.isEmpty { canLoadMore = page.count >= limit }
            hasViewerLocation = coordinate != nil
            if let freshSummary { summary = freshSummary }
            requiresSignIn = false
            error = nil
            hasLoaded = true
        } catch {
            guard token == generation else { return }
            handle(error)
            hasLoaded = true
        }
    }

    /// Son kart göründüğünde çağrılır.
    public func loadMoreIfNeeded(after post: CommunityPost, near coordinate: Coordinate?) async {
        guard post.id == posts.last?.id else { return }
        await loadMore(near: coordinate)
    }

    /// Sonraki sayfa: son paylaşımın `createdAt` değerinden eskiler (keyset).
    public func loadMore(near coordinate: Coordinate?) async {
        guard canLoadMore, !isLoadingMore, !isLoading, let last = posts.last else { return }
        let token = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await services.community.feed(
                near: coordinate ?? .modaKadikoy,
                radiusMeters: CommunityPolicy.feedRadiusMeters,
                kind: selectedKind,
                before: last.createdAt,
                limit: pageSize
            )
            guard token == generation else { return }
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.filter { !known.contains($0.id) })
            canLoadMore = page.count >= pageSize
            error = nil
        } catch {
            guard token == generation else { return }
            handle(error)
        }
    }

    /// Tür filtresi sunucuda uygulanır; yanıt gelene kadar eldeki paylaşımlar yerelde süzülür.
    public func selectKind(_ kind: CommunityPostKind?, near coordinate: Coordinate?) async {
        guard kind != selectedKind else { return }
        selectedKind = kind
        if let kind { posts.removeAll { $0.kind != kind } }
        await load(near: coordinate)
    }

    /// Detaydan dönünce tek paylaşımı tazeler (pati, yorum sayısı); artık yoksa listeden çıkarır.
    public func refreshPost(_ postId: UUID, near coordinate: Coordinate?) async {
        guard posts.contains(where: { $0.id == postId }) else { return }
        do {
            if let fresh = try await services.community.post(id: postId, near: coordinate ?? .modaKadikoy) {
                update(postId) { $0 = fresh }
            } else {
                posts.removeAll { $0.id == postId }
            }
        } catch {
            // Bağlantı sorunu: eldeki kart kalsın, sonraki yenilemede düzelir.
        }
    }

    // MARK: - Eylemler

    public func isOwn(_ post: CommunityPost, userId: UUID?) -> Bool {
        userId != nil && post.authorId == userId
    }

    public func isCoverOpen(_ post: CommunityPost) -> Bool {
        CommunityPolicy.isCoverOpen(post, now: services.now())
    }

    /// İyimser pati: önce ekranda çevrilir, sunucu reddederse eski haline döner.
    /// `nil` = bu paylaşım için süren bir istek var ya da paylaşım listede değil.
    public func togglePaw(_ postId: UUID) async -> CommunityPawResult? {
        guard !pawsInFlight.contains(postId), let original = posts.first(where: { $0.id == postId }) else { return nil }
        pawsInFlight.insert(postId)
        defer { pawsInFlight.remove(postId) }
        update(postId) { $0.applyOptimisticPawToggle() }
        do {
            guard let result = try await services.community.togglePaw(postId: postId) else {
                posts.removeAll { $0.id == postId }
                return .postGone
            }
            update(postId) { $0.apply(result) }
            return .toggled(pawed: result.pawed)
        } catch {
            update(postId) {
                $0.viewerPawed = original.viewerPawed
                $0.pawCount = original.pawCount
            }
            return .failed(MamaError.classify(error))
        }
    }

    /// "Ben bakarım" / "Vazgeç". `nil` = bu paylaşım için süren bir istek var.
    public func toggleVolunteer(_ postId: UUID) async -> CommunityVolunteerResult? {
        guard !busyPostIds.contains(postId) else { return nil }
        busyPostIds.insert(postId)
        defer { busyPostIds.remove(postId) }
        do {
            let outcome = try await services.community.toggleVolunteer(postId: postId)
            switch outcome {
            case .ok(let volunteered, let count):
                update(postId) {
                    $0.viewerVolunteered = volunteered
                    $0.volunteerCount = count
                }
            case .postNotFound:
                posts.removeAll { $0.id == postId }
            case .notCoverRequest, .ownPost, .closed:
                break
            }
            return CommunityVolunteerResult(outcome)
        } catch {
            return .failed(MamaError.classify(error))
        }
    }

    /// Kendi paylaşımını siler. `nil` = bu paylaşım için süren bir istek var.
    public func deletePost(_ postId: UUID) async -> CommunityDeleteResult? {
        guard !busyPostIds.contains(postId) else { return nil }
        busyPostIds.insert(postId)
        defer { busyPostIds.remove(postId) }
        do {
            guard try await services.community.deletePost(id: postId) else { return .notAllowed }
            posts.removeAll { $0.id == postId }
            return .deleted
        } catch {
            let classified = MamaError.classify(error)
            // Zaten silinmiş: kullanıcının istediği sonuç.
            guard classified == .notFound else { return .failed(classified) }
            posts.removeAll { $0.id == postId }
            return .deleted
        }
    }

    // MARK: - Yardımcılar

    /// Tazelenen baş kısmın en eski paylaşımından daha eski, hâlâ elde duran kartlar.
    private func olderPosts(than page: [CommunityPost]) -> [CommunityPost] {
        guard let oldest = page.last, posts.count > page.count else { return [] }
        let fresh = Set(page.map(\.id))
        return posts.filter { $0.createdAt < oldest.createdAt && !fresh.contains($0.id) }
    }

    private func update(_ postId: UUID, _ change: (inout CommunityPost) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        change(&posts[index])
    }

    private func handle(_ error: Error) {
        let classified = MamaError.classify(error)
        if classified == .notSignedIn {
            showSignInGate()
        } else {
            self.error = classified
        }
    }

    /// Oturum yokken besleyicilerin konuşmaları bellekte de tutulmaz.
    private func showSignInGate() {
        posts = []
        summary = nil
        canLoadMore = false
        isLoading = false
        requiresSignIn = true
        error = nil
        hasLoaded = true
    }
}
