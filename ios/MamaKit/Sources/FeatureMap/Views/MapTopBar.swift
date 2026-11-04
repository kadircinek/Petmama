#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Üst kontrol: arama, filtre (aktif sayı rozeti), lejant ve Harita / Liste / İhtiyaçlar segmenti (FR-H4).
struct MapTopBar: View {
    @Binding var mode: MapViewModel.Mode
    let activeFilterCount: Int
    let onSearch: () -> Void
    let onFilter: () -> Void
    let onLegend: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                searchButton
                filterButton
                Button(action: onLegend) {
                    Image(systemName: "info")
                }
                .buttonStyle(.mamaCircle)
                .accessibilityLabel(Text("Pin renklerinin anlamı"))
            }
            PillSegmentedControl(selection: $mode, options: [
                (value: MapViewModel.Mode.map, title: String(localized: "Harita")),
                (value: MapViewModel.Mode.list, title: String(localized: "Liste")),
                (value: MapViewModel.Mode.needs, title: String(localized: "İhtiyaçlar")),
            ])
        }
    }

    private var searchButton: some View {
        Button(action: onSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MamaColor.textPrimary)
                Text("Nokta, sokak veya park ara")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(MamaFont.subheadline)
            .foregroundStyle(MamaColor.textSecondary)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Capsule().fill(MamaColor.card).shadow(color: .black.opacity(0.1), radius: 8, y: 3))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Ara"))
    }

    private var filterButton: some View {
        Button(action: onFilter) {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .buttonStyle(.mamaCircle)
        .overlay(alignment: .topTrailing) {
            if activeFilterCount > 0 {
                Text("\(activeFilterCount)")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(MamaColor.onInk)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(MamaColor.ink))
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(activeFilterCount > 0
            ? Text("Filtreler, \(activeFilterCount) filtre aktif")
            : Text("Filtreler"))
    }
}
#endif
