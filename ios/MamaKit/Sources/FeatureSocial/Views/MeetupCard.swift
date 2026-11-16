#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Buluşma kartı: başlık, zaman, yer, düzenleyen ve katılım durumu.
struct MeetupCard: View {
    let meetup: Meetup
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: meetup.isTour ? "figure.walk" : "person.3.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(meetup.isTour ? MamaColor.tileMint : MamaColor.tileBlue))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: meetup.title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Label {
                        Text(verbatim: MeetupFormat.when(meetup, now: now))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(MamaFont.subheadline.weight(.semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    Label {
                        Text(verbatim: meetup.placeName)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            FlowLayout(spacing: 6) {
                if meetup.isTour { TourBadge() }
                MeetupStatusChips(meetup: meetup, now: now)
                TagChip(participantsText, systemImage: "person.2.fill")
                if let distance = meetup.distanceMeters {
                    TagChip(MamaFormat.distance(distance), systemImage: "location.fill")
                }
            }
            HStack(spacing: 8) {
                AvatarView(name: meetup.organizerName, url: meetup.organizerAvatarURL, size: 24)
                Text("Düzenleyen: \(meetup.organizerName)")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                if meetup.organizerIsVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(MamaColor.statusFed)
                        .accessibilityLabel(String(localized: "Doğrulanmış besleyici"))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MamaColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var participantsText: String {
        if let limit = meetup.capacity {
            return String(localized: "\(meetup.participantCount)/\(limit) kişi")
        }
        return String(localized: "\(meetup.participantCount) kişi")
    }
}

/// Anlık mama turu rozeti (Buluşmalar listesi, buluşma detayı, Mahalle üstü).
struct TourBadge: View {
    var body: some View {
        TagChip(String(localized: "Mama turu"), systemImage: "figure.walk", style: .positive)
    }
}

/// İptal, doldu, katılıyorsun… durum etiketleri.
struct MeetupStatusChips: View {
    let meetup: Meetup
    let now: Date

    var body: some View {
        if meetup.status == .cancelled {
            TagChip(String(localized: "İptal edildi"), systemImage: "xmark.circle.fill", style: .danger)
        } else if meetup.endsAt <= now {
            TagChip(String(localized: "Sona erdi"), systemImage: "clock.badge.checkmark", style: .neutral)
        } else {
            switch meetup.viewerRole {
            case .organizer:
                TagChip(String(localized: "Sen düzenliyorsun"), systemImage: "star.fill", style: .positive)
            case .participant:
                TagChip(String(localized: "Katılıyorsun"), systemImage: "checkmark.circle.fill", style: .positive)
            case .removed, .none:
                if meetup.isFull {
                    TagChip(String(localized: "Doldu"), systemImage: "person.fill.xmark", style: .warning)
                }
            }
        }
    }
}
#endif
