import XCTest
@testable import MamaCore

final class CommunityPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func day(_ offset: Int) -> Date {
        CommunityPolicy.istanbulCalendar.date(byAdding: .day, value: offset, to: now)!
    }

    func testBodyValidation() {
        XCTAssertEqual(CommunityPolicy.validate(CommunityPostDraft(body: "   ", coordinate: .modaKadikoy), now: now), .bodyEmpty)
        let long = String(repeating: "a", count: CommunityPolicy.maxBodyLength + 1)
        XCTAssertEqual(CommunityPolicy.validate(CommunityPostDraft(body: long, coordinate: .modaKadikoy), now: now), .bodyTooLong)
        XCTAssertNil(CommunityPolicy.validate(CommunityPostDraft(body: "Merhaba mahalle", coordinate: .modaKadikoy), now: now))
    }

    func testNoteNeedsLocationOrSpot() {
        XCTAssertEqual(CommunityPolicy.validate(CommunityPostDraft(body: "Merhaba"), now: now), .locationMissing)
        XCTAssertNil(CommunityPolicy.validate(CommunityPostDraft(body: "Merhaba", spotId: UUID()), now: now))
    }

    func testCoverRequestRules() {
        var draft = CommunityPostDraft(kind: .coverRequest, body: "Yerime bakar mısınız?", coverFrom: day(1), coverTo: day(3))
        XCTAssertEqual(CommunityPolicy.validate(draft, now: now), .coverNeedsSpot)
        draft.spotId = UUID()
        XCTAssertNil(CommunityPolicy.validate(draft, now: now))

        draft.coverFrom = day(-1)
        XCTAssertEqual(CommunityPolicy.validate(draft, now: now), .coverDates, "geçmiş başlangıç")
        draft.coverFrom = day(4)
        XCTAssertEqual(CommunityPolicy.validate(draft, now: now), .coverDates, "bitiş başlangıçtan önce")
        draft.coverFrom = day(0)
        draft.coverTo = day(CommunityPolicy.maxCoverDays)
        XCTAssertNil(CommunityPolicy.validate(draft, now: now), "bugün başlayıp tam 30 gün sürebilir")
        draft.coverTo = day(CommunityPolicy.maxCoverDays + 1)
        XCTAssertEqual(CommunityPolicy.validate(draft, now: now), .coverDates)
        draft.coverTo = nil
        XCTAssertEqual(CommunityPolicy.validate(draft, now: now), .coverDates)
    }

    func testCommentValidation() {
        XCTAssertEqual(CommunityPolicy.validateComment(" \n"), .bodyEmpty)
        XCTAssertEqual(CommunityPolicy.validateComment(String(repeating: "x", count: 301)), .bodyTooLong)
        XCTAssertNil(CommunityPolicy.validateComment("Ben uğrarım."))
    }

    func testCoverOpenIncludesLastDay() {
        let post = CommunityPost(kind: .coverRequest, body: "x", authorId: UUID(), authorName: "A", coverFrom: day(-2), coverTo: day(0))
        XCTAssertTrue(CommunityPolicy.isCoverOpen(post, now: now))
        XCTAssertFalse(CommunityPolicy.isCoverOpen(post, now: day(1)))
        let note = CommunityPost(kind: .note, body: "x", authorId: UUID(), authorName: "A")
        XCTAssertFalse(CommunityPolicy.isCoverOpen(note, now: now))
    }

    func testCellRoundsToTwoDecimals() {
        let cell = CommunityPolicy.cell(for: Coordinate(latitude: 40.98621, longitude: 29.02547))
        XCTAssertEqual(cell.latitude, 40.99, accuracy: 0.0001)
        XCTAssertEqual(cell.longitude, 29.03, accuracy: 0.0001)
    }
}

