#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Açılış (ekran 1): mint zemin, logo, "Mama Haritası" ve el yazısı slogan.
public struct SplashView: View {
    @State private var appeared = false

    public init() {}

    public var body: some View {
        ZStack {
            MamaBackground()
            DoodleLayer()
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 18) {
                MamaLogo(size: 128)
                    .scaleEffect(appeared ? 1 : 0.86)
                Text("Mama Haritası")
                    .font(MamaFont.largeTitle)
                    .foregroundStyle(MamaColor.textPrimary)
                Text("Bir kap mama, bir can")
                    .font(MamaFont.handwritten)
                    .foregroundStyle(MamaColor.textSecondary)
                    .rotationEffect(.degrees(-3))
                    .overlay(alignment: .bottom) {
                        Squiggle(waves: 4)
                            .stroke(MamaColor.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(height: 8)
                            .offset(y: 10)
                            .accessibilityHidden(true)
                    }
            }
            .opacity(appeared ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Mama Haritası. Bir kap mama, bir can."))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { appeared = true }
        }
    }
}

#Preview {
    SplashView()
}
#endif
