import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class ChatViewModel {
    public let conversationId: UUID
    public static let pageSize = 50

    /// Eskiden yeniye.
    public private(set) var messages: [ChatMessage] = []
    public var draft = ""
    public private(set) var title = ""
    /// Tür, karşı taraf ve bağlı buluşma (başlık menüsü için); yüklenemezse `nil`.
    public private(set) var summary: ConversationSummary?
    public private(set) var isReadOnly = false
    /// Sohbet artık listede yok (engel, bağlantı kaldırıldı, buluşmadan çıkarıldı): mesajlar temizlenir, ekran kapanmalı.
    public private(set) var isHidden = false
    public private(set) var isSending = false
    public private(set) var canLoadOlder = false
    public private(set) var message: String?
    public var error: MamaError?
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    public init(services: AppServices, conversationId: UUID) {
        self.services = services
        self.conversationId = conversationId
    }

    public var canSend: Bool {
        !isReadOnly && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// İlk sayfayı yükler, okundu işaretler ve canlı sinyalleri dinlemeye başlar. Tekrar çağrılırsa dinleme yenilenir.
    public func start() async {
        stop()
        // Önce abone ol: ilk sayfa yüklenirken gelen sinyal kaybolmasın.
        let stream = services.chatUpdates.updates(conversationId: conversationId)
        updatesTask = Task { [weak self] in
            for await _ in stream {
                guard let self, !Task.isCancelled else { break }
                await self.refresh()
            }
        }
        await refresh()
        canLoadOlder = !isHidden && messages.count >= Self.pageSize
    }

    /// Sohbet özetini (salt okunur / gizlendi) yeniden denetler, görünürse en yeni sayfayı çeker. Her canlı sinyalde çalışır:
    /// açık sohbet engel, bağlantı kaldırma ya da buluşma iptalini bir sonraki yenilemede fark eder.
    public func refresh() async {
        await loadSummary()
        guard !isHidden else { return }
        await refreshNewest()
    }

    /// Listeyi sıfırdan yükler: `start()` birleştirdiği için gizlenen (ör. engellenen kişinin) mesajları düşürmez.
    public func restart() async {
        stop()
        messages = []
        hasMarkedRead = false
        await start()
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    public func send() async {
        guard canSend else { return }
        isSending = true
        message = nil
        error = nil
        defer { isSending = false }
        do {
            let outcome = try await services.social.sendMessage(conversationId: conversationId, body: draft)
            switch outcome {
            case .sent(let sent):
                draft = ""
                merge([sent])
            case .readOnly:
                isReadOnly = true
                message = SocialMessages.message(for: outcome)
            default:
                message = SocialMessages.message(for: outcome)
            }
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    public func loadOlder() async {
        guard canLoadOlder, let first = messages.first else { return }
        do {
            let older = try await services.social.messages(conversationId: conversationId, before: first.createdAt, limit: Self.pageSize)
            canLoadOlder = older.count >= Self.pageSize
            merge(older)
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    private func loadSummary() async {
        // Ağ hatasında durum korunur; yalnızca başarılı listede yoksa gizlenmiş sayılır.
        guard let list = try? await services.social.conversations() else { return }
        guard let summary = list.first(where: { $0.id == conversationId }) else {
            isHidden = true
            isReadOnly = true
            summary = nil
            messages = []
            canLoadOlder = false
            draft = ""
            return
        }
        isHidden = false
        self.summary = summary
        title = summary.displayTitle
        isReadOnly = summary.isReadOnly
    }

    /// En yeni sayfayı çeker; yeni mesaj varsa okundu işaretler.
    private func refreshNewest() async {
        do {
            let page = try await services.social.messages(conversationId: conversationId, before: nil, limit: Self.pageSize)
            let known = Set(messages.map(\.id))
            let hasNew = page.contains { !known.contains($0.id) }
            merge(page)
            if hasNew || !hasMarkedRead {
                hasMarkedRead = true
                try? await services.social.markConversationRead(id: conversationId)
            }
        } catch {
            self.error = MamaError.classify(error)
        }
    }

    @ObservationIgnored private var hasMarkedRead = false

    private func merge(_ incoming: [ChatMessage]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for item in incoming { byId[item.id] = item }
        messages = byId.values.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString
        }
    }
}
