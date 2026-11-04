# Mama Haritası — Supabase backend

Tek doğruluk kaynağı: [`docs/backend-contract.md`](../docs/backend-contract.md). RPC adları, parametreleri ve dönüş
şekilleri oradakiyle birebir aynıdır.

```
config.toml                 CLI yapılandırması (project_id mama-haritasi, Apple + e-posta auth, photos bucket)
migrations/
  …0001_extensions.sql      postgis, pgcrypto, pg_trgm; pg_cron/pg_net (yoksa atlanır); private şeması + fuzz_salt
  …0002_enums.sql           sözleşmedeki enum'lar
  …0003_tables.sql          tablolar, GIST/btree indeksleri, FK silme davranışları
  …0004_helpers.sql         spot_row/need_row/animal_row, compute_spot_status, fuzz_point, küfür filtresi, görünürlük
  …0005_triggers.sql        auth.users → profiles + notification_prefs, updated_at, notify_center yuvarlama, …
  …0006_rls.sql             RLS + (sütun bazlı) yetkiler — sözleşmedeki matris
  …0007_rpc_read.sql        okuma RPC'leri
  …0008_rpc_write.sql       yazma RPC'leri
  …0009_cron_push.sql       refresh_spot_statuses, push kuyruğu, pg_cron işleri
  …0010_storage.sql         photos bucket + politikalar
  …0011_anon_read_grants.sql girişsiz gezinme için okuma RPC'leri (FR-P1, D15)
functions/
  push-dispatch/            APNs gönderici (pg_cron → pg_net, her dakika)
  delete-account/           hesap silme (PRD 9.5)
  _shared/                  saf mantık + Deno testleri (sessiz saat, günlük limit, ES256 JWT, storage listeleme)
seed.sql                    Kadıköy/Moda pilot demo verisi (25 nokta, 10 hayvan, 5 ihtiyaç, 4 demo kullanıcı)
tests/                      SQL testleri + run.sh
```

## Uzak projeye kurulum

