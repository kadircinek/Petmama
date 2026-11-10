import XCTest
import MamaCore
@testable import FeatureCommunity

@MainActor
final class CommunityFeedViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeBackend(signedIn: Bool = true) -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
    }

    private func makeServices(_ backend: InMemoryBackend, community: (any CommunityRepository)? = nil) -> AppServices {
        let fixed = now
        var services = AppServices.inMemory(backend, now: { fixed })
        if let community { services.community = community }
        return services
    }

    private var nearbyPostIds: [UUID] { (1...5).map { DemoData.id(6, $0) } }

    // MARK: - Giriş kapısı

    func testSignedOutShowsGateWithoutTouchingBackend() async {
        let backend = makeBackend(signedIn: false)
        let stub = CommunityRepositoryStub(backend)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub))

        await model.load(near: .modaKadikoy, signedIn: false)

        XCTAssertTrue(model.requiresSignIn)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertNil(model.summary)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isEmpty, "giriş kapısı boş durum değildir")
        let calls = await stub.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testBackendNotSignedInBecomesGateNotError() async {
        // Oturum deposu "giriş var" dese bile sunucu reddederse hata bandı değil giriş daveti gösterilir.
        let model = CommunityFeedViewModel(services: makeServices(makeBackend(signedIn: false)))
        await model.load(near: .modaKadikoy, signedIn: true)

        XCTAssertTrue(model.requiresSignIn)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testSigningOutClearsLoadedPosts() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)
        XCTAssertFalse(model.posts.isEmpty)

        await model.load(near: .modaKadikoy, signedIn: false)
        XCTAssertTrue(model.posts.isEmpty)
        XCTAssertNil(model.summary)
        XCTAssertTrue(model.requiresSignIn)

        await model.load(near: .modaKadikoy, signedIn: true)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertEqual(model.posts.count, 5)
    }

    // MARK: - Akış

    func testFeedOrderAndCounters() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)

        XCTAssertEqual(model.posts.map(\.id), nearbyPostIds, "yeniden eskiye; 9 km uzaktaki paylaşım yok")
        XCTAssertEqual(model.posts.map(\.createdAt), model.posts.map(\.createdAt).sorted(by: >))
        XCTAssertFalse(model.canLoadMore)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.hasViewerLocation)
        XCTAssertTrue(model.posts.allSatisfy { ($0.distanceMeters ?? .infinity) <= Double(CommunityPolicy.feedRadiusMeters) })

        let cover = model.posts[0]
        XCTAssertEqual(cover.kind, .coverRequest)
        XCTAssertEqual(cover.volunteerCount, 1)
        XCTAssertFalse(cover.viewerVolunteered)
        XCTAssertEqual(cover.commentCount, 1)
        XCTAssertEqual(cover.spotTitle, "Moda Sahili bankları")
        XCTAssertTrue(cover.authorIsVerified)
        XCTAssertTrue(model.isCoverOpen(cover))

        let note = model.posts[1]
        XCTAssertEqual(note.pawCount, 2)
        XCTAssertFalse(note.viewerPawed)
        XCTAssertEqual(note.animalName, "Pamuk")

        let question = model.posts[2]
        XCTAssertEqual(question.pawCount, 1)
        XCTAssertEqual(question.commentCount, 2)
        XCTAssertFalse(model.isCoverOpen(question))
    }

    func testFallsBackToModaWithoutLocationAndHidesDistance() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()))
        await model.load(near: nil)
        XCTAssertEqual(model.posts.count, 5)
        XCTAssertFalse(model.hasViewerLocation)
        XCTAssertNil(model.error)
    }

    func testFarAwayLocationIsEmpty() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()))
        XCTAssertTrue(model.showsLoadingPlaceholder, "ilk yüklemeden önce boş durum değil yükleniyor görünür")
        XCTAssertFalse(model.isEmpty)
        await model.load(near: GeoMath.offset(.modaKadikoy, north: 40_000, east: 0))
        XCTAssertTrue(model.isEmpty)
        XCTAssertFalse(model.showsLoadingPlaceholder)
        XCTAssertFalse(model.hasActiveFilter)
    }

    func testSummaryLoadsWithFeed() async throws {
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend))
        XCTAssertNil(model.summary)
        await model.load(near: .modaKadikoy)

        let expected = try await backend.summary(near: .modaKadikoy, radiusMeters: CommunityPolicy.feedRadiusMeters)
        XCTAssertEqual(model.summary, expected)
        XCTAssertEqual(model.summary?.openCoverRequests, 1)
        XCTAssertEqual(model.summary?.posts7d, 5)
        XCTAssertGreaterThan(model.summary?.fedSpotDays7d ?? 0, 0)
        XCTAssertGreaterThan(model.summary?.activeFeeders7d ?? 0, 0)
    }

    func testSummaryFailureKeepsFeed() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        await stub.fail(.summary)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.posts.count, 5)
        XCTAssertNil(model.summary)
        XCTAssertNil(model.error)
    }

    func testOfflineFeedSurfacesError() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        await stub.fail(.feed, with: .offline)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub))
        await model.load(near: .modaKadikoy)

        XCTAssertEqual(model.error, .offline)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isEmpty, "yüklenemeyen akış 'henüz paylaşım yok' diye gösterilmez")

        await stub.heal(.feed)
        await model.load(near: .modaKadikoy)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.posts.count, 5)
    }

    // MARK: - Tür filtresi

    func testKindFilter() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()))
        await model.load(near: .modaKadikoy)

        await model.selectKind(.coverRequest, near: .modaKadikoy)
        XCTAssertEqual(model.selectedKind, .coverRequest)
        XCTAssertTrue(model.hasActiveFilter)
        XCTAssertEqual(model.posts.map(\.id), [DemoData.id(6, 1)])

        await model.selectKind(.note, near: .modaKadikoy)
        XCTAssertEqual(model.posts.map(\.id), [DemoData.id(6, 2)])

        await model.selectKind(.alert, near: .modaKadikoy)
        XCTAssertEqual(model.posts.map(\.kind), [.alert])

        await model.selectKind(nil, near: .modaKadikoy)
        XCTAssertFalse(model.hasActiveFilter)
        XCTAssertEqual(model.posts.map(\.id), nearbyPostIds)
    }

    func testFilterWithNoMatchesIsEmpty() async throws {
        let backend = makeBackend()
        // Soru türündeki tek paylaşımı yazarı silsin.
        await backend.setCurrentUser(DemoData.emreId)
        let deleted = try await backend.deletePost(id: DemoData.id(6, 3))
        XCTAssertTrue(deleted)
        await backend.setCurrentUser(DemoData.meId)

        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.selectKind(.question, near: .modaKadikoy)
        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.hasActiveFilter)
    }

    // MARK: - Sayfalama

    func testPaginationWithPageSizeTwo() async {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let model = CommunityFeedViewModel(services: makeServices(backend, community: stub), pageSize: 2)

        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.posts.map(\.id), Array(nearbyPostIds.prefix(2)))
        XCTAssertTrue(model.canLoadMore)

        // Son kart dışındaki kartlar yeni sayfa istemez.
        await model.loadMoreIfNeeded(after: model.posts[0], near: .modaKadikoy)
        XCTAssertEqual(model.posts.count, 2)

        await model.loadMoreIfNeeded(after: model.posts[1], near: .modaKadikoy)
        XCTAssertEqual(model.posts.map(\.id), Array(nearbyPostIds.prefix(4)))
        XCTAssertTrue(model.canLoadMore)
        let secondPageCursor = model.posts[1].createdAt

        await model.loadMore(near: .modaKadikoy)
        XCTAssertEqual(model.posts.map(\.id), nearbyPostIds)
        XCTAssertFalse(model.canLoadMore, "son sayfa dolu değildi")
        XCTAssertFalse(model.isLoadingMore)

        await model.loadMore(near: .modaKadikoy)
        XCTAssertEqual(model.posts.count, 5)

        let befores = await stub.feedBefores
        let limits = await stub.feedLimits
        XCTAssertEqual(befores.count, 3, "dolu olmayan sayfadan sonra istek atılmaz")
        XCTAssertNil(befores[0])
        XCTAssertEqual(befores[1], secondPageCursor)
        XCTAssertEqual(limits, [2, 2, 2])
    }

    func testReloadKeepingDepthPreservesLoadedCount() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()), pageSize: 2)
        await model.load(near: .modaKadikoy)
        await model.loadMore(near: .modaKadikoy)
        XCTAssertEqual(model.posts.count, 4)

        await model.load(near: .modaKadikoy, keepingDepth: true)
        XCTAssertEqual(model.posts.map(\.id), Array(nearbyPostIds.prefix(4)))
        XCTAssertTrue(model.canLoadMore)

        await model.load(near: .modaKadikoy)
        XCTAssertEqual(model.posts.count, 2, "çekip yenileme ilk sayfaya döner")
    }

    func testDeepFeedRefreshesHeadAndKeepsOlderCards() async throws {
        // Tek istekte en fazla 3 paylaşım tazelenebiliyor; kullanıcı 5 paylaşım derinliğe inmiş.
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend), pageSize: 2, maxRowsPerRequest: 3)
        await model.load(near: .modaKadikoy)
        await model.loadMore(near: .modaKadikoy)
        await model.loadMore(near: .modaKadikoy)
        XCTAssertEqual(model.posts.map(\.id), nearbyPostIds)
        XCTAssertFalse(model.canLoadMore)

        // Sheet'ten yeni paylaşım geldi: başa eklenir, eski kartlar yerinde kalır.
        let outcome = try await backend.createPost(CommunityPostDraft(body: "Yeni haber", coordinate: .modaKadikoy))
        guard case .created(let newId, _) = outcome else { return XCTFail("paylaşım oluşmalıydı") }
        await model.load(near: .modaKadikoy, keepingDepth: true)
        XCTAssertEqual(model.posts.map(\.id), [newId] + nearbyPostIds)
        XCTAssertFalse(model.canLoadMore, "eski kartlar korunduğunda sayfalama durumu değişmez")

        // Baş kısımdan silinen paylaşım düşer; kuyruk yine korunur.
        await backend.setCurrentUser(DemoData.ayseId)
        _ = try await backend.deletePost(id: DemoData.id(6, 1))
        await backend.setCurrentUser(DemoData.meId)
        await model.load(near: .modaKadikoy, keepingDepth: true)
        XCTAssertEqual(model.posts.map(\.id), [newId] + Array(nearbyPostIds.dropFirst()))
        XCTAssertEqual(Set(model.posts.map(\.id)).count, model.posts.count)
    }

    func testPageSizeIsClampedToServerMaximum() async {
        let model = CommunityFeedViewModel(services: makeServices(makeBackend()), pageSize: 500)
        XCTAssertEqual(model.pageSize, CommunityFeedViewModel.maxServerRows)
        XCTAssertEqual(CommunityFeedViewModel(services: makeServices(makeBackend())).pageSize, CommunityPolicy.pageSize)
    }

    func testRefreshPostUpdatesCountersAndDropsDeleted() async throws {
        let backend = makeBackend()
        let model = CommunityFeedViewModel(services: makeServices(backend))
        await model.load(near: .modaKadikoy)

        // Detay ekranında yorum yazılmış gibi.
        let outcome = try await backend.addComment(postId: DemoData.id(6, 2), body: "Ne güzel haber!")
        guard case .created = outcome else { return XCTFail("yorum oluşmalıydı") }
        await model.refreshPost(DemoData.id(6, 2), near: .modaKadikoy)
        XCTAssertEqual(model.posts.first { $0.id == DemoData.id(6, 2) }?.commentCount, 1)
        XCTAssertEqual(model.posts.count, 5)

        await backend.setCurrentUser(DemoData.zeynepId)
        _ = try await backend.deletePost(id: DemoData.id(6, 2))
        await backend.setCurrentUser(DemoData.meId)
        await model.refreshPost(DemoData.id(6, 2), near: .modaKadikoy)
        XCTAssertFalse(model.posts.contains { $0.id == DemoData.id(6, 2) })
        XCTAssertEqual(model.posts.count, 4)
    }
}
