# Tanışma: Buluşmalar ve Hayvanseverler — Tasarım

_14 Kasım 2026 · durum: onaylandı_

## 1. Amaç ve neden

Kullanıcı (ürün sahibi) iki şey istiyor: **hayvanseverlerin birlikte mama dağıtması** ve bunun üzerinden **benzer
düşünen insanların sosyalleşmesi**. Tanışma amaç değil, ortak işin doğal sonucu. Bu bir flört ya da genel sosyal
ağ özelliği değildir.

İki parça birlikte yapılacak (ürün sahibinin kararı):

- **A) Buluşmalar:** herkese açık bir yerde, belirli saatte toplu mama turu / etkinlik. Katılanlar grup sohbetinde konuşur.
- **B) Hayvanseverler:** isteyen kişi profilini görünür yapar; yakınındakiler istek gönderir, kabul edilirse bire bir sohbet.

Bu, D17'deki "özel mesajlaşma yok" kararını **bilinçli olarak** değiştirir. Yeni karar D19 olarak
`docs/DECISIONS.md`'ye eklenecek: bire bir sohbet yalnızca **karşılıklı kabulle** açılır; raporlanabilir ve
engellenebilir.

## 2. Hedefler, hedef olmayanlar, anti-hedefler

**Hedefler**
- Birlikte beslemeyi kolaylaştırmak: buluşma aç, katıl, haberleş.
- Yakındaki hayvanseverleri güvenli biçimde bulmak ve tanışmak.
- Bugün demo modunda simülatörde baştan sona çalışmak; Supabase bağlanınca kod değişmeden gerçek backend'le çalışmak.

**Hedef olmayanlar (ilk sürüm)**
- Sohbette fotoğraf/ses/konum gönderme, "yazıyor…", okundu bilgisi, mesaj düzenleme.
- Tekrarlayan buluşmalar, takvim entegrasyonu, buluşma yorumları (sohbet yeterli).
- Eşleştirme algoritması / öneri; kişiler mesafe ve ilgilere göre basit listede.
- Android, web.

**Anti-hedefler (çalışsa bile başarısızlık sayılır)**
- Bir kullanıcının ev konumunun (veya ~100 m hassasiyetle yaşadığı yerin) başkaları tarafından çıkarılabilmesi.
- Kabul etmediği birinin kullanıcıya mesaj atabilmesi.
- Engellenen birinin kullanıcıyı listede, buluşmada veya sohbette görebilmesi / ona ulaşabilmesi.
- Özelliğin flört uygulaması gibi algılanması (dil, görsel, akış).

## 3. Kısıtlar

- Mevcut yapı: iOS 17+, SwiftUI, `MamaKit` Swift paketi (MVVM + feature modülleri), Supabase (Postgres + PostGIS,
  RLS, RPC, Edge Functions, Realtime), demo için `InMemoryBackend`. Tüm iş kuralları sunucuda (RPC) ve demo
  backend'de aynalanır; ViewModel'ler Linux'ta test edilir.
