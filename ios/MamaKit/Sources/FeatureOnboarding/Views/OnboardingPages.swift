#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Tanıtım sayfası (ekran 2–4).
struct IntroPageView: View {
    let page: OnboardingViewModel.IntroPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            SymbolComposition(symbol: page.symbol, accents: page.accentSymbols, tint: page.tint.color)
            VStack(spacing: 12) {
                Text(page.title)
                    .font(MamaFont.title)
                    .foregroundStyle(MamaColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(MamaFont.body)
                    .foregroundStyle(MamaColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MamaMetrics.screenPadding + 8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// İzin ekranı (ekran 5–6): neden istediğimizi anlatan metin, "izin ver" / "Şimdi değil".
struct PermissionStepView: View {
    struct Point: Identifiable {
        let systemImage: String
        let text: String
        var id: String { text }
    }

    let symbol: String
    let accents: [String]
    let tint: Color
    let title: String
    let message: String
    let points: [Point]
    let primaryTitle: String
    let primaryIcon: String
    let isWorking: Bool
    let onPrimary: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    SymbolComposition(symbol: symbol, accents: accents, tint: tint, size: 150)
                        .padding(.top, 24)
                    VStack(spacing: 10) {
                        Text(title)
                            .font(MamaFont.title2)
                            .foregroundStyle(MamaColor.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(message)
                            .font(MamaFont.body)
                            .foregroundStyle(MamaColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: point.systemImage)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(MamaColor.ink)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(MamaColor.tileMint))
                                    .accessibilityHidden(true)
                                Text(point.text)
                                    .font(MamaFont.subheadline)
                                    .foregroundStyle(MamaColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .mamaCard()
                }
                .padding(.horizontal, MamaMetrics.screenPadding)
            }
            VStack(spacing: 4) {
                Button(action: onPrimary) {
                    if isWorking {
                        ProgressView().tint(MamaColor.onInk)
                    } else {
                        Text(primaryTitle)
                    }
                }
                .buttonStyle(.mamaPrimary(systemImage: primaryIcon))
                .disabled(isWorking)
                MamaTextButton(String(localized: "Şimdi değil"), action: onNotNow)
                    .disabled(isWorking)
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}

/// Yasal metin URL'leri tanımlı değilken ilk kullanım akışında gösterilen kısa gizlilik özeti.
struct LegalHighlightsSheet: View {
    let supportEmail: String
    @Environment(\.dismiss) private var dismiss

    private var points: [PermissionStepView.Point] {
        [
            .init(systemImage: "location.slash.fill", text: String(localized: "Konum geçmişini saklamayız. \"Mama koydum\" dediğinde yalnızca noktaya olan mesafe (metre) kaydedilir.")),
            .init(systemImage: "photo.badge.checkmark", text: String(localized: "Fotoğraflar yüklenmeden önce küçültülür, içlerindeki konum (EXIF/GPS) bilgisi silinir.")),
            .init(systemImage: "bell.badge.fill", text: String(localized: "Yakındaki bildirimleri açarsan yalnızca son yaklaşık konumun tutulur; her güncellemede üzerine yazılır.")),
            .init(systemImage: "trash.fill", text: String(localized: "Hesabını istediğin an uygulama içinden silebilirsin.")),
            .init(systemImage: "envelope.fill", text: String(localized: "Soruların için: \(supportEmail)")),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BannerView(String(localized: "Taslak — hukuk onayı bekliyor"), style: .warning, systemImage: "doc.badge.clock.fill")
                    ForEach(points) { point in
                        Label {
                            Text(point.text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: point.systemImage).foregroundStyle(MamaColor.statusFed)
                        }
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textPrimary)
                    }
                    Text("Tam metne sonra Profil › Ayarlar › Gizlilik ve KVKK bölümünden de ulaşabilirsin.")
                        .font(MamaFont.footnote)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                .mamaCard()
                .padding(MamaMetrics.screenPadding)
            }
            .mamaBackground()
            .navigationTitle(String(localized: "Gizlilik özeti"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Tamam")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
