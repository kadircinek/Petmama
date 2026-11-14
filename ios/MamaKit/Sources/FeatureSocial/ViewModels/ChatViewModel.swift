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
    public private(set) var isReadOnly = false
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
                await self.refreshNewest()
            }
        }
        await loadSummary()
        await refreshNewest()
        canLoadOlder = messages.count >= Self.pageSize
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
        guard let summary = try? await services.social.conversations().first(where: { $0.id == conversationId }) else { return }
        title = summary.title
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
