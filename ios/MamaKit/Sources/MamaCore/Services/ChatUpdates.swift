import Foundation

/// Sohbet ekranına "yenile" sinyali. Her `Void` değeri yeni mesaj olabileceği anlamına gelir; ekran
/// mesajları repository'den yeniden okur. Supabase'de Realtime yayını, demoda bellek içi akış.
public protocol ChatUpdates: Sendable {
    func updates(conversationId: UUID) -> AsyncStream<Void>
}

/// Canlı akışı olmayan ortamlar için: belirli aralıklarla sinyal üretir.
public struct PollingChatUpdates: ChatUpdates {
    public let interval: Duration

    public init(interval: Duration = .seconds(5)) {
        self.interval = interval
    }

    public func updates(conversationId: UUID) -> AsyncStream<Void> {
        let interval = interval
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    if Task.isCancelled { break }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Sohbet başına abonelikler. Kilitli; actor dışından eşzamanlı (await'siz) kaydolunabilsin diye.
final class ChatUpdateHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: [UUID: AsyncStream<Void>.Continuation]] = [:]

    func stream(for conversationId: UUID) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        lock.withLock { continuations[conversationId, default: [:]][token] = continuation }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { _ = self.continuations[conversationId]?.removeValue(forKey: token) }
        }
        return stream
    }

    func notify(_ conversationId: UUID) {
        let targets = lock.withLock { continuations[conversationId].map { Array($0.values) } ?? [] }
        for continuation in targets { continuation.yield() }
    }
}
