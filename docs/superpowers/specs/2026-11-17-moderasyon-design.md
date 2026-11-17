# Moderasyon ekranı — Kısa tasarım (Faz 3.1)

_17 Kasım 2026 · durum: onaylandı (ürün sahibi: "Evet, başla"; ayrıntılar aşağıda benim kararlarım)_

## Amaç

Raporlara hızlı müdahale (App Store 1.2: kullanıcı içeriği olan uygulamada raporlar 24 saat içinde ele alınmalı).
Bugün inceleme yalnızca SQL Editor'den yapılabiliyor. Moderatör, uygulamanın içinden rapor kuyruğunu görsün,
içeriği gizlesin ya da geri açsın, gerekirse kullanıcıyı uzaklaştırsın; her işlem kayda geçsin.

## Yaklaşımlar

| | Yaklaşım | Sonuç |
|---|---|---|
| **A ✅** | **Uygulama içi moderatör ekranı** (yalnızca `is_moderator` olanlara görünür) + sunucuda moderatör RPC'leri | Seçildi: ayrı bir web paneli/barındırma gerekmez, mevcut RLS/RPC düzenine oturur, demo modunda denenebilir |
| B | Ayrı web yönetim paneli | Reddedildi: yeni proje, barındırma ve kimlik doğrulama; tek moderatörlü başlangıç için fazla |
| C | Supabase Dashboard / SQL ile devam | Reddedildi: telefondan hızlı müdahale yok, hata yapmaya açık |

## Davranış

- **Erişim:** Profil'de "Moderasyon" satırı yalnızca `is_moderator` kullanıcıya görünür (açık rapor sayısı rozetiyle).
  Sunucu tüm moderasyon RPC'lerinde moderatörlüğü yeniden doğrular (`not_allowed`).
- **Kuyruk:** Raporlar **hedefe göre gruplanır** (aynı içeriğe gelen raporlar tek satır): hedef türü, kısa önizleme
  (başlık/metin, varsa fotoğraf), içerik sahibinin adı, rapor sayısı, nedenler, ilk/son rapor zamanı, içeriğin şu anki
  durumu (yayında / incelemede / kaldırıldı). Sekmeler: **Açık** (varsayılan; en çok raporlanan ve en eski önce) ve
  **Kapananlar** (son 30 gün).
- **Detay:** içerik önizlemesi, her raporun nedeni + notu + zamanı (raporlayanın adı gösterilir), içerik sahibinin
  son 90 gündeki kaldırılan içerik ve uzaklaştırma sayısı.
- **Kararlar** (hepsi onay diyaloğuyla, isteğe bağlı kısa not):
  - **Uygun, yayında kalsın** → içerik `approved` olur (otomatik gizlendiyse geri açılır), açık raporlar `dismissed`.
  - **Kaldır** → içerik herkesten gizlenir, açık raporlar `resolved`:
    - nokta, paylaşım, yorum, sohbet mesajı: `moderation_state = 'rejected'`
    - buluşma / tur: iptal edilir; ihtiyaç ve hayvan profili: silinir; check-in / fotoğraf: fotoğraf URL'si temizlenir
    - kullanıcı raporu: içerik yok; yalnızca raporlar kapanır (uzaklaştırma ayrı karar)
  - **Kullanıcıyı uzaklaştır** (içerik sahibini ya da raporlanan kullanıcıyı): **7 gün / 30 gün / süresiz**. Uzaklaştırılan
    kullanıcı okumaya devam eder ama hiçbir şey yazamaz (nokta, check-in, paylaşım, yorum, mesaj, buluşma, istek…).
    Uygulamada "Hesabın … tarihine kadar askıya alındı" mesajı görür. Moderatör uzaklaştırmayı kaldırabilir.
    Moderatörler ve kişinin kendisi uzaklaştırılamaz.
- **Kayıt:** her karar `moderation_actions` tablosuna yazılır (kim, ne zaman, hangi hedef, hangi karar, not).
- **Sohbet gizliliği:** moderatör yalnızca **raporlanan mesajın** metnini görür; sohbetin geri kalanını göremez.
- **Demo modu:** demo kullanıcısı moderatördür ve kuyrukta birkaç hazır rapor vardır (ekranı Supabase'siz denemek için).

## Hedef dışı
Rapor edene / içerik sahibine bildirim, itiraz akışı, otomatik görsel moderasyon (3.2), birden fazla moderatör
rolü/yetki seviyesi, toplu işlem, web paneli.

## Yapıcıya bırakılanlar
RPC adları ve dönüş satırları (öneri: `moderation_queue(p_closed boolean default false, max_rows int default 50)`,
`moderation_target_reports(p_target_type, p_target_id)`, `moderation_decide(p_target_type, p_target_id, p_action text
/* approve | remove */, p_note text)`, `moderation_suspend_user(p_user_id, p_days int /* null = süresiz */, p_note)`,
`moderation_unsuspend_user(p_user_id)`, `moderation_open_count()`); `profiles.suspended_until`; uzaklaştırmanın yazma
yollarında merkezi uygulanması (`private.require_uid` ve doğrudan tablo yazmalarının RLS'i); ekran ayrıntıları.
