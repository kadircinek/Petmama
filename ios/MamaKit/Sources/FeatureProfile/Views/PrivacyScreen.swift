#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Uygulama içi KVKK özeti (PRD 9.5). Taslak: hukuk onayı bekliyor.
public struct PrivacyScreen: View {
    private let config: AppConfig
    @Environment(\.openURL) private var openURL

    public init(services: AppServices) {
        config = services.config
    }

    private struct Item: Identifiable {
        let systemImage: String
        let title: String
        let text: String
        var id: String { title }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BannerView(String(localized: "Taslak — hukuk onayı bekliyor"), style: .warning, systemImage: "doc.badge.clock.fill")
                Text("Mama Haritası'nı kullanırken kişisel verilerini 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) kapsamında nasıl işlediğimizi kısaca anlatıyoruz.")
                    .font(MamaFont.body)
                    .foregroundStyle(MamaColor.textPrimary)

                card(String(localized: "Hangi verileri işliyoruz?"), items: processedData)
                card(String(localized: "Neden işliyoruz?"), items: purposes)
                card(String(localized: "Ne kadar saklıyoruz?"), items: retention)
                rightsCard
                card(String(localized: "Veriler nerede?"), items: [
                    Item(systemImage: "server.rack", title: String(localized: "Avrupa Birliği (Frankfurt)"),
                         text: String(localized: "Sunucularımız AB'de, Frankfurt'ta bulunur. Yurt dışına aktarım KVKK hükümleri açısından hukuki değerlendirmeye tabidir.")),
                ])
                contactCard
            }
            .padding(.horizontal, MamaMetrics.screenPadding)
            .padding(.vertical, 12)
        }
        .mamaBackground()
        .navigationTitle(String(localized: "Gizlilik ve KVKK"))
    }

    // MARK: - İçerik

    private var processedData: [Item] {
        [
            Item(systemImage: "person.crop.circle", title: String(localized: "Hesap bilgileri"),
                 text: String(localized: "E-posta adresin veya Apple kimliğin, görünen adın, isteğe bağlı mahallen ve profil fotoğrafın.")),
            Item(systemImage: "photo", title: String(localized: "Fotoğraflar"),
                 text: String(localized: "Yüklemeden önce küçültülür; içindeki EXIF ve GPS konum bilgisi silinir.")),
            Item(systemImage: "ruler", title: String(localized: "Check-in mesafesi"),
                 text: String(localized: "\"Mama koydum\" dediğinde yalnızca noktaya olan uzaklık (metre) kaydedilir. Konum geçmişini asla saklamayız.")),
            Item(systemImage: "location.circle", title: String(localized: "Son yaklaşık konum"),
                 text: String(localized: "Yalnızca yakındaki bildirimler açıksa: yaklaşık 110 m'ye yuvarlanmış tek bir değer, her güncellemede üzerine yazılır.")),
            Item(systemImage: "bell.badge", title: String(localized: "Cihaz bildirim anahtarı"),
                 text: String(localized: "Sana bildirim gönderebilmek için cihazının push anahtarı.")),
            Item(systemImage: "flag", title: String(localized: "Raporlar ve engellemeler"),
                 text: String(localized: "Topluluğu ve hayvanları korumak için gönderdiğin raporlar ve engellediğin kullanıcılar.")),
        ]
    }

    private var purposes: [Item] {
        [
            Item(systemImage: "map", title: String(localized: "Haritayı ve bildirimleri sunmak"),
                 text: String(localized: "Yakındaki noktaları göstermek, \"mama gerekli\" haberlerini iletmek.")),
            Item(systemImage: "checkmark.shield", title: String(localized: "Sahte kayıtları önlemek"),
                 text: String(localized: "Check-in'in noktanın yanında yapıldığını doğrulamak, güven puanı ve günlük limitler.")),
            Item(systemImage: "pawprint", title: String(localized: "Hayvan güvenliği ve moderasyon"),
                 text: String(localized: "Konumları kötüye kullanıma karşı korumak, raporları 24 saat içinde incelemek.")),
        ]
    }

    private var retention: [Item] {
        [
            Item(systemImage: "clock", title: String(localized: "Hesabın açık olduğu sürece"),
                 text: String(localized: "Hesap bilgilerin, takip ettiklerin ve bildirimlerin hesabını kullandığın sürece saklanır.")),
            Item(systemImage: "trash", title: String(localized: "Hesabı silince"),
                 text: String(localized: "Kişisel verilerin silinir. Eklediğin noktalar ve hayvan kayıtları topluluk için anonim olarak kalır.")),
            Item(systemImage: "arrow.triangle.2.circlepath", title: String(localized: "Son yaklaşık konum"),
                 text: String(localized: "Her güncellemede üzerine yazılır; bildirimleri kapatırsan kullanılmaz.")),
        ]
    }

    private var rights: [String] {
        [
            String(localized: "Kişisel verilerinin işlenip işlenmediğini öğrenme ve bilgi talep etme"),
            String(localized: "İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme"),
            String(localized: "Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme"),
            String(localized: "Eksik veya yanlış işlenmişse düzeltilmesini, gerekirse silinmesini isteme"),
            String(localized: "Otomatik analiz sonucu aleyhine bir sonuca itiraz etme"),
            String(localized: "Kanuna aykırı işleme nedeniyle zarara uğradıysan giderilmesini talep etme"),
        ]
    }

    private func card(_ title: String, items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MamaColor.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(MamaColor.tileMint))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(MamaFont.headline).foregroundStyle(MamaColor.textPrimary)
                        Text(item.text)
                            .font(MamaFont.subheadline)
                            .foregroundStyle(MamaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    private var rightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(String(localized: "Hakların (KVKK md. 11)"))
            ForEach(rights, id: \.self) { right in
                Label {
                    Text(right).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MamaColor.statusFed)
                }
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textPrimary)
            }
            Text("Hesabını ve kişisel verilerini Ayarlar › Hesabı sil ile istediğin an silebilirsin.")
                .font(MamaFont.footnote)
                .foregroundStyle(MamaColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "İletişim"))
            Text("Başvuruların ve soruların için bize e-postayla ulaşabilirsin.")
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
            Button(config.supportEmail) {
                if let url = URL(string: "mailto:\(config.supportEmail)") { openURL(url) }
            }
            .buttonStyle(.mamaSecondary(systemImage: "envelope.fill"))
            legalLink(String(localized: "KVKK aydınlatma metninin tamamı"), url: config.kvkkNoticeURL)
            legalLink(String(localized: "Gizlilik politikası"), url: config.privacyPolicyURL)
            legalLink(String(localized: "Kullanım koşulları"), url: config.termsURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mamaCard()
    }

    @ViewBuilder
    private func legalLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: "arrow.up.right.square")
                    .font(MamaFont.subheadline.weight(.semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(minHeight: MamaMetrics.minTapSize)
            }
        }
    }
}

#Preview {
    PreviewEnvironment { services in PrivacyScreen(services: services) }
}
#endif
