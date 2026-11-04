-- Mama Haritası — 0006: RLS ve tablo yetkileri (docs/backend-contract.md "Doğrudan tablo erişimi")
--
-- Supabase varsayılan olarak public şemasındaki her yeni tabloda anon/authenticated'a TÜM yetkileri
-- verir. Burada önce hepsini geri alıp matristeki kadarını (gerektiğinde sütun bazında) geri veriyoruz.
-- service_role yetkilerine dokunulmaz (RLS'i zaten atlar; edge function'lar kullanır).

alter table public.profiles           enable row level security;
alter table public.spots              enable row level security;
alter table public.checkins           enable row level security;
alter table public.animals            enable row level security;
alter table public.animal_spots       enable row level security;
alter table public.needs              enable row level security;
alter table public.guardians          enable row level security;
alter table public.follows            enable row level security;
alter table public.spot_gone_reports  enable row level security;
alter table public.reports            enable row level security;
alter table public.blocks             enable row level security;
alter table public.notifications      enable row level security;
alter table public.device_tokens      enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.donation_events    enable row level security;
alter table public.donation_stats     enable row level security;

revoke all on
  public.profiles, public.spots, public.checkins, public.animals, public.animal_spots, public.needs,
  public.guardians, public.follows, public.spot_gone_reports, public.reports, public.blocks,
  public.notifications, public.device_tokens, public.notification_prefs, public.donation_events,
  public.donation_stats
from anon, authenticated;

-- spots, checkins, needs, spot_gone_reports, donation_events: doğrudan erişim YOK — yalnızca RPC.
-- (RLS açık + politika yok + yetki yok: iki kat koruma. Konum bulanıklaştırma atlanamaz, PRD 9.1.)

-- ---------------------------------------------------------------------------
-- profiles: herkes okur; kendi satırını ekler/günceller (trust/verified/moderator hariç)
-- ---------------------------------------------------------------------------
grant select on public.profiles to anon, authenticated;
grant insert (id, display_name, avatar_url, neighborhood) on public.profiles to authenticated;
grant update (display_name, avatar_url, neighborhood) on public.profiles to authenticated;

create policy profiles_select on public.profiles
  for select to anon, authenticated using (true);
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- animals: herkes okur; giriş yapmış ekler (created_by = kendisi);
-- oluşturan veya doğrulanmış besleyici günceller
-- ---------------------------------------------------------------------------
grant select on public.animals to anon, authenticated;
grant insert (id, species, name, color_pattern, sex, age_estimate, is_neutered, ear_tag, vaccination_info,
              temperament_tags, warning, about, photos, last_seen_at, last_seen_spot_id, created_by)
  on public.animals to authenticated;
grant update (species, name, color_pattern, sex, age_estimate, is_neutered, ear_tag, vaccination_info,
              temperament_tags, warning, about, photos, last_seen_at, last_seen_spot_id)
  on public.animals to authenticated;

create policy animals_select on public.animals
  for select to anon, authenticated using (true);
create policy animals_insert_own on public.animals
  for insert to authenticated with check (created_by = (select auth.uid()));
create policy animals_update_owner_or_verified on public.animals
  for update to authenticated
  using (
    created_by = (select auth.uid())
    or exists (select 1 from public.profiles p
               where p.id = (select auth.uid()) and (p.is_verified_feeder or p.is_moderator))
  )
  with check (
    created_by = (select auth.uid())
    or exists (select 1 from public.profiles p
               where p.id = (select auth.uid()) and (p.is_verified_feeder or p.is_moderator))
  );

-- ---------------------------------------------------------------------------
-- animal_spots: herkes okur; yazma yalnızca RPC (mark_animal_seen) / trigger
-- ---------------------------------------------------------------------------
grant select on public.animal_spots to anon, authenticated;
create policy animal_spots_select on public.animal_spots
  for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- guardians: herkes okur; kendi satırını ekler/günceller/siler.
