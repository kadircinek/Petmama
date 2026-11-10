import Foundation

/// Pilot ilçe Kadıköy / Moda için demo verisi (D3, D7). `supabase/seed.sql` ile aynı ruhta.
public struct DemoSeed: Sendable {
    public var users: [UserProfile]
    public var spots: [Spot]
    public var checkIns: [CheckIn]
    public var animals: [Animal]
    /// (hayvan, nokta, kaç kez görüldü)
    public var animalSpots: [(animalId: UUID, spotId: UUID, seenCount: Int)]
    public var needs: [Need]
    public var guardians: [(userId: UUID, spotId: UUID, schedule: Set<Weekday>)]
    public var donationOverview: DonationOverview
    /// Mahalle paylaşımları ve paylaşımın yapıldığı yer (yalnızca kaba konumu tutulur).
    public var posts: [(post: CommunityPost, coordinate: Coordinate)]
    public var comments: [CommunityComment]
    public var paws: [(postId: UUID, userIds: [UUID])]
    public var volunteers: [(postId: UUID, userIds: [UUID])]
    /// Demo modunda "giriş yap" ile oturum açılan kullanıcı.
    public var demoUserId: UUID
}

public enum DemoData {
    /// Kararlı demo kimlikleri: rotalar ve testler sabit kalsın.
    public static func id(_ group: Int, _ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8%03d-%012d", group, index))!
    }

    public static let ayseId = id(1, 1)
    public static let emreId = id(1, 2)
    public static let zeynepId = id(1, 3)
    public static let meId = id(1, 9)