1. **Proje**: Supabase'de proje aç (bölge `eu-central-1`, D6). CLI ile bağla:
   ```sh
   supabase link --project-ref <ref>
   supabase db push            # migrations/*.sql sırayla; seed.sql üretimde ÇALIŞTIRILMAZ
   ```
   CLI yoksa migration dosyalarını sırayla SQL Editor'e yapıştırmak da olur.
   `pg_cron` ve `pg_net` migration içinde açılır; açılamazsa (Dashboard → Database → Extensions'tan açıp)
   `20261104000009_cron_push.sql` dosyasının en sondaki `do $$ … cron.schedule … $$` bloğunu tekrar çalıştır.

2. **Auth** (Dashboard → Authentication → Providers):
   - Email: açık, e-posta doğrulaması açık.
   - Apple: açık. *Client IDs* = `app.petmama.mamaharitasi` (yerel iOS girişi; web akışı yoksa secret gerekmez).
   - Site URL: şifre sıfırlama/e-posta doğrulama bağlantılarının açılacağı web sayfası. iOS uygulaması henüz
     deep link işlemiyor; eklenince `mamaharitasi://auth-callback` Redirect URL'lere eklenmeli.

3. **Bulanıklaştırma tuzu** (PRD 9.1): migration rastgele 32 baytlık tuz üretir (`private.app_settings`,
   anahtar `fuzz_salt`). Elle belirlemek için **yayından önce** SQL Editor'de:
   ```sql
   update private.app_settings set value = encode(extensions.gen_random_bytes(32), 'hex'), updated_at = now()
   where key = 'fuzz_salt';
   ```
   Yayından sonra değiştirme: bulanık noktalar yeni yere taşınır, eski + yeni konumun ortalaması gerçeğe yaklaşır.
   Staging ve üretim farklı tuz kullanmalı.

4. **Edge function sırları ve dağıtım**:
   ```sh
   supabase secrets set \
     APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY \
     APNS_BUNDLE_ID=app.petmama.mamaharitasi APNS_ENV=production \
     APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
     PUSH_DISPATCH_SECRET="$(openssl rand -hex 32)"
   supabase functions deploy push-dispatch --no-verify-jwt
   supabase functions deploy delete-account
   ```
   `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` Supabase tarafından otomatik verilir. TestFlight/geliştirme
   derlemeleri sandbox token üretir: o ortamda `APNS_ENV=sandbox`.

5. **Cron → push-dispatch bağlantısı**: URL ve paylaşılan sır veritabanında saklanır (koda gömülmez).
   Vault (önerilen):
   ```sql
   select vault.create_secret('https://<ref>.supabase.co/functions/v1/push-dispatch', 'push_dispatch_url');
   select vault.create_secret('<PUSH_DISPATCH_SECRET ile aynı değer>', 'push_dispatch_secret');
   ```
   Vault yoksa: `insert into private.app_settings(key, value) values ('push_dispatch_url', '…'), ('push_dispatch_secret', '…');`
   İkisi de yoksa `push-dispatch` cron işi hiçbir şey yapmaz. Kuyruk boşken edge function çağrılmaz.
   Kontrol: `select * from cron.job;` ve `select * from net._http_response order by created desc limit 5;`

6. **Moderatör**: `update public.profiles set is_moderator = true where id = '<uuid>';` (SQL Editor).

## Davranış notları

- **Okuma**: `spots`, `checkins`, `needs`, `spot_gone_reports`, `donation_events` tablolarına anon/authenticated
  doğrudan erişemez; her şey RPC'lerden geçer. Bulanık noktalarda kutu/yarıçap filtresi ve `distance_m`
  *gösterilen* noktaya göre hesaplanır (aksi halde gerçek konum üçgenlenebilirdi).
- **Push** (`notifications.pushed_at` / `push_status`): `pushed_at`, satır push-dispatch tarafından işlendiğinde
  dolar — gönderilmese bile. `push_status`: `sent`, `quiet_hours`, `daily_cap` (need_food_nearby günde 3,
  İstanbul günü), `no_token`, `failed`, `expired` (30 dk'dan eski). Sessiz saatte/limitte push **ertelenmez**,
  bildirim yalnızca uygulama içinde kalır.
- **Hata eşlemesi**: iş kuralları jsonb `status` döner. Exception mesajları: `not_authenticated` (42501),
  `invalid_coordinates` / `invalid_parameter` / `invalid_title` (22023), `not_found` (P0002, detail = spot/need/animal),
  `rejected_content` (P0001, hint = profanity; `create_need`, profil adı, hayvan metinleri).
- **PostgREST**: `reports` tablosuna `Prefer: return=minimal` ile eklenmeli (yalnızca moderatör okuyabilir).

## Testler

```sh
bash supabase/tests/run.sh                      # Docker varsa supabase/postgres:15.8.1.085, yoksa yerel PG 16 + PostGIS
MAMA_PG_IMAGE=supabase/postgres:17.6.1.036 bash supabase/tests/run.sh
MAMA_TEST_MODE=local bash supabase/tests/run.sh # /usr/lib/postgresql/16/bin; 00_supabase_shim.sql roller/auth/storage'ı taklit eder
bash supabase/tests/run.sh 20_checkin.sql       # tek dosya
deno test supabase/functions/_shared/           # edge function saf mantığı
deno check supabase/functions/*/index.ts
```

`run.sh` geçici bir veritabanı açar, shim → migration'lar (her biri tek transaction) → seed (iki kez,
idempotent) → `01_helpers.sql` → `[1-9][0-9]_*.sql` sırasıyla çalıştırır. Her test dosyası kendi
transaction'ında çalışıp rollback eder; `tests.check()` başarısızlıkta `FAIL: …` fırlatır.
Testler düz SQL'dir (pgTAP değil): `supabase test db` ile değil `run.sh` ile çalıştır.

Yerel tam yığın: `supabase start` (migration + seed otomatik). Demo kullanıcıların şifresi yoktur; uygulamada yeni
hesap aç. Apple için `supabase/.env` içine `SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID` / `…_SECRET` yaz.
