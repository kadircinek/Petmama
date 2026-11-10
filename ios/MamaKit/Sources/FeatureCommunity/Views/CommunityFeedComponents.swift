#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Giriş yapmamış ziyaretçi için davet. Besleyicilerin konuşmaları girişsiz gezilemez (D17).
struct CommunitySignInGate: View {
    let onSignIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MascotView(.duo, mood: .happy, size: 120)
                Text("Mahallene katıl")
                    .font(MamaFont.title2)
                    .foregroundStyle(MamaColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Besleyicilerin paylaşımlarını görmek ve yazmak için giriş yap. Konuşmalar yalnızca giriş yapanlara açık.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onSignIn) {
                    Text("Giriş yap")
                }
                .buttonStyle(.mamaPrimary)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .mamaCard(padding: 24)
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 24)
        }
    }
}

/// "Bu hafta mahallende": beslenmiş nokta-gün (kuzey yıldızı metriği), besleyici ve paylaşım sayıları.
struct CommunitySummaryCard: View {
    let summary: CommunitySummary
    /// "N kişi yerine bakacak birini arıyor" satırı: akışı o türe süzer.
    let onShowCoverRequests: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bu hafta mahallende")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(summary.fedSpotDays7d)")
                            .font(MamaFont.largeTitle)
                            .foregroundStyle(MamaColor.textPrimary)
                            .monospacedDigit()
                        Text("beslenmiş nokta-gün")
                            .font(MamaFont.subheadline)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
                MascotView(.duo, mood: .happy, size: 72)
            }
            FlowLayout(spacing: 8) {
                TagChip(String(localized: "\(summary.activeFeeders7d) besleyici"), systemImage: "person.2.fill", style: .positive)
                TagChip(String(localized: "\(summary.posts7d) paylaşım"), systemImage: "text.bubble.fill")
            }
            if summary.openCoverRequests > 0 {
                coverRequestsButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    private var coverRequestsButton: some View {
        Button(action: onShowCoverRequests) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .accessibilityHidden(true)
                Text("\(summary.openCoverRequests) kişi yerine bakacak birini arıyor")
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(MamaFont.subheadline.weight(.semibold))
            .foregroundStyle(MamaColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: MamaMetrics.minTapSize, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                    .fill(MamaColor.tileLavender)
            )
            .contentShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Yerime bakar mısın isteklerini gösterir"))
    }
}

/// Yatay tür filtresi: "Tümü" + beş paylaşım türü.
struct CommunityKindFilterBar: View {
    let selected: CommunityPostKind?
    let onSelect: (CommunityPostKind?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SelectableChip(String(localized: "Tümü"), isSelected: selected == nil) {
                    onSelect(nil)
                }
                ForEach(CommunityPostKind.allCases, id: \.self) { kind in
                    SelectableChip(kind.label, systemImage: kind.systemImage, isSelected: selected == kind) {
                        onSelect(selected == kind ? nil : kind)
                    }
                }
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
        }
    }
}

/// Boş akış. Filtre açıkken "Filtreyi kaldır", değilken ilk paylaşıma davet.
struct CommunityEmptyState: View {
    let isFiltered: Bool
    let onCompose: () -> Void
    let onClearFilter: () -> Void

    private var title: String {
        isFiltered ? String(localized: "Bu türde henüz paylaşım yok") : String(localized: "Mahallende henüz paylaşım yok")
    }

    private var message: String {
        isFiltered
            ? String(localized: "Filtreyi kaldırıp mahalledeki tüm paylaşımlara bakabilirsin.")
            : String(localized: "İlk yazan sen ol.")
    }

    var body: some View {
        VStack(spacing: 14) {
            MascotView(.duo, mood: .neutral, size: 96)
            Text(title)
                .font(MamaFont.title3)
                .foregroundStyle(MamaColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .multilineTextAlignment(.center)
            if isFiltered {
                Button(action: onClearFilter) {
                    Text("Filtreyi kaldır")
                }
                .buttonStyle(.mamaSecondary(systemImage: "line.3.horizontal.decrease.circle", fullWidth: false))
                .padding(.top, 4)
            } else {
                Button(action: onCompose) {
                    Text("Mahalleye yaz")
                }
                .buttonStyle(.mamaPrimary(systemImage: "square.and.pencil", fullWidth: false))
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Giriş daveti") {
    CommunitySignInGate {}
        .mamaBackground()
}

#Preview("Özet ve boş durum") {
    ScrollView {
        VStack(spacing: 16) {
            CommunitySummaryCard(
                summary: CommunitySummary(fedSpotDays7d: 42, activeFeeders7d: 9, openCoverRequests: 2, posts7d: 14),
                onShowCoverRequests: {}
            )
            .padding(.horizontal, MamaMetrics.screenPadding)
            CommunityKindFilterBar(selected: .coverRequest) { _ in }
            CommunityEmptyState(isFiltered: true, onCompose: {}, onClearFilter: {})
            CommunityEmptyState(isFiltered: false, onCompose: {}, onClearFilter: {})
        }
    }
    .mamaBackground()
}
#endif
