#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Son 7 gün" besleme çizelgesi (FR-N4): 7 sütun, gün etiketleri; turuncu nokta "mama gerekli" bildirimi.
struct FeedingTimelineSection: View {
    let bars: [SpotDetailViewModel.TimelineBar]
    let maxCount: Int
    let weeklyCount: Int

    private let barHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Son 7 gün"))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(bars) { bar in
                        column(bar)
                    }
                }
                HStack(spacing: 14) {
                    legendItem(color: MamaColor.statusFed, text: String(localized: "Mama kondu"))
                    legendItem(color: MamaColor.statusNeeds, text: String(localized: "Mama gerekli dendi"))
                    Spacer(minLength: 0)
                    Text("Bu hafta \(weeklyCount) kez")
                        .font(MamaFont.caption.weight(.semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                }
            }
            .mamaCard()
        }
    }

    private func column(_ bar: SpotDetailViewModel.TimelineBar) -> some View {
        VStack(spacing: 6) {
            Text("\(bar.fedCount)")
                .font(MamaFont.caption)
                .foregroundStyle(bar.fedCount > 0 ? MamaColor.textPrimary : MamaColor.textSecondary)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(MamaColor.cardSecondary)
                    .frame(height: barHeight)
                Capsule()
                    .fill(MamaColor.statusFed)
                    .frame(height: fillHeight(for: bar))
            }
            .frame(maxWidth: 26)
            .overlay(alignment: .top) {
                if bar.needCount > 0 {
                    Circle()
                        .fill(MamaColor.statusNeeds)
                        .frame(width: 10, height: 10)
                        .offset(y: -5)
                }
            }
            Text(bar.weekday.localizedShortName)
                .font(MamaFont.caption.weight(bar.isToday ? .bold : .medium))
                .foregroundStyle(bar.isToday ? MamaColor.textPrimary : MamaColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(for: bar)))
    }

    private func fillHeight(for bar: SpotDetailViewModel.TimelineBar) -> CGFloat {
        guard maxCount > 0, bar.fedCount > 0 else { return 0 }
        return max(12, barHeight * CGFloat(bar.fedCount) / CGFloat(maxCount))
    }

    private func accessibilityText(for bar: SpotDetailViewModel.TimelineBar) -> String {
        let day = bar.isToday ? String(localized: "Bugün") : bar.weekday.localizedShortName
        if bar.needCount > 0 {
            return String(localized: "\(day): \(bar.fedCount) kez mama kondu, \(bar.needCount) kez mama gerekli dendi")
        }
        return String(localized: "\(day): \(bar.fedCount) kez mama kondu")
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
        }
    }
}

#Preview {
    let now = Date()
    let bars = (0..<7).map { offset in
        SpotDetailViewModel.TimelineBar(
            day: now.addingTimeInterval(Double(offset - 6) * 86_400),
            weekday: Weekday.allCases[offset],
            fedCount: [2, 1, 0, 3, 1, 2, 1][offset],
            needCount: offset == 2 ? 1 : 0,
            isToday: offset == 6
        )
    }
    return FeedingTimelineSection(bars: bars, maxCount: 3, weeklyCount: 10)
        .padding()
        .mamaBackground()
}
#endif
