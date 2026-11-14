import Foundation

/// Tüm repository protokollerinin bellek içi implementasyonu.
///
/// Demo modu (D7), SwiftUI önizlemeleri ve testler için. Sunucudaki iş kurallarının aynısını uygular
/// (mesafe doğrulama, mükerrer kontrol, günlük limit, durum eskitme, konum bulanıklaştırma, "teşekkürler"
/// bildirimi), böylece istemci akışları backend olmadan uçtan uca denenebilir.
public actor InMemoryBackend {
    var users: [UUID: UserProfile]
    var passwords: [String: (password: String, userId: UUID)] = [:]
    var currentUser: UUID?
    let demoUserId: UUID

    var spots: [UUID: Spot]
    var checkIns: [CheckIn]
    var animals: [UUID: Animal]
    var animalSpots: [AnimalSpotKey: (seenCount: Int, lastSeenAt: Date)] = [:]
    var needs: [UUID: Need]
    var guardians: [AnimalSpotKey: Set<Weekday>] = [:] // (userId, spotId)
    var follows: Set<FollowKey> = []
    var goneReports: [UUID: Set<UUID>] = [:]
    var notificationsByUser: [UUID: [AppNotification]] = [:]
    var preferencesByUser: [UUID: NotificationPreferences] = [:]
    var blocks: [UUID: Set<UUID>] = [:]
    private(set) var reports: [ReportDraft] = []
    private(set) var donationClicks: [String] = []
    private(set) var deviceTokens: [UUID: String] = [:]
    var donationOverview: DonationOverview

    // Mahalle (D17). Sayaç alanları okuma anında hesaplanır.
    var posts: [UUID: CommunityPost] = [:]
    var postCells: [UUID: Coordinate] = [:]
    var commentsByPost: [UUID: [CommunityComment]] = [:]
    var hiddenCommentIds: Set<UUID> = []
    var paws: [UUID: Set<UUID>] = [:]
    var coverVolunteers: [UUID: [UUID]] = [:]
    var reportersByTarget: [String: Set<UUID>] = [:]
    var mediaDirectory: URL

    let now: @Sendable () -> Date

    struct AnimalSpotKey: Hashable { let a: UUID; let b: UUID }
    struct FollowKey: Hashable { let user: UUID; let target: FollowTarget; let id: UUID }

    public init(seed: DemoSeed, signedIn: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        self.users = Dictionary(uniqueKeysWithValues: seed.users.map { ($0.id, $0) })
        self.demoUserId = seed.demoUserId
        self.currentUser = signedIn ? seed.demoUserId : nil
        self.spots = Dictionary(uniqueKeysWithValues: seed.spots.map { ($0.id, $0) })
        self.checkIns = seed.checkIns
        self.animals = Dictionary(uniqueKeysWithValues: seed.animals.map { ($0.id, $0) })
        self.needs = Dictionary(uniqueKeysWithValues: seed.needs.map { ($0.id, $0) })
        self.donationOverview = seed.donationOverview
        self.mediaDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("mama-demo-media", isDirectory: true)
        for link in seed.animalSpots {
            let lastSeen = seed.animals.first { $0.id == link.animalId }?.lastSeenAt ?? now()
            animalSpots[AnimalSpotKey(a: link.animalId, b: link.spotId)] = (link.seenCount, lastSeen)
        }
        for guardian in seed.guardians {
            guardians[AnimalSpotKey(a: guardian.userId, b: guardian.spotId)] = guardian.schedule
        }
        passwords["demo@mamaharitasi.app"] = ("demo1234", seed.demoUserId)
        for entry in seed.posts {
            posts[entry.post.id] = entry.post
            postCells[entry.post.id] = CommunityPolicy.cell(for: entry.coordinate)
        }
        for comment in seed.comments {
            commentsByPost[comment.postId, default: []].append(comment)
        }
        for entry in seed.paws { paws[entry.postId] = Set(entry.userIds) }
        for entry in seed.volunteers { coverVolunteers[entry.postId] = entry.userIds }
    }

    // MARK: - Test yardımcıları

    public func signInAsDemoUser() { currentUser = demoUserId }
    public func setCurrentUser(_ id: UUID?) { currentUser = id }
    public func allReports() -> [ReportDraft] { reports }
    public func allDonationClicks() -> [String] { donationClicks }
    public func notifications(for userId: UUID) -> [AppNotification] { notificationsByUser[userId] ?? [] }
    public func rawSpot(_ id: UUID) -> Spot? { spots[id] }
    public func setNotificationPreferences(_ preferences: NotificationPreferences, for userId: UUID) {
        preferencesByUser[userId] = preferences
    }

    // MARK: - Kurallar

    func requireUser() throws -> UUID {
        guard let currentUser else { throw MamaError.notSignedIn }
        return currentUser
    }

    func isPrivileged(_ userId: UUID?, for spot: Spot) -> Bool {
        guard let userId else { return false }
        if spot.createdBy == userId { return true }
        if users[userId]?.isVerifiedFeeder == true { return true }
        return guardians[AnimalSpotKey(a: userId, b: spot.id)] != nil
    }

    func hasOpenRequest(_ spotId: UUID) -> Bool {
        checkIns.contains { $0.spotId == spotId && $0.kind.isRequest && $0.resolvedAt == nil }
    }

    /// Okuma anında durum + gizlilik kuralları (docs/backend-contract.md → Konum hassasiyeti).
    func present(_ spot: Spot, origin: Coordinate? = nil) -> Spot? {
        let viewer = currentUser
        guard spot.isActive else { return nil }
        if spot.visibility == .private, viewer == nil { return nil }

        var result = spot
        let exact: Bool
        switch spot.visibility {
        case .public: exact = viewer != nil
        case .fuzzed, .private: exact = isPrivileged(viewer, for: spot)
        }
        if !exact {
            result.coordinate = LocationFuzzer.fuzz(spot.coordinate, seed: spot.id)
        }
        result.isLocationExact = exact
        result.status = SpotStatusRules.status(lastFedAt: spot.lastFedAt, hasOpenFoodRequest: hasOpenRequest(spot.id), now: now())
        let spotNeeds = needs.values.filter { need in
            need.status != .resolved && (need.spotId == spot.id || (need.animalId.map { animalIsAt($0, spot.id) } ?? false))
        }
        result.openNeedCount = spotNeeds.count
        result.hasUrgentNeed = spotNeeds.contains { $0.urgency == .urgent }
        result.animalCount = animalSpots.keys.filter { $0.b == spot.id }.count
        result.guardianCount = guardians.keys.filter { $0.b == spot.id }.count
        result.distanceMeters = origin.map { GeoMath.distance($0, result.coordinate) }
        return result
    }

    func animalIsAt(_ animalId: UUID, _ spotId: UUID) -> Bool {
        animalSpots[AnimalSpotKey(a: animalId, b: spotId)] != nil
    }

    func istanbulCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone
        return calendar
    }

    func notify(_ userId: UUID, _ notification: AppNotification) {
        notificationsByUser[userId, default: []].insert(notification, at: 0)
    }

    func isBlocked(_ a: UUID, _ b: UUID) -> Bool {
        (blocks[a]?.contains(b) ?? false) || (blocks[b]?.contains(a) ?? false)
    }
}

