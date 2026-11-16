# Backend sözleşmesi (Supabase) — v0.1

Bu doküman iOS veri katmanı (`MamaSupabase`) ile Supabase şeması (`supabase/migrations`) arasındaki
**tek doğruluk kaynağıdır**. İki taraf da bu isimlere ve şekillere birebir uyar. Değişiklik gerekirse önce
bu doküman güncellenir.

Genel kurallar

- Tüm tablolar `public` şemasında, **RLS her tabloda açık** (PRD 7.3).
- Konum içeren okumalar **yalnızca `security definer` RPC'ler üzerinden** yapılır; `spots` tablosu `anon`
  ve `authenticated` rollerine doğrudan `select` izni vermez. Böylece konum bulanıklaştırma (PRD 9.1) atlanamaz.
- RPC'ler `set search_path = public, extensions` ile tanımlanır.
- Zaman damgaları `timestamptz`, JSON'da ISO-8601 (`2026-11-04T08:15:00.123Z`).
- Koordinatlar her yerde `lat` / `lng` (`float8`, WGS84).
- Mesafeler metre (`float8` veya `int`).
- İş kuralı sonuçları istisna yerine `jsonb` içinde `status` alanıyla döner (istemci kolayca eşler).
  Yetki/doğrulama ihlalleri (oturum yok, geçersiz parametre) `raise exception` ile döner.

## Enum'lar

| Tip | Değerler |
|---|---|
| `spot_type` | `food`, `water`, `shelter`, `mixed` |
| `spot_species` | `cat`, `dog`, `both` |
| `spot_status` | `fed_recent` (yeşil, <12 sa), `fed_stale` (sarı, 12–24 sa), `unknown` (gri, 24 sa+ / hiç), `needs_food` (turuncu, açık mama/su gerekli bildirimi) |
| `spot_visibility` | `public`, `fuzzed`, `private` |
| `checkin_kind` | `fed`, `water`, `need_food`, `need_water`, `broken` |
| `food_amount` | `low`, `medium`, `full` |
| `animal_species` | `cat`, `dog` |
| `animal_sex` | `female`, `male`, `unknown` |
| `age_estimate` | `baby`, `young`, `adult`, `senior`, `unknown` |
| `animal_warning` | `do_not_approach`, `skittish`, `may_bite` |
| `need_type` | `vet`, `neuter`, `vaccine`, `meds`, `shelter`, `water`, `adoption`, `lost_found` |
| `need_urgency` | `normal`, `urgent` |
| `need_status` | `open`, `claimed`, `resolved` |
| `report_target` | `spot`, `animal`, `need`, `checkin`, `photo`, `user` |
| `report_reason` | `inappropriate`, `spam`, `wrong_location`, `animal_harm`, `harassment`, `other` |
| `report_status` | `open`, `actioned`, `dismissed` |
| `moderation_state` | `approved`, `pending`, `rejected` |
| `follow_target` | `spot`, `animal` |
| `notification_kind` | `need_food_nearby`, `followed_spot_changed`, `guardian_spot_unfed`, `need_resolved`, `thanks_fed`, `donation_delivered` |

`temperament_tags` serbest `text[]` ama istemci şu anahtarları kullanır:
`friendly`, `shy`, `may_be_aggressive`, `good_with_kids`, `energetic`, `calm`.

## Durum hesaplama (PRD 5.2 FR-N5, 7.5)

```
needs_food  ← noktada çözülmemiş need_food, need_water veya broken check-in'i varsa
fed_recent  ← now - last_fed_at < 12 saat
fed_stale   ← 12 saat ≤ now - last_fed_at < 24 saat
unknown     ← last_fed_at null veya ≥ 24 saat
```
`has_urgent_need` ← noktaya veya noktadaki bir hayvana bağlı `urgency = 'urgent'` ve `status <> 'resolved'` ihtiyaç var.
RPC'ler durumu **okuma anında** `compute_spot_status()` ile hesaplar; cron (15 dk) `spots.status` sütununu
kalıcılaştırır ve "24 saattir beslenmedi" bildirimlerini üretir.

## Konum hassasiyeti (PRD 9.1)

| visibility | anon | giriş yapmış | koruyucu / doğrulanmış besleyici / oluşturan |
|---|---|---|---|
| `public` | bulanık (50–100 m) | tam | tam |
| `fuzzed` | bulanık | bulanık | tam |
| `private` | **gizli** (dönmez) | bulanık | tam |

Bulanıklaştırma deterministiktir: `fuzz_point(spot_id, location)` → spot id + sunucu tuzu (`app.fuzz_salt`)
hash'inden 50–100 m arası sabit ofset. Aynı nokta her istekte aynı sahte konumda görünür (ortalama alma saldırısı yok).
Satırdaki `is_location_exact` istemciye hangi durumda olduğunu söyler.

## Tablolar (özet)

- `profiles(id uuid pk → auth.users on delete cascade, display_name, avatar_url, neighborhood, trust_score int default 10, is_verified_feeder bool default false, is_moderator bool default false, created_at)`
- `spots(id, location geography(Point,4326), type, species, title, note, photo_url, status, last_fed_at, created_by → profiles on delete set null, visibility, is_active, moderation_state, created_at, updated_at)` + GIST(location)
- `checkins(id, spot_id → spots cascade, user_id → profiles set null, kind, amount, photo_url, user_distance_m int, resolved_at, resolved_by uuid → checkins, created_at)`
  — Kullanıcının konumu **saklanmaz**, yalnızca `user_distance_m` (PRD 9.5).