-- Koruyucu tam konumu gördüğü için (PRD 9.1) herkes kendini her noktaya koruyucu yazamaz:
-- public.can_guard_spot() (0007) kuralı insert'te zorunlu.
-- ---------------------------------------------------------------------------
grant select on public.guardians to anon, authenticated;
grant insert (user_id, spot_id, schedule) on public.guardians to authenticated;
grant update (schedule) on public.guardians to authenticated;
grant delete on public.guardians to authenticated;

create policy guardians_select on public.guardians
  for select to anon, authenticated using (true);
create policy guardians_update_own on public.guardians
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy guardians_delete_own on public.guardians
  for delete to authenticated using (user_id = (select auth.uid()));
-- guardians_insert_own politikası can_guard_spot() tanımlandıktan sonra 0007'de eklenir.

-- ---------------------------------------------------------------------------
-- follows: yalnızca kendi
-- ---------------------------------------------------------------------------
grant select, delete on public.follows to authenticated;
grant insert (user_id, target_type, target_id) on public.follows to authenticated;

create policy follows_select_own on public.follows
  for select to authenticated using (user_id = (select auth.uid()));
create policy follows_insert_own on public.follows
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy follows_delete_own on public.follows
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- reports: herkes kendi adına şikâyet eder; yalnızca moderatör okur/günceller
-- ---------------------------------------------------------------------------
grant insert (reporter_id, target_type, target_id, reason, details) on public.reports to authenticated;
grant select on public.reports to authenticated;
grant update (status, resolved_at) on public.reports to authenticated;

create policy reports_insert_own on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));
create policy reports_select_moderator on public.reports
  for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_moderator));
create policy reports_update_moderator on public.reports
  for update to authenticated
  using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_moderator))
  with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_moderator));

-- ---------------------------------------------------------------------------
-- blocks: yalnızca kendi
-- ---------------------------------------------------------------------------
grant select, delete on public.blocks to authenticated;
grant insert (user_id, blocked_user_id) on public.blocks to authenticated;

create policy blocks_select_own on public.blocks
  for select to authenticated using (user_id = (select auth.uid()));
create policy blocks_insert_own on public.blocks
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy blocks_delete_own on public.blocks
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- notifications: kendi okur, yalnızca read_at günceller, siler; ekleme sunucuda
-- ---------------------------------------------------------------------------
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy notifications_delete_own on public.notifications
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- device_tokens: ekleme/güncelleme RPC ile (register_device_token); kendi satırını siler.
-- Not: PostgreSQL `delete ... where token = $1` için SELECT yetkisi + politikası ister; bu yüzden
-- kullanıcı yalnızca KENDİ token'larını okuyabilir (sözleşmede select "—", bkz. rapor).
-- ---------------------------------------------------------------------------
grant select, delete on public.device_tokens to authenticated;

create policy device_tokens_select_own on public.device_tokens
  for select to authenticated using (user_id = (select auth.uid()));
create policy device_tokens_delete_own on public.device_tokens
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- notification_prefs: yalnızca kendi (notify_center trigger ile yuvarlanır)
-- ---------------------------------------------------------------------------
grant select on public.notification_prefs to authenticated;
grant insert (user_id, radius_m, quiet_start, quiet_end, need_food_nearby, followed_updates,
              guardian_alerts, notify_center)
  on public.notification_prefs to authenticated;
grant update (radius_m, quiet_start, quiet_end, need_food_nearby, followed_updates, guardian_alerts,
              notify_center)
  on public.notification_prefs to authenticated;

create policy notification_prefs_select_own on public.notification_prefs
  for select to authenticated using (user_id = (select auth.uid()));
create policy notification_prefs_insert_own on public.notification_prefs
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy notification_prefs_update_own on public.notification_prefs
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- donation_stats: herkes okur
-- ---------------------------------------------------------------------------
grant select on public.donation_stats to anon, authenticated;
create policy donation_stats_select on public.donation_stats
  for select to anon, authenticated using (true);
