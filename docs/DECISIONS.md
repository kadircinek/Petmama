# Kararlar ve varsayımlar

PRD'deki açık sorular (11.4) netleşene kadar geliştirme aşağıdaki varsayımlarla ilerliyor. Her biri tek
bir yerden değiştirilebilir.

| # | Konu | Varsayım | Nereden değişir |
|---|---|---|---|
| D1 | Uygulama adı | Çalışma adı **Mama Haritası**. Bundle id `app.petmama.mamaharitasi` | `ios/project.yml` |
| D2 | Bağış modeli | Lansman: **Seçenek B** (derneğin bağış sayfası harici Safari'de, `utm` + anonim referans kodu). Uygulama içinde ödeme, IAP veya Apple Pay **yok**. Ortak dernek henüz belli değil, adı ve URL'si yer tutucu. | `DonationConfig` (Info.plist `MAMA_DONATION_URL`, `MAMA_PARTNER_NAME`) |
| D3 | Pilot ilçe | Kadıköy (Moda). Demo verisi ve harita başlangıç bölgesi buraya göre | `DemoData`, `supabase/seed.sql` |
| D4 | Harita | MapKit, sessize alınmış standart stil (POI kapalı). Harita katmanı `MapProvider` arkasında, Mapbox'a geçilebilir | `MamaMap` modülü |
| D5 | Kümeleme | SwiftUI `Map` iOS 17'de yerleşik kümeleme sunmuyor, bu yüzden istemcide ızgara tabanlı kümeleme (`SpotClusterer`) kullanılıyor. Rozet "mama gerekli" sayısını gösteriyor (FR-H2) | `MamaCore/Geo/SpotClusterer.swift` |
| D6 | Backend | Supabase (Postgres + PostGIS + Auth + Storage + Edge Functions), bölge **eu-central-1 (Frankfurt)**. KVKK yurt dışı aktarımı hukuk görüşüne bağlı (PRD 9.5) | `supabase/` |
| D7 | Demo modu | `SUPABASE_URL` tanımlı değilse uygulama, Kadıköy demo verisiyle bellek içi backend'de çalışır. Böylece simülatörde, önizlemede ve tasarım incelemesinde hemen denenebilir | `AppEnvironment` |
| D8 | Bildirim yarıçapı | Sunucu, yakındaki "mama gerekli" bildirimi için kullanıcının **yalnızca son kaba konumunu** (≈110 m'ye yuvarlanmış, üzerine yazılan tek değer) tutar. Konum geçmişi tutulmaz (PRD 9.5) | `update_notify_center` RPC |
| D9 | Görünürlük seviyeleri | `public` / `fuzzed` / `private`. Tablo: `docs/backend-contract.md` → Konum hassasiyeti | sözleşme |
| D10 | Ana sayfa ve harita | Tab bar PRD'deki gibi (Harita · İhtiyaçlar · + Ekle · Bağış · Profil). Ana sayfa içeriği (selamlama, 4 hızlı eylem, yakında mama gereken noktalar, "Bugün mahallende") harita sekmesinde çekilebilir alt panelde. Panel kapalıyken en yakın nokta ve tek dokunuşla "Mama koydum" görünür | `FeatureMap` |
| D11 | Görsel moderasyon | MVP'de otomatik görsel moderasyon yok. Raporla, engelle ve 24 saat moderasyon kuyruğu var, metinlerde küfür filtresi var. Görsel moderasyon için edge function kancası bırakıldı (PRD 9.2) | `supabase/functions` |
| D12 | Dil | Kaynak dil Türkçe, ikinci dil İngilizce (String Catalog) | `ios/App/Resources/Localizable.xcstrings` |
| D13 | v1.1 kapsamı | Apple Pay bağışı, teslim kanıtı, koruyuculuk takvimi, rozetler, liderlik tablosu MVP'de yok. "Bağışım nereye gitti?" ekranı açıklama ve "yakında" durumuyla var | — |
| D14 | Tasarım | Dribbble "Pet Social App" referansından yalnızca görsel dil ve bileşen yapısı alındı. Marka, logo ve fotoğraf kopyalanmadı. Görseller SF Symbols ve sistem bileşenleriyle | `MamaDesign` |

| D15 | Girişsiz gezinme | Harita, liste, nokta/ihtiyaç/hayvan detayı ve mahalle özeti girişsiz okunur (FR-P1). Bu durumda konumlar bulanık gelir, `private` noktalar hiç dönmez. Koruyucu adları ve profil istatistikleri yalnızca giriş yapanlara gösterilir | `supabase/migrations/…000011_anon_read_grants.sql` |
| D16 | Supabase kurulumu | Free plan'deki 2 aktif proje limiti dolu olduğundan proje henüz açılmadı (karar: şimdilik kurma). Şema ve fonksiyonlar repoda hazır, yerelde `supabase/postgres` imajıyla test edildi | `supabase/README.md` |

## Bilerek ertelenenler
Mesajlaşma, uygulama içi mağaza, barınak entegrasyonları (PRD 4), Android (v2).

## Takip edilecek teknik işler
- **Realtime:** PRD 7.3'te önerilen canlı durum güncellemesi yok. Harita görünürken 60 saniyede bir yenileniyor, ayrıca aşağı çekince ve öne gelince de yenileniyor. `spots` tablosu doğrudan okunamadığı için (konum gizliliği) canlı güncelleme Realtime Broadcast ile yapılmalı.
- **ViewModel metinleri:** Görünümlerdeki metinler String Catalog'da (TR/EN). ViewModel'lerin ürettiği geri bildirim mesajları (toast ve hata) şimdilik yalnızca Türkçe.
- **Görsel moderasyon** (D11), **APNs ve Sign in with Apple uçtan uca testi** gerçek Supabase projesi ve Apple Developer hesabıyla yapılacak.
- **SwiftUI derlemesi:** Görünümler Linux'ta derlenemediği için kod incelemesinden geçti. İlk Xcode derlemesinde çıkacak küçük API düzeltmeleri beklenmeli; CI'daki `ios-build` işi bunu yakalar.
