#if canImport(UIKit)
import SwiftUI
import MamaCore

/// Liste görünümündeki nokta kartı: fotoğraf, ad, mesafe, durum etiketi, ok (ekran 10).
public struct SpotCardView: View {
    let spot: Spot
    let now: Date

    public init(spot: Spot, now: Date = Date()) {
        self.spot = spot
        self.now = now
    }

    public var body: some View {
        let status = spot.currentStatus(now: now)
        HStack(spacing: 14) {
            SpotThumbnail(spot: spot, now: now)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if spot.hasUrgentNeed {
                        Circle().fill(MamaColor.statusUrgent).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(MamaColor.card, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(spot.title)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let distance = spot.distanceMeters {
                        Label(MamaFormat.distance(distance), systemImage: "location.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    Text("·")
                    Text(spot.lastFedAt == nil ? String(localized: "Henüz kayıt yok") : MamaFormat.relative(spot.lastFedAt, now: now))
                }
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
                .lineLimit(1)
                StatusBadge(status: status, hasUrgentNeed: spot.hasUrgentNeed)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MamaColor.textSecondary)
                .accessibilityHidden(true)
        }
        .mamaCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// İhtiyaç kartı: fotoğraf, tip, mesafe, aciliyet; "Ben ilgileniyorum" (siyah) / "Detay" (beyaz) (ekran 17).
public struct NeedCardView: View {
    let need: Need
    let now: Date
    let onClaim: (() -> Void)?
    let onDetail: (() -> Void)?

    public init(need: Need, now: Date = Date(), onClaim: (() -> Void)? = nil, onDetail: (() -> Void)? = nil) {
        self.need = need
        self.now = now
        self.onClaim = onClaim
        self.onDetail = onDetail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if need.mayContainSensitiveImagery, let photo = need.photoURLs.first {
                        SensitivePhoto(url: photo)
                    } else {
                        AsyncPhoto(
                            url: need.photoURLs.first ?? need.animalPhotoURL,
                            placeholderSystemImage: need.type.systemImage,
                            placeholderTint: need.isUrgent ? MamaColor.statusUrgent : MamaColor.textSecondary
                        )
                    }
                }
                .frame(width: 64, height: 64)
                .background(need.type.tileColor)
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TagChip(need.type.label, systemImage: need.type.systemImage)
                        if need.isUrgent {
                            TagChip(NeedUrgency.urgent.label, systemImage: "exclamationmark.triangle.fill", style: .danger)
                        }
                        if need.status != .open {
                            TagChip(need.status.label, systemImage: need.status.systemImage, style: need.status == .resolved ? .positive : .info)
                        }
                    }
                    Text(need.description)
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let name = need.animalName { Text(name).fontWeight(.semibold) }
                        if let title = need.spotTitle { Text(title).lineLimit(1) }
                        if let distance = need.distanceMeters {
                            Text("·")
                            Text(MamaFormat.distance(distance))
                        }
                        Text("·")
                        Text(MamaFormat.relative(need.createdAt, now: now))
                    }
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(1)
                }
            }
            if onClaim != nil || onDetail != nil {
                HStack(spacing: 10) {
                    if let onClaim, need.status == .open {
                        Button(String(localized: "Ben ilgileniyorum"), action: onClaim)
                            .buttonStyle(.mamaPrimary(systemImage: "hand.raised.fill"))
                    } else if need.status == .claimed, let name = need.claimedByName {
                        Label(String(localized: "\(name) ilgileniyor"), systemImage: "hand.raised.fill")
                            .font(MamaFont.subheadline.weight(.semibold))
                            .foregroundStyle(MamaColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let onDetail {
                        Button(String(localized: "Detay"), action: onDetail)
                            .buttonStyle(.mamaSecondary(fullWidth: false))
                    }
                }
            }
        }
        .mamaCard(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                .strokeBorder(need.isUrgent ? MamaColor.statusUrgent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
}

/// Yatay şeritteki küçük hayvan kartı ("Buradaki hayvanlar", ekran 13).
public struct AnimalChipCard: View {
    let animal: Animal

    public init(animal: Animal) {
        self.animal = animal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AnimalAvatar(animal: animal)
                .frame(width: 120, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let warning = animal.warning {
                        TagChip(warning.label, systemImage: "exclamationmark.triangle.fill", style: .danger)
                            .padding(6)
                    }
                }
            Text(animal.displayName)
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: animal.species.systemImage)
                Text(animal.species.label)
                if animal.isNeutered == true {
                    Text("·")
                    Text("Kısır")
                }
            }
            .font(MamaFont.caption)
            .foregroundStyle(MamaColor.textSecondary)
        }
        .frame(width: 120)
        .mamaCard(padding: 10)
        .accessibilityElement(children: .combine)
    }
}
#endif
