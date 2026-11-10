#if canImport(UIKit)
import SwiftUI
import MamaCore

/// Bölüm başlığı + isteğe bağlı "Tümünü gör".
public struct SectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(mama: title)
                .font(MamaFont.title3)
                .foregroundStyle(MamaColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                MamaTextButton(actionTitle, action: action)
            }
        }
    }
}

/// Ana sayfa pastel hızlı eylem karosu (PRD 6.1 "Kategori karoları").
public struct QuickActionTile: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MamaColor.card.opacity(0.7)))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mama: title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(mama: subtitle)
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous).fill(tint))
            .contentShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Profil istatistik şeridi: besledi nokta / check-in / kapatılan ihtiyaç (FR-P2).
public struct StatsStrip: View {
    public struct Item: Identifiable, Hashable {
        public let id: String
        public let value: String
        public let label: String

        public init(value: String, label: String) {
            self.id = label
            self.value = value
            self.label = label
        }
    }

    let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(MamaFont.title2)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text(mama: item.label)
                        .font(MamaFont.caption)
                        .foregroundStyle(MamaColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                if index < items.count - 1 {
                    Divider().frame(height: 36)
                }
            }
        }
        .mamaCard(padding: 14)
    }
}

/// Üst ilerleme çizgileri (onboarding ve 3 adımlı ekleme akışı, PRD 6.3 #2-4, #16).
public struct ProgressSegments: View {
    let count: Int
    let current: Int

    public init(count: Int, current: Int) {
        self.count = count
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? MamaColor.ink : MamaColor.stroke)
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Adım \(current + 1) / \(count)"))
    }
}

/// Hap biçimli segment kontrol (Harita / Liste / İhtiyaçlar, FR-H4).
public struct PillSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var namespace

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(MamaFont.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? MamaColor.onInk : MamaColor.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if isSelected {
                                Capsule().fill(MamaColor.ink).matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(MamaColor.card).shadow(color: .black.opacity(0.08), radius: 8, y: 2))
    }
}

/// Büyük seçim kartı (nokta tipi, hayvan türü gibi).
public struct ChoiceCard: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, systemImage: String, tint: Color = MamaColor.tileMint, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mama: title).font(MamaFont.headline).foregroundStyle(MamaColor.textPrimary)
                    if let subtitle {
                        Text(mama: subtitle).font(MamaFont.caption).foregroundStyle(MamaColor.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? MamaColor.statusFed : MamaColor.stroke)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                    .fill(MamaColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? MamaColor.ink : MamaColor.stroke, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// İkon + başlık + değer satırı (detay ekranları).
public struct InfoRow: View {
    let systemImage: String
    let title: String
    let value: String

    public init(systemImage: String, title: String, value: String) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(MamaColor.textSecondary)
                .frame(width: 24)
            Text(mama: title).foregroundStyle(MamaColor.textSecondary)
            Spacer()
            Text(value).foregroundStyle(MamaColor.textPrimary).multilineTextAlignment(.trailing)
        }
        .font(MamaFont.subheadline)
        .accessibilityElement(children: .combine)
    }
}
#endif