    public static func make(now: Date = Date()) -> DemoSeed {
        func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        let users = [
            UserProfile(id: ayseId, displayName: "Ayşe", neighborhood: "Moda", trustScore: 64, isVerifiedFeeder: true, createdAt: ago(hours: 24 * 120)),
            UserProfile(id: emreId, displayName: "Emre", neighborhood: "Caferağa", trustScore: 18, createdAt: ago(hours: 24 * 40)),
            UserProfile(id: zeynepId, displayName: "Zeynep", neighborhood: "Moda", trustScore: 12, createdAt: ago(hours: 24 * 10)),
            UserProfile(id: meId, displayName: "Sen", neighborhood: "Moda", trustScore: 10, createdAt: ago(hours: 24 * 3)),
        ]

        // (başlık, enlem, boylam, tip, tür, son beslenme saat önce, açık talep, acil, görünürlük, not)
        typealias Row = (String, Double, Double, SpotType, SpotSpecies, Double?, Bool, Bool, SpotVisibility, String?)
        let rows: [Row] = [
            ("Moda Parkı girişi", 40.98455, 29.02560, .food, .cat, 2, false, false, .public, "Çınarın dibinde, mavi kap"),
            ("Moda Sahili bankları", 40.98290, 29.02480, .mixed, .both, 5, false, false, .public, "Sahil yolu, üçüncü bankın arkası"),
            ("Kadife Sokak köşesi", 40.98710, 29.02870, .food, .cat, 14, false, false, .public, nil),
            ("Bahariye arka sokak", 40.98920, 29.02990, .water, .both, 30, false, false, .public, "Apartmanın arka bahçesi, çitin yanı"),
            ("Caferağa Spor Salonu yanı", 40.98640, 29.02720, .food, .dog, 9, false, false, .public, nil),
            ("Moda İskelesi arkası", 40.98200, 29.02310, .mixed, .cat, nil, true, false, .public, "Kap boş görünüyor"),
            ("Şair Nefi Sokak çınar", 40.98580, 29.03050, .shelter, .cat, 20, false, true, .public, "Kulübe ve su kabı"),
            ("Yeldeğirmeni durak", 40.99150, 29.02850, .food, .both, 1, false, false, .public, nil),
            ("Ali Suavi Sokak", 40.98810, 29.03160, .food, .cat, 50, false, false, .public, nil),
            ("Moda Çay Bahçesi altı", 40.98340, 29.02700, .water, .both, 3, false, false, .public, nil),
            ("Dr. Esat Işık otoparkı", 40.98760, 29.02560, .food, .dog, nil, true, false, .public, "Otopark girişinin solu"),
            ("Kuşdili Çayırı kenarı", 40.99050, 29.03350, .mixed, .dog, 11, false, false, .public, nil),
            ("Moda Caddesi pasajı", 40.98530, 29.02920, .food, .cat, 7, false, false, .fuzzed, "Pasajın iç avlusu"),
            ("Gönüllü bahçesi", 40.98400, 29.03000, .shelter, .cat, 4, false, false, .private, "Özel bahçe — yalnızca koruyucular"),
            ("Mühürdar parkı", 40.98100, 29.02650, .food, .cat, 16, false, false, .public, nil),
            ("Rıhtım arkası", 40.99030, 29.02420, .food, .both, 26, true, false, .public, "Kap kırık"),
            ("Moda Sahnesi yanı", 40.98680, 29.02990, .water, .cat, 6, false, false, .public, nil),
            ("Sarraf Ali Sokak", 40.98990, 29.03080, .food, .cat, 13, false, false, .public, nil),
            ("Feneryolu yürüyüş yolu", 40.98050, 29.03250, .mixed, .dog, 8, false, false, .public, nil),
            ("Kilise bahçesi önü", 40.98620, 29.02640, .food, .cat, 0.5, false, false, .public, nil),
        ]

        var spots: [Spot] = []
        var checkIns: [CheckIn] = []
        for (index, row) in rows.enumerated() {
            let (title, lat, lng, type, species, fedHoursAgo, openRequest, urgent, visibility, note) = row
            let spotId = id(2, index + 1)
            let lastFed = fedHoursAgo.map { ago(hours: $0) }
            let creator = [ayseId, emreId, zeynepId][index % 3]
            spots.append(Spot(
                id: spotId,
                coordinate: Coordinate(latitude: lat, longitude: lng),
                type: type,
                species: species,
                title: title,
                note: note,
                status: SpotStatusRules.status(lastFedAt: lastFed, hasOpenFoodRequest: openRequest, now: now),
                lastFedAt: lastFed,
                hasUrgentNeed: urgent,
                openNeedCount: urgent ? 1 : 0,
                visibility: visibility,
                createdBy: creator,
                createdAt: ago(hours: Double(24 * (30 + index)))
            ))
            // Son 7 günün çizelgesi için geçmiş check-in'ler (FR-N4).
            if let fedHoursAgo {
                for day in 0..<7 where (index + day) % 3 != 0 || day == 0 {
                    let hours = fedHoursAgo + Double(day) * 24
                    checkIns.append(CheckIn(
                        id: id(3, index * 10 + day),
                        spotId: spotId,
                        userId: [ayseId, emreId, zeynepId][(index + day) % 3],
                        kind: .fed,
                        amount: [.low, .medium, .full][day % 3],
                        userDistanceMeters: Double(10 + (index * 7 + day * 3) % 80),
                        createdAt: ago(hours: hours)
                    ))
                }
            }
            if openRequest {
                checkIns.append(CheckIn(
                    id: id(3, 900 + index),
                    spotId: spotId,
                    userId: emreId,
                    kind: title.contains("kırık") || (note ?? "").contains("kırık") ? .broken : .needFood,
                    userDistanceMeters: 40,
                    createdAt: ago(hours: 1.5)
                ))
            }
        }

        let animals: [Animal] = [
            Animal(id: id(4, 1), species: .cat, name: "Pamuk", colorPattern: "Beyaz", sex: .female, ageEstimate: .adult, isNeutered: true, earTag: true,
                   vaccinationInfo: "Kuduz aşısı 2026", temperamentTags: [.friendly, .goodWithKids], about: "Parkın neşesi. Sabahları bankların altında güneşlenir.",
                   lastSeenAt: ago(hours: 2), lastSeenSpotId: id(2, 1), createdBy: ayseId),
            Animal(id: id(4, 2), species: .cat, name: "Tarçın", colorPattern: "Sarman", sex: .male, ageEstimate: .young, isNeutered: false,
                   temperamentTags: [.energetic, .friendly], about: "Kısırlaştırılmadı, ihtiyaç açıldı.", lastSeenAt: ago(hours: 5), lastSeenSpotId: id(2, 1), createdBy: ayseId),
            Animal(id: id(4, 3), species: .dog, name: "Karabaş", colorPattern: "Siyah", sex: .male, ageEstimate: .adult, isNeutered: true, earTag: true,
                   temperamentTags: [.calm], warning: .skittish, about: "Ürkek ama çok uysal. Yavaş yaklaşın.", lastSeenAt: ago(hours: 9), lastSeenSpotId: id(2, 5), createdBy: emreId),
            Animal(id: id(4, 4), species: .cat, name: "Zeytin", colorPattern: "Siyah", sex: .female, ageEstimate: .baby, isNeutered: nil,
                   temperamentTags: [.shy], about: "Yavru, annesiyle birlikte.", lastSeenAt: ago(hours: 20), lastSeenSpotId: id(2, 7), createdBy: zeynepId),
            Animal(id: id(4, 5), species: .cat, name: "Duman", colorPattern: "Gri tekir", sex: .male, ageEstimate: .senior, isNeutered: true, earTag: true,
                   temperamentTags: [.calm, .friendly], lastSeenAt: ago(hours: 3), lastSeenSpotId: id(2, 2), createdBy: ayseId),
            Animal(id: id(4, 6), species: .dog, name: "Kont", colorPattern: "Kahverengi", sex: .male, ageEstimate: .adult, isNeutered: false,
                   temperamentTags: [.mayBeAggressive], warning: .doNotApproach, about: "Yemek sırasında gergin olabiliyor.", lastSeenAt: ago(hours: 30), lastSeenSpotId: id(2, 11), createdBy: emreId),
            Animal(id: id(4, 7), species: .cat, name: "Karamel", colorPattern: "Calico", sex: .female, ageEstimate: .adult, isNeutered: true, earTag: true,
                   temperamentTags: [.friendly], lastSeenAt: ago(hours: 7), lastSeenSpotId: id(2, 13), createdBy: zeynepId),
            Animal(id: id(4, 8), species: .dog, name: "Fındık", colorPattern: "Açık kahve", sex: .female, ageEstimate: .young, isNeutered: true, earTag: true,
                   temperamentTags: [.energetic, .goodWithKids], lastSeenAt: ago(hours: 8), lastSeenSpotId: id(2, 19), createdBy: ayseId),
        ]

        let animalSpots: [(animalId: UUID, spotId: UUID, seenCount: Int)] = [
            (id(4, 1), id(2, 1), 24), (id(4, 1), id(2, 2), 3),
            (id(4, 2), id(2, 1), 11),
            (id(4, 3), id(2, 5), 15), (id(4, 3), id(2, 12), 4),
            (id(4, 4), id(2, 7), 6),
            (id(4, 5), id(2, 2), 9), (id(4, 5), id(2, 10), 2),
            (id(4, 6), id(2, 11), 5),
            (id(4, 7), id(2, 13), 8),
            (id(4, 8), id(2, 19), 12),
        ]

        let needs: [Need] = [
            Need(id: id(5, 1), type: .vet, urgency: .urgent, description: "Arka bacağında yara var, topallıyor. Veterinere götürülmesi gerekiyor.",
                 spotId: id(2, 7), animalId: id(4, 4), createdBy: zeynepId, createdAt: ago(hours: 3)),
            Need(id: id(5, 2), type: .neuter, description: "Tarçın kısırlaştırılmamış. Belediye kısırlaştırma randevusu için gönüllü arıyoruz.",
                 spotId: id(2, 1), animalId: id(4, 2), createdBy: ayseId, createdAt: ago(hours: 26)),
            Need(id: id(5, 3), type: .shelter, description: "Kış geliyor, sahil tarafına bir kulübe lazım.",
                 spotId: id(2, 2), createdBy: emreId, createdAt: ago(hours: 50)),
            Need(id: id(5, 4), type: .water, status: .claimed, description: "Su kabı kırılmış, yenisi gerekiyor.",
                 spotId: id(2, 16), createdBy: emreId, claimedBy: ayseId, claimedByName: "Ayşe", createdAt: ago(hours: 10), claimedAt: ago(hours: 6)),
            Need(id: id(5, 5), type: .meds, description: "Pire-kene damlası zamanı geldi.",
                 spotId: id(2, 5), animalId: id(4, 3), createdBy: emreId, createdAt: ago(hours: 70)),
            Need(id: id(5, 6), type: .vaccine, status: .resolved, description: "Kuduz aşısı yapıldı.",
                 spotId: id(2, 1), animalId: id(4, 1), createdBy: ayseId, createdAt: ago(hours: 24 * 9), resolvedAt: ago(hours: 24 * 7)),
        ]

        let guardians: [(userId: UUID, spotId: UUID, schedule: Set<Weekday>)] = [
            (ayseId, id(2, 1), [.monday, .wednesday, .friday, .sunday]),
            (ayseId, id(2, 2), [.tuesday, .thursday, .saturday]),
            (ayseId, id(2, 14), Set(Weekday.allCases)),
            (emreId, id(2, 5), [.monday, .tuesday, .wednesday, .thursday, .friday]),
            (zeynepId, id(2, 7), [.saturday, .sunday]),
            (zeynepId, id(2, 14), [.saturday]),
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NotificationPolicy.timeZone

        // Mahalle akışı (D17). Kimlikler: paylaşım id(6, n), yorum id(7, n).
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let moda = Coordinate.modaKadikoy
        let posts: [(post: CommunityPost, coordinate: Coordinate)] = [
            (CommunityPost(id: id(6, 1), kind: .coverRequest,
                           body: "Hafta sonu şehir dışındayım. Moda Sahili'ndeki kaplara cumartesi ve pazar sabahı bakabilecek biri var mı? Mama dolabın yanındaki kutuda.",
                           authorId: ayseId, authorName: "Ayşe", authorIsVerified: true,
                           spotId: id(2, 2), coverFrom: day(2), coverTo: day(3), createdAt: ago(hours: 3)), moda),
            (CommunityPost(id: id(6, 2), kind: .note,
                           body: "Pamuk bu sabah parkın girişinde beni bekliyordu. Kışlık tüyleri gelmiş, pamuk gibi olmuş gerçekten.",
                           authorId: zeynepId, authorName: "Zeynep",
                           spotId: id(2, 1), animalId: id(4, 1), createdAt: ago(hours: 5)), moda),
            (CommunityPost(id: id(6, 3), kind: .question,
                           body: "Kış için köpük kulübe yapmak istiyorum. Daha önce yapan var mı, malzemeyi nereden aldınız?",
                           authorId: emreId, authorName: "Emre", createdAt: ago(hours: 20)),
             GeoMath.offset(moda, north: 400, east: 300)),
            (CommunityPost(id: id(6, 4), kind: .supply,
                           body: "Elimde açılmamış 3 kg yavru kedi maması var. Yavrusu olan bir noktaya bakan varsa vereyim.",
                           authorId: zeynepId, authorName: "Zeynep", createdAt: ago(hours: 28)),
             GeoMath.offset(moda, north: -300, east: 200)),
            (CommunityPost(id: id(6, 5), kind: .alert,
                           body: "Rıhtım tarafında kaldırıma bırakılmış şüpheli bir mama gördüm, topladım ve zabıtaya haber verdim. O taraftan geçenler dikkat etsin.",
                           authorId: emreId, authorName: "Emre",
                           spotId: id(2, 16), createdAt: ago(hours: 40)), moda),
            (CommunityPost(id: id(6, 6), kind: .note,
                           body: "Kadıköy tarafında yeni bir su kabı noktası açtık, sabahları dolduruyorum.",
                           authorId: emreId, authorName: "Emre", createdAt: ago(hours: 60)),
             GeoMath.offset(moda, north: 9000, east: 0)),
        ]
        let comments: [CommunityComment] = [
            CommunityComment(id: id(7, 1), postId: id(6, 3), body: "Ben geçen kış yaptım. Yapı marketten strafor levha ve alüminyum bant yetiyor, istersen ölçüleri atarım.",
                             authorId: ayseId, authorName: "Ayşe", authorIsVerified: true, createdAt: ago(hours: 18)),
            CommunityComment(id: id(7, 2), postId: id(6, 3), body: "Girişini rüzgâr almayan tarafa bakacak şekilde koy, içine saman iyi oluyor.",
                             authorId: zeynepId, authorName: "Zeynep", createdAt: ago(hours: 16)),
            CommunityComment(id: id(7, 3), postId: id(6, 1), body: "Pazar sabahı ben uğrarım.",
                             authorId: emreId, authorName: "Emre", createdAt: ago(hours: 2)),
        ]
        let paws: [(postId: UUID, userIds: [UUID])] = [
            (id(6, 2), [ayseId, emreId]),
            (id(6, 3), [zeynepId]),
            (id(6, 5), [ayseId, zeynepId]),
        ]
        let volunteers: [(postId: UUID, userIds: [UUID])] = [
            (id(6, 1), [emreId]),
        ]

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        return DemoSeed(
            users: users,
            spots: spots,
            checkIns: checkIns,
            animals: animals,
            animalSpots: animalSpots,
            needs: needs,
            guardians: guardians,
            donationOverview: DonationOverview(month: monthStart, kgDistributed: 412, donorCount: 37),
            posts: posts,
            comments: comments,
            paws: paws,
            volunteers: volunteers,
            demoUserId: meId
        )
    }
}
