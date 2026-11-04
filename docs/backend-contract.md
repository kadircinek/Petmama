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
- `blocks(user_id, blocked_user_id, created_at, pk)`
- `notifications(id, user_id, kind, title, body, spot_id null, need_id null, read_at, pushed_at, created_at)`
- `device_tokens(token pk, user_id, platform text default 'ios', updated_at)`
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
| `register_device_token` | `p_token text` | `void` | auth |
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
| `delete-account` | istemci (JWT ile) | `auth.admin.deleteUser`; FK'lar sayesinde kişisel veri silinir, nokta/hayvan kayıtları `created_by = null` ile kalır (PRD 9.5). |

## Cron (pg_cron)

| İş | Sıklık | SQL |
|---|---|---|
| `refresh-spot-status` | `*/15 * * * *` | `select refresh_spot_statuses();` — durum kalıcılaştırma + koruyuculara `guardian_spot_unfed` (24 saatte bir kez) + doğrulanmış besleyici rozeti (30 günde 20+ doğrulanmış check-in, FR-P4) |
| `push-dispatch` | `* * * * *` | pg_net ile edge function çağrısı |

## Storage

- Bucket `photos` (public read). Yol: `{auth.uid()}/{uuid}.jpg`. Yalnızca kendi klasörüne yükleme.
- İstemci yüklemeden önce EXIF/GPS siler ve uzun kenarı 1600 px'e küçültür (PRD 7.1).
