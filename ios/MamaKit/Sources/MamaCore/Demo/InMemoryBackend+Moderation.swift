import Foundation

// Moderasyon (Faz 3.1) bellek içi implementasyonu. Sunucudaki kuralların aynası:
// supabase/migrations/20261117000026_moderation.sql ve supabase/tests/97_moderation.sql.

extension InMemoryBackend {
    struct ReportRecord {
        let id = UUID()
        /// Hesabını silen raporlayanda `nil`.
        var reporterId: UUID?
        var draft: ReportDraft
        var createdAt: Date
        var status: ModerationReportStatus = .open
        var resolvedAt: Date?
    }

    public struct ModerationActionRecord: Hashable, Sendable {
        public let id: UUID
        public var moderatorId: UUID?
        public var target: ReportTarget
        public var targetId: UUID
        public var ownerId: UUID?
        /// approve | remove | suspend | unsuspend
        public var action: String
        public var note: String?
        public var suspendDays: Int?
        public var createdAt: Date
    }

    struct Preview {
        var title: String?
        var body: String?
        var photoURL: URL?
        var ownerId: UUID?
        var found: Bool
        /// İnceleme durumu: pending / rejected (yalnızca durum taşıyan içerikte).
        var pending = false
        var rejected = false
    }

    // Test yardımcıları
    public func allModerationActions() -> [ModerationActionRecord] { moderationActions }
    public func setSuspendedUntil(_ date: Date?, for userId: UUID) { users[userId]?.suspendedUntil = date }
    /// Sunucudaki ham satır gibi (uzaklaştırma bitişi dahil).
    public func rawUser(_ id: UUID) -> UserProfile? { users[id] }

    // MARK: - Önizleme

    func moderationPreview(_ target: ReportTarget, _ id: UUID) -> Preview {
        switch target {
        case .spot:
            guard let spot = spots[id] else { return Preview(found: false) }
            return Preview(title: spot.title, body: spot.note, photoURL: spot.photoURL, ownerId: spot.createdBy, found: true,
                           rejected: rejectedSpotIds.contains(id))
        case .animal:
            guard let animal = animals[id] else { return Preview(found: false) }
            return Preview(title: animal.name, body: animal.about, photoURL: animal.photoURLs.first, ownerId: animal.createdBy, found: true)
        case .need:
            guard let need = needs[id] else { return Preview(found: false) }
            return Preview(title: need.type.rawValue, body: need.description, photoURL: need.photoURLs.first, ownerId: need.createdBy, found: true)
        case .checkin, .photo:
            if let checkIn = checkIns.first(where: { $0.id == id }) {
                return Preview(title: spots[checkIn.spotId]?.title, body: checkIn.kind.rawValue, photoURL: checkIn.photoURL,
                               ownerId: checkIn.userId, found: true)
            }
            if target == .photo, let spot = spots[id] {
                return Preview(title: spot.title, photoURL: spot.photoURL, ownerId: spot.createdBy, found: true)
            }
            return Preview(found: false)
        case .user:
            guard let user = users[id] else { return Preview(found: false) }
            return Preview(title: user.displayName, photoURL: user.avatarURL, ownerId: user.id, found: true)
        case .post:
            guard let post = posts[id] else { return Preview(found: false) }
            return Preview(title: post.kind.rawValue, body: post.body, photoURL: post.photoURL, ownerId: post.authorId, found: true,
                           pending: post.isPendingModeration, rejected: rejectedPostIds.contains(id))
        case .comment:
            guard let comment = commentsByPost.values.joined().first(where: { $0.id == id }) else { return Preview(found: false) }
            return Preview(body: comment.body, ownerId: comment.authorId, found: true,
                           pending: hiddenCommentIds.contains(id), rejected: rejectedCommentIds.contains(id))
        case .meetup:
            guard let meetup = meetups[id] else { return Preview(found: false) }
            return Preview(title: meetup.title, body: meetup.description, ownerId: meetup.organizerId, found: true)
        case .chatMessage:
            // Yalnızca raporlanan mesaj; sohbetin geri kalanı asla.
            guard let message = chatMessages.values.joined().first(where: { $0.id == id }) else { return Preview(found: false) }
            return Preview(body: message.body, ownerId: message.authorId, found: true,
                           pending: message.isPendingModeration, rejected: rejectedMessageIds.contains(id))
        }
    }

    func lastDecision(_ target: ReportTarget, _ id: UUID) -> ModerationActionRecord? {
        moderationActions.last { $0.target == target && $0.targetId == id && ($0.action == "approve" || $0.action == "remove") }
    }

    /// Sunucuda `private.moderation_restorable`.
    func isRestorable(_ target: ReportTarget, _ id: UUID) -> Bool {
        !(ModerationPolicy.nonRestorableTargets.contains(target)
          && moderationActions.contains { $0.target == target && $0.targetId == id && $0.action == "remove" })
    }

    func contentState(_ target: ReportTarget, _ id: UUID, _ preview: Preview) -> ModerationContentState {
        if target == .user { return preview.found ? .live : .gone }
        if !isRestorable(target, id) { return .removed }
        if lastDecision(target, id)?.action == "remove" { return .removed }
        if !preview.found { return .gone }
        if preview.rejected { return .removed }
        if preview.pending { return .pending }
        return .live
    }

