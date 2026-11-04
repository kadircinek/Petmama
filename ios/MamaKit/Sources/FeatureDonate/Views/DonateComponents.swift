#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Bağışın doğrudan … derneğine gider" şeffaflık kartı (PRD 8.2).
struct DonationTransparencyCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(MamaColor.statusFed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Şeffaf bağış")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                Text(text)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .mamaCard()
        .accessibilityElement(children: .combine)
    }
}

/// "Bu ay X kg mama dağıtıldı" sayacı.
struct DonationCounterCard: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bag.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MamaColor.tileMint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .mamaCard()
        .accessibilityElement(children: .combine)
    }
}

/// Büyük paket kartı: Kedi maması 5 USD / Köpek maması 7 USD (PRD 8.1).
struct DonationPackageCard: View {
    let title: String
    let species: AnimalSpecies
    let price: String
    let tryText: String?
    let impact: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: species.systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(species == .cat ? MamaColor.tilePeach : MamaColor.tileBlue)
                        )
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? MamaColor.statusFed : MamaColor.stroke)
                }
                .accessibilityHidden(true)
                Text(title)
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(price)
                        .font(MamaFont.title)
                        .foregroundStyle(MamaColor.textPrimary)
                    if let tryText {
                        Text(tryText)
                            .font(MamaFont.headline)
                            .foregroundStyle(MamaColor.textSecondary)
                        Text("günlük kurla")
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                }
                Text(impact)
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                    .fill(MamaColor.card)
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? MamaColor.ink : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Bağışım nereye gitti?" satırı → `AppRoute.donationTrace`.
struct DonationTraceRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MamaColor.tileLavender))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bağışım nereye gitti?")
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                Text("Bağıştan mama kabına yolculuk")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MamaColor.textSecondary)
                .accessibilityHidden(true)
        }
        .mamaCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Teslim fotoğrafları akışı v1.1'de (D13); şimdilik açıklama.
struct DeliveryPhotosPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(String(localized: "Teslim fotoğrafları"))
                TagChip(String(localized: "v1.1'de"), systemImage: "sparkles", style: .info)
            }
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous)
                        .fill(MamaColor.cardSecondary)
                        .frame(height: 84)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(MamaColor.textSecondary.opacity(0.6))
                        )
                }
            }
            .accessibilityHidden(true)
            Text("Teslim kanıtları v1.1'de geliyor. Gönüllüler mamayı noktalara bıraktığında fotoğrafını, konumunu ve kilosunu burada göreceksin.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .mamaCard()
    }
}
#endif
