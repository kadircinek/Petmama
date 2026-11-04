#if canImport(UIKit)
import SwiftUI
import MamaCore

/// Küçük hap etiket ("Kedi", "Kısır", "Doğrulanmış besleyici").
public struct TagChip: View {
    public enum Style: Sendable {
        case neutral, positive, warning, danger, info
    }

    let text: String
    let systemImage: String?
    let style: Style

    public init(_ text: String, systemImage: String? = nil, style: Style = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    private var foreground: Color {
        switch style {
        case .neutral: return MamaColor.textSecondary
        case .positive: return MamaColor.statusFed
        case .warning: return Color(hex: 0xB7791F)
        case .danger: return MamaColor.statusUrgent
        case .info: return Color(hex: 0x3B82C4)
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return MamaColor.cardSecondary
        case .positive: return MamaColor.statusFed.opacity(0.14)
        case .warning: return MamaColor.statusStale.opacity(0.22)
        case .danger: return MamaColor.statusUrgent.opacity(0.12)
        case .info: return Color(hex: 0x3B82C4).opacity(0.12)
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(LocalizedStringKey(text)).lineLimit(1)
        }
        .font(MamaFont.caption)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(background))
    }
}

/// Durum rozeti: renk + ikon + metin (renk körleri için üçü birlikte, PRD 6.1).
public struct StatusBadge: View {
    let status: SpotStatus
    let hasUrgentNeed: Bool
    let compact: Bool

    public init(status: SpotStatus, hasUrgentNeed: Bool = false, compact: Bool = false) {
        self.status = status
        self.hasUrgentNeed = hasUrgentNeed
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
            if !compact {
                Text(status.label)
                    .foregroundStyle(MamaColor.textPrimary)
            }
            if hasUrgentNeed {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(MamaColor.statusUrgent)
                if !compact {
                    Text("Acil ihtiyaç").foregroundStyle(MamaColor.statusUrgent)
                }
            }
        }
        .font(MamaFont.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(status.color.opacity(0.16)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasUrgentNeed ? "\(status.label), \(String(localized: "acil ihtiyaç var"))" : status.label)
    }
}

/// Seçilebilir hap (filtreler, form seçenekleri).
public struct SelectableChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(LocalizedStringKey(title)).lineLimit(1)
            }
            .font(MamaFont.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? MamaColor.onInk : MamaColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: MamaMetrics.minTapSize)
            .background(Capsule().fill(isSelected ? MamaColor.ink : MamaColor.card))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : MamaColor.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Satır satır kayan etiket dizilimi.
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
