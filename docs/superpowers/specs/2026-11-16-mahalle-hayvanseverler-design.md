# Mahalle'de hayvanseverler ve anlık mama turu — Kısa tasarım

_16 Kasım 2026 · durum: onaylandı (ürün sahibi: "haydi yap onaylıyorum")_

Temel: `2026-11-14-tanisma-design.md` (Tanışma). Bu not onun üstüne eklenir; orada yazan tüm kurallar
(18+ sosyal onay, engelleme, mesafe bandı, kabul olmadan bire bir mesaj yok — D19) aynen geçerlidir.

## Amaç

Tanışma ve sohbet bir menünün içinde kaybolmasın: Mahalle açılınca **mahalledeki hayvanseverler** ve
**şu an mama turunda olanlar** en üstte görünsün; turu gören kişi **katılabilsin ve mesaj atabilsin**;
kimlerin **aktif** olduğu anlaşılsın.

## Yaklaşımlar

| | Yaklaşım | Sonuç |
|---|---|---|
| **A ✅** | **Anlık mama turu:** tek dokunuşla, herkese açık bir mama noktasından başlayan kısa buluşma; grup sohbeti | Seçildi: mevcut buluşma/sohbet/engelleme altyapısını kullanır, kişinin anlık konumu paylaşılmaz |
| B | Canlı durum + canlı konum paylaşımı | Reddedildi: rota ifşası, arka plan konumu, KVKK/App Store riski, birkaç kat iş |
| Aktiflik | "Bugün besledi" rozeti ✅ / "şu an çevrimiçi" | Çevrimiçi göstergesi ilk sürümde yok (boş görünen mahalle + izlenme riski); sonra isteğe bağlı eklenebilir |

## Davranış

### Anlık mama turu
- Sosyal onayı olan kullanıcı **"Mama turuna çıkıyorum"** der: bir **mama noktası** (yalnızca `public` görünürlüklü
  ve aktif nokta) ve **süre** (60 / 90 / 120 dk, varsayılan 90) seçer. Tur **hemen** başlar.
- Tur, `is_tour = true` olan bir buluşmadır: başlık "Mama turu: <nokta adı>", yer adı = nokta adı, konum =
  noktanın konumu, `spot_id` = nokta. Normal buluşmadaki "en erken 1 saat sonra" kuralı tura uygulanmaz.
- Kullanıcının aynı anda **en fazla bir** açık turu olur; günde **en fazla 3** tur (buluşma limitinden ayrı).
- Diğerleri turu Mahalle'nin üstündeki **"Şu an turda"** kartında ve haritada (buluşma pini) görür:
  düzenleyenin adı/fotoğrafı, nokta adı, kalan süre, katılımcı sayısı.
- **Katıl** → tura katılır (sosyal onay yoksa önce onay). **Mesaj at** → katılır ve turun grup sohbetini açar.
  Zaten katılmış kişi için ikisi "Sohbete git" olur.
- Düzenleyen **"Turu bitir"** diyebilir (mevcut iptal); süre dolunca tur kendiliğinden kapanır. Sohbet kuralları
  buluşmalarla aynıdır (bitişten 24 saat sonra salt okunur, 30 gün sonra silinir).
- Turlar "Buluşmalar" listesinde de görünür (rozetle), geçmiş turlar görünmez.
- Engelleme, raporlama, bildirim (yeni katılımcı, iptal) buluşmalarla aynı. Hatırlatma bildirimi tura gönderilmez.

### Mahalledeki hayvanseverler şeridi
- Mahalle › Akış'ın en üstünde yatay şerit: fotoğraf/baş harf, ad, mesafe bandı; **"Bugün besledi"** rozeti;
  şu an turda olanlarda **"Turda"** rozeti. Sıra: turda olanlar → bugün besleyenler → mesafe bandı → ortak ilgi.
- Karta dokununca kişinin kartı açılır (Hayvanseverler'deki ile aynı): **Tanış** isteği / bekleyen istek / Mesaj yaz.
  "Tümünü gör" → Hayvanseverler ekranı.
- **"Bugün besledi"** = kişi bugün (İstanbul günü) en az bir "mama/su koydum" check-in'i yaptı ya da bir tur açtı.
  Yalnızca Hayvanseverler'de **görünür olmayı seçmiş** kişiler için gösterilir.
- Görüntüleyen kişi sosyal onay vermemişse ya da kendisi görünür değilse şerit yerine davet kartı çıkar:
  "Mahallendeki hayvanseverleri gör" → onay / görünür ol akışı. (Kendini göstermeyen başkalarını göremez — 5.5/1.)

## Gizlilik notları
- Turun konumu zaten herkese açık bir mama noktasıdır; kişinin anlık konumu hiçbir yerde paylaşılmaz.
- "Bugün besledi" hangi noktada/ne zaman beslediğini söylemez; yalnızca gün bazında evet/hayır.
- Çevrimiçi / son görülme bilgisi tutulmaz.

## Hedef dışı
Canlı konum, çevrimiçi göstergesi, tur rotası (birden fazla nokta), tur başlayınca bağlantılara bildirim,
kabul olmadan bire bir mesaj.

## Yapıcıya bırakılanlar
RPC adları ve imzaları (öneri: `start_feeding_tour(p_spot_id uuid, p_duration_minutes int default 90)` →
`{status:'started', meetup_id, conversation_id}` | `consent_required | spot_not_found | already_touring |
{status:'limit_reached', limit:3} | {status:'invalid', reason:'duration_range'}`; `meetup_row` ve
`animal_lovers_near` dönüşlerine `is_tour` / `fed_today` / `on_tour_meetup_id` eklenmesi), ekran ayrıntıları,
demo verisi (bir demo kullanıcısı açık turda, biri bugün beslemiş).
