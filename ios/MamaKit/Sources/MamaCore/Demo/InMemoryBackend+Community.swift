import Foundation

// Mahalle akışının bellek içi implementasyonu. Sunucudaki kuralların aynısı:
// docs/backend-contract.md → Mahalle (topluluk).

extension InMemoryBackend: CommunityRepository {
    public func feed(near center: Coordinate, radiusMeters: Int, kind: CommunityPostKind?, before: Date?, limit: Int) async throws -> [CommunityPost] {
        let viewer = try requireUser()
        let radius = Double(min(max(radiusMeters, 0), 10_000))
        return posts.values
            .filter { kind == nil || $0.kind == kind }
            .filter { before == nil || $0.createdAt < before! }
            .compactMap { presentPost($0, viewer: viewer, origin: center) }
            .filter { ($0.distanceMeters ?? .infinity) <= radius }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(min(max(limit, 1), 50))
            .map { $0 }
    }

    public func post(id: UUID, near center: Coordinate?) async throws -> CommunityPost? {
        let viewer = try requireUser()
        return posts[id].flatMap { presentPost($0, viewer: viewer, origin: center) }
    }

    public func comments(postId: UUID) async throws -> [CommunityComment] {
        let viewer = try requireUser()
        guard let post = posts[postId], presentPost(post, viewer: viewer, origin: nil) != nil else { return [] }
        return visibleComments(of: postId, viewer: viewer)
    }

    public func volunteers(postId: UUID) async throws -> [CommunityVolunteer] {
        let viewer = try requireUser()
        guard let post = posts[postId], presentPost(post, viewer: viewer, origin: nil) != nil else { return [] }
        return (coverVolunteers[postId] ?? []).compactMap { id in
            users[id].map {
                CommunityVolunteer(userId: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL, isVerifiedFeeder: $0.isVerifiedFeeder)
            }
        }
    }

    public func createPost(_ draft: CommunityPostDraft) async throws -> CreatePostOutcome {
        let userId = try requireUser()
        guard let author = users[userId] else { throw MamaError.notSignedIn }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return .invalid(.bodyEmpty) }
        if body.count > CommunityPolicy.maxBodyLength { return .invalid(.bodyTooLong) }
        if ContentFilter.containsProfanity(body) { return .rejectedContent }

        let today = istanbulCalendar().startOfDay(for: now())
        let postedToday = posts.values.filter { $0.authorId == userId && $0.createdAt >= today }.count
        if postedToday >= CommunityPolicy.dailyPostLimit { return .limitReached(limit: CommunityPolicy.dailyPostLimit) }

        var cellSource = draft.coordinate
        if let spotId = draft.spotId {
            // Yalnızca yazara görünür bir nokta bağlanabilir.
            guard let raw = spots[spotId], present(raw) != nil else { return .invalid(.spotNotFound) }
            cellSource = raw.coordinate
        }
        if draft.kind == .coverRequest {
            if let error = CommunityPolicy.validate(draft, now: now()) { return .invalid(error) }
        }
        guard let cellSource else { return .invalid(.locationMissing) }

