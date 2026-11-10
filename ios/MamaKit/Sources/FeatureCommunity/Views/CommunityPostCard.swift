#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Mahalle paylaşım kartı. Akışta metin 6 satıra kısalır ve dokununca detay açılır; detayda tam metin görünür.
struct CommunityPostCard: View {
    enum Layout {
        case feed, detail
    }

    let post: CommunityPost
    let now: Date
    let viewerId: UUID?
    var layout: Layout = .feed
    /// Konum bilinmiyorsa (varsayılan merkezle yüklendiyse) mesafe gösterilmez.
    var showsDistance = true
    /// "Yerime bakar mısın?" isteği hâlâ gönüllü kabul ediyor mu?
    let isCoverOpen: Bool
    /// "Ben bakarım" veya silme isteği sürüyor.
    var isBusy = false
    let onPaw: () -> Void
    let onVolunteer: () -> Void
    /// Akışta detayı açar, detayda yorum kutusuna odaklanır.
    let onComment: () -> Void
    /// Silme onayını ekran sorar.
    let onDelete: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    private var isOwn: Bool { viewerId != nil && post.authorId == viewerId }

    /// "3 sa önce · ≈ 600 m"
    private var metaLine: String {
        let time = MamaFormat.relative(post.createdAt, now: now)
        guard showsDistance, let distance = post.distanceMeters else { return time }
        return "\(time) · ≈ \(MamaFormat.distance(distance))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommunityAuthorLine(
                name: post.authorName,
                avatarURL: post.authorAvatarURL,
                isVerified: post.authorIsVerified,
                detail: metaLine
            )
            TagChip(post.kind.label, systemImage: post.kind.systemImage, style: post.kind.chipStyle)
            bodyText
            photo
            links
            if post.kind == .coverRequest {
                CommunityCoverBox(post: post, isOwn: isOwn, isOpen: isCoverOpen, isBusy: isBusy, onVolunteer: onVolunteer)
            }
            if post.kind == .alert {
                alertFootnote
            }
            if isOwn, post.isPendingModeration {
                BannerView(String(localized: "Paylaşımın kısa bir incelemeden sonra mahallede görünecek."), style: .info)
            }
            CommunityPostFooter(
                post: post,
                isOwn: isOwn,
                isBusy: isBusy,
                onPaw: onPaw,
                onComment: onComment,
                onDelete: onDelete,
                onReportPost: { router.present(.report(.post, post.id), session: session) },
                onReportUser: { router.present(.report(.user, post.authorId), session: session) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
        .overlay {
            // Uyarı paylaşımları renk + ikon + metinle ayrışır.
            if post.kind == .alert {
                RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(MamaColor.statusUrgent.opacity(0.45), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        switch layout {
        case .feed:
            Button(action: onComment) {
                Text(verbatim: post.body)
                    .font(MamaFont.body)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Paylaşımı ve yorumları açar"))
        case .detail:
            Text(verbatim: post.body)
                .font(MamaFont.body)
                .foregroundStyle(MamaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let url = post.photoURL {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .overlay {
                    AsyncPhoto(url: url, placeholderSystemImage: post.kind.systemImage)
                }
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Paylaşım fotoğrafı"))
        }
    }

    /// Bağlı nokta ve hayvan.
    @ViewBuilder
    private var links: some View {
        if post.spotId != nil || post.animalId != nil {
            FlowLayout(spacing: 8) {
                if let spotId = post.spotId {
                    CommunityLinkChip(title: post.spotTitle ?? String(localized: "Nokta"), systemImage: "mappin.and.ellipse") {
                        router.push(.spot(spotId))
                    }
                }
                if let animalId = post.animalId {
                    CommunityLinkChip(title: post.animalName ?? String(localized: "Hayvan"), systemImage: "pawprint.fill") {
                        router.push(.animal(animalId))
                    }
                }
            }
        }
    }

    private var alertFootnote: some View {
        Label {
            Text("Şüpheli bir durumda Alo 153'ü, acil durumda 112'yi ara.")
        } icon: {
            Image(systemName: "phone.fill")
        }
        .font(MamaFont.footnote)
        .foregroundStyle(MamaColor.textSecondary)
    }
}

/// "Yerime bakar mısın?" kutusu: tarih aralığı, gönüllü sayısı ve "Ben bakarım".
struct CommunityCoverBox: View {
    let post: CommunityPost
    let isOwn: Bool
    let isOpen: Bool
    let isBusy: Bool
    let onVolunteer: () -> Void

    private var dateText: String {
        CommunityFormat.coverRange(from: post.coverFrom, to: post.coverTo) ?? String(localized: "Tarih belirtilmedi")
    }

    private var volunteerText: String {
        post.volunteerCount > 0
            ? String(localized: "\(post.volunteerCount) kişi bakacak")
            : String(localized: "Henüz bakacak kimse yok")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(MamaColor.card.opacity(0.7)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: dateText)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text(volunteerText)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            action
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                .fill(MamaColor.tileLavender)
        )
    }

    /// Kendi paylaşımında buton yok; süresi dolduysa pasif.
    @ViewBuilder
    private var action: some View {
        if isOwn {
            EmptyView()
        } else if !isOpen {
            Button {} label: {
                Text("Süresi doldu")
            }
            .buttonStyle(.mamaSecondary(tint: MamaColor.textSecondary, systemImage: "clock"))
            .disabled(true)
        } else if post.viewerVolunteered {
            Button(action: onVolunteer) {
                Text("Bakıyorsun · Vazgeç")
            }
            .buttonStyle(.mamaSecondary(tint: MamaColor.statusFed, systemImage: "checkmark.circle.fill"))
            .disabled(isBusy)
            .accessibilityHint(String(localized: "Gönüllülüğünü geri alır"))
        } else {
            Button(action: onVolunteer) {
                Text("Ben bakarım")
            }
            .buttonStyle(.mamaPrimary(systemImage: "hand.raised.fill"))
            .disabled(isBusy)
        }
    }
}

#Preview("Kartlar") {
    PreviewEnvironment { _ in
        ScrollView {
            VStack(spacing: 14) {
                ForEach(CommunityPostCardPreview.posts) { post in
                    CommunityPostCard(
                        post: post,
                        now: Date(),
                        viewerId: DemoData.meId,
                        isCoverOpen: CommunityPolicy.isCoverOpen(post, now: Date()),
                        onPaw: {},
                        onVolunteer: {},
                        onComment: {},
                        onDelete: {}
                    )
                }
            }
            .padding(MamaMetrics.screenPadding)
        }
        .mamaBackground()
    }
}

/// Önizleme verisi: demo paylaşımları + izleyicinin inceleme bekleyen kendi paylaşımı.
private enum CommunityPostCardPreview {
    static var posts: [CommunityPost] {
        var posts = DemoData.make().posts.map { $0.post }
        posts.append(
            CommunityPost(
                kind: .note,
                body: "Bugün ilk kez mama koydum, çok mutluyum.",
                authorId: DemoData.meId,
                authorName: "Sen",
                isPendingModeration: true
            )
        )
        return posts
    }
}
#endif