- Gizlilik (PRD 9.1, D8): konum geçmişi tutulmaz; kişisel konum yalnızca kaba ve üzerine yazılan tek değer.
- Bu bölümdeki her şey **giriş gerektirir** (anon'a kapalı), Mahalle ile aynı.
- KVKK: profil görünürlüğü açık rıza ile; hesap silinince tüm sosyal veri silinir (cascade).
- App Store 1.2 (UGC): raporla, engelle, içerik filtresi, kullanım koşullarında sıfır tolerans maddesi;
  bire bir sohbet olduğu için 18+ beyanı.
- Supabase henüz bağlı değil (ürün sahibi kararı): her şey demo backend + yerel Docker SQL testleriyle doğrulanır.

## 4. Yaklaşımlar

| | Yaklaşım | Artı | Eksi |
|---|---|---|---|
| **1 ✅** | **Tamamen Supabase:** tablolar + RLS + RPC; sohbet Supabase Realtime, yoksa yenileme ile | Tek veri yeri (KVKK basit), mevcut moderasyon/engelleme yeniden kullanılır, ek maliyet yok, demo modunda tam çalışır | "Yazıyor…", okundu gibi incelikler elle yazılır (ilk sürümde yok) |
| 2 | Sohbet için hazır servis (Stream/Sendbird) + Supabase | Hazır zengin sohbet arayüzü | Ücretli üçüncü taraf, mesajlar ayrı sistemde (yeni KVKK aktarımı), engelleme/rapor iki yere bölünür, demo modu zor |

**Seçilen: 1** (ürün sahibi onayladı). Gerekçe: mevcut mimariye ve gizlilik ilkelerine oturuyor.

## 5. Kararlaştırılan davranış

### 5.1 A) Buluşmalar

- Sosyal onayı (5.5/0) vermiş herkes buluşma açabilir. Alanlar: **başlık** (3–80), **açıklama** (0–600), **başlangıç zamanı**
  (en erken 1 saat sonra, en geç 60 gün sonra), **süre** (30 dk – 8 saat, varsayılan 2 saat), **buluşma noktası**
  (haritadan seçilen nokta + yer adı metni, ör. "Moda İskelesi önü"), isteğe bağlı **bağlı mama noktası**,
  isteğe bağlı **kişi sınırı** (2–50).
- Buluşma noktası **herkese açık bir yer** olmalı; oluşturma ekranı bunu hatırlatır. Konum tam saklanır ve
  gösterilir (bir yerde buluşmak için gerekli), ama **kişisel değildir**: düzenleyenin evi değil.
- Görünürlük: Mahalle'de yeni **"Buluşmalar"** bölümü (Akış · Buluşmalar · İhtiyaçlar) ve haritada ayrı pin türü.
  Yalnızca giriş yapanlar görür. Liste yakından uzağa, sonra tarihe göre; geçmiş buluşmalar listede yok.
- **Katıl / Ayrıl.** Sınır dolduysa katılım kapanır. Düzenleyen bir katılımcıyı çıkarabilir (çıkarılan tekrar katılamaz).
- Düzenleyen buluşmayı **iptal** edebilir → katılımcılara bildirim, sohbet salt okunur.
- **Grup sohbeti:** düzenleyen + katılımcılar. Buluşma bitişinden **24 saat sonra** salt okunur; **30 gün sonra**
  mesajlar silinir (veri saklamayı sınırlamak için, benim önerim).
- Bildirimler: yeni katılımcı (düzenleyene), buluşma iptal edildi, buluşmaya 2 saat kala hatırlatma, yeni sohbet mesajı
  (sohbet açık değilse; aynı sohbet için okunmamış bildirim varsa yenisi gitmez).

### 5.2 B) Hayvanseverler

- **Varsayılan kapalı.** Profil → "Hayvanseverler"de açılır. Sosyal onay (5.5/0) daha önce verilmediyse önce o
  ekran gelir. Onay zamanı saklanır (KVKK açık rıza kaydı).
- Görünür profil: ad, fotoğraf, **hakkımda** (0–300), **ilgi etiketleri** (sabit liste: kedi, köpek, kuş,
  kısırlaştırma gönüllüsü, geçici yuva, veteriner taşıma, mama bağışı, sokak hayvanı fotoğrafçılığı — benim önerim),
  doğrulanmış besleyici rozeti, besleme istatistiği (son 30 gün check-in sayısı).
- **Konum:** kişi hiçbir zaman haritada pin olarak gösterilmez. Sunucu görünür kişinin konumunu yalnızca
  **≈1 km'ye yuvarlanmış tek değer** olarak tutar (`notify_center` ile aynı yaklaşım, ama daha kaba); listede yalnızca
  **mesafe aralığı** döner: "1 km'den yakın", "1–3 km", "3–10 km". Liste en fazla 10 km'yi gösterir.
  Aralıklar ve yuvarlama birlikte üçgenlemeyi pratikte anlamsız kılar.
- Liste: mesafe aralığına, sonra ortak ilgi sayısına göre; ilgi etiketine göre filtre.
- **İstek → kabul → sohbet.** İstekle birlikte isteğe bağlı kısa not (0–200). Alıcı kabul eder ya da reddeder;
  reddedilen kişi aynı kişiye 30 gün yeni istek gönderemez (gönderen "reddedildi" görmez, istek "beklemede" kalır gibi
  görünür — benim önerim, reddetmeyi sosyal olarak kolaylaştırmak için). Günlük **10 yeni istek** sınırı.
- Kabul edilince iki kişi arasında bire bir sohbet açılır. Her iki taraf "bağlantıyı kaldır" diyebilir → sohbet kapanır.
- Görünürlük kapatılınca kişi listeden **anında** çıkar; mevcut bağlantılar ve sohbetler sürer.

### 5.3 Sohbet (A ve B ortak)

- Yalnızca metin, 1–1000 karakter, mevcut küfür filtresi (`ContentFilter` + sunucu `rejected_content`).
- Hız sınırı: sohbet başına dakikada 20 mesaj; kullanıcı başına günde 500.
- Her mesaj **raporlanabilir** (`report_target` + `chat_message`). Kişi engellenince: bire bir sohbet kapanır ve
  gizlenir; grup sohbetinde engellenenin mesajları görünmez; listelerde birbirlerini görmezler; engellenen kişi
  engelleyenin açtığı buluşmayı görmez/katılamaz.
- 3 farklı kişi tarafından raporlanan mesaj gizlenir (`pending`), Mahalle'deki kuralla aynı.
- **Canlı güncelleme:** açık sohbet ekranı Supabase Realtime'a abone olur; bağlantı yoksa 5 sn'de bir yeniler.
  Demo backend'de mesajlar anında görünür (bellek içi akış).
- Sohbetler listesi: Profil → "Sohbetler" (buluşma ve bire bir birlikte, son mesaja göre); okunmamış sayısı rozeti.

### 5.4 Uygulamadaki yerleşim (benim kararım)

- Yeni modül: **`FeatureSocial`** (Buluşmalar, Hayvanseverler, Sohbet ekranları + ViewModel'ler).
- Mahalle sekmesi: Akış · **Buluşmalar** · İhtiyaçlar. "+ Ekle" menüsüne "Buluşma aç".
- Harita: buluşma pinleri (ayrı ikon), filtrede aç/kapa.
- Profil: "Hayvanseverler" ve "Sohbetler" satırları. Bildirimler ilgili ekranı açar (`PushPayload` genişletilir).
- Ton: hayvanlar ve iş merkezli dil ("birlikte besleyelim", "tanış"), flört çağrışımı yapan dil yok.

### 5.5 Gözden geçirmeden sonra netleşen kurallar

0. **18+ her şey için (ürün sahibinin kararı):** buluşma açmak, buluşmaya katılmak, grup sohbeti, Hayvanseverler ve
   bire bir sohbet dahil **tüm sosyal özellikler** tek seferlik bir **sosyal onay** adımının arkasındadır:
   "18 yaşından büyüğüm" + kullanım koşulları + kısa güvenlik ipuçları. Onay `social_profiles.adult_confirmed_at` /
   `terms_accepted_at` olarak saklanır; satır, kişi Hayvanseverler'de görünür olmasa da oluşur (`is_visible = false`).
   Onaysız kullanıcı buluşmaları **görebilir** ama katılmaya / açmaya çalışınca onay ekranı açılır. Sunucu, onayı
   olmayanın bu RPC'leri çağırmasını `consent_required` ile reddeder. Hayvanseverler'de görünür olmak ayrı bir
   aç/kapa düğmesidir (onay bir kez verilir).

Aşağıdakiler benim kararlarım (onaya tabi):

1. **Listeyi kim görür, kim istek atar:** yalnızca görünürlüğü **açık** olanlar (yani 18+ ve koşulları onaylamış
   olanlar). Kendini göstermeyen biri başkalarını tarayamaz ve istek gönderemez. "Sadece bakan" hesap olmaz.
2. **Konum kaynağı:** `social_profiles.cell`, görünürlük açılırken cihaz konumundan alınır ve liste her açıldığında,
   kişi ~1 km'den fazla yer değiştirdiyse güncellenir. Listeyi sorgulayanın konumu da istemcinin gönderdiği nokta
   değil, **sunucudaki kendi yuvarlanmış `cell` değeri** olur. Böylece farklı noktalardan sorgulayarak birinin yerini
   bulmak mümkün olmaz.
3. **Hesap silme:** düzenlediği gelecek buluşmalar **otomatik iptal edilir** (katılımcılara "iptal" bildirimi) ve
   silinir. Kullanıcının tüm sohbet mesajları, bağlantıları ve sosyal profili silinir (Mahalle'deki gibi kişisel
   içerik cascade).
4. **Demo modu:** `InMemoryBackend`'e sahte hayvanseverler ve hazır buluşmalar eklenir. Sahte kişiler isteği birkaç
   saniye sonra kabul eder ve kısa hazır cevaplar yazar. Böylece simülatörde iki taraflı akış denenebilir.
5. **Ortak buluşmadaki iki kişi arasında engelleme:** engelleyen düzenleyense engellenen buluşmadan otomatik çıkarılır;
   engellenen düzenleyense engelleyen buluşmadan ayrılır (buluşma ona gizlenir, sohbet ve bildirimler biter).
   İki katılımcı arasındaysa ikisi de kalır ama birbirlerinin mesajlarını ve katılımcı listesinde birbirlerini görmez.
6. **Bağlantı isteğinin yaşam döngüsü:** iki kişi arasında tek bağlantı kaydı (sırasız çift benzersiz).
   Karşı taraf zaten istek attıysa yeni istek **otomatik kabul** olur. Gönderen bekleyen isteğini geri çekebilir.
   Reddedilen istek gönderene "beklemede" görünür ve **30 gün sonra** sessizce düşer. O sürede aynı kişiye yeni istek
   atılamaz.

## 6. Veri ve sözleşme (taslak; ayrıntı yapıcıya)

Yeni tablolar (hepsi RLS açık, **doğrudan erişim yok, yalnızca RPC**, kullanıcı silinince cascade):

- `meetups(id, organizer_id, title, description, starts_at, ends_at, place_name, location geography, spot_id null,
  capacity null, status: active|cancelled, created_at)`
- `meetup_participants(meetup_id, user_id, status: joined|removed, joined_at)`
- `social_profiles(user_id pk, is_visible, about, interests text[], cell geography null, adult_confirmed_at,
  terms_accepted_at, updated_at)` — `cell` ≈1 km'ye yuvarlanmış
- `connections(id, requester_id, addressee_id, note, status: pending|accepted|declined|removed, created_at,
  responded_at)` + tek yönlü çift için benzersizlik
- `conversations(id, kind: meetup|direct, meetup_id null, connection_id null, created_at, closed_at null)`
- `conversation_members(conversation_id, user_id, last_read_at)`
- `chat_messages(id, conversation_id, author_id, body, moderation_state, created_at)`

Enum ekleri: `report_target` + `meetup`, `chat_message`; `notification_kind` + `meetup_joined`, `meetup_cancelled`,
`meetup_reminder`, `connection_request`, `connection_accepted`, `chat_message`.

RPC'ler (taslak): `meetups_near`, `meetup_detail`, `create_meetup`, `join_meetup`, `leave_meetup`,
`remove_meetup_participant`, `cancel_meetup`, `social_profile_me`, `update_social_profile`, `animal_lovers_near`,
`send_connection_request`, `respond_connection`, `remove_connection`, `my_connections`, `my_conversations`,
`conversation_messages(p_conversation_id, p_before)`, `send_chat_message`, `mark_conversation_read`.
Sonuçlar Mahalle'deki gibi `{status: ...}` jsonb. Realtime: `chat_messages` üzerinde Realtime Broadcast (RLS'li
`realtime.messages` yetkilendirmesi), kanal adı `conversation:<id>`.

iOS: yeni `SocialRepository` protokolü (+ `InMemoryBackend` ve `SupabaseBackend` uygulamaları),
`ChatStream` soyutlaması (Realtime veya yenileme). Tüm metinler TR + EN (`scripts/l10n/en.json`).

## 7. Yapıcıya bırakılanlar

- RPC imzalarının ve dönüş satırlarının ayrıntıları, indeksler, migration bölümlemesi.
- Ekranların görsel ayrıntıları (mevcut `MamaDesign` bileşenleriyle).
- Hatırlatma bildirimi için cron zamanlaması.
- Realtime kurulumu: Supabase bağlanana kadar yalnızca protokol + demo uygulaması + yenileme yedeği; Realtime
  aboneliği kodu yazılır ama Faz 2'de gerçek projede doğrulanır.

## 8. Test

- SQL: her RPC için kural, görünürlük, engelleme, hız sınırı, 18+ ve görünürlük kapalıyken listeden çıkma testleri.
- Swift: ViewModel testleri (Linux), demo backend kural testleri, Supabase decode testleri.
- Simülatör: demo modunda buluşma aç → katıl → grup sohbeti; görünürlük aç → istek → kabul → bire bir sohbet;
  engelle → her şeyin kaybolması.