        let pending = TrustPolicy.requiresModeration(trustScore: author.trustScore)
        let isCover = draft.kind == .coverRequest
        let post = CommunityPost(
            kind: draft.kind,
            body: body,
            photoURL: draft.photoURL,
            authorId: userId,
            authorName: author.displayName,
            authorAvatarURL: author.avatarURL,
            authorIsVerified: author.isVerifiedFeeder,
            spotId: draft.spotId,
            animalId: draft.animalId,
            coverFrom: isCover ? draft.coverFrom : nil,
            coverTo: isCover ? draft.coverTo : nil,
            isPendingModeration: pending,
            createdAt: now()
        )
        posts[post.id] = post
        postCells[post.id] = CommunityPolicy.cell(for: cellSource)
        return .created(id: post.id, pendingModeration: pending)
    }

    public func addComment(postId: UUID, body: String) async throws -> CommentOutcome {
        let userId = try requireUser()
        guard let author = users[userId] else { throw MamaError.notSignedIn }
        if let error = CommunityPolicy.validateComment(body) { return .invalid(error) }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if ContentFilter.containsProfanity(text) { return .rejectedContent }
        guard let post = posts[postId], presentPost(post, viewer: userId, origin: nil) != nil else { return .postNotFound }

        let today = istanbulCalendar().startOfDay(for: now())
        let commentedToday = commentsByPost.values.joined().filter { $0.authorId == userId && $0.createdAt >= today }.count
        if commentedToday >= CommunityPolicy.dailyCommentLimit { return .limitReached(limit: CommunityPolicy.dailyCommentLimit) }

        let comment = CommunityComment(
            postId: postId,
            body: text,
            authorId: userId,
            authorName: author.displayName,
            authorAvatarURL: author.avatarURL,
            authorIsVerified: author.isVerifiedFeeder,
            createdAt: now()
        )
        commentsByPost[postId, default: []].append(comment)
        notifyPostAuthor(
            post,
            actor: userId,
            kind: .communityComment,
            title: "Paylaşımına yorum geldi",
            body: "\(author.displayName): \(String(text.prefix(80)))"
        )
        return .created(id: comment.id)
    }

    public func togglePaw(postId: UUID) async throws -> PawToggleResult? {
        let userId = try requireUser()
        guard let post = posts[postId], presentPost(post, viewer: userId, origin: nil) != nil else { return nil }
        var set = paws[postId] ?? []
        let pawed = !set.contains(userId)
        if pawed { set.insert(userId) } else { set.remove(userId) }
        paws[postId] = set
        return PawToggleResult(pawed: pawed, pawCount: set.count)
    }

    public func toggleVolunteer(postId: UUID) async throws -> CoverVolunteerOutcome {
        let userId = try requireUser()
        guard let post = posts[postId], presentPost(post, viewer: userId, origin: nil) != nil else { return .postNotFound }
        guard post.kind == .coverRequest else { return .notCoverRequest }
        guard post.authorId != userId else { return .ownPost }
        guard CommunityPolicy.isCoverOpen(post, now: now()) else { return .closed }

        var list = coverVolunteers[postId] ?? []
        let volunteered: Bool
        if let index = list.firstIndex(of: userId) {
            list.remove(at: index)
            volunteered = false
        } else {
            list.append(userId)
            volunteered = true
        }
        coverVolunteers[postId] = list
        if volunteered {
            let name = users[userId]?.displayName ?? "Bir gönüllü"
            let spotTitle = post.spotId.flatMap { spots[$0]?.title } ?? "noktan"
            notifyPostAuthor(
                post,
                actor: userId,
                kind: .coverVolunteered,
                title: "Yerine bakacak biri var!",
                body: "\(name), \(spotTitle) için \"Ben bakarım\" dedi."
            )
        }
        return .ok(volunteered: volunteered, volunteerCount: list.count)
    }

    public func deletePost(id: UUID) async throws -> Bool {
        let userId = try requireUser()
        guard let post = posts[id] else { throw MamaError.notFound }
        guard post.authorId == userId || (users[userId]?.isModerator ?? false) else { return false }
        posts[id] = nil
        postCells[id] = nil
        commentsByPost[id] = nil
        paws[id] = nil
        coverVolunteers[id] = nil
        return true
    }

    public func deleteComment(id: UUID) async throws -> Bool {
        let userId = try requireUser()
        for (postId, list) in commentsByPost {
            guard let index = list.firstIndex(where: { $0.id == id }) else { continue }
            let comment = list[index]
            let allowed = comment.authorId == userId
                || posts[postId]?.authorId == userId
                || (users[userId]?.isModerator ?? false)
            guard allowed else { return false }
            commentsByPost[postId]?.remove(at: index)
            return true
        }
        throw MamaError.notFound
    }

    public func summary(near center: Coordinate, radiusMeters: Int) async throws -> CommunitySummary {
        _ = try requireUser()
        let radius = Double(radiusMeters)
        let calendar = istanbulCalendar()
        let weekAgo = now().addingTimeInterval(-7 * 86_400)
        let nearbySpotIds = Set(spots.values.filter { $0.isActive && GeoMath.distance(center, $0.coordinate) <= radius }.map(\.id))
        let recent = checkIns.filter { nearbySpotIds.contains($0.spotId) && $0.createdAt >= weekAgo }

        struct SpotDay: Hashable { let spot: UUID; let day: Date }
        let fedSpotDays = Set(recent.filter { $0.kind == .fed }.map { SpotDay(spot: $0.spotId, day: calendar.startOfDay(for: $0.createdAt)) })
        let feeders = Set(recent.filter { $0.kind == .fed || $0.kind == .water }.compactMap(\.userId))

        let nearbyPosts = posts.values.filter { post in
            guard !post.isPendingModeration, let cell = postCells[post.id] else { return false }
            return GeoMath.distance(center, cell) <= radius
        }
        return CommunitySummary(
            fedSpotDays7d: fedSpotDays.count,
            activeFeeders7d: feeders.count,
            openCoverRequests: nearbyPosts.filter { CommunityPolicy.isCoverOpen($0, now: now()) }.count,
            posts7d: nearbyPosts.filter { $0.createdAt >= weekAgo }.count
        )
    }
}

