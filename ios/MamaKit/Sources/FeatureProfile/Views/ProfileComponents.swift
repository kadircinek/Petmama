#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Profil menüsündeki satır: pastel ikon karosu, başlık, isteğe bağlı rozet ve ok.
struct MenuRow: View {
    let title: String
    let systemImage: String
    var tint: Color = MamaColor.tileMint
    var subtitle: String?
    /// Okunmamış sayısı gibi küçük kırmızı rozet.
    var badge: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(MamaFont.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MamaColor.statusUrgent))
                    .accessibilityLabel(String(localized: "\(badge) okunmamış"))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MamaColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Satırları beyaz kart içinde ince çizgilerle gruplar.
struct MenuCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                .fill(MamaColor.card)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider().padding(.leading, 66)
    }
}

/// v1.1 rozeti: gri, kilitli, "yakında".
struct LockedBadgeView: View {
    let badge: ProfileViewModel.Badge

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: badge.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(MamaColor.statusUnknown)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(MamaColor.cardSecondary))
                    .overlay(Circle().strokeBorder(MamaColor.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])))
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MamaColor.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(MamaColor.card))
                    .overlay(Circle().strokeBorder(MamaColor.stroke, lineWidth: 1))
            }
            Text(badge.title)
                .font(MamaFont.caption.weight(.semibold))
                .foregroundStyle(MamaColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("yakında")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.statusUnknown)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(badge.title) rozeti. Kilitli, yakında."))
    }
}

/// Takip edilen hayvan satırı.
struct FollowedAnimalRow: View {
    let item: FollowingViewModel.AnimalItem
    let now: Date

    var body: some View {
        let animal = item.animal
        HStack(spacing: 14) {
            AsyncPhoto(url: animal.photoURLs.first, placeholderSystemImage: animal.species.systemImage, placeholderTint: MamaColor.mint)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(animal.displayName)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(animal.species.label, systemImage: animal.species.systemImage)
                    if let warning = animal.warning {
                        TagChip(warning.label, systemImage: "exclamationmark.triangle.fill", style: .danger)
                    }
                }
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
                Text(lastSeenText)
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(1)
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

    private var lastSeenText: String {
        var parts: [String] = []
        if let spot = item.lastSeenSpot { parts.append(spot.title) }
        if let distance = item.distanceMeters { parts.append(MamaFormat.distance(distance)) }
        if let seen = item.animal.lastSeenAt { parts.append(MamaFormat.relative(seen, now: now)) }
        guard !parts.isEmpty else { return String(localized: "Henüz görülme kaydı yok") }
        return String(localized: "Son görülme: \(parts.joined(separator: " · "))")
    }
}

/// Bildirim satırı: tür ikonu, başlık, metin, göreli zaman, okunmamış noktası.
struct NotificationRow: View {
    let notification: AppNotification
    let relativeTime: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.kind.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(notification.kind.tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(notification.kind.tint.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notification.title)
                        .font(notification.isRead ? MamaFont.subheadline.weight(.semibold) : MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(relativeTime)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                        .fixedSize()
                }
                Text(notification.body)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(3)
            }
            Circle()
                .fill(notification.isRead ? Color.clear : MamaColor.statusNeeds)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(notification.isRead ? "" : String(localized: "Okunmadı"))
    }
}
#endif
