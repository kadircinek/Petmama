#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Haritada seçilen noktanın alt kartı: ad, durum, mesafe, son mama; "Mama koydum" ve "Detay" (FR-C1).
struct SelectedSpotCard: View {
    let spot: Spot
    let now: Date
    let onFed: () -> Void
    let onDetail: () -> Void
    let onClose: () -> Void

    var body: some View {
        let status = spot.currentStatus(now: now)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SpotThumbnail(spot: spot, now: now)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(spot.title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .lineLimit(2)
                    StatusBadge(status: status, hasUrgentNeed: spot.hasUrgentNeed)
                    HStack(spacing: 6) {
                        if let distance = spot.distanceMeters {
                            Label(MamaFormat.distance(distance), systemImage: "location.fill")
                            Text("·")
                        }
                        Text(lastFedText)
                    }
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(MamaColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(MamaColor.cardSecondary))
                        .frame(width: MamaMetrics.minTapSize, height: MamaMetrics.minTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Kartı kapat"))
            }
            HStack(spacing: 10) {
                Button("Mama koydum", action: onFed)
                    .buttonStyle(.mamaFed)
                Button("Detay", action: onDetail)
                    .buttonStyle(.mamaSecondary(fullWidth: false))
            }
        }
        .mamaCard()
    }

    private var lastFedText: String {
        guard let lastFedAt = spot.lastFedAt else { return String(localized: "Henüz kayıt yok") }
        return String(localized: "Son mama \(MamaFormat.relative(lastFedAt, now: now))")
    }
}

#Preview {
    PreviewEnvironment { _ in
        SelectedSpotCard(
            spot: DemoData.make().spots[0],
            now: Date(),
            onFed: {},
            onDetail: {},
            onClose: {}
        )
        .padding()
        .mamaBackground()
    }
}
#endif
