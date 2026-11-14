import Foundation
import MamaCore

/// Testlerde ilerletilebilen saat.
final class SocialTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

let socialTestStart = Date(timeIntervalSince1970: 1_800_000_000)

struct SocialEnvironment {
    let backend: InMemoryBackend
    let services: AppServices
    let clock: SocialTestClock
}

/// Demo kullanıcısı oturum açık; `consented` ise sosyal onay verilmiş.
func makeSocialEnvironment(consented: Bool = true, tweakSeed: (inout DemoSeed) -> Void = { _ in }) async throws -> SocialEnvironment {
    let clock = SocialTestClock(socialTestStart)
    var seed = DemoData.make(now: clock.now)
    tweakSeed(&seed)
    let backend = InMemoryBackend(seed: seed, signedIn: true, now: { clock.now })
    if consented { _ = try await backend.giveSocialConsent() }
    return SocialEnvironment(backend: backend, services: AppServices.inMemory(backend, now: { clock.now }), clock: clock)
}
