import Foundation
import MamaCore
import Supabase

/// Sohbet "yenile" sinyali: sunucunun `conversation:<uuid>` özel Realtime kanalına yaptığı `message`
/// yayınını dinler (yetki: `public.can_listen_conversation`). Abonelik kurulamazsa ya da koparsa
/// `fallback` (yoklama) akışına geçer; sohbet hiçbir durumda sinyalsiz kalmaz.
///
/// Sinyal yükü okunmaz: ekran mesajları repository'den yeniden okur.
public struct SupabaseChatUpdates: ChatUpdates {
    public let client: SupabaseClient
    public let fallback: PollingChatUpdates

    public init(client: SupabaseClient, fallback: PollingChatUpdates = PollingChatUpdates()) {
        self.client = client
        self.fallback = fallback
    }

    /// Sunucudaki yayın konusu (`uuid` küçük harf, `auth.uid()::text` gibi).
    static func topic(for conversationId: UUID) -> String {
        "conversation:\(conversationId.postgresString)"
    }

    public func updates(conversationId: UUID) -> AsyncStream<Void> {
        let client = client
        let fallback = fallback
        let topic = Self.topic(for: conversationId)
        return AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                await Self.run(client: client, topic: topic, fallback: fallback, conversationId: conversationId, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        client: SupabaseClient,
        topic: String,
        fallback: PollingChatUpdates,
        conversationId: UUID,
        continuation: AsyncStream<Void>.Continuation
    ) async {
        let channel = client.channel(topic) { $0.isPrivate = true }
        // Dinleyici abonelikten önce kaydedilir: katılma ile ilk yayın arasında olay kaçmaz.
        let broadcasts = channel.onBroadcast(event: "message") { _ in continuation.yield() }
        do {
            try await channel.subscribeWithError()
        } catch {
            broadcasts.cancel()
            await client.removeChannel(channel)
            await poll(fallback, conversationId: conversationId, continuation: continuation)
            return
        }
        // Abonelikten önce gelen mesajları yakalamak için bir kez yenile.
        continuation.yield()

        // Kanal koparsa (abonelik düştü) yoklamaya geç; aksi halde akış iptal edilene kadar bekler.
        for await status in channel.statusChange where status == .unsubscribed {
            guard !Task.isCancelled else { break }
            continuation.yield()
            await poll(fallback, conversationId: conversationId, continuation: continuation)
            break
        }
        broadcasts.cancel()
        await client.removeChannel(channel)
    }

    private static func poll(
        _ fallback: PollingChatUpdates,
        conversationId: UUID,
        continuation: AsyncStream<Void>.Continuation
    ) async {
        for await _ in fallback.updates(conversationId: conversationId) {
            if Task.isCancelled { return }
            continuation.yield()
        }
    }
}
