import Foundation

// Tanışma (buluşmalar, Hayvanseverler, sohbet) bellek içi implementasyonu. Sunucudaki kuralların aynası:
// supabase/migrations/20261114000020…23 ve supabase/tests/91–94. Bildirim üretimi (0024) yalnızca hesap silmedeki
// iptal bildirimi için aynalanır.
//
// Senaryolu demo davranışı saatten (`now()`) türetilir, zamanlayıcı yoktur:
//   * Senaryolu kullanıcıya giden istek, `gönderim + demoResponseDelay` geçince okumalarda kabul edilmiş görünür.
//   * Senaryolu kullanıcıyla bire bir sohbette her mesaja `createdAt + demoResponseDelay` damgalı hazır cevap
//     eklenir; zamanı gelene kadar hiçbir okumada görünmez.

extension InMemoryBackend {
    /// Senaryolu demo kullanıcılarının isteği kabul etme / cevap yazma gecikmesi.
    public static let demoResponseDelay: TimeInterval = 3

    struct SocialProfileRecord {
        var isVisible = false
        var about = ""
        var interests: [SocialInterest] = []
        /// Yuvarlanmış kaba konum.
        var cell: Coordinate?
        var consentedAt: Date?
    }

    enum ParticipantStatus { case joined, removed }

    struct ParticipantRecord {
        var userId: UUID
        var status: ParticipantStatus
        var joinedAt: Date
    }

    enum ConnectionStatus { case pending, accepted, declined, removed }

    struct ConnectionRecord {
        let id: UUID
        var requesterId: UUID
        var addresseeId: UUID
        var note: String
        var status: ConnectionStatus
        var createdAt: Date
        var respondedAt: Date?

        func involves(_ a: UUID, _ b: UUID) -> Bool {
            (requesterId == a && addresseeId == b) || (requesterId == b && addresseeId == a)
        }
    }

    struct ConversationRecord {
        let id: UUID
        var kind: ConversationKind
        var meetupId: UUID?
        var connectionId: UUID?
        var createdAt: Date
        var closedAt: Date?
        /// Üye → son okuma zamanı.
        var members: [UUID: Date]
    }
}

// MARK: - SocialRepository

extension InMemoryBackend: SocialRepository {
    // MARK: Profil

    public func socialProfile() async throws -> SocialProfile? {
        let me = try requireUser()
        return socialProfiles[me].map {
            SocialProfile(isVisible: $0.isVisible, about: $0.about, interests: $0.interests, hasConsented: $0.consentedAt != nil)
        }
    }

    public func giveSocialConsent() async throws -> SocialProfile {
        let me = try requireWriter()
        var record = socialProfiles[me] ?? SocialProfileRecord()
        record.consentedAt = record.consentedAt ?? now()
        socialProfiles[me] = record
        return SocialProfile(isVisible: record.isVisible, about: record.about, interests: record.interests, hasConsented: true)
    }

    public func updateSocialProfile(isVisible: Bool, about: String, interests: [SocialInterest], at coordinate: Coordinate?) async throws -> SocialProfileOutcome {
        let me = try requireUser()
        guard hasConsented(me), var record = socialProfiles[me] else {
            _ = try requireWriter()
            return .consentRequired
        }
        let text = SocialPolicy.trimmed(about)
        // Uzaklaştırılmış kişi yalnızca kendini gizleyebilir (hakkımda/ilgi aynı kalmalı): güvenlik eylemi.
        if isSuspended(me) {
            guard !isVisible, text == record.about, Set(interests) == Set(record.interests) else {
                _ = try requireWriter()
                return .saved
            }
            socialProfiles[me]?.isVisible = false
            return .saved
        }
        if SocialPolicy.length(text) > SocialPolicy.maxAbout { return .aboutTooLong }
        if ContentFilter.containsProfanity(text) { return .rejectedContent }
        if isVisible, coordinate == nil, record.cell == nil { return .locationRequired }

        var unique: [SocialInterest] = []
        for interest in interests where !unique.contains(interest) { unique.append(interest) }
        record.isVisible = isVisible
        record.about = text
        record.interests = unique
        if let coordinate { record.cell = SocialPolicy.roundedCell(coordinate) }
        socialProfiles[me] = record
        return .saved
    }

    // MARK: Buluşmalar

