#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

// Fotoğraf kullanılmadan (D14) SF Symbols ve basit `Path`'lerle kurulan illüstrasyonlar.

/// Logo: mint daire içinde pati, el çizimi hissi veren kesikli halka, yanlarda kedi ve köpek.
struct MamaLogo: View {
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(MamaColor.ink.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
                .frame(width: size * 1.18, height: size * 1.18)
                .rotationEffect(.degrees(-8))
            Circle()
                .fill(MamaColor.mint)
                .frame(width: size, height: size)
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(MamaColor.ink)
            Image(systemName: "cat.fill")
                .font(.system(size: size * 0.2, weight: .semibold))
                .foregroundStyle(MamaColor.ink)
                .rotationEffect(.degrees(-10))
                .offset(x: -size * 0.58, y: size * 0.42)
            Image(systemName: "dog.fill")
                .font(.system(size: size * 0.2, weight: .semibold))
                .foregroundStyle(MamaColor.ink)
                .rotationEffect(.degrees(10))
                .offset(x: size * 0.58, y: size * 0.42)
        }
        .frame(width: size * 1.5, height: size * 1.3)
        .accessibilityHidden(true)
    }
}

/// Dalgalı, el çizimi gibi duran çizgi.
struct Squiggle: Shape {
    var waves: Int = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let segments = max(1, waves * 2)
        let step = rect.width / CGFloat(segments)
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for index in 0..<segments {
            let x = rect.minX + CGFloat(index + 1) * step
            let controlY = index.isMultiple(of: 2) ? rect.minY : rect.maxY
            path.addQuadCurve(to: CGPoint(x: x, y: rect.midY), control: CGPoint(x: x - step / 2, y: controlY))
        }
        return path
    }
}

/// Zemine dağılmış kalp, pati ve dalga karalamaları.
struct DoodleLayer: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Squiggle()
                    .stroke(MamaColor.ink.opacity(0.16), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 110, height: 28)
                    .rotationEffect(.degrees(-14))
                    .position(x: width * 0.24, y: height * 0.18)
                Squiggle(waves: 2)
                    .stroke(MamaColor.ink.opacity(0.14), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 90, height: 24)
                    .rotationEffect(.degrees(10))
                    .position(x: width * 0.78, y: height * 0.84)
                doodle("heart", size: 28, rotation: -14, color: MamaColor.statusNeeds.opacity(0.7))
                    .position(x: width * 0.82, y: height * 0.2)
                doodle("heart.fill", size: 16, rotation: 12, color: MamaColor.statusUrgent.opacity(0.45))
                    .position(x: width * 0.14, y: height * 0.7)
                doodle("sparkle", size: 20, rotation: 0, color: MamaColor.ink.opacity(0.3))
                    .position(x: width * 0.7, y: height * 0.3)
                doodle("pawprint", size: 22, rotation: 22, color: MamaColor.ink.opacity(0.22))
                    .position(x: width * 0.24, y: height * 0.86)
                doodle("pawprint", size: 16, rotation: -28, color: MamaColor.ink.opacity(0.18))
                    .position(x: width * 0.86, y: height * 0.62)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func doodle(_ name: String, size: CGFloat, rotation: Double, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(rotation))
    }
}

/// Tanıtım ve izin sayfalarının büyük sembol kompozisyonu.
struct SymbolComposition: View {
    let symbol: String
    let accents: [String]
    let tint: Color
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(MamaColor.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 7]))
                .frame(width: size * 1.16, height: size * 1.16)
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(MamaColor.ink)
            ForEach(Array(accents.prefix(3).enumerated()), id: \.offset) { index, accent in
                let angle = Angle.degrees(-140 + Double(index) * 100)
                Image(systemName: accent)
                    .font(.system(size: size * 0.11, weight: .bold))
                    .foregroundStyle(MamaColor.ink)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .background(Circle().fill(MamaColor.card).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
                    .offset(x: CGFloat(cos(angle.radians)) * size * 0.56, y: CGFloat(sin(angle.radians)) * size * 0.56)
            }
        }
        .frame(width: size * 1.4, height: size * 1.3)
        .accessibilityHidden(true)
    }
}

extension OnboardingViewModel.IntroPage.Tint {
    var color: Color {
        switch self {
        case .mint: return MamaColor.tileMint
        case .blue: return MamaColor.tileBlue
        case .peach: return MamaColor.tilePeach
        }
    }
}
#endif
