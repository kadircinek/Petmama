import XCTest
import MamaCore
@testable import FeatureCommunity

/// Yükleme sayısını sayan fotoğraf yükleyici.
actor CommunityCountingUploader: MediaUploader {
    private(set) var uploadCount = 0

    func uploadJPEG(_ data: Data) async throws -> URL {
        uploadCount += 1
        return URL(fileURLWithPath: "/tmp/mahalle-\(uploadCount).jpg")
    }
}

@MainActor
final class CommunityCreatePostViewModelTests: XCTestCase {
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

    // MARK: - Başlangıç durumu

    func testDefaults() async {
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(makeBackend()))
        XCTAssertEqual(model.kind, .note)
        XCTAssertNil(model.selectedSpotId)
        XCTAssertFalse(model.isSpotRequired)
        XCTAssertFalse(model.hasDraftContent)
        XCTAssertEqual(model.remainingCharacters, CommunityPolicy.maxBodyLength)
        XCTAssertNil(model.visibleProblem(near: nil), "ilk denemeden önce uyarı yok")
        XCTAssertTrue(sameDay(model.coverFrom, day(1)))
        XCTAssertTrue(sameDay(model.coverTo, day(2)))

        let preset = CreatePostViewModel(kind: .coverRequest, spotId: parkSpotId, services: makeServices(makeBackend()))
        XCTAssertEqual(preset.kind, .coverRequest)
        XCTAssertEqual(preset.selectedSpotId, parkSpotId)
        XCTAssertTrue(preset.isSpotRequired)
    }

    func testDraftContentTracksTextAndPhoto() async {
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(makeBackend()))
        model.bodyText = "   "
        XCTAssertFalse(model.hasDraftContent)
        model.bodyText = "Merhaba"
        XCTAssertTrue(model.hasDraftContent)
        model.bodyText = ""
        model.setPhoto(Data([1, 2, 3]))
        XCTAssertTrue(model.hasDraftContent)
        model.removePhoto()
        XCTAssertFalse(model.hasDraftContent)
    }

    // MARK: - Ön kontrol

    func testEmptyBodyIsRejectedBeforeServer() async throws {
        let backend = makeBackend()
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(backend))
        model.bodyText = "  \n "

        let result = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(result, .invalid(.bodyEmpty))
        XCTAssertTrue(model.attemptedSubmit)
        XCTAssertEqual(model.visibleProblem(near: .modaKadikoy), "Birkaç kelime yazar mısın?")
        let feed = try await backend.feed(near: .modaKadikoy, radiusMeters: 3000, kind: nil, before: nil, limit: 50)
        XCTAssertEqual(feed.count, 5, "hiçbir şey oluşmadı")

        // Uyarı kullanıcı düzelttikçe canlı güncellenir.
        model.bodyText = validText
        XCTAssertNil(model.visibleProblem(near: .modaKadikoy))
    }

    func testTooLongBody() async {
        let model = CreatePostViewModel(kind: .question, spotId: nil, services: makeServices(makeBackend()))
        model.bodyText = String(repeating: "a", count: CommunityPolicy.maxBodyLength + 1)
        XCTAssertTrue(model.isOverLimit)
        XCTAssertEqual(model.remainingCharacters, -1)

        let result = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(result, .invalid(.bodyTooLong))
        XCTAssertEqual(result?.message, CommunityValidationError.bodyTooLong.userMessage)

        model.bodyText = String(repeating: "a", count: CommunityPolicy.maxBodyLength)
        XCTAssertFalse(model.isOverLimit)
        XCTAssertNil(model.validationError(near: .modaKadikoy))
    }

    func testCoverRequestNeedsSpot() async {
        let model = CreatePostViewModel(kind: .coverRequest, spotId: nil, services: makeServices(makeBackend()))
        model.bodyText = "Hafta sonu yokum, bakabilecek var mı?"

        let result = await model.submit(near: .modaKadikoy)
        XCTAssertEqual(result, .invalid(.coverNeedsSpot))
        XCTAssertEqual(model.visibleProblem(near: .modaKadikoy), "Hangi noktaya bakılacağını seçer misin?")

        model.toggleSpot(parkSpotId)
        XCTAssertNil(model.validationError(near: .modaKadikoy))
        model.toggleSpot(parkSpotId)
        XCTAssertNil(model.selectedSpotId, "aynı noktaya tekrar dokununca seçim kalkar")
    }

    func testCoverRequestBadDates() async {
        let model = CreatePostViewModel(kind: .coverRequest, spotId: parkSpotId, services: makeServices(makeBackend()))
        model.bodyText = "Hafta sonu yokum, bakabilecek var mı?"
        XCTAssertNil(model.validationError(near: nil))

        model.coverFrom = day(-1)
        XCTAssertEqual(model.validationError(near: nil), .coverDates, "geçmiş başlangıç")

        model.coverFrom = day(5)
        model.coverTo = day(3)
        let result = await model.submit(near: nil)
        XCTAssertEqual(result, .invalid(.coverDates), "bitiş başlangıçtan önce")

        model.coverFrom = day(1)
        model.coverTo = day(1 + CommunityPolicy.maxCoverDays + 1)
        XCTAssertEqual(model.validationError(near: nil), .coverDates, "30 günden uzun")
        model.coverTo = day(1 + CommunityPolicy.maxCoverDays)
        XCTAssertNil(model.validationError(near: nil))

        // Diğer türlerde tarihler yok sayılır.
        model.coverTo = day(-3)
        model.kind = .note
        XCTAssertNil(model.validationError(near: nil))
        XCTAssertNil(model.makeDraft(near: nil).coverFrom)
    }

    func testNormalizeCoverDatesPullsEndIntoRange() async {
        let model = CreatePostViewModel(kind: .coverRequest, spotId: parkSpotId, services: makeServices(makeBackend()))
        model.bodyText = "Bir hafta yokum."

        model.coverFrom = day(6)
        model.normalizeCoverDates()
        XCTAssertTrue(sameDay(model.coverTo, day(6)), "bitiş başlangıcın gerisinde kalamaz")
        XCTAssertNil(model.validationError(near: nil))

        model.coverTo = day(90)
        model.normalizeCoverDates()
        XCTAssertTrue(sameDay(model.coverTo, day(6 + CommunityPolicy.maxCoverDays)))
        XCTAssertNil(model.validationError(near: nil))

        model.coverFrom = day(-4)
        model.normalizeCoverDates()
        XCTAssertTrue(sameDay(model.coverFrom, day(0)), "başlangıç bugünden önce olamaz")
        XCTAssertNil(model.validationError(near: nil))
        XCTAssertTrue(model.coverToRange.contains(model.coverTo))
    }

    func testMissingLocationWithoutSpot() async {
        let model = CreatePostViewModel(kind: .supply, spotId: nil, services: makeServices(makeBackend()))
        model.bodyText = "Elimde iki fazla mama kabı var."

        let result = await model.submit(near: nil)
        XCTAssertEqual(result, .invalid(.locationMissing))
        XCTAssertEqual(model.visibleProblem(near: nil), CommunityValidationError.locationMissing.userMessage)

        // Konum gelince ya da nokta seçilince sorun kalkar.
        XCTAssertNil(model.visibleProblem(near: .modaKadikoy))
        model.toggleSpot(parkSpotId)
        XCTAssertNil(model.visibleProblem(near: nil))
    }

    func testExactLocationIsNotSentWhenSpotIsLinked() async {
        let model = CreatePostViewModel(kind: nil, spotId: nil, services: makeServices(makeBackend()))
        model.bodyText = validText
        XCTAssertEqual(model.makeDraft(near: .modaKadikoy).coordinate, .modaKadikoy)
        model.toggleSpot(parkSpotId)
        XCTAssertNil(model.makeDraft(near: .modaKadikoy).coordinate)
        XCTAssertEqual(model.makeDraft(near: .modaKadikoy).spotId, parkSpotId)
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