    func makeCase(_ target: ReportTarget, _ id: UUID, records: [ReportRecord], decided: Bool) -> ModerationCase {
        let preview = moderationPreview(target, id)
        let decision = decided ? lastDecision(target, id) : nil
        let dates = records.map(\.createdAt)
        var reasons: [ReportReason] = []
        for reason in ReportReason.allCases where records.contains(where: { $0.draft.reason == reason }) {
            reasons.append(reason)
        }
        return ModerationCase(
            target: target,
            targetId: id,
            title: preview.title.map { String($0.prefix(ModerationPolicy.previewLength)) },
            body: preview.body.map { String($0.prefix(ModerationPolicy.previewLength)) },
            photoURL: preview.photoURL,
            ownerId: preview.ownerId,
            ownerName: preview.ownerId.flatMap { users[$0]?.displayName },
            reportCount: records.count,
            reasons: reasons,
            firstReportedAt: dates.min() ?? now(),
            lastReportedAt: dates.max() ?? now(),
            contentState: contentState(target, id, preview),
            decision: decision.flatMap { ModerationDecision(rawValue: $0.action) },
            decidedAt: decided ? (decision?.createdAt ?? records.compactMap(\.resolvedAt).max()) : nil,
            isRestorable: isRestorable(target, id)
        )
    }

    struct TargetKey: Hashable { let target: ReportTarget; let id: UUID }

    func groupedReports() -> [TargetKey: [ReportRecord]] {
        Dictionary(grouping: reportRecords) { TargetKey(target: $0.draft.target, id: $0.draft.targetId) }
    }
}

// MARK: - ModeratorRepository

extension InMemoryBackend: ModeratorRepository {
    public func openCaseCount() async throws -> Int {
        let me = try requireUser()
        guard isModerator(me) else { return 0 }
        return Set(reportRecords.filter { $0.status == .open }.map { TargetKey(target: $0.draft.target, id: $0.draft.targetId) }).count
    }

    public func moderationQueue(closed: Bool, limit: Int) async throws -> [ModerationCase] {
        let me = try requireUser()
        guard isModerator(me) else { return [] }
        let max = min(Swift.max(limit, 1), 200)
        let groups = groupedReports()
        if !closed {
            return groups
                .compactMap { key, records -> ModerationCase? in
                    let open = records.filter { $0.status == .open }
                    guard !open.isEmpty else { return nil }
                    return makeCase(key.target, key.id, records: open, decided: false)
                }
                .sorted {
                    if $0.reportCount != $1.reportCount { return $0.reportCount > $1.reportCount }
                    if $0.firstReportedAt != $1.firstReportedAt { return $0.firstReportedAt < $1.firstReportedAt }
                    return $0.targetId.uuidString < $1.targetId.uuidString
                }
                .prefix(max)
                .map { $0 }
        }
        let windowStart = now().addingTimeInterval(-Double(ModerationPolicy.closedWindowDays) * 86_400)
        return groups
            .compactMap { key, records -> (ModerationCase, Date)? in
                guard records.allSatisfy({ $0.status != .open }),
                      let closedAt = records.compactMap(\.resolvedAt).max(), closedAt >= windowStart else { return nil }
                return (makeCase(key.target, key.id, records: records, decided: true), closedAt)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.targetId.uuidString < $1.0.targetId.uuidString
            }
            .prefix(max)
            .map(\.0)
    }

    public func moderationCase(target: ReportTarget, id: UUID) async throws -> ModerationCaseDetail? {
        let me = try requireUser()
        guard isModerator(me) else { throw MamaError.permissionDenied }
        let records = reportRecords.filter { $0.draft.target == target && $0.draft.targetId == id }
        guard !records.isEmpty else { return nil }
        let open = records.filter { $0.status == .open }
        let summary = makeCase(target, id, records: open.isEmpty ? records : open, decided: open.isEmpty)
        let entries = records
            .sorted { $0.createdAt > $1.createdAt }
            .map {
                ModerationReportEntry(id: $0.id, reason: $0.draft.reason, details: $0.draft.details, createdAt: $0.createdAt,
                                      reporterId: $0.reporterId, reporterName: $0.reporterId.flatMap { users[$0]?.displayName },
                                      status: $0.status)
            }
        let owner = summary.ownerId.map { ownerId -> ModerationOwnerHistory in
            let windowStart = now().addingTimeInterval(-Double(ModerationPolicy.historyWindowDays) * 86_400)
            let recent = moderationActions.filter { $0.createdAt >= windowStart }
            let until = users[ownerId]?.suspendedUntil
            return ModerationOwnerHistory(
                userId: ownerId,
                displayName: users[ownerId]?.displayName,
                avatarURL: users[ownerId]?.avatarURL,
                isModerator: isModerator(ownerId),
                removedCount90d: recent.filter { $0.ownerId == ownerId && $0.action == "remove" && $0.target != .user }.count,
                suspensionCount90d: recent.filter { $0.target == .user && $0.targetId == ownerId && $0.action == "suspend" }.count,
                suspendedUntil: ModerationPolicy.isSuspended(until: until, now: now()) ? until : nil
            )
        }
        return ModerationCaseDetail(moderationCase: summary, reports: entries, owner: owner)
    }

