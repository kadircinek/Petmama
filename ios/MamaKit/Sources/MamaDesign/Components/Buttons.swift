#if canImport(UIKit)
import SwiftUI

/// Birincil: siyah hap buton, sağda mint daire içinde ok (PRD 6.1).
/// "Mama koydum", "Devam", "Bağış yap" gibi eylemler.
public struct PrimaryPillButtonStyle: ButtonStyle {
    var accent: Color
    var systemImage: String
    var fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    public init(accent: Color = MamaColor.mint, systemImage: String = "arrow.right", fullWidth: Bool = true) {
        self.accent = accent
        self.systemImage = systemImage
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.onInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if fullWidth { Spacer(minLength: 8) }
            Image(systemName: systemImage)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(MamaColor.onStatus)
                .frame(width: 38, height: 38)
                .background(Circle().fill(accent))
                .accessibilityHidden(true)
        }
        .padding(.leading, 22)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .frame(minHeight: 54)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background(Capsule().fill(MamaColor.ink))
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// İkincil: beyaz hap, ince kenarlık. "Mama gerekli" (turuncu ikonlu), "Vazgeç".
public struct SecondaryPillButtonStyle: ButtonStyle {
    var tint: Color
    var systemImage: String?
    var fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    public init(tint: Color = MamaColor.textPrimary, systemImage: String? = nil, fullWidth: Bool = true) {
        self.tint = tint
        self.systemImage = systemImage
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            configuration.label
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background(Capsule().fill(MamaColor.card))
        .overlay(Capsule().strokeBorder(MamaColor.stroke, lineWidth: 1))
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Harita üstündeki yuvarlak beyaz kontrol (konumum, filtre).
public struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat
    public init(size: CGFloat = 48) { self.size = size }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(MamaColor.textPrimary)
            .frame(width: size, height: size)
            .background(Circle().fill(MamaColor.card).shadow(color: .black.opacity(0.12), radius: 8, y: 3))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryPillButtonStyle {
    public static var mamaPrimary: PrimaryPillButtonStyle { PrimaryPillButtonStyle() }

    public static func mamaPrimary(accent: Color = MamaColor.mint, systemImage: String = "arrow.right", fullWidth: Bool = true) -> PrimaryPillButtonStyle {
        PrimaryPillButtonStyle(accent: accent, systemImage: systemImage, fullWidth: fullWidth)
    }

    /// "Mama koydum": yeşil daire içinde pati.
    public static var mamaFed: PrimaryPillButtonStyle {
        PrimaryPillButtonStyle(accent: MamaColor.statusFed, systemImage: "pawprint.fill")
    }
}

extension ButtonStyle where Self == SecondaryPillButtonStyle {
    public static var mamaSecondary: SecondaryPillButtonStyle { SecondaryPillButtonStyle() }

    public static func mamaSecondary(tint: Color = MamaColor.textPrimary, systemImage: String? = nil, fullWidth: Bool = true) -> SecondaryPillButtonStyle {
        SecondaryPillButtonStyle(tint: tint, systemImage: systemImage, fullWidth: fullWidth)
    }

    /// "Mama gerekli": turuncu ikonlu beyaz hap.
    public static var mamaNeedsFood: SecondaryPillButtonStyle {
        SecondaryPillButtonStyle(tint: MamaColor.statusNeeds, systemImage: "exclamationmark.circle.fill")
    }
}

extension ButtonStyle where Self == CircleIconButtonStyle {
    public static var mamaCircle: CircleIconButtonStyle { CircleIconButtonStyle() }
}

/// Sade metin butonu ("Atla", "Tümünü gör").
public struct MamaTextButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(mama: title)
                .font(MamaFont.subheadline.weight(.semibold))
                .foregroundStyle(MamaColor.textSecondary)
                .frame(minHeight: MamaMetrics.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
