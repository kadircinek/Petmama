# Mama Haritası — Durum ve Yol Haritası

_Son kontrol: 14 Kasım 2026 · Xcode 26.2 · macOS_

## 1. Bugünkü durum (doğrulandı)

| Kontrol | Sonuç |
|---|---|
| `xcodegen generate` + simülatör derlemesi (iPhone 17 Pro) | ✅ BUILD SUCCEEDED, 1 uyarı |
| Uygulama simülatörde (demo modu) | ✅ Harita, pinler, maskotlar, sekmeler çalışıyor |
| Swift paket testleri (`swift test`, macOS'ta yerel) | ✅ 414 test, 0 hata |
| SQL testleri (`supabase/tests/run.sh`, Docker) | ✅ 10 dosya, 592 assertion |
| iOS ↔ Supabase sözleşmesi | ✅ iOS'un çağırdığı 37 RPC'nin hepsi migration'larda var; repository'lerde boş/placeholder gövde yok |

Kod tabanı sağlam. Eksikler büyük ölçüde **bağlantı (wiring), operasyon ve yayın hazırlığı**.

## 2. Faz 1 — Kod hataları (backend olmadan yapılabilir)

| # | Sorun | Nerede | Öncelik |
|---|---|---|---|
| 1.1 ✅ | E-posta onayı / şifre sıfırlama linki uygulamaya dönemiyor: `CFBundleURLTypes` yok, `onOpenURL` yok, `authRedirectURL` hiç verilmiyor | `Info.plist`, `ServiceFactory.swift:30-36`, `AppServices+Supabase.swift:20`, `config.toml:51` | 🔴 Kritik |
| 1.2 ✅ | Çıkışta cihaz token'ı silinmiyor → eski hesap bildirim almaya devam ediyor, yeni hesap token'ı yeniden açılışa kadar alamıyor | `SessionStore.swift:49-52`, `AppModel.swift:52-56` | 🔴 Kritik |
| 1.3 ✅ | Çevrimdışı check-in kuyruğu kullanıcıya bağlı değil, çıkışta temizlenmiyor → başka hesap adına gönderilebilir | `CheckIn.swift:73-82`, `OfflineCheckInQueue.swift:41-46` | 🔴 Kritik |
| 1.4 ✅ | `Secrets.xcconfig` yoksa Release build sessizce demo moduna düşüyor (demo giriş ipucu, `example.org` bağış linki) | `AppConfiguration.swift:31,48`, `ServiceFactory.swift:11-13` | 🔴 Kritik |
| 1.5 ✅ | Hesap silmede Apple token iptali (revoke) yok — Apple, SIWA hesapları için zorunlu tutuyor | `functions/delete-account/index.ts:64-65` | 🟠 Yüksek |
| 1.6 ✅ | APNs ortamı backend genelinde tek; TestFlight token'ları production olduğu hâlde README sandbox diyor → token'lar `BadDeviceToken` ile siliniyor. Ortam token ile birlikte saklanmalı | `_shared/push_logic.ts:102-103`, `supabase/README.md:68-69` | 🟠 Yüksek |
| 1.7 ✅ | Engelleme yalnızca Mahalle içeriğini gizliyor; engellenen kullanıcının nokta/ihtiyaç/hayvanları görünmeye devam ediyor | RPC'ler + ilgili ViewModel'ler | 🟡 Orta |
| 1.8 | ViewModel toast/hata metinleri yalnızca Türkçe (EN eksik) | `DECISIONS.md:33` | 🟡 Orta |

**1.1–1.4 tamamlandı (14 Kasım 2026):** e-posta bağlantıları (`AuthLink`, `onOpenURL`, "Yeni şifre" ekranı),
çıkışta token silme ve yeni hesaba yeniden kayıt, kullanıcıya bağlı check-in kuyruğu, Release'de `Secrets.xcconfig`
zorunluluğu (derleme adımı; bilerek demo için `MAMA_ALLOW_DEMO_RELEASE=YES`).

**1.5–1.7 tamamlandı (14 Kasım 2026):** hesap silmede Apple token iptali (yeniden Apple onayı +
`delete-account` → appleid.apple.com/auth/revoke), APNs ortamı token başına (`device_tokens.apns_env`), engelleme
ihtiyaç/hayvan/koruyucu/nokta notu-fotoğrafına da uygulanıyor (noktalar haritada kalır).

## 3. Faz 2 — Gerçek backend kurulumu (hesap/erişim gerekiyor)

- [ ] Supabase projesi (Frankfurt) oluştur, `supabase db push` ile migration'ları uygula
- [ ] Vault: `push_dispatch_url`, `push_dispatch_secret`; konum bulanıklaştırma tuzu (fuzz salt)
- [ ] Apple: APNs anahtarı (.p8), Sign in with Apple servis kimliği → Supabase Auth provider
- [ ] Edge function secret'ları: APNs (`APNS_*`), Apple token iptali (`APPLE_TEAM_ID`, `APPLE_CLIENT_ID`, `APPLE_SIWA_KEY_ID`, `APPLE_SIWA_PRIVATE_KEY`)
- [ ] `ios/App/Config/Secrets.xcconfig` (URL + publishable key) ve gerçek cihazda uçtan uca test

## 4. Faz 3 — Eksik özellikler

| # | Özellik | Not |
|---|---|---|
| 3.1 | Moderasyon paneli (rapor kuyruğu, gizle/ban) | Şu an yalnızca SQL Editor; App Review UGC raporlarına hızlı müdahale bekliyor |
| 3.2 | Görsel moderasyon edge function'ı | D11'de kanca bırakıldı ama fonksiyon yok; `photos` bucket'ı public |
| 3.3 | `donation_stats` beslemesi + `donation_delivered` bildirimi | Hiçbir şey yazmıyor; "Bağışım nereye gitti?" boş kalıyor |
| 3.4 | Realtime (harita 60 sn'de bir yokluyor) | v1.1 adayı |
| 3.5 | USD/TRY kuru sabit config | Edge function ya da günlük cron ile güncelle |
| 3.6 | Rozetler, bağış izi ekranı ("yakında" yer tutucuları) | `ProfileTabScreen.swift:122`, `DonationTraceViewModel.swift:11` |

## 5. Faz 4 — Yayın hazırlığı

- [ ] `DEVELOPMENT_TEAM` (`project.yml:17`), sürüm 0.1.0 → 1.0.0
- [ ] Kalıcı uygulama ikonu ve marka adı
- [ ] Gizlilik politikası / kullanım koşulları / KVKK URL'leri (`Base.xcconfig:11-13` boş) — App Store Connect zorunlu
- [ ] Ortak dernek seçimi + bağış URL'si (Guideline 3.2.1(vi): harici bağış yalnızca kayıtlı dernek için)
- [ ] Hukuk görüşü: 2860 sayılı Kanun, KVKK (yurt dışı sunucu)
- [ ] CI'a imzalı archive/TestFlight adımı (şu an yalnızca imzasız simülatör derlemesi)
- [ ] Ekran görüntüleri, review notları, demo hesabı

## 6. Önerilen sıra

1. **Faz 1.1–1.4** (kritik hatalar, testleriyle birlikte) → tek PR
2. **Faz 1.5–1.7** → ikinci PR
3. **Faz 2** backend kurulumu (Supabase MCP bağlı; proje oluşturma senin onayınla)
4. **Faz 3.1–3.3** → TestFlight öncesi gerekli
5. **Faz 4** + TestFlight

## 7. Geliştirme ortamı (bu Mac için notlar)

```bash
cd ios && xcodegen generate && open MamaHaritasi.xcodeproj   # uygulama
cd ios/MamaKit && swift test                                  # 414 Swift testi (~1 dk, Docker gerekmez)
colima start                                                  # Docker çalışma zamanı
PATH="/opt/homebrew/opt/libpq/bin:$PATH" MAMA_TEST_MODE=docker bash supabase/tests/run.sh   # SQL testleri
```

- `psql` için `brew install libpq` kuruldu (keg-only; yukarıdaki PATH ile kullanılır).
- `~/.docker/config.json` içindeki `"credsStore": "desktop"` satırı eski Docker Desktop'tan kalma; Colima ile imaj çekmeyi
  bozuyor. Silinirse SQL testleri ek ayar olmadan çalışır.
- Simülatörde konum: `xcrun simctl location booted set 40.9877,29.0252` (Moda). Harita karoları ilk açılışta birkaç saniye gecikebilir.
