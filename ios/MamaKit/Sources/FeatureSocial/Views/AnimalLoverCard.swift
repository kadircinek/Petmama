#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Hayvansever kartı: ad, rozet, mesafe aralığı (asla kesin mesafe), besleme istatistiği, hakkında, ilgi etiketleri
/// ve bağlantı durumuna göre tek eylem.
struct AnimalLoverCard: View {
    let lover: AnimalLover
    let myInterests: Set<SocialInterest>
    let isSending: Bool
    let isDisabled: Bool
    let onRequest: () -> Void
    let onRespond: (_ requestId: UUID, _ accept: Bool) -> Void
    let onOpenChat: (_ conversationId: UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: lover.displayName, url: lover.avatarURL, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: lover.displayName)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    FlowLayout(spacing: 6) {
                        TagChip(lover.distanceBand.label, systemImage: "location.circle.fill", style: .info)
                        if lover.isVerifiedFeeder {
                            TagChip(String(localized: "Doğrulanmış besleyici"), systemImage: "checkmark.seal.fill", style: .positive)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if lover.fedLast30Days > 0 {
                let count = lover.fedLast30Days
                Label {
                    Text("Son 30 günde \(count) kez mama koydu")
                } icon: {
                    Image(systemName: "pawprint.fill")
                }
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
            }
            if !lover.about.isEmpty {
                Text(verbatim: lover.about)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !lover.interests.isEmpty {
                InterestTags(interests: lover.interests, highlighted: myInterests)
            }
            if lover.sharedInterestCount > 0 {
                let count = lover.sharedInterestCount
                Text("\(count) ortak ilgi alanı")
                    .font(MamaFont.caption.weight(.semibold))
                    .foregroundStyle(MamaColor.statusFed)
            }
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    @ViewBuilder
    private var action: some View {
        switch lover.connection {
        case .none:
            Button(action: onRequest) {
                if isSending {
                    HStack(spacing: 8) {
                        ProgressView().tint(MamaColor.onInk)
                        Text("Gönderiliyor…")
                    }
                } else {
                    Text("İstek gönder")
                }
            }
            .buttonStyle(.mamaPrimary(systemImage: "hand.wave.fill"))
            .disabled(isSending || isDisabled)
        case .outgoingPending:
            HStack(spacing: 8) {
                if isSending {
                    // Demo'da senaryolu kabul birkaç saniye sürer; bu sürede ilerleme gösterilir.
                    ProgressView()
                }
                TagChip(String(localized: "İstek gönderildi, yanıt bekleniyor"), systemImage: "hourglass", style: .neutral)
            }
        case .incomingPending(let requestId):
            VStack(alignment: .leading, spacing: 8) {
                Text("Seninle tanışmak istiyor")
                    .font(MamaFont.caption.weight(.semibold))
                    .foregroundStyle(MamaColor.textSecondary)
                HStack(spacing: 10) {
                    Button { onRespond(requestId, true) } label: { Text("Kabul et") }
                        .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
                    Button { onRespond(requestId, false) } label: { Text("Reddet") }
                        .buttonStyle(.mamaSecondary(fullWidth: false))
                }
                .disabled(isDisabled)
            }
        case .connected(let conversationId):
            Button { onOpenChat(conversationId) } label: { Text("Mesaj yaz") }
                .buttonStyle(.mamaSecondary(systemImage: "bubble.left.fill"))
        }
    }
}
#endif