    public func decide(target: ReportTarget, id: UUID, decision: ModerationDecision, note: String?) async throws -> ModerationOutcome {
        let me = try requireWriter()
        guard isModerator(me) else { return .notAllowed }
        let text = ModerationPolicy.normalizedNote(note)
        if (text?.count ?? 0) > ModerationPolicy.maxNoteLength { return .invalid(reason: "note_too_long") }
        guard reportRecords.contains(where: { $0.draft.target == target && $0.draft.targetId == id }) else { return .notFound }

        if decision == .approve, !isRestorable(target, id) { return .invalid(reason: "not_restorable") }
        let owner = moderationPreview(target, id).ownerId
        switch decision {
        case .approve: approveContent(target, id)
        case .remove: removeContent(target, id)
        }
        var closed = 0
        for index in reportRecords.indices
        where reportRecords[index].draft.target == target && reportRecords[index].draft.targetId == id && reportRecords[index].status == .open {
            reportRecords[index].status = decision == .approve ? .dismissed : .actioned
            reportRecords[index].resolvedAt = now()
            closed += 1
        }
        moderationActions.append(ModerationActionRecord(
            id: UUID(), moderatorId: me, target: target, targetId: id, ownerId: owner,
            action: decision.rawValue, note: text, suspendDays: nil, createdAt: now()
        ))
        return .done(closedReports: closed)
    }

    public func suspend(userId: UUID, length: SuspensionLength, note: String?) async throws -> SuspendOutcome {
        let me = try requireWriter()
        guard isModerator(me) else { return .notAllowed }
        guard let target = users[userId] else { return .notFound }
        guard userId != me, !target.isModerator else { return .notAllowed }
        let text = ModerationPolicy.normalizedNote(note)
        if (text?.count ?? 0) > ModerationPolicy.maxNoteLength { return .invalid(reason: "note_too_long") }
        let until = length.days.map { now().addingTimeInterval(Double($0) * 86_400) } ?? .distantFuture
        users[userId]?.suspendedUntil = until
        moderationActions.append(ModerationActionRecord(
            id: UUID(), moderatorId: me, target: .user, targetId: userId, ownerId: userId,
            action: "suspend", note: text, suspendDays: length.days, createdAt: now()
        ))
        return .suspended(until: until)
    }

    public func unsuspend(userId: UUID) async throws -> ModerationOutcome {
        let me = try requireWriter()
        guard isModerator(me) else { return .notAllowed }
        guard users[userId] != nil else { return .notFound }
        users[userId]?.suspendedUntil = nil
        moderationActions.append(ModerationActionRecord(
            id: UUID(), moderatorId: me, target: .user, targetId: userId, ownerId: userId,
            action: "unsuspend", note: nil, suspendDays: nil, createdAt: now()
        ))
        return .done(closedReports: 0)
    }
}

// MARK: - Kararların içeriğe etkisi

extension InMemoryBackend {
    /// Uygun: içerik onaylanır, otomatik gizlendiyse geri açılır.
    func approveContent(_ target: ReportTarget, _ id: UUID) {
        switch target {
        case .spot:
            rejectedSpotIds.remove(id)
        case .post:
            rejectedPostIds.remove(id)
            posts[id]?.isPendingModeration = false
        case .comment:
            rejectedCommentIds.remove(id)
            hiddenCommentIds.remove(id)
        case .chatMessage:
            rejectedMessageIds.remove(id)
            for (conversationId, list) in chatMessages {
                guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
                chatMessages[conversationId]?[index].isPendingModeration = false
            }
        default:
            break
        }
    }

    /// Kaldır: nokta/paylaşım/yorum/mesaj herkesten gizlenir; buluşma iptal; ihtiyaç ve hayvan silinir;
    /// check-in/fotoğrafın fotoğrafı temizlenir; kullanıcı raporunda içerik yok.
    func removeContent(_ target: ReportTarget, _ id: UUID) {
        switch target {
        case .spot:
            rejectedSpotIds.insert(id)
        case .post:
            rejectedPostIds.insert(id)
        case .comment:
            rejectedCommentIds.insert(id)
        case .chatMessage:
            rejectedMessageIds.insert(id)
        case .meetup:
            guard meetups[id] != nil else { return }
            meetups[id]?.status = .cancelled
            if let conversationId = meetupConversationId(id), conversationRecords[conversationId]?.closedAt == nil {
                conversationRecords[conversationId]?.closedAt = now()
            }
        case .need:
            needs[id] = nil
        case .animal:
            animals[id] = nil
            animalSpots = animalSpots.filter { $0.key.a != id }
        case .checkin, .photo:
            if let index = checkIns.firstIndex(where: { $0.id == id }) {
                checkIns[index].photoURL = nil
            } else if target == .photo {
                spots[id]?.photoURL = nil
            }
        case .user:
            break
        }
    }
}
