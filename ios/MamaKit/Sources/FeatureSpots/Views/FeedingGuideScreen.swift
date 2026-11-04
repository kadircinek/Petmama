#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Sorumlu besleme rehberi (PRD 9.4). Statik içerik; tıbbi tavsiye vermez (FR-I4).
public struct FeedingGuideScreen: View {
    public init() {}

    private struct Tip: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let text: String
        let tint: Color
    }

    private let tips: [Tip] = [
        Tip(id: 1, systemImage: "sparkles", title: String(localized: "Alanı temiz tut"),
            text: String(localized: "Kapların çevresini temiz bırak, poşet ve ambalajları geri al. Temiz bir nokta komşuların da gönlünü kazanır."),
            tint: MamaColor.tileMint),
        Tip(id: 2, systemImage: "trash.slash.fill", title: String(localized: "Artık bırakma"),
            text: String(localized: "Hayvanlar yedikten sonra kalan mamayı topla. Ortada bekleyen mama koku ve haşere yapar."),
            tint: MamaColor.tilePeach),
        Tip(id: 3, systemImage: "door.left.hand.closed", title: String(localized: "Kapı önlerine koyma"),
            text: String(localized: "Apartman ve dükkân girişlerinin önü yerine ağaç dibi, bahçe kenarı gibi sakin köşeleri seç."),
            tint: MamaColor.tileBlue),
        Tip(id: 4, systemImage: "drop.fill", title: String(localized: "Su kaplarını temizle"),
            text: String(localized: "Su kaplarını sık sık yıka ve tazele. Yazın gölgeye, kışın donmayacak bir yere koy."),
            tint: MamaColor.tileBlue),
        Tip(id: 5, systemImage: "person.2.fill", title: String(localized: "Komşularla konuş"),
            text: String(localized: "Beslediğin noktayı komşularına anlat, birlikte sahiplenin. Sorun çıkarsa yeri birlikte değiştirmek kolaylaşır."),
            tint: MamaColor.tileLavender),
        Tip(id: 6, systemImage: "clock.fill", title: String(localized: "Kuru mama, sabit saat"),
            text: String(localized: "Kuru mamayı tercih et ve her gün aynı saatlerde koy. Hayvanlar düzene alışır, mama ortada beklemez."),
            tint: MamaColor.tileMint),
        Tip(id: 7, systemImage: "xmark.octagon.fill", title: String(localized: "İnsan yemeği verme"),
            text: String(localized: "Yemek artıkları, soğan, sarımsak, çikolata, kemik ve baharatlı yiyecekler hayvanlara zarar verir."),
            tint: MamaColor.tilePeach),
        Tip(id: 8, systemImage: "scissors", title: String(localized: "Kısırlaştırma ihtiyacını bildir"),
            text: String(localized: "Kısırlaştırılmamış bir hayvan görürsen \"İhtiyaç bildir\" ile kısırlaştırma talebi aç. Kulak küpesi veya kesiği kısırlık işaretidir."),
            tint: MamaColor.tileLavender),
    ]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bir kap mama, bir can")
                        .font(MamaFont.handwritten)
                        .foregroundStyle(MamaColor.textPrimary)
                    Text("Sokaktaki dostlarımızı beslerken komşularımızla da iyi geçinmek, beslemenin sürmesini sağlar. Birkaç küçük alışkanlık büyük fark yaratır.")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                }
                .padding(.bottom, 4)
                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(MamaColor.textPrimary)
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tip.tint))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title)
                                .font(MamaFont.headline)
                                .foregroundStyle(MamaColor.textPrimary)
                            Text(tip.text)
                                .font(MamaFont.subheadline)
                                .foregroundStyle(MamaColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .mamaCard(padding: 14)
                    .accessibilityElement(children: .combine)
                }
                Label("Bu rehber tıbbi tavsiye değildir. Hasta veya yaralı bir hayvan görürsen bir veterinere danış ve \"İhtiyaç bildir\" ile gönüllülere haber ver.", systemImage: "info.circle")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .mamaBackground()
        .navigationTitle("Sorumlu besleme rehberi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    PreviewEnvironment { _ in
        FeedingGuideScreen()
    }
}
#endif
