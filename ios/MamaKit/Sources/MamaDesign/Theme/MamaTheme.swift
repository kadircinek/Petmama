#if canImport(UIKit)
import SwiftUI
import UIKit

// Tasarım dili (PRD 6.1): çok açık mint/adaçayı zemin, beyaz kartlar, siyah hap birincil buton,
// pastel karolar, SF Pro Rounded. Koyu temada mint yerine koyu adaçayı.

public enum MamaColor {
    // Zemin gradyanı: bgMint ≈ #E9F5F0 → #F4FAF7
    public static let backgroundTop = Color(light: 0xE9F5F0, dark: 0x15201B)
    public static let backgroundBottom = Color(light: 0xF4FAF7, dark: 0x0F1613)

    public static let card = Color(light: 0xFFFFFF, dark: 0x1E2925)
    public static let cardSecondary = Color(light: 0xF3F7F5, dark: 0x26332E)
    public static let stroke = Color(light: 0xDCE5E1, dark: 0x34433D)

    public static let textPrimary = Color(light: 0x13201A, dark: 0xF0F5F2)
    public static let textSecondary = Color(light: 0x56645E, dark: 0xA8B5AF)

    /// Birincil hap butonun zemini: açık temada siyah, koyu temada açık.
    public static let ink = Color(light: 0x111714, dark: 0xEEF4F1)
    public static let onInk = Color(light: 0xFFFFFF, dark: 0x111714)
    /// Birincil butondaki ok dairesi.
    public static let mint = Color(light: 0x8ED8B5, dark: 0x5DBE93)

    // Kategori karoları (pastel kareler)
    public static let tileMint = Color(light: 0xD6F0E3, dark: 0x21362C)
    public static let tileBlue = Color(light: 0xDCEAF8, dark: 0x1D2B39)
    public static let tileLavender = Color(light: 0xE7E0F7, dark: 0x2A2439)
    public static let tilePeach = Color(light: 0xFCE6D6, dark: 0x3A2A1F)

    // Durum renkleri (PRD 6.1) — her zaman ikon + metinle birlikte kullanılır (renk körlüğü).
    public static let statusFed = Color(hex: 0x3BB273)
    public static let statusStale = Color(hex: 0xF2C14E)
    public static let statusNeeds = Color(hex: 0xF28C38)
    public static let statusUrgent = Color(hex: 0xE5484D)
    public static let statusUnknown = Color(hex: 0xA0A7A4)

    /// Durum renginin üzerindeki metin/ikon için yeterli kontrast.
    public static let onStatus = Color(hex: 0x13201A)
}

public enum MamaFont {
    /// Büyük ve ferah başlıklar (28–32 pt).
    public static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let title = Font.system(.title, design: .rounded, weight: .bold)
    public static let title2 = Font.system(.title2, design: .rounded, weight: .bold)
    public static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)
    public static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let body = Font.system(.body, design: .rounded)
    public static let bodyEmphasized = Font.system(.body, design: .rounded, weight: .semibold)
    public static let callout = Font.system(.callout, design: .rounded)
    public static let subheadline = Font.system(.subheadline, design: .rounded)
    public static let footnote = Font.system(.footnote, design: .rounded)
    public static let caption = Font.system(.caption, design: .rounded, weight: .medium)
    /// El yazısı slogan ("Bir kap mama, bir can"). Noteworthy iOS'ta yerleşik.
    public static let handwritten = Font.custom("Noteworthy-Bold", size: 24, relativeTo: .title2)
}

public enum MamaMetrics {
    public static let cornerRadius: CGFloat = 20
    public static let smallCornerRadius: CGFloat = 14
    public static let screenPadding: CGFloat = 20
    /// Minimum dokunma alanı (PRD 6.1 erişilebilirlik).
    public static let minTapSize: CGFloat = 44
}

/// Tam ekran mint gradyan zemin.
public struct MamaBackground: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [MamaColor.backgroundTop, MamaColor.backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Ekran zemini. `List`/`Form` için gizli scroll zemini de ayarlanır.
    public func mamaBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(MamaBackground())
    }

    /// Beyaz kart: 20 pt köşe, çok hafif gölge.
    public func mamaCard(padding: CGFloat = 16, cornerRadius: CGFloat = MamaMetrics.cornerRadius) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MamaColor.card)
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            )
    }
}

extension Color {
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Açık/koyu temaya göre değişen renk.
    public init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