- `animals(id, species, name, color_pattern, sex, age_estimate, is_neutered bool null, ear_tag bool, vaccination_info, temperament_tags text[], warning animal_warning null, about, photos text[], last_seen_at, last_seen_spot_id → spots set null, created_by → profiles set null, created_at)`
- `animal_spots(animal_id, spot_id, seen_count int, last_seen_at, pk(animal_id, spot_id))`
- `needs(id, animal_id null, spot_id null, type, urgency, description, photos text[], status, created_by, claimed_by, claimed_at, resolved_at, created_at)` — `check (animal_id is not null or spot_id is not null)`
- `guardians(user_id, spot_id, schedule smallint[] /* ISO 1=Pzt..7=Paz */, created_at, pk(user_id, spot_id))`
- `follows(user_id, target_type follow_target, target_id uuid, created_at, pk(user_id, target_type, target_id))`
- `spot_gone_reports(spot_id, user_id, created_at, pk(spot_id, user_id))`
- `reports(id, reporter_id, target_type, target_id, reason, details, status, created_at, resolved_at)`
- `blocks(user_id, blocked_user_id, created_at, pk)` — engelleme Mahalle dışında da uygulanır (iki yönlü,
  moderatör hariç): engellenenin ihtiyaçları (`need_visible`), hayvanları (`animals_at_spot`; tablo okumasında RLS
  tek yönlü), koruyucu kaydı gizlenir; oluşturduğu nokta haritada kalır ama `note`/`photo_url` null döner.
