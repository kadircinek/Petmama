#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Tab bar: Harita · İhtiyaçlar · + Ekle (ortada, belirgin) · Bağış · Profil (PRD 6.2).
/// Seçili sekme mint daire içinde (PRD 6.1).
struct MamaTabBar: View {
    let selected: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.map, title: String(localized: "Harita"), systemImage: "map.fill")
            item(.needs, title: String(localized: "İhtiyaçlar"), systemImage: "cross.case.fill")
            addButton
            item(.donate, title: String(localized: "Bağış"), systemImage: "gift.fill")
            item(.profile, title: String(localized: "Profil"), systemImage: "person.fill")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            MamaColor.card
                .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ tab: AppTab, title: String, systemImage: String) -> some View {
        let isSelected = selected == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? MamaColor.onStatus : MamaColor.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isSelected ? MamaColor.mint : Color.clear))
                Text(title)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? MamaColor.textPrimary : MamaColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: MamaMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var addButton: some View {
        Button {
            onSelect(.add)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(MamaColor.onInk)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(MamaColor.ink))
                    .overlay(Circle().strokeBorder(MamaColor.mint, lineWidth: 3))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .offset(y: -10)
                Text("Ekle")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .offset(y: -10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Ekle: nokta, hayvan, ihtiyaç veya mama koydum"))
    }
}
#endif