// MARK: - AuthRepository

extension InMemoryBackend: AuthRepository {
    public func currentUserId() async -> UUID? { currentUser }

    public func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> UserProfile {
        currentUser = demoUserId
        if let fullName, !fullName.isEmpty { users[demoUserId]?.displayName = fullName }
        return users[demoUserId]!
    }

    public func signIn(email: String, password: String) async throws -> UserProfile {
        let key = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard let entry = passwords[key], entry.password == password, let user = users[entry.userId] else {
            throw MamaError.invalidCredentials
        }
        currentUser = user.id
        return user
    }

    public func signUp(email: String, password: String, displayName: String) async throws -> UserProfile {
        let key = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard key.contains("@"), password.count >= 8 else {
            throw MamaError.invalidInput("Geçerli bir e-posta ve en az 8 karakterli şifre gir.")
        }
        guard passwords[key] == nil else { throw MamaError.emailAlreadyInUse }
        let user = UserProfile(displayName: displayName.isEmpty ? "Gönüllü" : displayName, createdAt: now())
        users[user.id] = user
        passwords[key] = (password, user.id)
        currentUser = user.id
        return user
    }

    public func sendPasswordReset(email: String) async throws {}

    public func completeAuthLink(_ url: URL) async throws -> UserProfile {
        throw MamaError.invalidInput("Demo modunda e-posta bağlantıları kullanılmaz.")
    }

