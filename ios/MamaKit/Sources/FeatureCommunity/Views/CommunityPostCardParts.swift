#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Avatar + ad + "Doğrulanmış" etiketi + alt satır (zaman, mesafe). Paylaşım ve yorumlarda ortak.
struct CommunityAuthorLine: View {
    let name: String
    let avatarURL: URL?
    let isVerified: Bool
    let detail: String
    var avatarSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AvatarView(name: name, url: avatarURL, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: name)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .lineLimit(1)
                    if isVerified {
                        TagChip(String(localized: "Doğrulanmış"), systemImage: "checkmark.seal.fill", style: .positive)
                    }
                }
                Text(verbatim: detail)
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bağlı nokta / hayvan: dokununca ilgili sayfaya gider. Görünen hap küçük, dokunma alanı 44 pt.
struct CommunityLinkChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(MamaFont.caption)
            .foregroundStyle(MamaColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Capsule().fill(MamaColor.cardSecondary))
            .frame(minHeight: MamaMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kartın alt satırı: pati, yorumlar ve "…" menüsü.
struct CommunityPostFooter: View {
    let post: CommunityPost
    let isOwn: Bool
    let isBusy: Bool
    let onPaw: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    let onReportPost: () -> Void
    let onReportUser: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CommunityPawButton(count: post.pawCount, isOn: post.viewerPawed, action: onPaw)
            Button(action: onComment) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                    Text(verbatim: "\(post.commentCount)")
                        .monospacedDigit()
                }
                .font(MamaFont.subheadline.weight(.semibold))
                .foregroundStyle(MamaColor.textSecondary)
                .padding(.horizontal, 8)
                .frame(minWidth: MamaMetrics.minTapSize, minHeight: MamaMetrics.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Yorumlar"))
            .accessibilityValue(String(localized: "\(post.commentCount) yorum"))
            Spacer(minLength: 0)
            menu
        }
    }

    private var menu: some View {
        Menu {
            if isOwn {
                Button(role: .destructive, action: onDelete) {
                    Label("Sil", systemImage: "trash")
                }
                .disabled(isBusy)
            } else {
                Button(action: onReportPost) {
                    Label("Paylaşımı bildir", systemImage: "flag")
                }
                Button(action: onReportUser) {
                    Label("Kullanıcıyı bildir veya engelle", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textSecondary)
                .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "Diğer seçenekler"))
    }
}

/// "Pati bırak": beğeninin mahalle hali. Durum renk + dolu ikon + sayı ile gösterilir.
struct CommunityPawButton: View {
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "pawprint.fill" : "pawprint")
                    .symbolEffect(.bounce, value: isOn)
                Text(verbatim: "\(count)")
                    .monospacedDigit()
            }
            .font(MamaFont.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? MamaColor.statusFed : MamaColor.textSecondary)
            .padding(.horizontal, 8)
            .frame(minWidth: MamaMetrics.minTapSize, minHeight: MamaMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(String(localized: "Pati bırak"))
        .accessibilityValue(String(localized: "\(count) pati"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
#endif