final class InMemoryCommunityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeBackend(signedIn: Bool = true) -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
    }

    func day(_ offset: Int) -> Date {
        CommunityPolicy.istanbulCalendar.date(byAdding: .day, value: offset, to: now)!
    }

    func testFeedRequiresSignIn() async {
        let backend = makeBackend(signedIn: false)
        do {
            _ = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 30)
            XCTFail("giriş gerekmeli")
        } catch {
            XCTAssertEqual(error as? MamaError, .notSignedIn)
        }
    }

    func testFeedIsNearbyNewestFirstWithCounters() async throws {
        let backend = makeBackend()
        let feed = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 30)
        XCTAssertEqual(feed.map(\.id), [1, 2, 3, 4, 5].map { DemoData.id(6, $0) }, "9 km uzaktaki paylaşım gelmez")
        XCTAssertEqual(feed, feed.sorted { $0.createdAt > $1.createdAt })

        let cover = try XCTUnwrap(feed.first)
        XCTAssertEqual(cover.kind, .coverRequest)
        XCTAssertEqual(cover.spotTitle, "Moda Sahili bankları")
        XCTAssertEqual(cover.volunteerCount, 1)
        XCTAssertFalse(cover.viewerVolunteered)
        XCTAssertEqual(cover.commentCount, 1)
        XCTAssertTrue(cover.authorIsVerified)

        let question = try XCTUnwrap(feed.first { $0.kind == .question })
        XCTAssertEqual(question.commentCount, 2)
        XCTAssertEqual(question.pawCount, 1)
        XCTAssertTrue(feed.allSatisfy { $0.distanceMeters != nil })
    }

    func testKindFilterAndPagination() async throws {
        let backend = makeBackend()
        let notes = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: .note, before: nil, limit: 30)
        XCTAssertEqual(notes.map(\.id), [DemoData.id(6, 2)])

        let firstPage = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 2)
        XCTAssertEqual(firstPage.count, 2)
        let secondPage = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: firstPage.last?.createdAt, limit: 2)
        XCTAssertEqual(secondPage.map(\.id), [DemoData.id(6, 3), DemoData.id(6, 4)])
    }

    func testCreateNoteStoresOnlyCoarseCell() async throws {
        let backend = makeBackend()
        let exact = Coordinate(latitude: 40.98621, longitude: 29.02547)
        let outcome = try await backend.createPost(CommunityPostDraft(body: "  Merhaba mahalle!  ", coordinate: exact))
        guard case .created(let id, let pending) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(pending)
        let post = try await backend.post(id: id, near: exact)
        XCTAssertEqual(post?.body, "Merhaba mahalle!")
        XCTAssertEqual(post?.authorName, "Sen")
        // Mesafe kaba hücreye göre ölçülür: tam konum saklanmadığından sıfır çıkmaz.
        XCTAssertGreaterThan(post?.distanceMeters ?? 0, 100)
    }

    func testCreateValidationProfanityAndLimit() async throws {
        let backend = makeBackend()
        let empty = try await backend.createPost(CommunityPostDraft(body: " ", coordinate: .modaKadikoy))
        XCTAssertEqual(empty, .invalid(.bodyEmpty))
        let rude = try await backend.createPost(CommunityPostDraft(body: "siktir git", coordinate: .modaKadikoy))
        XCTAssertEqual(rude, .rejectedContent)
        let noLocation = try await backend.createPost(CommunityPostDraft(body: "Merhaba"))
        XCTAssertEqual(noLocation, .invalid(.locationMissing))

        for index in 0..<CommunityPolicy.dailyPostLimit {
            let outcome = try await backend.createPost(CommunityPostDraft(body: "Paylaşım \(index)", coordinate: .modaKadikoy))
            guard case .created = outcome else { return XCTFail("\(outcome)") }
        }
        let over = try await backend.createPost(CommunityPostDraft(body: "Bir tane daha", coordinate: .modaKadikoy))
        XCTAssertEqual(over, .limitReached(limit: CommunityPolicy.dailyPostLimit))
    }

    func testCoverRequestNeedsVisibleSpotAndValidDates() async throws {
        let backend = makeBackend()
        let missingSpot = try await backend.createPost(
            CommunityPostDraft(kind: .coverRequest, body: "Bakar mısınız?", spotId: UUID(), coverFrom: day(1), coverTo: day(2))
        )
        XCTAssertEqual(missingSpot, .invalid(.spotNotFound))
        let badDates = try await backend.createPost(
            CommunityPostDraft(kind: .coverRequest, body: "Bakar mısınız?", spotId: DemoData.id(2, 3), coverFrom: day(3), coverTo: day(1))
        )
        XCTAssertEqual(badDates, .invalid(.coverDates))
        let ok = try await backend.createPost(
            CommunityPostDraft(kind: .coverRequest, body: "Bakar mısınız?", spotId: DemoData.id(2, 3), coverFrom: day(1), coverTo: day(2))
        )
        guard case .created(let id, _) = ok else { return XCTFail("\(ok)") }
        let post = try await backend.post(id: id, near: nil)
        XCTAssertEqual(post?.spotTitle, "Kadife Sokak köşesi")
        XCTAssertNotNil(post?.coverFrom)
        XCTAssertNil(post?.distanceMeters)
    }

    func testLowTrustPostIsPendingAndOnlyAuthorSeesIt() async throws {
        let backend = makeBackend()
        await backend.setTrustScore(2, for: DemoData.meId)
        let outcome = try await backend.createPost(CommunityPostDraft(body: "İlk paylaşımım", coordinate: .modaKadikoy))
        guard case .created(let id, let pending) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(pending)
        let mine = try await backend.post(id: id, near: nil)
        XCTAssertEqual(mine?.isPendingModeration, true)

        await backend.setCurrentUser(DemoData.emreId)
        let others = try await backend.post(id: id, near: nil)
        XCTAssertNil(others)
    }

    func testPawToggle() async throws {
        let backend = makeBackend()
        let postId = DemoData.id(6, 2)
        let on = try await backend.togglePaw(postId: postId)
        XCTAssertEqual(on, PawToggleResult(pawed: true, pawCount: 3))
        let seen = try await backend.post(id: postId, near: nil)
        XCTAssertEqual(seen?.viewerPawed, true)
        let off = try await backend.togglePaw(postId: postId)
        XCTAssertEqual(off, PawToggleResult(pawed: false, pawCount: 2))
        let missing = try await backend.togglePaw(postId: UUID())
        XCTAssertNil(missing)
    }

    func testVolunteerFlowNotifiesAuthorOnce() async throws {
        let backend = makeBackend()
        let postId = DemoData.id(6, 1) // Ayşe'nin isteği
        let first = try await backend.toggleVolunteer(postId: postId)
        XCTAssertEqual(first, .ok(volunteered: true, volunteerCount: 2))
        let volunteers = try await backend.volunteers(postId: postId)
        XCTAssertEqual(volunteers.map(\.displayName), ["Emre", "Sen"])

        let notes = await backend.notifications(for: DemoData.ayseId)
        XCTAssertEqual(notes.first?.kind, .coverVolunteered)
        XCTAssertEqual(notes.first?.postId, postId)

        // Vazgeçip tekrar gönüllü olunca okunmamış bildirim varken ikincisi gitmez.
        let off = try await backend.toggleVolunteer(postId: postId)
        XCTAssertEqual(off, .ok(volunteered: false, volunteerCount: 1))
        _ = try await backend.toggleVolunteer(postId: postId)
        let after = await backend.notifications(for: DemoData.ayseId)
        XCTAssertEqual(after.filter { $0.kind == .coverVolunteered }.count, 1)
    }

    func testVolunteerGuards() async throws {
        let backend = makeBackend()
        let notCover = try await backend.toggleVolunteer(postId: DemoData.id(6, 2))
        XCTAssertEqual(notCover, .notCoverRequest)
        let missing = try await backend.toggleVolunteer(postId: UUID())
        XCTAssertEqual(missing, .postNotFound)

        await backend.setCurrentUser(DemoData.ayseId)
        let own = try await backend.toggleVolunteer(postId: DemoData.id(6, 1))
        XCTAssertEqual(own, .ownPost)
    }

    func testClosedCoverRequestRejectsVolunteers() async throws {
        let fixed = now
        let later = fixed.addingTimeInterval(10 * 86_400)
        // Tohum verisi `fixed` anına göre; saat 10 gün ileri alınınca istek kapanmış olur.
        let backend = InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: true, now: { later })
        let outcome = try await backend.toggleVolunteer(postId: DemoData.id(6, 1))
        XCTAssertEqual(outcome, .closed)
    }

    func testCommentNotifiesAuthorAndRespectsPreferences() async throws {
        let backend = makeBackend()
        let postId = DemoData.id(6, 3) // Emre'nin sorusu
        let outcome = try await backend.addComment(postId: postId, body: " Ben de yapmak istiyorum. ")
        guard case .created = outcome else { return XCTFail("\(outcome)") }
        let comments = try await backend.comments(postId: postId)
        XCTAssertEqual(comments.count, 3)
        XCTAssertEqual(comments.last?.body, "Ben de yapmak istiyorum.")
        XCTAssertEqual(comments, comments.sorted { $0.createdAt < $1.createdAt })

        let notes = await backend.notifications(for: DemoData.emreId)
        XCTAssertEqual(notes.first?.kind, .communityComment)
        XCTAssertEqual(notes.first?.postId, postId)

        // Tercihi kapalı yazara bildirim gitmez.
        await backend.setNotificationPreferences(NotificationPreferences(communityUpdates: false), for: DemoData.zeynepId)
        _ = try await backend.addComment(postId: DemoData.id(6, 2), body: "Çok tatlı!")
        let muted = await backend.notifications(for: DemoData.zeynepId)
        XCTAssertTrue(muted.isEmpty)
    }

    func testCommentValidationAndOwnPost() async throws {
        let backend = makeBackend()
        let empty = try await backend.addComment(postId: DemoData.id(6, 3), body: " ")
        XCTAssertEqual(empty, .invalid(.bodyEmpty))
        let rude = try await backend.addComment(postId: DemoData.id(6, 3), body: "siktir")
        XCTAssertEqual(rude, .rejectedContent)
        let missing = try await backend.addComment(postId: UUID(), body: "Merhaba")
        XCTAssertEqual(missing, .postNotFound)

        await backend.setCurrentUser(DemoData.emreId)
        _ = try await backend.addComment(postId: DemoData.id(6, 3), body: "Teşekkürler!")
        let own = await backend.notifications(for: DemoData.emreId)
        XCTAssertTrue(own.isEmpty, "kendi paylaşımına yorum bildirim üretmez")
    }

    func testBlockedUsersDisappearBothWays() async throws {
        let backend = makeBackend()
        try await backend.block(userId: DemoData.emreId)
        let feed = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 30)
        XCTAssertFalse(feed.contains { $0.authorId == DemoData.emreId })
        let cover = try XCTUnwrap(feed.first { $0.id == DemoData.id(6, 1) })
        XCTAssertEqual(cover.commentCount, 0, "engellenen kişinin yorumu sayılmaz")
        let comments = try await backend.comments(postId: DemoData.id(6, 1))
        XCTAssertTrue(comments.isEmpty)

        await backend.setCurrentUser(DemoData.emreId)
        let fromEmre = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 30)
        XCTAssertTrue(fromEmre.allSatisfy { $0.authorId != DemoData.meId })
    }

    func testDeletePermissions() async throws {
        let backend = makeBackend()
        let notMine = try await backend.deletePost(id: DemoData.id(6, 2))
        XCTAssertFalse(notMine)
        let notMyComment = try await backend.deleteComment(id: DemoData.id(7, 1))
        XCTAssertFalse(notMyComment)

        // Paylaşımın sahibi kendi paylaşımındaki yorumu kaldırabilir.
        await backend.setCurrentUser(DemoData.emreId)
        let ownerRemoves = try await backend.deleteComment(id: DemoData.id(7, 1))
        XCTAssertTrue(ownerRemoves)
        let deleted = try await backend.deletePost(id: DemoData.id(6, 3))
        XCTAssertTrue(deleted)
        let gone = try await backend.post(id: DemoData.id(6, 3), near: nil)
        XCTAssertNil(gone)

        await backend.signInAsDemoUser()
        await backend.setModerator(true, for: DemoData.meId)
        let moderator = try await backend.deletePost(id: DemoData.id(6, 2))
        XCTAssertTrue(moderator)
    }

    func testThreeReportsHidePostAndComment() async throws {
        let backend = makeBackend()
        let postId = DemoData.id(6, 4) // Zeynep'in paylaşımı
        let commentId = DemoData.id(7, 2)
        for user in [DemoData.meId, DemoData.ayseId, DemoData.emreId] {
            await backend.setCurrentUser(user)
            try await backend.report(ReportDraft(target: .post, targetId: postId, reason: .spam))
            try await backend.report(ReportDraft(target: .comment, targetId: commentId, reason: .harassment))
        }
        let hidden = try await backend.post(id: postId, near: nil)
        XCTAssertNil(hidden)
        let comments = try await backend.comments(postId: DemoData.id(6, 3))
        XCTAssertFalse(comments.contains { $0.id == commentId })

        await backend.setCurrentUser(DemoData.zeynepId)
        let author = try await backend.post(id: postId, near: nil)
        XCTAssertEqual(author?.isPendingModeration, true, "yazar incelemede olduğunu görür")
    }

    func testDeleteAccountRemovesCommunityContent() async throws {
        let backend = makeBackend()
        await backend.setCurrentUser(DemoData.emreId)
        try await backend.deleteAccount()
        await backend.signInAsDemoUser()
        let feed = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 30)
        XCTAssertFalse(feed.contains { $0.authorId == DemoData.emreId })
        let cover = try XCTUnwrap(feed.first { $0.id == DemoData.id(6, 1) })
        XCTAssertEqual(cover.volunteerCount, 0)
        XCTAssertEqual(cover.commentCount, 0)
    }

    func testSummaryCountsFedSpotDays() async throws {
        let backend = makeBackend()
        let summary = try await backend.summary(near: .modaKadikoy, radiusMeters: 3000)
        XCTAssertGreaterThan(summary.fedSpotDays7d, 20)
        XCTAssertEqual(summary.activeFeeders7d, 3)
        XCTAssertEqual(summary.openCoverRequests, 1)
        XCTAssertEqual(summary.posts7d, 5)
    }

    func testPostLinkedToInvisibleSpotHidesTheLink() async throws {
        let backend = makeBackend()
        // Zeynep özel bahçenin koruyucusu; noktaya bağlı paylaşım yapabilir.
        await backend.setCurrentUser(DemoData.zeynepId)
        let outcome = try await backend.createPost(CommunityPostDraft(body: "Bahçedeki kulübe yenilendi.", spotId: DemoData.id(2, 14)))
        guard case .created(let id, _) = outcome else { return XCTFail("\(outcome)") }
        let own = try await backend.post(id: id, near: nil)
        XCTAssertEqual(own?.spotTitle, "Gönüllü bahçesi")
    }
}