    public func updatePassword(_ newPassword: String) async throws {
        let userId = try requireUser()
        for (email, entry) in passwords where entry.userId == userId {
            passwords[email] = (newPassword, userId)
        }
    }

    public func signOut() async throws { currentUser = nil }

    public func deleteAccount() async throws {
        let userId = try requireUser()
        users[userId] = nil
        passwords = passwords.filter { $0.value.userId != userId }
        for (id, spot) in spots where spot.createdBy == userId { spots[id]?.createdBy = nil }
        for (id, animal) in animals where animal.createdBy == userId { animals[id]?.createdBy = nil }
        checkIns = checkIns.map { var c = $0; if c.userId == userId { c.userId = nil }; return c }
        follows = follows.filter { $0.user != userId }
        guardians = guardians.filter { $0.key.a != userId }
        notificationsByUser[userId] = nil
        preferencesByUser[userId] = nil
        blocks[userId] = nil
        removeCommunityContent(of: userId)
        currentUser = nil
    }
}

// MARK: - SpotRepository

extension InMemoryBackend: SpotRepository {
    public func spots(in bounds: GeoBounds) async throws -> [Spot] {
        spots.values.compactMap { present($0) }.filter { bounds.contains($0.coordinate) }
    }

    public func spots(near center: Coordinate, radiusMeters: Int) async throws -> [Spot] {
        spots.values
            .compactMap { present($0, origin: center) }
            .filter { ($0.distanceMeters ?? .infinity) <= Double(radiusMeters) }
            .sorted { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
    }

    public func spot(id: UUID) async throws -> Spot? {
        spots[id].flatMap { present($0) }
    }

    public func search(query: String, near center: Coordinate?) async throws -> [Spot] {
        let locale = Locale(identifier: "tr_TR")
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased(with: locale)
        guard !needle.isEmpty else { return [] }
        let matches = spots.values
            .compactMap { present($0, origin: center) }
            .filter { spot in
                spot.title.lowercased(with: locale).contains(needle)
                    || (spot.note?.lowercased(with: locale).contains(needle) ?? false)
            }
        if center != nil {
            return matches.sorted { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
        }
        return matches.sorted { ($0.lastFedAt ?? .distantPast) > ($1.lastFedAt ?? .distantPast) }
    }

    public func feedingTimeline(spotId: UUID, days: Int) async throws -> [FeedingDay] {
        let calendar = istanbulCalendar()
        let today = calendar.startOfDay(for: now())
        return (0..<max(1, days)).reversed().compactMap { offset -> FeedingDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let inDay = checkIns.filter { $0.spotId == spotId && $0.createdAt >= day && $0.createdAt < next }
            let fed = inDay.filter { $0.kind == .fed }
            return FeedingDay(
                day: day,
                fedCount: fed.count,
                needCount: inDay.filter(\.kind.isRequest).count,
                lastFedAt: fed.map(\.createdAt).max()
            )
        }
    }

    public func guardians(spotId: UUID) async throws -> [Guardian] {
        // Sunucuyla aynı: koruyucu adları girişe bağlı.
        guard currentUser != nil else { return [] }
        return guardians
            .filter { $0.key.b == spotId }
            .compactMap { key, schedule in
                users[key.a].map {
                    Guardian(userId: $0.id, displayName: $0.displayName, avatarURL: $0.avatarURL, isVerifiedFeeder: $0.isVerifiedFeeder, schedule: schedule)
                }
            }
            .sorted { $0.displayName < $1.displayName }
    }

    public func duplicates(near coordinate: Coordinate) async throws -> [DuplicateCandidate] {
        _ = try requireUser()
        return DuplicateSpotPolicy.candidates(near: coordinate, among: Array(spots.values))
    }

    public func createSpot(_ draft: SpotDraft) async throws -> CreateSpotOutcome {
        let userId = try requireUser()
        let user = users[userId]
        if ContentFilter.containsProfanity(draft.title) || ContentFilter.containsProfanity(draft.note ?? "") {
            return .rejectedContent
        }
        let calendar = istanbulCalendar()
        let today = calendar.startOfDay(for: now())
        let createdToday = spots.values.filter { $0.createdBy == userId && $0.createdAt >= today }.count
        let limit = TrustPolicy.dailySpotLimit(isVerifiedFeeder: user?.isVerifiedFeeder ?? false)
        if createdToday >= limit { return .limitReached(limit: limit) }

        if !draft.force {
            let duplicates = DuplicateSpotPolicy.candidates(near: draft.coordinate, among: Array(spots.values))
            if !duplicates.isEmpty { return .duplicate(duplicates) }
        }
        let pending = TrustPolicy.requiresModeration(trustScore: user?.trustScore ?? TrustPolicy.initialTrustScore)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let spot = Spot(
            coordinate: draft.coordinate,
            type: draft.type,
            species: draft.species,
            title: title.isEmpty ? "Yeni nokta" : title,
            note: draft.note,
            photoURL: draft.photoURL,
            status: .unknown,
            visibility: draft.visibility,
            createdBy: userId,
            createdAt: now()
        )
        spots[spot.id] = spot
        return .created(id: spot.id, pendingModeration: pending)
    }

    public func reportGone(spotId: UUID) async throws -> GoneReportOutcome {
        let userId = try requireUser()
        guard spots[spotId] != nil else { throw MamaError.notFound }
        goneReports[spotId, default: []].insert(userId)
        let count = goneReports[spotId]?.count ?? 0
        let deactivate = InactiveSpotPolicy.shouldDeactivate(distinctReporterCount: count)
        if deactivate { spots[spotId]?.isActive = false }
        return GoneReportOutcome(reportCount: count, deactivated: deactivate)
    }

    public func neighborhoodSummary(near center: Coordinate) async throws -> NeighborhoodSummary {
        let radius = 1500.0
        let nearby = spots.values.filter { $0.isActive && GeoMath.distance(center, $0.coordinate) <= radius }
        let ids = Set(nearby.map(\.id))
        let today = istanbulCalendar().startOfDay(for: now())
        let weekAgo = now().addingTimeInterval(-7 * 86_400)
        let fedToday = Set(checkIns.filter { ids.contains($0.spotId) && $0.kind == .fed && $0.createdAt >= today }.map(\.spotId))
        let active = Set(checkIns.filter { ids.contains($0.spotId) && $0.createdAt >= weekAgo }.map(\.spotId))
        let openNeeds = needs.values.filter { need in
            guard need.status != .resolved, let spotId = need.spotId else { return false }
            return ids.contains(spotId)
        }
        return NeighborhoodSummary(
            fedSpotsToday: fedToday.count,
            openNeeds: openNeeds.count,
            needsFoodSpots: nearby.filter { hasOpenRequest($0.id) }.count,
            activeSpots7d: active.count
        )
    }
}

// MARK: - CheckInRepository

extension InMemoryBackend: CheckInRepository {
    public func checkIn(_ draft: CheckInDraft) async throws -> CheckInOutcome {
        let userId = try requireUser()
        guard let spot = spots[draft.spotId] else { throw MamaError.notFound }
        guard spot.isActive else { return .spotInactive }

        // Sunucu her zaman gerçek konuma göre ölçer (FR-C2, FR-C3).
        let distance = GeoMath.distance(draft.userCoordinate, spot.coordinate)
        let maxDistance = draft.kind.maxDistanceMeters
        guard distance <= maxDistance else {
            return .tooFar(distanceMeters: distance, maxDistanceMeters: maxDistance)
        }
        if checkIns.contains(where: { $0.id == draft.id }) {
            // Kuyruktan tekrar gönderim: idempotent.
            return .success(CheckInReceipt(checkInId: draft.id, distanceMeters: distance, closedNeedCount: 0,
                                           spotStatus: present(spot)?.status ?? .unknown))
        }
        let recentDuplicate = checkIns.contains {
            $0.spotId == spot.id && $0.userId == userId && $0.kind == draft.kind
                && now().timeIntervalSince($0.createdAt) < 600
        }
        if recentDuplicate { return .rateLimited }

        let checkIn = CheckIn(
            id: draft.id,
            spotId: spot.id,
            userId: userId,
            kind: draft.kind,
            amount: draft.amount,
            photoURL: draft.photoURL,
            userDistanceMeters: distance.rounded(),
            createdAt: now()
        )
        checkIns.append(checkIn)
        var closed = 0

        if draft.kind == .fed || draft.kind == .water {
            if draft.kind == .fed { spots[spot.id]?.lastFedAt = now() }
            let actorName = users[userId]?.displayName ?? "Bir gönüllü"
            for index in checkIns.indices where checkIns[index].spotId == spot.id
                && checkIns[index].kind.isRequest && checkIns[index].resolvedAt == nil {
                checkIns[index].resolvedAt = now()
                closed += 1
                // FR-C5: "Teşekkürler, X kişisi mama koydu".
                if let opener = checkIns[index].userId, opener != userId {
                    notify(opener, AppNotification(
                        kind: .thanksFed,
                        title: "Teşekkürler!",
                        body: "\(actorName), \(spot.title) noktasına mama koydu.",
                        spotId: spot.id,
                        createdAt: now()
                    ))
                }
            }
        } else {
            // FR-C4: yakındaki gönüllülere bildirim (demo: tercihi açık diğer kullanıcılar).
            for other in users.keys where other != userId && !isBlocked(other, userId) {
                let prefs = preferencesByUser[other] ?? .default
                guard prefs.needFoodNearby else { continue }
                notify(other, AppNotification(
                    kind: .needFoodNearby,
                    title: "Yakında mama bekleyen bir nokta var",
                    body: "\(spot.title) · \(MamaFormat.distance(distance))",
                    spotId: spot.id,
                    createdAt: now()
                ))
            }
        }

        if var user = users[userId] {
            user.trustScore += TrustPolicy.scoreDelta(forCheckInWithPhoto: draft.photoURL != nil)
            users[userId] = user
        }
        let status = present(spots[spot.id]!)?.status ?? .unknown
        spots[spot.id]?.status = status
        return .success(CheckInReceipt(checkInId: checkIn.id, distanceMeters: distance, closedNeedCount: closed, spotStatus: status))
    }
}

// MARK: - AnimalRepository

extension InMemoryBackend: AnimalRepository {
    public func animals(atSpot spotId: UUID) async throws -> [Animal] {
        animalSpots
            .filter { $0.key.b == spotId }
            .compactMap { key, info -> Animal? in
                guard var animal = animals[key.a] else { return nil }
                animal.seenCount = info.seenCount
                return animal
            }
            .sorted { ($0.seenCount ?? 0) > ($1.seenCount ?? 0) }
    }

    public func animal(id: UUID) async throws -> Animal? { animals[id] }

    public func spots(forAnimal animalId: UUID) async throws -> [Spot] {
        animalSpots.keys
            .filter { $0.a == animalId }
            .compactMap { spots[$0.b].flatMap { present($0) } }
            .sorted { $0.title < $1.title }
    }

    public func createAnimal(_ draft: AnimalDraft) async throws -> Animal {
        let userId = try requireUser()
        if ContentFilter.containsProfanity(draft.name ?? "") || ContentFilter.containsProfanity(draft.about ?? "") {
            throw MamaError.rejectedContent
        }
        let animal = Animal(
            species: draft.species,
            name: draft.name,
            colorPattern: draft.colorPattern,
            sex: draft.sex,
            ageEstimate: draft.ageEstimate,
            isNeutered: draft.isNeutered,
            earTag: draft.earTag,
            vaccinationInfo: draft.vaccinationInfo,
            temperamentTags: draft.temperamentTags,
            warning: draft.warning,
            about: draft.about,
            photoURLs: draft.photoURLs,
            lastSeenAt: now(),
            lastSeenSpotId: draft.spotId,
            createdBy: userId,
            createdAt: now()
        )
        animals[animal.id] = animal
        if let spotId = draft.spotId {
            animalSpots[AnimalSpotKey(a: animal.id, b: spotId)] = (1, now())
        }
        return animal
    }

    public func markSeen(animalId: UUID, spotId: UUID) async throws {
        _ = try requireUser()
        guard animals[animalId] != nil else { throw MamaError.notFound }
        let key = AnimalSpotKey(a: animalId, b: spotId)
        animalSpots[key] = ((animalSpots[key]?.seenCount ?? 0) + 1, now())
        animals[animalId]?.lastSeenAt = now()
        animals[animalId]?.lastSeenSpotId = spotId
    }
}

// MARK: - NeedRepository

extension InMemoryBackend: NeedRepository {
    func presentNeed(_ need: Need, origin: Coordinate?) -> Need? {
        var result = need
        let spotId = need.spotId ?? need.animalId.flatMap { animals[$0]?.lastSeenSpotId }
        if let spotId, let raw = spots[spotId] {
            guard let spot = present(raw) else { return nil }
            result.spotTitle = spot.title
            result.coordinate = spot.coordinate
            result.isLocationExact = spot.isLocationExact
        }
        if let animalId = need.animalId, let animal = animals[animalId] {
            result.animalName = animal.displayName
            result.animalPhotoURL = animal.photoURLs.first
        }
        if let claimedBy = need.claimedBy { result.claimedByName = users[claimedBy]?.displayName }
        return result.withDistance(from: origin)
    }

    public func needs(near center: Coordinate, radiusMeters: Int, includeResolved: Bool) async throws -> [Need] {
        let list = needs.values
            .filter { includeResolved || $0.status != .resolved }
            .compactMap { presentNeed($0, origin: center) }
            .filter { ($0.distanceMeters ?? 0) <= Double(radiusMeters) }
        return NeedSorting.sorted(list)
    }

    public func needs(spotId: UUID?, animalId: UUID?, includeResolved: Bool) async throws -> [Need] {
        let list = needs.values
            .filter { includeResolved || $0.status != .resolved }
            .filter { need in
                (spotId != nil && need.spotId == spotId) || (animalId != nil && need.animalId == animalId)
            }
            .compactMap { presentNeed($0, origin: nil) }
        return NeedSorting.sorted(list)
    }

    public func need(id: UUID) async throws -> Need? {
        needs[id].flatMap { presentNeed($0, origin: nil) }
    }

    public func createNeed(_ draft: NeedDraft) async throws -> UUID {
        let userId = try requireUser()
        guard draft.isValid else { throw MamaError.invalidInput("Bir açıklama yaz ve ihtiyacı bir noktaya veya hayvana bağla.") }
        if ContentFilter.containsProfanity(draft.description) { throw MamaError.rejectedContent }
        let need = Need(
            type: draft.type,
            urgency: draft.urgency,
            description: draft.description,
            photoURLs: draft.photoURLs,
            spotId: draft.spotId,
            animalId: draft.animalId,
            createdBy: userId,
            createdAt: now()
        )
        needs[need.id] = need
        return need.id
    }

    public func claim(needId: UUID) async throws -> ClaimOutcome {
        let userId = try requireUser()
        guard let need = needs[needId] else { throw MamaError.notFound }
        switch need.status {
        case .resolved: return .resolved
        case .claimed: return need.claimedBy == userId ? .ok : .alreadyClaimed
        case .open:
            needs[needId]?.status = .claimed
            needs[needId]?.claimedBy = userId
            needs[needId]?.claimedAt = now()
            return .ok
        }
    }

    public func resolve(needId: UUID) async throws -> Bool {
        let userId = try requireUser()
        guard let need = needs[needId] else { throw MamaError.notFound }
        let allowed = need.createdBy == userId || need.claimedBy == userId || (users[userId]?.isVerifiedFeeder ?? false)
        guard allowed else { return false }
        needs[needId]?.status = .resolved
        needs[needId]?.resolvedAt = now()
        if let creator = need.createdBy, creator != userId {
            notify(creator, AppNotification(
                kind: .needResolved,
                title: "Açtığın ihtiyaç çözüldü",
                body: need.description,
                spotId: need.spotId,
                needId: need.id,
                createdAt: now()
            ))
        }
        return true
    }
}

// MARK: - ProfileRepository

extension InMemoryBackend: ProfileRepository {
    public func profile(id: UUID) async throws -> UserProfile? { users[id] }

    public func stats(userId: UUID) async throws -> ProfileStats {
        let mine = checkIns.filter { $0.userId == userId }
        let monthAgo = now().addingTimeInterval(-30 * 86_400)
        return ProfileStats(
            fedSpotCount: Set(mine.filter { $0.kind == .fed }.map(\.spotId)).count,
            checkInCount: mine.count,
            resolvedNeedCount: needs.values.filter { $0.status == .resolved && $0.claimedBy == userId }.count,
            verifiedCheckInsLast30Days: mine.filter { $0.createdAt >= monthAgo && $0.userDistanceMeters != nil }.count
        )
    }

    public func updateProfile(displayName: String, neighborhood: String?, avatarURL: URL?) async throws -> UserProfile {
        let userId = try requireUser()
        guard !ContentFilter.containsProfanity(displayName) else { throw MamaError.rejectedContent }
        guard var user = users[userId] else { throw MamaError.notFound }
        user.displayName = displayName
        user.neighborhood = neighborhood
        user.avatarURL = avatarURL ?? user.avatarURL
        users[userId] = user
        return user
    }

    public func followedSpotIds() async throws -> Set<UUID> {
        guard let currentUser else { return [] }
        return Set(follows.filter { $0.user == currentUser && $0.target == .spot }.map(\.id))
    }

    public func followedSpots() async throws -> [Spot] {
        let ids = try await followedSpotIds()
        return ids.compactMap { spots[$0].flatMap { present($0) } }.sorted { $0.title < $1.title }
    }

    public func followedAnimals() async throws -> [Animal] {
        guard let currentUser else { return [] }
        return follows
            .filter { $0.user == currentUser && $0.target == .animal }
            .compactMap { animals[$0.id] }
            .sorted { $0.displayName < $1.displayName }
    }

    public func setFollowing(_ following: Bool, target: FollowTarget, id: UUID) async throws {
        let userId = try requireUser()
        let key = FollowKey(user: userId, target: target, id: id)
        if following { follows.insert(key) } else { follows.remove(key) }
    }

    public func guardedSpotIds() async throws -> Set<UUID> {
        guard let currentUser else { return [] }
        return Set(guardians.keys.filter { $0.a == currentUser }.map(\.b))
    }

    public func setGuardian(spotId: UUID, schedule: Set<Weekday>?) async throws {
        let userId = try requireUser()
        guardians[AnimalSpotKey(a: userId, b: spotId)] = schedule
    }
}

// MARK: - NotificationRepository

extension InMemoryBackend: NotificationRepository {
    public func notifications() async throws -> [AppNotification] {
        guard let currentUser else { return [] }
        return notificationsByUser[currentUser] ?? []
    }

    public func markRead(ids: [UUID]) async throws {
        guard let currentUser else { return }
        let set = Set(ids)
        notificationsByUser[currentUser] = (notificationsByUser[currentUser] ?? []).map { item in
            var copy = item
            if set.contains(item.id), copy.readAt == nil { copy.readAt = now() }
            return copy
        }
    }

    public func preferences() async throws -> NotificationPreferences {
        guard let currentUser else { return .default }
        return preferencesByUser[currentUser] ?? .default
    }

    public func updatePreferences(_ preferences: NotificationPreferences) async throws {
        let userId = try requireUser()
        preferencesByUser[userId] = preferences
    }

    public func registerDeviceToken(_ token: String) async throws {
        let userId = try requireUser()
        deviceTokens[userId] = token
    }

    public func unregisterDeviceToken(_ token: String) async throws {
        let userId = try requireUser()
        if deviceTokens[userId] == token { deviceTokens[userId] = nil }
    }

    public func updateNotifyCenter(_ coordinate: Coordinate) async throws {
        _ = try requireUser()
    }
}

// MARK: - ModerationRepository

extension InMemoryBackend: ModerationRepository {
    public func report(_ draft: ReportDraft) async throws {
        let reporter = try requireUser()
        reports.append(draft)
        guard draft.target == .post || draft.target == .comment else { return }
        let key = "\(draft.target.rawValue)-\(draft.targetId)"
        reportersByTarget[key, default: []].insert(reporter)
        if (reportersByTarget[key]?.count ?? 0) >= CommunityPolicy.reportsToAutoHide {
            hideReportedCommunityContent(target: draft.target, id: draft.targetId)
        }
    }

    public func block(userId: UUID) async throws {
        let me = try requireUser()
        blocks[me, default: []].insert(userId)
    }

    public func unblock(userId: UUID) async throws {
        let me = try requireUser()
        blocks[me]?.remove(userId)
    }

    public func blockedUserIds() async throws -> Set<UUID> {
        guard let currentUser else { return [] }
        return blocks[currentUser] ?? []
    }
}

// MARK: - DonationRepository & MediaUploader

extension InMemoryBackend: DonationRepository {
    public func overview() async throws -> DonationOverview? { donationOverview }

    public func logDonationClick(refCode: String) async throws {
        donationClicks.append(refCode)
    }
}

extension InMemoryBackend: MediaUploader {
    /// Demo: dosyayı geçici dizine yazar, `file://` URL döner (AsyncImage yükleyebilir).
    public func uploadJPEG(_ data: Data) async throws -> URL {
        _ = try requireUser()
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let url = mediaDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }
}