// MARK: - Yardımcılar

extension InMemoryBackend {
    /// Görünürlük (inceleme, engel) ve okuma anında hesaplanan sayaçlar.
    func presentPost(_ post: CommunityPost, viewer: UUID, origin: Coordinate?) -> CommunityPost? {
        guard let author = users[post.authorId], !isBlocked(viewer, post.authorId) else { return nil }
        let isModerator = users[viewer]?.isModerator ?? false
        if post.isPendingModeration, post.authorId != viewer, !isModerator { return nil }

        var result = post
        result.authorName = author.displayName
        result.authorAvatarURL = author.avatarURL
        result.authorIsVerified = author.isVerifiedFeeder
        if let spotId = post.spotId, let raw = spots[spotId], let spot = present(raw) {
            result.spotTitle = spot.title
        } else {
            result.spotId = nil
            result.spotTitle = nil
        }
        if let animalId = post.animalId, let animal = animals[animalId] {
            result.animalName = animal.displayName
        } else {
            result.animalId = nil
            result.animalName = nil
        }
        let pawSet = paws[post.id] ?? []
        result.pawCount = pawSet.count
        result.viewerPawed = pawSet.contains(viewer)
        let volunteerList = coverVolunteers[post.id] ?? []
        result.volunteerCount = volunteerList.count
        result.viewerVolunteered = volunteerList.contains(viewer)
        result.commentCount = visibleComments(of: post.id, viewer: viewer).count
        if let origin, let cell = postCells[post.id] {
            result.distanceMeters = GeoMath.distance(origin, cell)
        } else {
            result.distanceMeters = nil
        }
        return result
    }

    func visibleComments(of postId: UUID, viewer: UUID) -> [CommunityComment] {
        (commentsByPost[postId] ?? [])
            .filter { !hiddenCommentIds.contains($0.id) && !isBlocked(viewer, $0.authorId) }
            .compactMap { comment -> CommunityComment? in
                guard let author = users[comment.authorId] else { return nil }
                var copy = comment
                copy.authorName = author.displayName
                copy.authorAvatarURL = author.avatarURL
                copy.authorIsVerified = author.isVerifiedFeeder
                return copy
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Bildirim bastırma kuralları: kendi içeriği, engel, tercih kapalı, aynı paylaşım için okunmamış aynı tür.
    func notifyPostAuthor(_ post: CommunityPost, actor: UUID, kind: NotificationKind, title: String, body: String) {
        let author = post.authorId
        guard author != actor, !isBlocked(author, actor) else { return }
        guard (preferencesByUser[author] ?? .default).communityUpdates else { return }
        let hasUnread = (notificationsByUser[author] ?? []).contains { $0.kind == kind && $0.postId == post.id && !$0.isRead }
        guard !hasUnread else { return }
        notify(author, AppNotification(kind: kind, title: title, body: body, spotId: post.spotId, postId: post.id, createdAt: now()))
    }

    func removeCommunityContent(of userId: UUID) {
        for id in posts.values.filter({ $0.authorId == userId }).map(\.id) {
            posts[id] = nil
            postCells[id] = nil
            commentsByPost[id] = nil
            paws[id] = nil
            coverVolunteers[id] = nil
        }
        for key in commentsByPost.keys { commentsByPost[key]?.removeAll { $0.authorId == userId } }
        for key in paws.keys { paws[key]?.remove(userId) }
        for key in coverVolunteers.keys { coverVolunteers[key]?.removeAll { $0 == userId } }
    }

    func hideReportedCommunityContent(target: ReportTarget, id: UUID) {
        switch target {
        case .post: posts[id]?.isPendingModeration = true
        case .comment: hiddenCommentIds.insert(id)
        default: break
        }
    }

    // Test yardımcıları
    public func rawPost(_ id: UUID) -> CommunityPost? { posts[id] }
    public func setTrustScore(_ score: Int, for userId: UUID) { users[userId]?.trustScore = score }
    public func setModerator(_ value: Bool, for userId: UUID) { users[userId]?.isModerator = value }
}