@MainActor
final class CommunityRouterTests: XCTestCase {
    func testShowCommunitySelectsTabAndSection() async {
        let router = AppRouter()
        router.sheet = .addMenu
        router.showCommunity(.needs)
        XCTAssertEqual(router.selectedTab, .community)
        XCTAssertEqual(router.communitySection, .needs)
        XCTAssertNil(router.sheet)
    }

    func testCreatePostRequiresSignIn() async {
        let services = AppServices.demo()
        let session = SessionStore(auth: services.auth, profiles: services.profiles)
        let router = AppRouter()
        router.present(.createPost(kind: .coverRequest, spotId: nil), session: session)
        XCTAssertEqual(router.sheet, .signIn)
    }
}

final class MascotTests: XCTestCase {
    func testMoodFollowsSpotStatus() {
        XCTAssertEqual(MascotMood(status: .fedRecent), .happy)
        XCTAssertEqual(MascotMood(status: .needsFood), .hungry)
        XCTAssertEqual(MascotMood(status: .fedStale), .neutral)
        XCTAssertEqual(MascotMood(status: .unknown), .neutral)
    }

    func testCoatMatchingFromTurkishDescriptions() {
        let seed = UUID()
        func cat(_ text: String?) -> MascotCoat { MascotCoat.matching(species: .cat, colorPattern: text, seed: seed) }
        func dog(_ text: String?) -> MascotCoat { MascotCoat.matching(species: .dog, colorPattern: text, seed: seed) }
        XCTAssertEqual(cat("Sarman"), .catOrange)
        XCTAssertEqual(cat("Gri tekir"), .catGray)
        XCTAssertEqual(cat("BEYAZ"), .catWhite)
        XCTAssertEqual(cat("Siyah"), .catBlack)
        XCTAssertEqual(cat("Calico"), .catCalico)
        XCTAssertEqual(dog("Açık kahve"), .dogCream, "açık ton koyu kahveden önce gelir")
        XCTAssertEqual(dog("Kahverengi"), .dogBrown)
        XCTAssertEqual(dog("Siyah"), .dogBlack)
        XCTAssertEqual(dog("Beyaz benekli"), .dogSpotted)
    }

