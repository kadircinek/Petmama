#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Büyük fotoğraf başlığı; fotoğraf yoksa duruma göre ifadesi değişen maskot (D18).
struct SpotHeroHeader: View {
    let spot: Spot
    let status: SpotStatus

    var body: some View {
        SpotThumbnail(spot: spot)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityHidden(true)
    }
}

/// Ad, durum rozeti, tip/tür etiketleri, son mama ve yaklaşık konum notu.
struct SpotSummaryBlock: View {
    let spot: Spot
    let status: SpotStatus
    let lastFedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spot.title)
                .font(MamaFont.title)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            StatusBadge(status: status, hasUrgentNeed: spot.hasUrgentNeed)
            FlowLayout(spacing: 8) {
                TagChip(spot.type.label, systemImage: spot.type.systemImage)
                TagChip(spot.species.label, systemImage: spot.species.systemImage)
                if spot.visibility != .public {
                    TagChip(spot.visibility.label, systemImage: spot.visibility.systemImage, style: .info)
                }
                if let distance = spot.distanceMeters {
                    TagChip(MamaFormat.distance(distance), systemImage: "location.fill")
                }
            }
            Label(lastFedText, systemImage: "clock")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
            if let note = spot.note, !note.isEmpty {
                Text(note)
                    .font(MamaFont.body)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            if !spot.isLocationExact {
                BannerView(
                    String(localized: "Yaklaşık konum gösteriliyor. Tam konumu koruyucular ve doğrulanmış besleyiciler görür."),
                    style: .info,
                    systemImage: "circle.dashed"
                )
            }
        }
    }
}

/// "Buradaki hayvanlar (N)" yatay şeridi + "Hayvan ekle".
struct SpotAnimalsSection: View {
    let spotId: UUID
    let animals: [Animal]

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Buradaki hayvanlar (\(animals.count))"))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(animals) { animal in
                        Button {
                            router.push(.animal(animal.id))
                        } label: {
                            AnimalChipCard(animal: animal)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        router.present(.createAnimal(spotId: spotId), session: session)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(MamaColor.tileMint))
                            Text("Hayvan ekle")
                                .font(MamaFont.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(MamaColor.textPrimary)
                        .frame(width: 120, height: 160)
                        .background(
                            RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                                .strokeBorder(MamaColor.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }
}

/// Açık ihtiyaçlar + "İhtiyaç bildir".
struct SpotNeedsSection: View {
    let spotId: UUID
    let needs: [Need]
    let now: Date

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Açık ihtiyaçlar"))
            if needs.isEmpty {
                Text("Şu an açık bir ihtiyaç yok.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(needs) { need in
                    NeedCardView(need: need, now: now, onDetail: { router.push(.need(need.id)) })
                }
            }
            Button("İhtiyaç bildir") {
                router.present(.createNeed(spotId: spotId, animalId: nil), session: session)
            }
            .buttonStyle(.mamaSecondary(systemImage: "cross.case.fill"))
        }
    }
}

/// Koruyucular (avatar + haftalık gün çizelgesi) ve "Koruyucu ol / Günleri düzenle".
/// Koruyucu, yokken noktasını mahalleye emanet edebilir: "Yerime bakar mısın?" (D17).
struct SpotGuardiansSection: View {
    let guardians: [Guardian]
    let isGuardian: Bool
    let onEdit: () -> Void
    let onAskCover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Koruyucular"))
            if guardians.isEmpty {
                Text("Bu noktanın henüz koruyucusu yok. Düzenli besliyorsan koruyucu olabilirsin.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(guardians) { guardian in
                        HStack(spacing: 12) {
                            AvatarView(name: guardian.displayName, url: guardian.avatarURL)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(guardian.displayName)
                                        .font(MamaFont.headline)
                                        .foregroundStyle(MamaColor.textPrimary)
                                    if guardian.isVerifiedFeeder {
                                        TagChip(String(localized: "Doğrulanmış besleyici"), systemImage: "checkmark.seal.fill", style: .positive)
                                    }
                                }
                                WeekdayDots(schedule: guardian.schedule)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .mamaCard(padding: 14)
            }
            Button(isGuardian ? String(localized: "Koruyuculuk günlerini düzenle") : String(localized: "Koruyucu ol"), action: onEdit)
                .buttonStyle(.mamaSecondary(systemImage: "shield.lefthalf.filled"))
            if isGuardian {
                Button(action: onAskCover) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MamaColor.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(MamaColor.card.opacity(0.7)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bir süre yok musun?")
                                .font(MamaFont.headline)
                                .foregroundStyle(MamaColor.textPrimary)
                            Text("Mahalleden yerine bakacak birini bul.")
                                .font(MamaFont.caption)
                                .foregroundStyle(MamaColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(MamaColor.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: MamaMetrics.minTapSize)
                    .background(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous).fill(MamaColor.tileLavender))
                    .contentShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Haftanın 7 günü; koruyucunun uğradığı günler dolu.
struct WeekdayDots: View {
    let schedule: Set<Weekday>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let active = schedule.contains(day)
                Text(day.localizedShortName)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(active ? MamaColor.onInk : MamaColor.textSecondary)
                    .frame(width: 30, height: 22)
                    .background(Capsule().fill(active ? MamaColor.ink : MamaColor.cardSecondary))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        let days = Weekday.allCases.filter(schedule.contains).map(\.localizedShortName)
        return days.isEmpty
            ? String(localized: "Belirli gün yok")
            : String(localized: "Uğradığı günler: \(days.joined(separator: ", "))")
    }
}

/// "Sorumlu besleme rehberi" bağlantısı (PRD 9.4).
struct FeedingGuideLink: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.push(.feedingGuide)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MamaColor.tileLavender))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sorumlu besleme rehberi")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text("Komşularla iyi geçinmenin küçük yolları")
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MamaColor.textSecondary)
            }
            .mamaCard(padding: 12)
        }
        .buttonStyle(.plain)
    }
}
#endif