- `notifications(id, user_id, kind, title, body, spot_id null, need_id null, read_at, pushed_at, created_at)`
- `device_tokens(token pk, user_id, platform text default 'ios', apns_env text default 'production' — sandbox | production, updated_at)`
- `notification_prefs(user_id pk, radius_m int default 1000, quiet_start smallint default 22, quiet_end smallint default 7, need_food_nearby bool default true, followed_updates bool default true, guardian_alerts bool default true, notify_center geography(Point) null, updated_at)`
  — `notify_center` kullanıcının **yalnızca son** kaba konumudur (3 ondalık, ≈110 m'ye yuvarlanır), geçmiş tutulmaz.
- `donation_events(id, user_id null, kind text, ref_code, created_at)`
- `donation_stats(month date pk, kg_distributed numeric, donor_count int, updated_at)` — ortak dernekten gelen aylık toplam.

Doğrudan tablo erişimi (RLS ile)

| Tablo | select | insert | update | delete |
|---|---|---|---|---|
| profiles | herkes (public alanlar) | kendi | kendi (trust/verified/moderator hariç) | — |
| animals | herkes | authenticated, `created_by = auth.uid()` | oluşturan veya doğrulanmış besleyici | — |
| animal_spots | herkes | RPC ile | RPC ile | — |
| guardians | herkes | kendi | kendi | kendi |
| follows | kendi | kendi | — | kendi |
| reports | moderatör | kendi | moderatör | — |
| blocks | kendi | kendi | — | kendi |
| notifications | kendi | — (sunucu) | kendi (`read_at`) | kendi |
| device_tokens | — | RPC ile | RPC ile | kendi |
| notification_prefs | kendi | kendi | kendi | — |
| donation_stats | herkes | — | — | — |
| spots, checkins, needs, spot_gone_reports, donation_events | **yok** — yalnızca RPC | | | |

## `spot_row` (RPC'lerin döndüğü nokta satırı)

```
id uuid, lat float8, lng float8, is_location_exact bool,
type spot_type, species spot_species, title text, note text, photo_url text,
status spot_status, last_fed_at timestamptz, has_urgent_need bool, open_need_count int,
visibility spot_visibility, is_active bool, created_by uuid, created_at timestamptz,
animal_count int, guardian_count int, distance_m float8 /* referans nokta yoksa null */
```

## `need_row`

```
id uuid, type need_type, urgency need_urgency, status need_status, description text, photos text[],
spot_id uuid, spot_title text, animal_id uuid, animal_name text, animal_photo_url text,
lat float8, lng float8, is_location_exact bool, distance_m float8,
created_by uuid, claimed_by uuid, claimed_by_name text, created_at timestamptz, claimed_at timestamptz, resolved_at timestamptz
```

## `animal_row`

```
animals tablosunun tüm sütunları (id, species, name, color_pattern, sex, age_estimate, is_neutered, ear_tag,
vaccination_info, temperament_tags, warning, about, photos, last_seen_at, last_seen_spot_id, created_by, created_at)
+ seen_count int, spot_last_seen_at timestamptz   /* ilgili noktadaki görülme bilgisi */
```

## RPC'ler

Hepsi `select * from rpc(...)` / PostgREST `POST /rpc/<ad>` ile çağrılır. "auth" = oturum zorunlu.

| RPC | Parametreler | Dönüş | Not |
|---|---|---|---|
| `spots_in_bounds` | `min_lat, min_lng, max_lat, max_lng float8, max_rows int = 500` | `setof spot_row` | anon OK; pasif ve `rejected` gizli, `pending` yalnızca oluşturana |
| `spots_near` | `lat, lng float8, radius_m int = 1000, max_rows int = 200` | `setof spot_row` (distance_m dolu, artan) | anon OK |
| `spot_detail` | `p_spot_id uuid` | `setof spot_row` (0/1 satır) | anon OK |
| `spot_feeding_timeline` | `p_spot_id uuid, days int = 7` | `table(day date, fed_count int, need_count int, last_fed_at timestamptz)` | anon OK; gün `Europe/Istanbul`'a göre, boş günler de döner |
| `spot_guardians` | `p_spot_id uuid` | `table(user_id uuid, display_name text, avatar_url text, is_verified_feeder bool, schedule smallint[])` | auth (kişi adları girişe bağlı) |
| `find_duplicate_spots` | `lat, lng float8, radius_m int = 15` | `table(id uuid, title text, distance_m float8)` | auth |
| `create_spot` | `lat, lng float8, p_type spot_type, p_species spot_species, p_title text, p_note text, p_photo_url text, p_visibility spot_visibility, p_force bool = false` | `jsonb` | auth. Bkz. aşağı |
| `check_in` | `p_spot_id uuid, p_kind checkin_kind, p_amount food_amount, p_photo_url text, user_lat float8, user_lng float8, p_client_id uuid = null` | `jsonb` | auth. Bkz. aşağı. `p_client_id` çevrimdışı kuyruktan tekrar gönderimde çift kaydı önler (idempotent) |
| `report_spot_gone` | `p_spot_id uuid` | `jsonb {status:'ok', count int, deactivated bool}` | auth, kullanıcı başına 1 kez; 3 farklı kullanıcı → `is_active=false` (FR-N6) |
| `needs_near` | `lat, lng float8, radius_m int = 5000, include_resolved bool = false` | `setof need_row` | anon OK. Sıra: urgent önce, sonra mesafe (FR-I5) |
| `need_detail` | `p_need_id uuid` | `setof need_row` | anon OK |
| `needs_for` | `p_spot_id uuid = null, p_animal_id uuid = null, include_resolved bool = false` | `setof need_row` | anon OK; noktaya veya hayvana bağlı ihtiyaçlar (hayvan profili, nokta detayı) |
| `search_spots` | `q text, lat float8 = null, lng float8 = null, max_rows int = 30` | `setof spot_row` | anon OK; başlık/not `ilike` (Türkçe büyük/küçük harf duyarsız), konum verilirse yakından uzağa; gizlilik kuralları aynen geçerli |
| `create_need` | `p_spot_id uuid, p_animal_id uuid, p_type need_type, p_urgency need_urgency, p_description text, p_photos text[]` | `uuid` | auth, küfür filtresi |
| `claim_need` | `p_need_id uuid` | `jsonb {status:'ok'|'already_claimed'|'resolved'}` | auth (FR-I3) |
| `resolve_need` | `p_need_id uuid` | `jsonb {status:'ok'|'not_allowed'}` | auth; oluşturan, üstlenen veya doğrulanmış besleyici |
| `animals_at_spot` | `p_spot_id uuid` | `setof animal_row` (bkz. aşağı), `seen_count` azalan | anon OK |
| `animal_spots_of` | `p_animal_id uuid` | `setof spot_row` | anon OK; hayvanın görüldüğü noktalar |
| `mark_animal_seen` | `p_animal_id uuid, p_spot_id uuid` | `void` | auth (FR-A3) |
| `profile_stats` | `p_user_id uuid` | `table(fed_spot_count int, checkin_count int, resolved_need_count int, verified_checkins_30d int)` | |
| `neighborhood_summary` | `lat, lng float8, radius_m int = 1500` | `table(fed_spots_today int, open_needs int, needs_food_spots int, active_spots_7d int)` | anon OK |
| `followed_spots` | — | `setof spot_row` | auth |
| `register_device_token` | `p_token text, p_env text default 'production'` (sandbox \| production) | `void` | auth |
| _(tablo)_ `device_tokens` DELETE | `token = …` (RLS: kendi) | — | auth — çıkıştan hemen önce istemci kendi token'ını siler |
| `update_notify_center` | `lat, lng float8` | `void` | auth; 3 ondalığa yuvarlar |
| `donation_overview` | — | `table(month date, kg_distributed numeric, donor_count int)` | anon OK, içinde bulunulan ay |
| `log_donation_click` | `p_ref_code text` | `void` | anon OK (PRD 8.2: yalnızca "sayfaya gidildi" ölçülür) |

### `create_spot` sonucu

```jsonc
{ "status": "created", "spot_id": "…", "moderation_state": "approved" | "pending" }
{ "status": "duplicate", "duplicates": [ { "id": "…", "title": "…", "distance_m": 9.4 } ] }   // p_force=false ve 15 m içinde nokta var (FR-N3)
{ "status": "limit_reached", "limit": 5 }                                                     // günlük limit: yeni 5, doğrulanmış 30 (PRD 9.3)
{ "status": "rejected_content" }                                                              // başlık/notta küfür
```
`trust_score < 5` olan kullanıcının noktası `moderation_state = 'pending'` ile oluşur.

### `check_in` sonucu

```jsonc
{ "status": "ok", "checkin_id": "…", "distance_m": 42, "closed_need_count": 1, "spot_status": "fed_recent" }
{ "status": "too_far", "distance_m": 180, "max_distance_m": 100 }   // fed/water: 100 m (FR-C2), need_*/broken: 300 m (FR-C3)
{ "status": "spot_inactive" }
{ "status": "rate_limited" }                                          // aynı kullanıcı + nokta + tür için 10 dk içinde ikinci kayıt
```
Yan etkiler:
- `fed`/`water` → `spots.last_fed_at = now()` (yalnızca `fed`), açık `need_food`/`need_water`/`broken` check-in'leri
  `resolved_at = now(), resolved_by = yeni id` olur, her açan kişiye `thanks_fed` bildirimi (FR-C5).
- `need_food`/`need_water`/`broken` → yarıçapı içinde `notify_center`'ı olan ve tercihi açık kullanıcılara
  `need_food_nearby` bildirimi (oluşturan ve engellenenler hariç) (FR-C4).
- Takipçilere `followed_spot_changed`.
- Güven puanı: konumu doğrulanmış check-in +1, fotoğraflı +1 ek (PRD 9.3).

## Edge Functions

| Fonksiyon | Tetikleyici | Görev |
|---|---|---|
| `push-dispatch` | pg_cron her dakika (pg_net) veya elle | `notifications.pushed_at is null` satırlarını APNs'e gönderir. Sessiz saat (kullanıcının `quiet_start`–`quiet_end`, `Europe/Istanbul`) ve `need_food_nearby` için günde en fazla 3 push kuralı uygulanır; uygulanmayanlar uygulama içi kalır. |
| `delete-account` | istemci (JWT ile) | `auth.admin.deleteUser`; FK'lar sayesinde kişisel veri silinir, nokta/hayvan kayıtları `created_by = null` ile kalır (PRD 9.5). Apple ile bağlı hesapta gövde `{"apple_authorization_code": "…"}` zorunlu: sunucu Apple token'ını iptal eder (App Store 5.1.1(v)); kod yok/geçersiz → `400 apple_reauth_required`. |

## Cron (pg_cron)

| İş | Sıklık | SQL |
|---|---|---|
| `refresh-spot-status` | `*/15 * * * *` | `select refresh_spot_statuses();` — durum kalıcılaştırma + koruyuculara `guardian_spot_unfed` (24 saatte bir kez) + doğrulanmış besleyici rozeti (30 günde 20+ doğrulanmış check-in, FR-P4) |
| `push-dispatch` | `* * * * *` | pg_net ile edge function çağrısı |

## Storage

- Bucket `photos` (public read). Yol: `{auth.uid()}/{uuid}.jpg`. Yalnızca kendi klasörüne yükleme.
- İstemci yüklemeden önce EXIF/GPS siler ve uzun kenarı 1600 px'e küçültür (PRD 7.1).

---

# Mahalle (topluluk) — v0.2

Besleyicilerin birbiriyle etkileşime girdiği sayfa (D17). İlkeler:

- **Özel mesajlaşma yok.** Tüm etkileşim mahalleye açık, raporlanabilir ve engellenebilir (PRD 4: mesajlaşmanın
  moderasyon yükü). Etkileşim biçimleri: paylaşım, yorum, "pati" tepkisi ve "Ben bakarım" gönüllülüğü.
- **Tümü giriş gerektirir.** Bu bölümdeki hiçbir RPC `anon` rolüne açık değildir: besleyicilerin konuşmaları ve
  adları girişsiz taranamasın (PRD 9.1).
- **Konum:** paylaşımın yalnızca kaba konumu saklanır (`cell`: enlem/boylam **2 ondalığa** yuvarlanır, ≈1,1 km).
  Paylaşım bir noktaya bağlıysa `cell` noktanın konumundan, değilse istemcinin gönderdiği konumdan türetilir.
- Engellenen (iki yönde) kullanıcıların paylaşım ve yorumları görünmez.

## Enum'lar

| Tip | Değerler |
|---|---|
| `community_post_kind` | `note` (paylaşım), `question` (soru/tavsiye), `cover_request` ("Yerime bakar mısın?"), `supply` (mama/malzeme paylaşımı), `alert` (uyarı) |
| `report_target` (ek) | `post`, `comment` |
| `notification_kind` (ek) | `community_comment`, `cover_volunteered` |

`alter type … add value` kendi migration dosyasında durur (aynı transaction'da kullanılamaz).

## Tablolar

- `community_posts(id, author_id → profiles on delete cascade, kind, body text, photo_url, spot_id → spots on delete set null, animal_id → animals on delete set null, cell geography(Point,4326), cover_from date, cover_to date, moderation_state default 'approved', created_at, updated_at)` + GIST(cell), btree(created_at desc), btree(author_id)
- `community_comments(id, post_id → community_posts on delete cascade, author_id → profiles on delete cascade, body text, moderation_state default 'approved', created_at)`
- `community_paws(post_id, user_id, created_at, pk(post_id, user_id))` — "pati bırak" tepkisi
- `cover_volunteers(post_id, user_id, created_at, pk(post_id, user_id))` — "Ben bakarım"
- `notifications.post_id uuid null → community_posts on delete cascade` (yeni sütun)
- `notifications.actor_id uuid null → profiles on delete cascade` (yeni sütun): bildirimi tetikleyen kişi; hesabı silinince adını anan bildirim de silinir
- `notification_prefs.community_updates bool not null default true` (yeni sütun)

Dördü de RLS açık ve **doğrudan erişim yok**; yalnızca RPC. Hesap silinince kullanıcının paylaşım, yorum, pati ve
gönüllülük kayıtları silinir (kişisel içerik, PRD 9.5).

## Kurallar

| Kural | Değer |
|---|---|
| Paylaşım metni | 1–600 karakter (trim sonrası) |
| Yorum metni | 1–300 karakter |
| Günlük limit (İstanbul günü) | 10 paylaşım, 60 yorum → `limit_reached` |
| Küfür filtresi | `rejected_content` |
| `cover_request` | görünür bir `spot_id` zorunlu; `cover_from ≥ bugün`, `cover_to ≥ cover_from`, süre ≤ 30 gün |
| Düşük güven puanı (`trust_score < 5`) | paylaşım `moderation_state = 'pending'` ile oluşur, yalnızca yazarına görünür |
| Otomatik gizleme | bir paylaşım veya yorum **3 farklı kullanıcı** tarafından raporlanırsa `pending` olur (reports insert trigger'ı) |
| Akış yarıçapı | varsayılan 3000 m; sunucu 1000–10 000 m aralığına sıkıştırır (kaba konum ≈1 km olduğundan daha küçüğü anlamsız) |

## `community_post_row`

```
id uuid, kind community_post_kind, body text, photo_url text,
author_id uuid, author_name text, author_avatar_url text, author_is_verified bool,
spot_id uuid, spot_title text,          /* nokta izleyene görünür değilse ikisi de null */
animal_id uuid, animal_name text,
cover_from date, cover_to date, volunteer_count int, viewer_volunteered bool,
paw_count int, viewer_pawed bool, comment_count int,
distance_m float8,                      /* izleyicinin konumundan cell'e; konum verilmediyse null */
moderation_state moderation_state, created_at timestamptz
```
`comment_count` yalnızca izleyiciye görünür (onaylı, engelsiz) yorumları sayar.

## `community_comment_row`

```
id uuid, post_id uuid, body text,
author_id uuid, author_name text, author_avatar_url text, author_is_verified bool,
created_at timestamptz
```

## RPC'ler (hepsi auth)

| RPC | Parametreler | Dönüş | Not |
|---|---|---|---|
| `community_feed` | `lat, lng float8, radius_m int = 3000, p_kind community_post_kind = null, p_before timestamptz = null, max_rows int = 30` | `setof community_post_row` | `created_at` azalan; sayfalama `p_before` ile (keyset); `max_rows` en fazla 50. `created_at` satırda **milisaniyeye kırpılmış** döner ve imleç aynı kırpılmış değerle karşılaştırılır (istemci milisaniye hassasiyetiyle gönderir) |
| `community_post_detail` | `p_post_id uuid, lat float8 = null, lng float8 = null` | `setof community_post_row` (0/1) | gizli/engelli/yok → 0 satır |
| `community_comments_of` | `p_post_id uuid` | `setof community_comment_row` | `created_at` artan, en fazla 200 |
| `cover_volunteers_of` | `p_post_id uuid` | `table(user_id uuid, display_name text, avatar_url text, is_verified_feeder bool)` | |
| `create_community_post` | `p_kind community_post_kind, p_body text, p_photo_url text, p_spot_id uuid, p_animal_id uuid, lat float8, lng float8, p_cover_from date, p_cover_to date` | `jsonb` | bkz. aşağı |
| `add_community_comment` | `p_post_id uuid, p_body text` | `jsonb` | bkz. aşağı |
| `toggle_post_paw` | `p_post_id uuid` | `jsonb` | `{status:'ok', pawed bool, paw_count int}` \| `{status:'post_not_found'}` |
| `toggle_cover_volunteer` | `p_post_id uuid` | `jsonb` | bkz. aşağı |
| `delete_community_post` | `p_post_id uuid` | `jsonb {status:'ok'|'not_allowed'}` | yazar veya moderatör; bilinmeyen id → `not_found` istisnası |
| `delete_community_comment` | `p_comment_id uuid` | `jsonb {status:'ok'|'not_allowed'}` | yorumun yazarı, paylaşımın yazarı veya moderatör |
| `community_summary` | `lat, lng float8, radius_m int = 3000` | `table(fed_spot_days_7d int, active_feeders_7d int, open_cover_requests int, posts_7d int)` | "Bu hafta mahallende" kartı. `fed_spot_days_7d` = son 7 günde `fed` check-in'i olan farklı (nokta, gün) sayısı: PRD'nin kuzey yıldızı metriği |

### `create_community_post` sonucu

```jsonc
{ "status": "created", "post_id": "…", "moderation_state": "approved" | "pending" }
{ "status": "rejected_content" }
{ "status": "limit_reached", "limit": 10 }
{ "status": "invalid", "reason": "body_empty" | "body_too_long" | "cover_needs_spot" | "cover_dates" | "spot_not_found" }
```
`lat`/`lng` nokta bağlı değilse zorunludur (yoksa `invalid_coordinates` istisnası; istemci bunu göndermeden önce yakalar). `cover_request` dışındaki
türlerde `p_cover_*` yok sayılır. Denetim sırası: metin, küfür, günlük limit, nokta, tarih kuralları, konum.
Görünürlük: `pending` içeriği yazarı ve moderatör görür, `rejected` içeriği yalnızca moderatör. Gönüllü sayısı ve listesi
izleyiciyle engelli kullanıcıları içermez.

### `add_community_comment` sonucu

```jsonc
{ "status": "created", "comment_id": "…" }
{ "status": "rejected_content" }
{ "status": "limit_reached", "limit": 60 }
{ "status": "invalid", "reason": "body_empty" | "body_too_long" }
{ "status": "post_not_found" }
```
Yan etki: paylaşımın yazarına `community_comment` bildirimi (`post_id` dolu). Yazar kendine yorum yazdıysa,
taraflar engelliyse, yazarın `community_updates` tercihi kapalıysa veya aynı paylaşım için okunmamış aynı tür
bildirim zaten varsa gönderilmez.

### `toggle_cover_volunteer` sonucu

```jsonc
{ "status": "ok", "volunteered": true, "volunteer_count": 2 }
{ "status": "not_cover_request" }
{ "status": "own_post" }
{ "status": "closed" }            // cover_to geçmişte
{ "status": "post_not_found" }
```
Yan etki (gönüllü olunca): yazara `cover_volunteered` bildirimi (`post_id` ve `spot_id` dolu); yukarıdaki aynı
koşullarla bastırılır.

## Push

`push-dispatch` APNs payload'una `post_id` ekler. `community_comment` ve `cover_volunteered` sessiz saat kuralına
uyar; günlük 3 push limiti yalnızca `need_food_nearby` içindir.

# Tanışma (buluşmalar + Hayvanseverler + sohbet) — v0.3

Mahalle'nin üstüne kurulan sosyal katman (D19, spec: `docs/superpowers/specs/2026-11-14-tanisma-design.md`).
Migration'lar: `20261114000018…24`, anlık mama turu ve "Bugün besledi" için `20261116000025` (D20). İlkeler:

- **Tümü giriş gerektirir.** Bu bölümdeki her RPC yalnızca `authenticated` rolüne açıktır; tablolar RLS açık ve
  `anon`/`authenticated` doğrudan okuyamaz/yazamaz (yalnızca `security definer` RPC'ler).
- **18+ sosyal onay** (`social_profiles.adult_confirmed_at` + `terms_accepted_at`, `give_social_consent`). Onay yoksa
  yazma RPC'leri `{status:'consent_required'}` döner; okuma RPC'leri boş döner. İstisna: buluşma listesi ve detayı
  onaysız da okunur (kullanıcı görür, katılmak/açmak isteyince onay ekranı gelir).
- **Bire bir sohbet yalnızca karşılıklı kabulle** açılır (istek → kabul). Kişiler haritada asla pin değildir;
  Hayvanseverler listesi yalnızca **mesafe bandı** döner.
- **Konum:** `social_profiles.cell` enlem/boylam **2 ondalığa** yuvarlanır (≈1 km, `round_social_cell` trigger'ı).
  Liste sorgusu istemcinin noktasını değil, izleyicinin **sunucudaki kendi `cell`**'ini kullanır (üçgenleme yok).
  Buluşma noktası ise tam saklanır ve gösterilir: herkese açık bir buluşma yeri, kişisel konum değil.
- **Engelleme iki yönlü** (`private.blocked_between`): bire bir sohbet gizlenir, grup sohbetinde mesajlar görünmez,
  listelerde birbirlerini görmezler; buluşmanın düzenleyeniyle engel varsa buluşma `not_found`/görünmez.
- Hesap silinince sosyal profil, bağlantılar, mesajlar ve üyelikler cascade silinir; düzenlenen **gelecek** buluşmalar
  katılımcılara `meetup_cancelled` bildirimiyle silinir.

## Enum'lar

| Tip | Değerler |
|---|---|
| `social_interest` | `cats`, `dogs`, `birds`, `neutering`, `fostering`, `vet_transport`, `food_donation`, `photography` |
| `meetup_status` | `active`, `cancelled` |
| `participant_status` | `joined`, `removed` (çıkarılan tekrar katılamaz) |
| `connection_status` | `pending`, `accepted`, `declined`, `removed` |
| `conversation_kind` | `meetup`, `direct` |
| `distance_band` | `under_1km` (< 1000 m), `1_3km` (< 3000 m), `3_10km` (≤ 10 000 m); 10 km dışı dönmez |
| `report_target` (ek) | `meetup`, `chat_message` |
| `notification_kind` (ek) | `meetup_joined`, `meetup_cancelled`, `meetup_reminder`, `connection_request`, `connection_accepted`, `chat_message` |

## Tablolar

- `social_profiles(user_id pk → profiles on delete cascade, is_visible bool default false, about text ≤300, interests social_interest[], cell geography(Point) [≈1 km], adult_confirmed_at, terms_accepted_at, updated_at)`
- `meetups(id, organizer_id → profiles cascade, title 3–80, description ≤600, starts_at, ends_at [süre 30 dk–8 saat], place_name 1–80, location geography(Point) [tam], spot_id → spots set null, capacity null|2–50, status, created_at, is_tour bool not null default false [0025])`
- `meetup_participants(meetup_id → meetups cascade, user_id → profiles cascade, status participant_status, joined_at, pk(meetup_id, user_id))` — düzenleyen de `joined` satırıdır
- `connections(id, requester_id, addressee_id → profiles cascade, note ≤200, status, created_at, responded_at)` — sırasız çift başına tek satır
- `conversations(id, kind, meetup_id unique → meetups cascade, connection_id unique → connections set null, created_at, closed_at)`
- `conversation_members(conversation_id → conversations cascade, user_id → profiles cascade, last_read_at, pk)`
- `chat_messages(id, conversation_id → conversations cascade, author_id → profiles cascade, body 1–1000, moderation_state default 'approved', created_at)`
- `notifications.meetup_id → meetups on delete set null`, `notifications.conversation_id → conversations on delete cascade` (yeni sütunlar)
- `notification_prefs.social_updates bool not null default true` (yeni sütun; iOS `NotificationPreferences.socialUpdates`, Ayarlar › "Mahalle ve tanışma bildirimleri")

Görünürlüğün tek kaynağı `private.conversation_visible` / `private.conversation_read_only`. Üyesi 2'den az kalan
direct sohbet salt okunurdur, başlığı "Silinmiş kullanıcı".

## Kurallar

| Kural | Değer |
|---|---|
| Buluşma başlangıcı | `now() + 1 saat` … `now() + 60 gün` |
| Buluşma süresi | 30 dk – 8 saat (istemci varsayılanı 2 saat) |
| Günlük buluşma (İstanbul günü) | 3 → `limit_reached` (turlar sayılmaz) |
| Anlık mama turu | hemen başlar (`starts_at = now()`), süre **60–120 dk** (istemci 60/90/120, varsayılan 90); yalnızca aktif, izleyene görünür ve `visibility = 'public'` nokta; aynı anda **tek** açık tur (`already_touring`); günde **3** tur (iptal/bitmiş dahil, buluşma limitinden ayrı); hatırlatma bildirimi yok |
| "Bugün besledi" (`fed_today`) | bugün (İstanbul günü) `fed` ya da `water` check-in'i **veya** bugün açılmış bir tur; nerede/ne zaman bilgisi dönmez |
| Buluşma sohbeti | bitişten **24 saat** sonra (ya da iptalde) salt okunur; bitişten **30 gün** sonra mesajlar silinir (`social-chat-retention` cron, 03:20) |
| Günlük bağlantı isteği | 10 → `limit_reached` |
| Reddedilen istek | gönderene "beklemede" görünür; aynı kişiye **30 gün** `cooldown` |
| Karşı taraf zaten istek attıysa | yeni istek `auto_accepted` |
| Mesaj | yalnızca metin, 1–1000; sohbet başına dakikada 20, kullanıcı başına günde 500 → `rate_limited` |
| Küfür filtresi | `private.contains_profanity` → `rejected_content` |
| Otomatik gizleme | mesaj **3 farklı kullanıcı** tarafından raporlanırsa `pending` (yalnızca yazarı görür) |
| Hayvanseverleri kim görür | yalnızca kendisi görünür (`is_visible`) ve konumlu olanlar; görünmeyen tarayamaz, istek atamaz |

## `meetup_row`

```
id uuid, title text, description text, starts_at timestamptz, ends_at timestamptz,
place_name text, lat float8, lng float8,
spot_id uuid, spot_title text,          /* nokta izleyene görünür değilse ikisi de null */
capacity int, participant_count int,    /* düzenleyen dahil, joined olanlar */
status meetup_status,
organizer_id uuid, organizer_name text, organizer_avatar_url text, organizer_is_verified bool,
viewer_role text,                       /* organizer | participant | removed | none */
conversation_id uuid,                   /* yalnızca organizer/participant için dolu */
distance_m float8,                      /* izleyicinin verdiği konumdan; verilmediyse null */
created_at timestamptz,
is_tour bool                            /* 0025: anlık mama turu (sona eklendi) */
```

## RPC'ler (hepsi auth)

| RPC | Parametreler | Dönüş | Not |
|---|---|---|---|
| `social_profile_me` | — | `table(is_visible bool, about text, interests social_interest[], consented bool)` | satır yoksa 0 satır |
| `give_social_consent` | — | `jsonb {status:'ok'}` | idempotent; satırı `is_visible = false` ile oluşturur |
| `update_social_profile` | `p_is_visible bool, p_about text, p_interests social_interest[], lat float8 = null, lng float8 = null` | `jsonb` | `ok` \| `consent_required` \| `rejected_content` \| `invalid` (`reason: about_too_long \| location_required`). Görünür olmak için konum gerekir (verilmezse önceki `cell`) |
| `meetups_near` | `lat, lng float8, radius_m int = 10000` | `setof meetup_row` | aktif, bitmemiş; yakından uzağa, sonra başlangıca göre. `radius_m` 1–50 000 dışı → `invalid_radius` istisnası. Onaysız da okunur |
| `meetup_detail` | `p_meetup_id uuid, lat float8 = null, lng float8 = null` | `setof meetup_row` (0/1) | iptal edilmiş de döner; düzenleyenle engel → 0 satır |
| `meetup_participants` | `p_meetup_id uuid` | `table(user_id uuid, display_name text, avatar_url text, is_verified_feeder bool, is_organizer bool)` | yalnızca düzenleyen/katılımcı görür; diğerlerine boş |
| `create_meetup` | `p_title text, p_description text, p_starts_at timestamptz, p_duration_minutes int, p_place_name text, lat float8, lng float8, p_spot_id uuid = null, p_capacity int = null` | `jsonb` | bkz. aşağı |
| `join_meetup` | `p_meetup_id uuid` | `jsonb` | `{status:'joined', conversation_id}` \| `full` \| `removed` \| `cancelled` \| `ended` \| `consent_required` \| `not_found` |
| `leave_meetup` | `p_meetup_id uuid` | `jsonb` | `ok` \| `organizer_cannot_leave` (düzenleyen iptal eder) |
| `remove_meetup_participant` | `p_meetup_id uuid, p_user_id uuid` | `jsonb` | `ok` \| `not_allowed` (yalnızca düzenleyen, aktif ve bitmemiş buluşma) |
| `cancel_meetup` | `p_meetup_id uuid` | `jsonb` | `ok` (zaten iptalse de) \| `not_allowed` (düzenleyen değil ya da bitmiş). Turda "Turu bitir" de budur |
| `start_feeding_tour` | `p_spot_id uuid, p_duration_minutes int = 90` | `jsonb` | "Mama turuna çıkıyorum" (0025). Bkz. aşağı |
| `animal_lovers_near` | `p_interest social_interest = null` | `table(user_id, display_name, avatar_url, about, interests, is_verified_feeder, fed_30d int, distance_band, shared_interest_count int, connection_state text, request_id uuid, conversation_id uuid, fed_today bool, on_tour_meetup_id uuid)` | izleyicinin kendi `cell`'inden ≤10 km. Sıra (0025): şu an turda olanlar → `fed_today` → mesafe bandı → ortak ilgi sayısı → ad. `on_tour_meetup_id`: kişinin şu an açık turu (engel zaten süzülür), yoksa null. `connection_state`: `none \| outgoing_pending \| incoming_pending \| connected` |
| `incoming_connection_requests` | — | `table(request_id, user_id, display_name, avatar_url, about, interests, is_verified_feeder, note, created_at)` | bana gelen `pending` istekler |
| `send_connection_request` | `p_user_id uuid, p_note text = null` | `jsonb` | bkz. aşağı |
| `respond_connection` | `p_request_id uuid, p_accept bool` | `jsonb` | `{status:'accepted', conversation_id}` \| `declined` \| `not_found` |
| `withdraw_connection_request` | `p_request_id uuid` | `jsonb` | `ok` \| `not_found` |
| `remove_connection` | `p_user_id uuid` | `jsonb` | `ok` \| `not_found`; bire bir sohbet kapanır. Yeniden kabulde aynı sohbet yeniden açılır |
| `my_conversations` | — | `table(conversation_id, kind, title, meetup_id, other_user_id, other_avatar_url, last_body, last_at, unread int, read_only bool)` | son mesaja göre, en fazla 200. `title`: buluşma başlığı ya da karşı tarafın adı |
| `conversation_messages` | `p_conversation_id uuid, p_before timestamptz = null, max_rows int = 50` | `table(id, author_id, author_name, author_avatar_url, body, created_at, is_pending bool)` | eskiden yeniye; `p_before` ile daha eskiler (keyset) |
| `send_chat_message` | `p_conversation_id uuid, p_body text` | `jsonb` | `{status:'sent', message_id, created_at}` \| `not_member` \| `read_only` \| `rate_limited` \| `rejected_content` \| `consent_required` \| `invalid` (`reason: body_empty \| body_too_long`) |
| `mark_conversation_read` | `p_conversation_id uuid` | `void` | `last_read_at = now()`; o sohbetin `chat_message` bildirimlerini de okundu yapar |
| `can_listen_conversation` | `p_topic text` | `bool` | Realtime yetkisi: `conversation:<uuid>` biçimli konu ve izleyici görünür sohbetin üyesi. Hatalı konu → `false` (istisna değil) |

### `create_meetup` sonucu

```jsonc
{ "status": "created", "meetup_id": "…", "conversation_id": "…" }
{ "status": "consent_required" }
{ "status": "rejected_content" }
{ "status": "limit_reached", "limit": 3 }
{ "status": "invalid", "reason": "title_length" | "description_too_long" | "place_name_length" | "start_too_soon"
                                | "start_too_late" | "duration_range" | "capacity_range" | "spot_not_found" }
```
Düzenleyen `joined` katılımcı olarak eklenir ve buluşmanın grup sohbeti açılır.

### `start_feeding_tour` sonucu

```jsonc
{ "status": "started", "meetup_id": "…", "conversation_id": "…" }
{ "status": "consent_required" }
{ "status": "invalid", "reason": "duration_range" }   // 60–120 dk dışı ya da null
{ "status": "spot_not_found" }    // yok, pasif, izleyene görünmüyor ya da visibility <> 'public'
{ "status": "already_touring" }   // düzenlediği aktif, bitmemiş bir tur var
{ "status": "limit_reached", "limit": 3 }
```
Sıra: onay → süre → nokta → açık tur → günlük limit (son ikisi kullanıcı başına advisory kilit altında). Tur,
`is_tour = true` bir buluşmadır: başlık `'Mama turu: ' || nokta adı` (80'e kırpılır), `place_name` = nokta adı,
`location` = noktanın konumu, `spot_id` = nokta, `capacity` yok. Düzenleyen `create_meetup`'taki gibi katılımcı ve
sohbet üyesi olur. Katıl/ayrıl/çıkar/iptal, sohbet, rapor ve `meetup_joined` / `meetup_cancelled` bildirimleri
buluşmalarla aynı; `meetup_reminder` turlara gönderilmez.

### `send_connection_request` sonucu

```jsonc
{ "status": "sent", "request_id": "…" }
{ "status": "auto_accepted", "conversation_id": "…" }   // karşı taraf zaten istek atmıştı
{ "status": "consent_required" }
{ "status": "not_visible" }        // ben ya da karşı taraf görünür değil
{ "status": "already_connected" }
{ "status": "already_pending" }
{ "status": "cooldown" }           // reddedilen istekten sonra 30 gün
{ "status": "rejected_content" }
{ "status": "limit_reached", "limit": 10 }
{ "status": "invalid", "reason": "note_too_long" }
{ "status": "not_found" }
```

## Bildirimler

Hepsi `private.notify_social` üstünden üretilir (AFTER trigger'lar): iki yönlü engel, alıcının `social_updates`
tercihi (satır yoksa açık) ve "gönderen = alıcı değil" kuralı. İptal edilmiş ya da bitmiş buluşma için bildirim yok.

| Tür | Alıcı | Dolu sütunlar |
|---|---|---|
| `meetup_joined` | düzenleyen | `meetup_id`, `actor_id` |
| `meetup_cancelled` | katılımcılar (düzenleyen hariç); hesap silmede de | `meetup_id` |
| `meetup_reminder` | düzenleyen + katılımcılar, buluşma başına bir kez; cron `meetup-reminders` her 15 dk, 2 saat içinde başlayanlar. **Turlara gönderilmez** (0025) | `meetup_id` |
| `connection_request` | alıcı | `actor_id` |
| `connection_accepted` | ilk gönderen (otomatik kabulde diğer taraf) | `actor_id` |
| `chat_message` | yazar dışındaki üyeler; aynı sohbet için okunmamış bildirim varsa yenisi yok. **Mesaj metni içermez**, yalnızca yazar adı | `conversation_id`, `actor_id` |

## Push

`push_claim_batch` sonuna `meetup_id`, `conversation_id` eklendi; `push-dispatch` bunları APNs payload'una koyar
(`thread-id` = sohbet). Sosyal türler sessiz saate uyar, `need_food_nearby` günlük sınırına girmez. iOS yönlendirmesi
(`PushPayload`): `conversation_id` → Profil › sohbet, `meetup_id` → Mahalle › buluşma (öncelik: sohbet > buluşma >
paylaşım > ihtiyaç > nokta). Bildirimler ekranı da aynı önceliği kullanır.

## Realtime

Mesaj eklenince (`approved` ise) `chat_messages_realtime` trigger'ı **özel** Broadcast kanalına yayın yapar:
konu `conversation:<conversation_id>`, olay `message`, payload yalnızca `{conversation_id}` (metin yok; istemci
`conversation_messages` ile çeker). `realtime.messages` üzerindeki `chat_members_can_listen` politikası dinlemeyi
`can_listen_conversation(realtime.topic())` ile üyelere sınırlar. `realtime.send` yoksa (yerel test imajı) kurulum
atlanır; istemci bağlantı yoksa 5 sn'de bir yeniler.