    func testUnknownDescriptionIsStablePerAnimal() {
        let seed = UUID()
        let first = MascotCoat.matching(species: .cat, colorPattern: nil, seed: seed)
        let second = MascotCoat.matching(species: .cat, colorPattern: "çok tatlı", seed: seed)
        XCTAssertEqual(first, second)
        XCTAssertTrue(MascotCoat.cats.contains(first))
        XCTAssertTrue(MascotCoat.dogs.contains(MascotCoat.matching(species: .dog, colorPattern: nil, seed: seed)))
    }

    func testAssetNamesMatchGeneratedCatalog() {
        XCTAssertEqual(MascotCoat.catCalico.assetName(mood: .hungry), "mascot-cat-calico-hungry")
        XCTAssertEqual(MascotSpecies.duo.assetName(mood: .happy), "mascot-duo-happy")
        XCTAssertEqual(MascotSpecies(SpotSpecies.both), .duo)
        XCTAssertEqual(MascotSpecies.dog.assetName(mood: .neutral), "mascot-dog-cream-neutral")
    }

    /// Koddaki her maskot adının asset catalog'da karşılığı olmalı (üretici betikle senkron).
    func testEveryAssetExistsInCatalog() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MamaDesign/Resources/Mascots.xcassets")
        var names: [String] = []
        for mood in MascotMood.allCases {
            names += MascotCoat.allCases.map { $0.assetName(mood: mood) }
            names += MascotSpecies.allCases.map { $0.assetName(mood: mood) }
        }
        names += ["spot-food", "spot-water", "spot-shelter", "spot-mixed"]
        for name in Set(names) {
            let file = catalog.appendingPathComponent("\(name).imageset/\(name).svg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "eksik ikon: \(name)")
        }
    }
}
