#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Bakacaklar": "Ben bakarım" diyen gönüllüler.
struct PostVolunteersSection: View {
    let volunteers: [CommunityVolunteer]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Bakacaklar"))
            if volunteers.isEmpty {
                Text("Henüz kimse “Ben bakarım” demedi.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(volunteers) { volunteer in
                    HStack(spacing: 10) {
                        AvatarView(name: volunteer.displayName, url: volunteer.avatarURL, size: 36)
                        Text(verbatim: volunteer.displayName)
                            .font(MamaFont.bodyEmphasized)
                            .foregroundStyle(MamaColor.textPrimary)
                            .lineLimit(1)
                        if volunteer.isVerifiedFeeder {
                            TagChip(String(localized: "Doğrulanmış"), systemImage: "checkmark.seal.fill", style: .positive)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }
}

/// Yorum listesi (eskiden yeniye).
struct PostCommentsSection: View {
    let comments: [CommunityComment]
    let now: Date
    let viewerId: UUID?
    let canDelete: (CommunityComment) -> Bool
    let onDelete: (CommunityComment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Yorumlar"))
            if comments.isEmpty {
                Text("Henüz yorum yok. İlk yorumu sen yaz.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(comments) { comment in
                    PostCommentRow(
                        comment: comment,
                        now: now,
                        isOwn: viewerId != nil && comment.authorId == viewerId,
                        canDelete: canDelete(comment),
                        onDelete: { onDelete(comment) }
                    )
                }
            }
        }
    }
}

/// Tek yorum: yazar, zaman, metin ve "…" menüsü (sil / bildir / engelle).
struct PostCommentRow: View {
    let comment: CommunityComment
    let now: Date
    let isOwn: Bool
    /// Yorumun yazarı ya da paylaşımın sahibi silebilir.
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                CommunityAuthorLine(
                    name: comment.authorName,
                    avatarURL: comment.authorAvatarURL,
                    isVerified: comment.authorIsVerified,
                    detail: MamaFormat.relative(comment.createdAt, now: now),
                    avatarSize: 36
                )
                menu
            }
            Text(verbatim: comment.body)
                .font(MamaFont.body)
                .foregroundStyle(MamaColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard(padding: 12, cornerRadius: MamaMetrics.smallCornerRadius)
    }

    private var menu: some View {
        Menu {
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Sil", systemImage: "trash")
                }
            }
            if !isOwn {
                Button {
                    router.present(.report(.comment, comment.id), session: session)
                } label: {
                    Label("Yorumu bildir", systemImage: "flag")
                }
                Button {
                    router.present(.report(.user, comment.authorId), session: session)
                } label: {
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
        .accessibilityLabel(String(localized: "Yorum seçenekleri"))
    }
}

/// Altta sabit yorum kutusu: 1–4 satır, sınıra yaklaşınca sayaç. Gönderirken yalnızca gönder butonu
/// pasifleşir; metin alanı açık kalır ki klavye kapanmasın.
struct PostCommentComposer: View {
    @Bindable var model: PostDetailViewModel
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.commentProblem {
                BannerView(problem, style: .warning)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Yorum yaz…", text: $model.commentText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(isFocused)
                    .font(MamaFont.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: MamaMetrics.minTapSize)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(MamaColor.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(MamaColor.stroke, lineWidth: 1)
                    )
                sendButton
            }
            if model.showsCommentCounter {
                counter
            }
        }
        .padding(.horizontal, MamaMetrics.screenPadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Sınıra 40 karakter kala görünür; aşılınca kırmızıya döner ve gönder pasifleşir.
    private var counter: some View {
        let remaining = model.remainingCommentCharacters
        return Group {
            if remaining >= 0 {
                Text("\(remaining) karakter kaldı")
            } else {
                Text("\(-remaining) karakter fazla")
            }
        }
        .font(MamaFont.caption)
        .monospacedDigit()
        .foregroundStyle(remaining < 0 ? MamaColor.statusUrgent : MamaColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Group {
                if model.isSending {
                    ProgressView().tint(MamaColor.onInk)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(MamaColor.onInk)
                }
            }
            .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
            .background(Circle().fill(MamaColor.ink))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(model.canSendComment ? 1 : 0.4)
        .disabled(!model.canSendComment)
        .accessibilityLabel(String(localized: "Yorumu gönder"))
    }
}
#endif
