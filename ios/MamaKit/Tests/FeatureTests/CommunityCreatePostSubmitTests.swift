import XCTest
import MamaCore
@testable import FeatureCommunity

@MainActor
final class CommunityCreatePostSubmitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let validText = "Parktaki su kaplarını bu sabah tazeledim."
    private let parkSpotId = DemoData.id(2, 1)

    private func makeBackend(signedIn: Bool = true) -> InMemoryBackend {
        let fixed = now
        return InMemoryBackend(seed: DemoData.make(now: fixed), signedIn: signedIn, now: { fixed })
    }

    private func makeServices(_ backend: InMemoryBackend) -> AppServices {
        let fixed = now
        return AppServices.inMemory(backend, now: { fixed })
    }

    private func day(_ offset: Int) -> Date {
        let calendar = CommunityFormat.istanbulCalendar
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func sameDay(_ lhs: Date?, _ rhs: Date) -> Bool {
        guard let lhs else { return false }
        return CommunityFormat.istanbulCalendar.isDate(lhs, inSameDayAs: rhs)
    }

    // MARK: - Gönderme

    func testNoteIsCreatedTrimmedAndVisibleInFeed() async throws {
        let backend = makeBackend()
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(backend))
        model.bodyText = "  \(validText)\n"

        let result = await model.submit(near: .modaKadikoy)
        guard case .created(let id, let pending)? = result else { return XCTFail("paylaşım oluşmalıydı: \(String(describing: result))") }
        XCTAssertFalse(pending)
        XCTAssertEqual(result?.message, "Paylaşımın mahallede!")
        XCTAssertEqual(result?.toastStyle, .success)
        XCTAssertNil(model.submitProblem)
        XCTAssertFalse(model.isSubmitting)

        let stored = await backend.rawPost(id)
        let raw = try XCTUnwrap(stored)
        XCTAssertEqual(raw.body, validText)
        XCTAssertEqual(raw.kind, .note)
        XCTAssertEqual(raw.authorId, DemoData.meId)
        XCTAssertNil(raw.coverFrom)
        let feed = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 50)
        XCTAssertEqual(feed.first?.id, id)
    }

    func testCoverRequestSuccess() async throws {
        let backend = makeBackend()
        let model = CreatePostViewModel(kind: .coverRequest, spotId: parkSpotId, services: makeServices(backend))
        model.bodyText = "Cumartesi ve pazar yokum. Mama dolabın yanındaki kutuda."
        model.coverFrom = day(3)
        model.normalizeCoverDates()
        model.coverTo = day(4)

        // Nokta bağlı olduğu için konum olmadan da gönderilir.
        let result = await model.submit(near: nil)
        guard case .created(let id, false)? = result else { return XCTFail("istek oluşmalıydı: \(String(describing: result))") }

        let stored = await backend.rawPost(id)
        let raw = try XCTUnwrap(stored)
        XCTAssertEqual(raw.kind, .coverRequest)
        XCTAssertEqual(raw.spotId, parkSpotId)
        XCTAssertTrue(sameDay(raw.coverFrom, day(3)))
        XCTAssertTrue(sameDay(raw.coverTo, day(4)))
        XCTAssertTrue(CommunityPolicy.isCoverOpen(raw, now: now))
        XCTAssertEqual(CommunityFormat.coverRange(from: raw.coverFrom, to: raw.coverTo, language: .turkish), "18–19 Ocak")
    }

    func testPendingModerationMessage() async throws {
        let backend = makeBackend()
        await backend.setTrustScore(2, for: DemoData.meId)
        let model = CreatePostViewModel(kind: .question, spotId: nil, services: makeServices(backend))
        model.bodyText = "Kış için kulübe nereden alınır?"

        let result = await model.submit(near: .modaKadikoy)
        guard case .created(let id, true)? = result else { return XCTFail("inceleme bekleyen paylaşım oluşmalıydı") }
        XCTAssertEqual(result?.message, "Paylaşımın kısa bir incelemeden sonra görünecek.")
        XCTAssertEqual(result?.toastStyle, .info)
        let raw = await backend.rawPost(id)
        XCTAssertEqual(raw?.isPendingModeration, true)
    }

    func testDailyLimitMessage() async throws {
        let backend = makeBackend()
        for index in 0..<CommunityPolicy.dailyPostLimit {
            let outcome = try await backend.createPost(CommunityPostDraft(body: "Paylaşım \(index)", coordinate: .modaKadikoy))
            guard case .created = outcome else { return XCTFail("\(index). paylaşım oluşmalıydı") }
        }
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(backend))
        model.bodyText = validText

        let result = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(result, .limitReached(limit: 10))
        XCTAssertEqual(result?.message, "Bugün 10 paylaşım yaptın, yarın devam edebilirsin.")
        XCTAssertEqual(model.submitProblem, result?.message)
        XCTAssertEqual(model.visibleProblem(near: .modaKadikoy), result?.message)
        XCTAssertEqual(model.bodyText, validText, "taslak korunur")
    }

    func testRejectedContentAndServerSideInvalid() async {
        let backend = makeBackend()
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(backend))
        model.bodyText = "Kapları yine devirmişler amk"
        let rejected = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(rejected, .rejectedContent)
        XCTAssertEqual(model.submitProblem, MamaError.rejectedContent.userMessage)

        // Ön kontrolden geçen ama sunucunun bulamadığı nokta.
        model.bodyText = validText
        model.selectedSpotId = UUID()
        let invalid = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(invalid, .invalid(.spotNotFound))
        XCTAssertEqual(model.visibleProblem(near: .modaKadikoy), "Seçtiğin nokta artık görünmüyor.")
    }

    func testSignedOutSubmitFailsGently() async {
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(makeBackend(signedIn: false)))
        model.bodyText = validText
        let result = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(result, .failed(.notSignedIn))
        XCTAssertEqual(model.submitProblem, MamaError.notSignedIn.userMessage)
        XCTAssertEqual(result?.toastStyle, .warning)
    }

    func testPhotoIsUploadedOnceAcrossRetries() async throws {
        let backend = makeBackend()
        let stub = CommunityRepositoryStub(backend)
        let uploader = CommunityCountingUploader()
        var services = makeServices(backend)
        services.community = stub
        services.media = uploader
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: services)
        model.bodyText = validText
        model.setPhoto(Data([0xFF, 0xD8, 0xFF]))

        await stub.fail(.createPost, with: .offline)
        let failed = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(failed, .failed(.offline))
        XCTAssertEqual(model.submitProblem, MamaError.offline.userMessage)

        await stub.heal(.createPost)
        let retried = await model.submit(near: .modaKadikoy)
        guard case .created(let id, _)? = retried else { return XCTFail("yeniden denemede oluşmalıydı") }
        let uploads = await uploader.uploadCount
        XCTAssertEqual(uploads, 1)
        let raw = await backend.rawPost(id)
        XCTAssertNotNil(raw?.photoURL)
        XCTAssertNil(model.submitProblem)
    }

    func testOutcomeMapping() async {
        let id = UUID()
        XCTAssertEqual(CreatePostResult(.created(id: id, pendingModeration: false)), .created(id: id, pendingModeration: false))
        XCTAssertEqual(CreatePostResult(.rejectedContent), .rejectedContent)
        XCTAssertEqual(CreatePostResult(.limitReached(limit: 10)), .limitReached(limit: 10))
        XCTAssertEqual(CreatePostResult(.invalid(.coverDates)), .invalid(.coverDates))
        XCTAssertTrue(CreatePostResult.created(id: id, pendingModeration: true).isCreated)
        XCTAssertFalse(CreatePostResult.rejectedContent.isCreated)
        XCTAssertEqual(CreatePostResult.invalid(.coverDates).message, CommunityValidationError.coverDates.userMessage)
    }
}