    public func meetups(near center: Coordinate, radiusMeters: Int) async throws -> [Meetup] {
        let me = try requireUser()
        guard (1...50_000).contains(radiusMeters) else { throw MamaError.invalidInput("invalid_radius") }
        return meetups.values
            .filter { $0.status == .active && $0.endsAt > now() }
            .compactMap { presentMeetup($0, viewer: me, origin: center) }
            .filter { ($0.distanceMeters ?? .infinity) <= Double(radiusMeters) }
            .sorted {
                if $0.distanceMeters != $1.distanceMeters { return ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
                if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(100)
            .map { $0 }
    }

    public func meetup(id: UUID, near center: Coordinate?) async throws -> Meetup? {
        let me = try requireUser()
        return meetups[id].flatMap { presentMeetup($0, viewer: me, origin: center) }
    }

    public func meetupParticipants(meetupId: UUID) async throws -> [MeetupParticipant] {
        let me = try requireUser()
        guard let meetup = meetups[meetupId], isJoined(me, meetupId) else { return [] }
        return (participantsByMeetup[meetupId] ?? [])
            .filter { $0.status == .joined && ($0.userId == me || !isBlocked(me, $0.userId)) }
            .sorted {
                let a = $0.userId == meetup.organizerId, b = $1.userId == meetup.organizerId
                if a != b { return a }
                if $0.joinedAt != $1.joinedAt { return $0.joinedAt < $1.joinedAt }
                return $0.userId.uuidString < $1.userId.uuidString
            }
            .compactMap { record in
                users[record.userId].map {
                    MeetupParticipant(id: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL,
                                      isVerifiedFeeder: $0.isVerifiedFeeder, isOrganizer: $0.id == meetup.organizerId)
                }
            }
    }

    public func createMeetup(_ draft: MeetupDraft) async throws -> CreateMeetupOutcome {
        let me = try requireWriter()
        guard let organizer = users[me] else { throw MamaError.notSignedIn }
        guard hasConsented(me) else { return .consentRequired }

        // Sunucudaki sıra: metin uzunlukları → küfür → günlük sınır → zaman/süre/kişi → nokta.
        let title = SocialPolicy.trimmed(draft.title)
        let description = SocialPolicy.trimmed(draft.description)
        let place = SocialPolicy.trimmed(draft.placeName)
        if !SocialPolicy.titleLength.contains(SocialPolicy.length(title)) { return .invalid(.titleLength) }
        if SocialPolicy.length(description) > SocialPolicy.maxDescription { return .invalid(.descriptionTooLong) }
        if !SocialPolicy.placeNameLength.contains(SocialPolicy.length(place)) { return .invalid(.placeNameLength) }
        if [title, description, place].contains(where: ContentFilter.containsProfanity) { return .rejectedContent }

        let today = istanbulCalendar().startOfDay(for: now())
        if meetups.values.filter({ $0.organizerId == me && !$0.isTour && $0.createdAt >= today }).count >= SocialPolicy.dailyMeetups {
            return .limitReached(SocialPolicy.dailyMeetups)
        }
        if let reason = SocialPolicy.validate(draft, now: now()) { return .invalid(reason) }
        if let spotId = draft.spotId {
            guard let raw = spots[spotId], present(raw) != nil else { return .invalid(.spotNotFound) }
        }

        let meetup = Meetup(
            title: title, description: description, startsAt: draft.startsAt,
            endsAt: draft.startsAt.addingTimeInterval(TimeInterval(draft.durationMinutes) * 60),
            placeName: place, coordinate: draft.coordinate, spotId: draft.spotId, capacity: draft.capacity,
            organizerId: me, organizerName: organizer.displayName, createdAt: now()
        )
        meetups[meetup.id] = meetup
        participantsByMeetup[meetup.id] = [ParticipantRecord(userId: me, status: .joined, joinedAt: now())]
        let conversation = ConversationRecord(id: UUID(), kind: .meetup, meetupId: meetup.id, createdAt: now(), members: [me: now()])
        conversationRecords[conversation.id] = conversation
        return .created(meetupId: meetup.id, conversationId: conversation.id)
    }

    public func joinMeetup(id: UUID) async throws -> JoinMeetupOutcome {
        let me = try requireWriter()
        guard hasConsented(me) else { return .consentRequired }
        guard let meetup = meetups[id], !isBlocked(me, meetup.organizerId) else { return .notFound }
        if meetup.status == .cancelled { return .cancelled }
        if meetup.endsAt <= now() { return .ended }
        guard let conversationId = meetupConversationId(id) else { return .notFound }

        let list = participantsByMeetup[id] ?? []
        if let existing = list.first(where: { $0.userId == me }) {
            return existing.status == .removed ? .removed : .joined(conversationId: conversationId)
        }
        if let capacity = meetup.capacity, list.filter({ $0.status == .joined }).count >= capacity { return .full }

        participantsByMeetup[id, default: []].append(ParticipantRecord(userId: me, status: .joined, joinedAt: now()))
        if conversationRecords[conversationId]?.members[me] == nil {
            conversationRecords[conversationId]?.members[me] = now()
        }
        return .joined(conversationId: conversationId)
    }

    public func leaveMeetup(id: UUID) async throws -> Bool {
        let me = try requireUser()
        guard let meetup = meetups[id] else { return true }
        if meetup.organizerId == me { return false }
        participantsByMeetup[id]?.removeAll { $0.userId == me && $0.status == .joined }
        if let conversationId = meetupConversationId(id) { conversationRecords[conversationId]?.members[me] = nil }
        return true
    }

    public func removeParticipant(meetupId: UUID, userId: UUID) async throws -> Bool {
        let me = try requireWriter()
        guard let meetup = meetups[meetupId], meetup.organizerId == me, userId != me,
              let index = participantsByMeetup[meetupId]?.firstIndex(where: { $0.userId == userId && $0.status == .joined })
        else { return false }
        participantsByMeetup[meetupId]?[index].status = .removed
        if let conversationId = meetupConversationId(meetupId) { conversationRecords[conversationId]?.members[userId] = nil }
        return true
    }

    public func cancelMeetup(id: UUID) async throws -> Bool {
        let me = try requireUser()
        guard let meetup = meetups[id], meetup.organizerId == me else { return false }
        if meetup.status == .cancelled { return true }
        if meetup.endsAt <= now() { return false }
        meetups[id]?.status = .cancelled
        if let conversationId = meetupConversationId(id) { conversationRecords[conversationId]?.closedAt = now() }
        return true
    }

    /// Sunucudaki sıra: onay → süre → nokta (aktif, görünür, `public`) → açık tur → günlük tur sınırı.
    public func startFeedingTour(spotId: UUID, durationMinutes: Int) async throws -> StartTourOutcome {
        let me = try requireWriter()
        guard let organizer = users[me] else { throw MamaError.notSignedIn }
        guard hasConsented(me) else { return .consentRequired }
        guard SocialPolicy.tourDurationRange.contains(durationMinutes) else { return .durationRange }
        guard let raw = spots[spotId], raw.visibility == .public, let spot = present(raw) else { return .spotNotFound }

        if meetups.values.contains(where: { $0.organizerId == me && $0.isTour && $0.status == .active && $0.endsAt > now() }) {
            return .alreadyTouring
        }
        let today = istanbulCalendar().startOfDay(for: now())
        if meetups.values.filter({ $0.organizerId == me && $0.isTour && $0.createdAt >= today }).count >= SocialPolicy.dailyTours {
            return .limitReached(SocialPolicy.dailyTours)
        }

        let place = SocialPolicy.prefix(SocialPolicy.trimmed(spot.title), maxLength: SocialPolicy.placeNameLength.upperBound)
        let tour = Meetup(
            title: SocialPolicy.tourTitle(spotTitle: place), startsAt: now(),
            endsAt: now().addingTimeInterval(TimeInterval(durationMinutes) * 60),
            placeName: place, coordinate: raw.coordinate, spotId: spotId,
            organizerId: me, organizerName: organizer.displayName, createdAt: now(), isTour: true
        )
        meetups[tour.id] = tour
        participantsByMeetup[tour.id] = [ParticipantRecord(userId: me, status: .joined, joinedAt: now())]
        let conversation = ConversationRecord(id: UUID(), kind: .meetup, meetupId: tour.id, createdAt: now(), members: [me: now()])
        conversationRecords[conversation.id] = conversation
        return .started(meetupId: tour.id, conversationId: conversation.id)
    }

    // MARK: Hayvanseverler

    public func animalLovers(interest: SocialInterest?) async throws -> [AnimalLover] {
        let me = try requireUser()
        settleScriptedConnections()
        guard hasConsented(me), let mine = socialProfiles[me], mine.isVisible, let myCell = mine.cell else { return [] }
        let monthAgo = now().addingTimeInterval(-30 * 86_400)
        let today = istanbulCalendar().startOfDay(for: now())

        return socialProfiles.compactMap { userId, record -> (AnimalLover, Double)? in
            guard userId != me, record.isVisible, record.consentedAt != nil, let cell = record.cell,
                  let user = users[userId], !isBlocked(me, userId) else { return nil }
            if let interest, !record.interests.contains(interest) { return nil }
            let meters = GeoMath.distance(myCell, cell)
            guard let band = SocialPolicy.band(meters: meters) else { return nil }
            let lover = AnimalLover(
                id: userId,
                displayName: user.displayName,
                avatarURL: user.avatarURL,
                about: record.about,
                interests: record.interests,
                isVerifiedFeeder: user.isVerifiedFeeder,
                fedLast30Days: checkIns.filter { $0.userId == userId && $0.kind == .fed && $0.createdAt >= monthAgo }.count,
                distanceBand: band,
                sharedInterestCount: record.interests.filter { mine.interests.contains($0) }.count,
                connection: connectionState(between: me, and: userId),
                fedToday: fedToday(userId, since: today),
                onTourMeetupId: activeTour(of: userId)?.id
            )
            return (lover, meters)
        }
        .map(\.0)
        .sorted {
            if $0.isOnTour != $1.isOnTour { return $0.isOnTour }
            if $0.fedToday != $1.fedToday { return $0.fedToday }
            if $0.distanceBand != $1.distanceBand { return $0.distanceBand.rank < $1.distanceBand.rank }
            if $0.sharedInterestCount != $1.sharedInterestCount { return $0.sharedInterestCount > $1.sharedInterestCount }
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.id.uuidString < $1.id.uuidString
        }
        .prefix(100)
        .map { $0 }
    }

    public func sendConnectionRequest(to userId: UUID, note: String?) async throws -> SendRequestOutcome {
        let me = try requireWriter()
        settleScriptedConnections()
        guard hasConsented(me) else { return .consentRequired }
        guard socialProfiles[me]?.isVisible == true else { return .notVisible }
        guard userId != me, users[userId] != nil, !isBlocked(me, userId) else { return .notFound }
        guard let target = socialProfiles[userId], target.isVisible, target.consentedAt != nil else { return .notVisible }

        let existing = connection(between: me, and: userId)
        if let existing {
            switch existing.status {
            case .accepted: return .alreadyConnected
            case .declined where existing.requesterId == me && isInCooldown(existing): return .cooldown
            case .pending where existing.requesterId == me: return .alreadyPending
            default: break
            }
        }
        let text = SocialPolicy.trimmed(note ?? "")
        if SocialPolicy.length(text) > SocialPolicy.maxNote { return .noteTooLong }
        if ContentFilter.containsProfanity(text) { return .rejectedContent }

        // Karşı taraf zaten istek atmışsa otomatik kabul (gönderim sayılmaz; günlük sınırdan önce).
        if let existing, existing.status == .pending, existing.requesterId == userId {
            connections[existing.id]?.status = .accepted
            connections[existing.id]?.respondedAt = now()
            let conversationId = openDirectConversation(connectionId: existing.id, me, userId, at: now())
            return .autoAccepted(conversationId: conversationId)
        }

        let today = istanbulCalendar().startOfDay(for: now())
        if (requestSends[me] ?? []).filter({ $0 >= today }).count >= SocialPolicy.dailyRequests {
            return .limitReached(SocialPolicy.dailyRequests)
        }

        let requestId: UUID
        if let existing {
            // Yok sayılan satır (kaldırılmış / eski ya da benim reddettiğim) sıfırlanır: çift tekil kalır.
            requestId = existing.id
            connections[existing.id] = ConnectionRecord(
                id: existing.id, requesterId: me, addresseeId: userId, note: text, status: .pending, createdAt: now()
            )
        } else {
            requestId = UUID()
            connections[requestId] = ConnectionRecord(
                id: requestId, requesterId: me, addresseeId: userId, note: text, status: .pending, createdAt: now()
            )
        }
        requestSends[me, default: []].append(now())
        return .sent(requestId: requestId)
    }

    public func respondToConnection(requestId: UUID, accept: Bool) async throws -> UUID? {
        // Reddetmek bir güvenlik eylemi: uzaklaştırmada da açık; kabul etmek yazmadır.
        let me = accept ? try requireWriter() : try requireUser()
        settleScriptedConnections()
        guard let request = connections[requestId], request.addresseeId == me, request.status == .pending,
              !isBlocked(me, request.requesterId) else { return nil }
        connections[requestId]?.respondedAt = now()
        guard accept else {
            connections[requestId]?.status = .declined
            return nil
        }
        connections[requestId]?.status = .accepted
        return openDirectConversation(connectionId: requestId, request.requesterId, me, at: now())
    }

    public func withdrawConnectionRequest(id: UUID) async throws {
        let me = try requireUser()
        settleScriptedConnections()
        guard let request = connections[id], request.requesterId == me, request.status == .pending else { return }
        deleteConnection(id)
    }

    public func removeConnection(userId: UUID) async throws {
        let me = try requireUser()
        settleScriptedConnections()
        guard let existing = connection(between: me, and: userId), existing.status == .accepted else { return }
        connections[existing.id]?.status = .removed
        closeDirectConversation(of: existing.id)
    }

    public func incomingConnectionRequests() async throws -> [ConnectionRequest] {
        let me = try requireUser()
        settleScriptedConnections()
        guard hasConsented(me) else { return [] }
        return connections.values
            .filter { $0.addresseeId == me && $0.status == .pending && !isBlocked(me, $0.requesterId) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .compactMap { request in
                guard let user = users[request.requesterId] else { return nil }
                let profile = socialProfiles[request.requesterId]
                return ConnectionRequest(
                    id: request.id, userId: user.id, displayName: user.displayName, avatarURL: user.avatarURL,
                    about: profile?.about ?? "", interests: profile?.interests ?? [], isVerifiedFeeder: user.isVerifiedFeeder,
                    note: request.note.isEmpty ? nil : request.note, createdAt: request.createdAt
                )
            }
    }

    // MARK: Sohbet

    public func conversations() async throws -> [ConversationSummary] {
        let me = try requireUser()
        settleScriptedConnections()
        guard hasConsented(me) else { return [] }
        return conversationRecords.values
            .filter { $0.members[me] != nil && conversationVisible($0, to: me) }
            .map { conversation -> (ConversationSummary, Date) in
                let visible = visibleMessages(in: conversation.id, viewer: me)
                let last = visible.last
                let lastRead = conversation.members[me] ?? .distantPast
                let other = conversation.kind == .direct ? otherMember(of: conversation, than: me) : nil
                let otherUser = other.flatMap { users[$0] }
                let title: String
                switch conversation.kind {
                case .meetup: title = conversation.meetupId.flatMap { meetups[$0]?.title } ?? ""
                case .direct: title = otherUser?.displayName ?? "Silinmiş kullanıcı"
                }
                let summary = ConversationSummary(
                    id: conversation.id,
                    kind: conversation.kind,
                    title: title,
                    meetupId: conversation.meetupId,
                    otherUserId: otherUser?.id,
                    otherAvatarURL: otherUser?.avatarURL,
                    lastBody: last?.body,
                    lastAt: last?.createdAt,
                    unreadCount: visible.filter { $0.createdAt > lastRead && $0.authorId != me }.count,
                    isReadOnly: conversationReadOnly(conversation, for: me)
                )
                return (summary, last?.createdAt ?? conversation.createdAt)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.id.uuidString > $1.0.id.uuidString
            }
            .prefix(200)
            .map(\.0)
    }

    public func messages(conversationId: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        let me = try requireUser()
        settleScriptedConnections()
        guard hasConsented(me), let conversation = conversationRecords[conversationId],
              conversation.members[me] != nil, conversationVisible(conversation, to: me) else { return [] }
        let page = visibleMessages(in: conversationId, viewer: me)
            .filter { message in before.map { message.createdAt < $0 } ?? true }
            .suffix(min(max(limit, 1), 100))
        return Array(page)
    }

    public func sendMessage(conversationId: UUID, body: String) async throws -> SendMessageOutcome {
        let me = try requireWriter()
        settleScriptedConnections()
        // Onay yoksa üyelik de olamaz (protokolde ayrı bir sonuç yok).
        guard hasConsented(me), let conversation = conversationRecords[conversationId],
              conversation.members[me] != nil, let author = users[me] else { return .notMember }
        if conversationReadOnly(conversation, for: me) || !conversationVisible(conversation, to: me) { return .readOnly }

        let text = SocialPolicy.trimmed(body)
        if text.isEmpty { return .bodyEmpty }
        if SocialPolicy.length(text) > SocialPolicy.maxMessage { return .bodyTooLong }
        if ContentFilter.containsProfanity(text) { return .rejectedContent }

        let minuteAgo = now().addingTimeInterval(-60)
        let today = istanbulCalendar().startOfDay(for: now())
        let inThisChat = (chatMessages[conversationId] ?? []).filter { $0.authorId == me && $0.createdAt > minuteAgo }.count
        let todayTotal = chatMessages.values.joined().filter { $0.authorId == me && $0.createdAt >= today }.count
        if inThisChat >= SocialPolicy.perMinute || todayTotal >= SocialPolicy.perDay { return .rateLimited }

        let message = ChatMessage(authorId: me, authorName: author.displayName, authorAvatarURL: author.avatarURL,
                                  body: text, createdAt: now())
        chatMessages[conversationId, default: []].append(message)
        scheduleCannedReply(in: conversation, to: message)
        chatHub.notify(conversationId)
        return .sent(message)
    }

    public func markConversationRead(id: UUID) async throws {
        let me = try requireUser()
        guard let lastRead = conversationRecords[id]?.members[me] else { return }
        conversationRecords[id]?.members[me] = max(lastRead, now())
    }
}

// MARK: - ChatUpdates

extension InMemoryBackend: ChatUpdates {
    /// Bu sohbete mesaj eklendiğinde (kullanıcının kendi mesajı dahil) sinyal verir.
    public nonisolated func updates(conversationId: UUID) -> AsyncStream<Void> {
        chatHub.stream(for: conversationId)
    }
}

// MARK: - Kurallar

extension InMemoryBackend {
    func hasConsented(_ userId: UUID) -> Bool {
        socialProfiles[userId]?.consentedAt != nil
    }

    func isJoined(_ userId: UUID, _ meetupId: UUID) -> Bool {
        (participantsByMeetup[meetupId] ?? []).contains { $0.userId == userId && $0.status == .joined }
    }

    /// Bugün "mama/su koydum" check-in'i ya da açılmış bir tur (sunucuda `animal_lovers_near.fed_today`).
    func fedToday(_ userId: UUID, since today: Date) -> Bool {
        checkIns.contains { $0.userId == userId && ($0.kind == .fed || $0.kind == .water) && $0.createdAt >= today }
            || meetups.values.contains { $0.organizerId == userId && $0.isTour && $0.createdAt >= today }
    }

    /// Kişinin şu an açık turu (en son başlayan).
    func activeTour(of userId: UUID) -> Meetup? {
        meetups.values
            .filter { $0.organizerId == userId && $0.isTour && $0.status == .active && $0.startsAt <= now() && $0.endsAt > now() }
            .max { ($0.startsAt, $1.id.uuidString) < ($1.startsAt, $0.id.uuidString) }
    }

    func meetupConversationId(_ meetupId: UUID) -> UUID? {
        conversationRecords.values.first { $0.meetupId == meetupId }?.id
    }

    func presentMeetup(_ meetup: Meetup, viewer: UUID, origin: Coordinate?) -> Meetup? {
        guard let organizer = users[meetup.organizerId], !isBlocked(viewer, meetup.organizerId) else { return nil }
        var result = meetup
        result.organizerName = organizer.displayName
        result.organizerAvatarURL = organizer.avatarURL
        result.organizerIsVerified = organizer.isVerifiedFeeder
        if let spotId = meetup.spotId, let raw = spots[spotId], let spot = present(raw) {
            result.spotTitle = spot.title
        } else {
            result.spotId = nil
            result.spotTitle = nil
        }
        let list = participantsByMeetup[meetup.id] ?? []
        result.participantCount = list.filter { $0.status == .joined }.count
        if meetup.organizerId == viewer {
            result.viewerRole = .organizer
        } else if let mine = list.first(where: { $0.userId == viewer }) {
            result.viewerRole = mine.status == .joined ? .participant : .removed
        } else {
            result.viewerRole = .none
        }
        let isMember = result.viewerRole == .organizer || result.viewerRole == .participant
        result.conversationId = isMember ? meetupConversationId(meetup.id) : nil
        result.distanceMeters = origin.map { GeoMath.distance($0, meetup.coordinate) }
        return result
    }

    func connection(between a: UUID, and b: UUID) -> ConnectionRecord? {
        connections.values.first { $0.involves(a, b) }
    }

    func isInCooldown(_ record: ConnectionRecord) -> Bool {
        guard let respondedAt = record.respondedAt else { return false }
        return respondedAt > now().addingTimeInterval(-TimeInterval(SocialPolicy.cooldownDays) * 86_400)
    }

    func connectionState(between me: UUID, and other: UUID) -> ConnectionState {
        guard let record = connection(between: me, and: other) else { return .none }
        switch record.status {
        case .accepted:
            guard let conversationId = conversationRecords.values.first(where: { $0.connectionId == record.id })?.id else { return .none }
            return .connected(conversationId: conversationId)
        case .pending:
            return record.requesterId == me ? .outgoingPending(requestId: record.id) : .incomingPending(requestId: record.id)
        case .declined where record.requesterId == me && isInCooldown(record):
            // Reddedilen taraf, bekleme süresince isteğini hâlâ bekliyor görür.
            return .outgoingPending(requestId: record.id)
        default:
            return .none
        }
    }

    /// Bağlantının bire bir sohbetini açar (varsa yeniden açar) ve iki üyeyi ekler.
    @discardableResult
    func openDirectConversation(connectionId: UUID, _ a: UUID, _ b: UUID, at date: Date) -> UUID {
        var conversation = conversationRecords.values.first { $0.connectionId == connectionId }
            ?? ConversationRecord(id: UUID(), kind: .direct, connectionId: connectionId, createdAt: date, members: [:])
        conversation.closedAt = nil
        for member in [a, b] where conversation.members[member] == nil { conversation.members[member] = date }
        conversationRecords[conversation.id] = conversation
        return conversation.id
    }

    func closeDirectConversation(of connectionId: UUID) {
        for (id, conversation) in conversationRecords where conversation.connectionId == connectionId && conversation.closedAt == nil {
            conversationRecords[id]?.closedAt = now()
        }
    }

    /// Bağlantı satırı silinir. Kabul edilmemişse bire bir sohbeti de silinir (yetim kalıp geri görünmesin);
    /// kabul edilmişse (yalnızca hesap silmede) sohbet kalan kişi için bağlantısız kalır.
    func deleteConnection(_ id: UUID) {
        guard let record = connections.removeValue(forKey: id) else { return }
        for (conversationId, conversation) in conversationRecords where conversation.connectionId == id {
            if record.status == .accepted {
                conversationRecords[conversationId]?.connectionId = nil
            } else {
                conversationRecords[conversationId] = nil
                chatMessages[conversationId] = nil
            }
        }
    }

    /// Senaryolu kullanıcıya giden bekleyen istekler, gecikme dolunca kabul edilir.
    func settleScriptedConnections() {
        for record in connections.values where record.status == .pending && scriptedSocialUsers.contains(record.addresseeId) {
            let acceptedAt = record.createdAt.addingTimeInterval(Self.demoResponseDelay)
            guard now() >= acceptedAt, !isBlocked(record.requesterId, record.addresseeId) else { continue }
            connections[record.id]?.status = .accepted
            connections[record.id]?.respondedAt = acceptedAt
            openDirectConversation(connectionId: record.id, record.requesterId, record.addresseeId, at: acceptedAt)
        }
    }

    func scheduleCannedReply(in conversation: ConversationRecord, to message: ChatMessage) {
        guard conversation.kind == .direct, let other = otherMember(of: conversation, than: message.authorId),
              scriptedSocialUsers.contains(other), let author = users[other], !DemoData.cannedReplies.isEmpty else { return }
        let body = DemoData.cannedReplies[cannedReplyIndex % DemoData.cannedReplies.count]
        cannedReplyIndex += 1
        chatMessages[conversation.id, default: []].append(ChatMessage(
            authorId: other, authorName: author.displayName, authorAvatarURL: author.avatarURL,
            body: body, createdAt: message.createdAt.addingTimeInterval(Self.demoResponseDelay)
        ))
        // Görünürlük `now()`'a bağlı kalır; yalnızca "yenile" sinyali duvar saatiyle zamanlanır, böylece açık sohbet
        // ekranı cevap vakti gelince yeniden okur.
        let hub = chatHub
        let conversationId = conversation.id
        let delay = replySignalDelay
        Task.detached {
            try? await Task.sleep(for: delay)
            hub.notify(conversationId)
        }
    }

    /// Test yardımcısı: hazır cevap sinyalinin gecikmesi (varsayılan `demoResponseDelay`).
    public func setReplySignalDelay(_ delay: Duration) { replySignalDelay = delay }

    func otherMember(of conversation: ConversationRecord, than me: UUID) -> UUID? {
        conversation.members.keys.filter { $0 != me }.min { $0.uuidString < $1.uuidString }
    }

    /// Üyelik + bire bir için bağlantı/engel durumu (sunucuda `private.conversation_visible`).
    func conversationVisible(_ conversation: ConversationRecord, to me: UUID) -> Bool {
        guard conversation.members[me] != nil else { return false }
        switch conversation.kind {
        case .meetup:
            return true
        case .direct:
            if let connectionId = conversation.connectionId {
                guard connections[connectionId]?.status == .accepted else { return false }
                return !(otherMember(of: conversation, than: me).map { isBlocked(me, $0) } ?? false)
            }
            // Bağlantı satırı yok: yalnızca karşı taraf hesabını sildiyse görünür.
            return conversation.members.count < 2
        }
    }

    /// Sunucuda `private.conversation_read_only`.
    func conversationReadOnly(_ conversation: ConversationRecord, for me: UUID) -> Bool {
        if conversation.closedAt != nil { return true }
        switch conversation.kind {
        case .meetup:
            guard let meetup = conversation.meetupId.flatMap({ meetups[$0] }) else { return true }
            return meetup.status == .cancelled || meetup.endsAt.addingTimeInterval(SocialPolicy.readOnlyAfterEnd) < now()
        case .direct:
            guard conversation.members.count >= 2, let connectionId = conversation.connectionId,
                  connections[connectionId]?.status == .accepted else { return true }
            return otherMember(of: conversation, than: me).map { isBlocked(me, $0) } ?? false
        }
    }

    /// İnceleme (yalnızca yazarına), engel ve zamanı gelmemiş senaryolu cevaplar süzülür; eskiden yeniye.
    func visibleMessages(in conversationId: UUID, viewer: UUID) -> [ChatMessage] {
        (chatMessages[conversationId] ?? [])
            .filter { $0.createdAt <= now() }
            .filter { !$0.isPendingModeration || $0.authorId == viewer }
            .filter { !rejectedMessageIds.contains($0.id) }
            .filter { $0.authorId == viewer || !isBlocked(viewer, $0.authorId) }
            .compactMap { message -> ChatMessage? in
                guard let author = users[message.authorId] else { return nil }
                var copy = message
                copy.authorName = author.displayName
                copy.authorAvatarURL = author.avatarURL
                return copy
            }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func markChatMessagePending(_ id: UUID) {
        for (conversationId, list) in chatMessages {
            guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
            chatMessages[conversationId]?[index].isPendingModeration = true
        }
    }

    /// Engel kancası (sunucuda `private.apply_block_to_social`).
    func applyBlockToSocial(blocker: UUID, blocked: UUID) {
        for record in connections.values where record.involves(blocker, blocked) {
            switch record.status {
            case .pending: deleteConnection(record.id)
            case .accepted: connections[record.id]?.status = .removed
            default: break
            }
            closeDirectConversation(of: record.id)
        }
        // Engelleyen düzenleyense engellenen onun buluşmalarından çıkarılır.
        for meetup in meetups.values where meetup.organizerId == blocker {
            if let index = participantsByMeetup[meetup.id]?.firstIndex(where: { $0.userId == blocked && $0.status == .joined }) {
                participantsByMeetup[meetup.id]?[index].status = .removed
            }
            if let conversationId = meetupConversationId(meetup.id) {
                conversationRecords[conversationId]?.members[blocked] = nil
            }
        }
        // Engellenen düzenleyense engelleyen onun buluşmalarından `leaveMeetup` gibi ayrılır (buluşma artık ona
        // gizli; "Ayrıl" göremez, grup sohbeti ve bildirimleri kalmasın). Yeniden katılabilir (engel kalkarsa).
        for meetup in meetups.values where meetup.organizerId == blocked {
            participantsByMeetup[meetup.id]?.removeAll { $0.userId == blocker && $0.status == .joined }
            if let conversationId = meetupConversationId(meetup.id) {
                conversationRecords[conversationId]?.members[blocker] = nil
            }
        }
    }

    /// Hesap silme: kişisel sosyal veri silinir; düzenlenen gelecek buluşmalar katılımcılara iptal bildirimiyle silinir;
    /// kabul edilmiş bağlantının sohbeti kalan kişi için kalır ('Silinmiş kullanıcı', salt okunur).
    func removeSocialData(of userId: UUID) {
        for meetup in meetups.values where meetup.organizerId == userId {
            if meetup.status == .active, meetup.endsAt > now() {
                for participant in participantsByMeetup[meetup.id] ?? []
                where participant.status == .joined && participant.userId != userId && !isBlocked(participant.userId, userId) {
                    notify(participant.userId, AppNotification(
                        kind: .meetupCancelled,
                        title: "Buluşma iptal edildi",
                        body: "\"\(meetup.title)\" buluşması iptal edildi.",
                        createdAt: now()
                    ))
                }
            }
            if let conversationId = meetupConversationId(meetup.id) {
                conversationRecords[conversationId] = nil
                chatMessages[conversationId] = nil
            }
            meetups[meetup.id] = nil
            participantsByMeetup[meetup.id] = nil
        }
        for key in participantsByMeetup.keys { participantsByMeetup[key]?.removeAll { $0.userId == userId } }
        for record in connections.values where record.requesterId == userId || record.addresseeId == userId {
            deleteConnection(record.id)
        }
        for key in conversationRecords.keys { conversationRecords[key]?.members[userId] = nil }
        for key in chatMessages.keys { chatMessages[key]?.removeAll { $0.authorId == userId } }
        socialProfiles[userId] = nil
        requestSends[userId] = nil
    }
}
