# Mama Haritası

Sokak hayvanlarını besleyenlerin mama ve su bıraktıkları noktaları, oradaki hayvanları ve ihtiyaçlarını
sokak sokak bir haritada işaretleyip birlikte koordine olduğu iOS uygulaması.

> **Ürünün kalbi üç eylem:** "Mama koydum" (nokta yeşile döner) · "Mama gerekli" (nokta turuncuya döner,
> yakındaki gönüllülere bildirim gider) · "İhtiyaç var" (veteriner, kısırlaştırma, kış barınağı…).

Bu repo PRD'deki (Mama Haritası — iOS Uygulama PRD, 4 Kasım 2026) **MVP kapsamını** uygular.

## Yapı

```
ios/
  project.yml              XcodeGen proje tanımı (iOS 17+, Xcode 16+)
  App/                     Uygulama hedefi: giriş noktası, Info.plist, izin metinleri, Privacy Manifest, ikon
  MamaKit/                 Swift Package — tüm kod burada (PRD 7.1: MVVM + feature modülleri)
    Sources/
      MamaCore/            Domain modelleri, PRD iş kuralları, repository protokolleri, demo backend (Linux'ta test edilir)
      MamaDesign/          Tasarım sistemi (mint zemin, siyah hap butonlar, pastel karolar, pinler)
      MamaSupabase/        Supabase implementasyonu (supabase-swift)
      MamaPersistence/     SwiftData çevrimdışı önbellek + check-in kuyruğu
      FeatureMap/          Harita / Liste / İhtiyaçlar segmenti, ana sayfa paneli, filtre, arama
      FeatureSpots/        Nokta detayı, check-in, tek dokunuş "Mama koydum", nokta ekleme akışı
      FeatureAnimals/      Hayvan profili, hayvan ekleme
      FeatureNeeds/        İhtiyaçlar, ihtiyaç detayı/oluşturma, acil veteriner bilgisi
      FeatureDonate/       Bağış (harici Safari linki), "Bağışım nereye gitti?"
      FeatureCommunity/    Mahalle: besleyicilerin akışı, yorumlar, pati, "Yerime bakar mısın?" (D17)
      FeatureProfile/      Profil, takip edilenler, bildirimler, ayarlar, hesap silme, raporla
      FeatureOnboarding/   Açılış, 3 adımlı tanıtım, konum/bildirim izni, giriş (Apple + e-posta)
      AppFeature/          Kompozisyon kökü: tab bar, rota çözümleme, konum, push, servis kurulumu
supabase/                  Postgres + PostGIS şeması, RLS, RPC'ler, cron, edge functions, SQL testleri
docs/
  backend-contract.md      iOS ↔ Supabase sözleşmesi (RPC adları, dönüş şekilleri, gizlilik kuralları)
  DECISIONS.md             PRD'deki açık sorular için alınan varsayımlar
  ios-conventions.md       Kodlama kuralları
scripts/linux-swift.sh     MamaKit'i Docker'da (Swift 6, Linux) derler/test eder
scripts/generate_mascots.py  Maskot ikonlarını (SVG) üretir; önizleme: docs/mascots.png
```

## Çalıştırma (macOS)

```bash
brew install xcodegen
```
```bash
cd ios && xcodegen generate && open MamaHaritasi.xcodeproj
```

- **Demo modu:** `MAMA_SUPABASE_URL` boşsa uygulama Kadıköy/Moda demo verisiyle bellek içi backend'de çalışır
  (D7). Demo giriş: `demo@mamaharitasi.app` / `demo1234` veya Sign in with Apple.
- **Gerçek backend:** `ios/App/Config/Secrets.example.xcconfig` dosyasını `Secrets.xcconfig` olarak kopyalayıp
  Supabase URL ve publishable key girin. Backend kurulumu: [`supabase/README.md`](supabase/README.md).
- Signing: Xcode'da takımınızı seçin; Sign in with Apple ve Push Notifications capability'leri entitlements'ta hazır.

## Test

```bash
scripts/linux-swift.sh test
```
```bash
bash supabase/tests/run.sh
```
Son durum: Linux'ta **271 Swift testi** (MamaCore, Supabase DTO'ları, tüm ViewModel'ler, AppFeature) ve
**315 SQL assertion'ı** (`supabase/postgres` Docker imajı) geçiyor. SwiftUI görünümleri Linux'ta derlenemediği için
kod incelemesinden geçti; ilk gerçek derleme Xcode 16+ ile (veya CI'daki `ios-build` işiyle) yapılmalı.

CI (`.github/workflows/ci.yml`): Linux `swift test`, String Catalog kontrolü, SQL testleri ve macOS'ta Xcode
simülatör derlemesi.

Yeni metin eklediysen:
```bash
python3 scripts/extract_strings.py
```
(İngilizce karşılıkları `scripts/l10n/en.json` dosyasına ekle.)

## PRD → kod eşlemesi (MVP)

| PRD | Nerede |
|---|---|
| FR-H1…H8 harita, kümeleme, pin renkleri, filtre, uzun basma, Apple Haritalar, çevrimdışı | `FeatureMap`, `MamaCore/Geo/SpotClusterer`, `SpotStatusRules`, `OfflineCheckInQueue` |
| FR-N1…N6 nokta tipleri, 3 adımlı ekleme, 15 m mükerrer, 7 gün çizelge, eskime, "artık yok" | `FeatureSpots`, `DuplicateSpotPolicy`, `InactiveSpotPolicy` |
| FR-C1…C5 check-in, 100/300 m, bildirim limiti, "Teşekkürler" döngüsü | `CheckInPolicy`, `NotificationPolicy`, `supabase` `check_in` RPC |
| FR-A1…A4 hayvan profili, "gördüm", uyarı etiketi | `FeatureAnimals` |
| FR-I1…I5 ihtiyaçlar, üstlenme, acil veteriner | `FeatureNeeds` |
| FR-P1…P4 giriş, profil, hesap silme, doğrulanmış besleyici | `FeatureOnboarding`, `FeatureProfile`, `TrustPolicy` |
| 8.2 bağış (Seçenek B, harici Safari + utm) | `FeatureDonate`, `DonationConfig` |
| Mahalle (D17): akış, yorum, pati, "Ben bakarım" | `FeatureCommunity`, `CommunityPolicy`, `supabase` `community_*` RPC'leri |
| Maskot ikonlar (D18) | `scripts/generate_mascots.py`, `MamaDesign/Components/Mascots.swift` |
| 9.1 konum bulanıklaştırma, 9.2 raporla/engelle/filtre, 9.3 güven puanı, 9.5 KVKK | `supabase` RPC'leri, `LocationFuzzer`, `ContentFilter`, `ReportSheet`, `PrivacyInfo.xcprivacy` |

## Lansmandan önce yapılacaklar (PRD 11.2, 11.4)

- [ ] Hukuk görüşü: 2860 sayılı Yardım Toplama Kanunu ve KVKK (yurt dışı sunucu, aydınlatma/açık rıza metinleri)
- [ ] Ortak dernek: ad, bağış sayfası URL'si (`MAMA_DONATION_URL`, `MAMA_PARTNER_NAME`)
- [ ] Uygulama adı ve marka (geçici ikon `ios/App/Resources/Assets.xcassets`)
- [ ] Supabase projesi (Frankfurt), APNs anahtarı, Sign in with Apple servis kimliği
- [ ] Gizlilik politikası, kullanım koşulları, KVKK metni URL'leri
- [ ] Pilot ilçede 200+ nokta ile soğuk başlangıç
- [ ] App Store: ekran görüntüleri, review notları (test hesabı + "bağış nasıl işliyor")
