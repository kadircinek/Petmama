-- Mama Haritası — 0008: yazma RPC'leri
--
-- Kullanıcı kimliği her zaman auth.uid()'den alınır; istemciden gelen kullanıcı id'sine güvenilmez.
-- İş kuralı sonuçları jsonb `status` ile döner; yetki/doğrulama ihlalleri exception'dır.

-- Profil satırı trigger ile oluşur; yine de yazma RPC'leri öncesi garanti altına alınır (FK).
create function private.ensure_profile(p_uid uuid)
returns void
language sql
set search_path = public, extensions
as $$
  insert into public.profiles (id) values (p_uid) on conflict (id) do nothing;
  insert into public.notification_prefs (user_id) values (p_uid) on conflict (user_id) do nothing;
$$;
revoke all on function private.ensure_profile(uuid) from public;

-- ---------------------------------------------------------------------------
-- create_spot (FR-N1..N3, PRD 9.3)
-- Sıra: içerik → günlük limit → mükerrer (p_force=false ise) → ekleme
-- ---------------------------------------------------------------------------
create function public.create_spot(
  lat          float8,
  lng          float8,
  p_type       public.spot_type,
  p_species    public.spot_species,
  p_title      text,
  p_note       text,
  p_photo_url  text,
  p_visibility public.spot_visibility,
  p_force      boolean default false
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := private.require_uid();
  v_mod   boolean;
  v_title text := btrim(coalesce(p_title, ''));
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_photo text := nullif(btrim(coalesce(p_photo_url, '')), '');
  v_ref   extensions.geography;
  v_limit int;
  v_count int;
  v_dups  jsonb;
  v_trust int;
  v_state public.moderation_state;
  v_id    uuid;
begin
  perform private.assert_lat_lng(create_spot.lat, create_spot.lng);
  if char_length(v_title) not between 1 and 80 then
    raise exception 'invalid_title' using errcode = '22023';
  end if;
  if char_length(v_note) > 500 or char_length(v_photo) > 1024 then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  perform private.ensure_profile(v_uid);
  -- Aynı kullanıcının eşzamanlı istekleri sırayla: günlük limit yarışsız
  perform pg_advisory_xact_lock(hashtextextended('create_spot:' || v_uid::text, 0));

  if private.contains_profanity(v_title) or private.contains_profanity(v_note) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  -- PRD 9.3: günlük limit (İstanbul günü) — yeni 5, doğrulanmış besleyici 30
  v_limit := private.daily_spot_limit(v_uid);
  select count(*) into v_count
  from public.spots s
  where s.created_by = v_uid and s.created_at >= private.istanbul_day_start();
  if v_count >= v_limit then
    return jsonb_build_object('status', 'limit_reached', 'limit', v_limit);
  end if;

  v_ref := private.make_point(create_spot.lat, create_spot.lng);

  -- FR-N3: 15 m içinde nokta varsa önce kullanıcıya sor
  if not coalesce(p_force, false) then
    select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
    select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title,
                                        'distance_m', round(d.distance_m::numeric, 1))
                     order by d.distance_m)
      into v_dups
    from private.duplicate_candidates(v_ref, 15, v_uid, v_mod) d;
    if v_dups is not null then
      return jsonb_build_object('status', 'duplicate', 'duplicates', v_dups);
    end if;
  end if;

  -- PRD 9.3: trust_score < 5 → moderasyon kuyruğu
  select p.trust_score into v_trust from public.profiles p where p.id = v_uid;
  v_state := case when coalesce(v_trust, 0) < 5 then 'pending' else 'approved' end;

  insert into public.spots (location, type, species, title, note, photo_url, visibility,
                            moderation_state, created_by, status)
  values (v_ref, coalesce(p_type, 'food'), coalesce(p_species, 'cat'), v_title, v_note, v_photo,
          coalesce(p_visibility, 'public'), v_state, v_uid, 'unknown')
  returning id into v_id;

  return jsonb_build_object('status', 'created', 'spot_id', v_id, 'moderation_state', v_state);
end
$$;

-- ---------------------------------------------------------------------------
-- check_in (FR-C1..C5)
-- ---------------------------------------------------------------------------
create function public.check_in(
  p_spot_id   uuid,
  p_kind      public.checkin_kind,
  p_amount    public.food_amount,
  p_photo_url text,
  user_lat    float8,
  user_lng    float8,
  p_client_id uuid default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid       uuid := private.require_uid();
  v_priv      boolean;
  v_mod       boolean;
  v_spot      public.spots;
  v_user_pt   extensions.geography;
  v_dist      int;
  v_shown     int;
  v_max       int;
  v_photo     text := nullif(btrim(coalesce(p_photo_url, '')), '');
  v_id        uuid;
  v_closed    int := 0;
  v_notified  uuid[] := '{}';
  v_label     text;
  v_status    public.spot_status;
  v_prev      public.checkins;
begin
  if p_kind is null then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if char_length(v_photo) > 1024 then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;
  perform private.assert_lat_lng(check_in.user_lat, check_in.user_lng);
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;

  -- Satır kilidi: aynı noktadaki eşzamanlı check-in'ler (talep kapatma, hız limiti) sırayla işlenir
  select * into v_spot from public.spots s where s.id = p_spot_id for update;
  if not found or not private.spot_visible(v_spot, v_uid, v_mod) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'spot';
  end if;

  -- PRD 9.5: kullanıcının konumu saklanmaz; yalnızca noktaya uzaklığı (m) tutulur.
  v_user_pt := private.make_point(check_in.user_lat, check_in.user_lng);
  v_dist := round(extensions.st_distance(v_spot.location, v_user_pt))::int;
  -- İstemciye dönen mesafe: tam konumu göremeyen izleyici için GÖSTERİLEN (bulanık) noktaya mesafe,
  -- aksi halde farklı konumlardan denenerek gerçek konum üçgenlenebilirdi (PRD 9.1).
  v_shown := case when private.spot_exact(v_spot, v_uid, v_priv) then v_dist
                  else round(extensions.st_distance(private.fuzz_point(v_spot.id, v_spot.location), v_user_pt))::int
             end;

  -- FR-H8: çevrimdışı kuyruktan tekrar gönderim → mevcut kaydı yan etkisiz döndür.
  -- Hız limiti ve pasiflik kontrollerinden ÖNCE çalışır (ilk gönderim zaten kabul edilmişti).
  -- Nokta satırı kilitli olduğundan aynı client_id ile eşzamanlı iki istek sıralanır.
  if p_client_id is not null then
    select * into v_prev from public.checkins c where c.client_id = p_client_id;
    if found then
      if v_prev.user_id is distinct from v_uid or v_prev.spot_id <> p_spot_id or v_prev.kind <> p_kind then
        raise exception 'invalid_parameter' using errcode = '22023', hint = 'client_id';
      end if;
      return jsonb_build_object(
        'status', 'ok',
        'checkin_id', v_prev.id,
        'distance_m', case when private.spot_exact(v_spot, v_uid, v_priv) then v_prev.user_distance_m else v_shown end,
        'closed_need_count', 0,
        'spot_status', public.compute_spot_status(v_spot.last_fed_at, private.spot_has_open_request(v_spot.id))
      );
    end if;
  end if;

  if not v_spot.is_active then
    return jsonb_build_object('status', 'spot_inactive');
  end if;

  -- FR-C2: fed/water 100 m; FR-C3: need_food/need_water/broken 300 m
  v_max := case when p_kind in ('fed', 'water') then 100 else 300 end;
  if v_dist > v_max then
    return jsonb_build_object('status', 'too_far', 'distance_m', v_shown, 'max_distance_m', v_max);
  end if;

  -- Aynı kullanıcı + nokta + tür için 10 dk içinde ikinci kayıt yok
  if exists (select 1 from public.checkins c
             where c.spot_id = p_spot_id and c.user_id = v_uid and c.kind = p_kind
               and c.created_at > now() - interval '10 minutes') then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  perform private.ensure_profile(v_uid);
  insert into public.checkins (spot_id, user_id, kind, amount, photo_url, user_distance_m, client_id)
  values (p_spot_id, v_uid, p_kind, p_amount, v_photo, v_dist, p_client_id)
  returning id into v_id;

  v_label := private.checkin_kind_label(p_kind);

  if p_kind in ('fed', 'water') then
    -- last_fed_at yalnızca `fed` ile güncellenir
    if p_kind = 'fed' then
      update public.spots set last_fed_at = now() where id = p_spot_id;
    end if;

    -- FR-C5: fed VEYA water açık need_food / need_water / broken taleplerinin hepsini kapatır;
    -- talebi açan herkese (kendisi ve engelli ilişkiler hariç) thanks_fed
    with closed as (
      update public.checkins c
         set resolved_at = now(), resolved_by = v_id
       where c.spot_id = p_spot_id
         and c.resolved_at is null
         and c.kind = any (private.request_kinds())
         and c.id <> v_id
      returning c.user_id
    ),
    thanked as (
      insert into public.notifications (user_id, kind, title, body, spot_id)
      select distinct cl.user_id, 'thanks_fed'::public.notification_kind, 'Teşekkürler!',
             format('"%s" için bildirdiğin talep karşılandı: %s.', v_spot.title, v_label), p_spot_id
      from closed cl
      where cl.user_id is not null
        and cl.user_id <> v_uid
        and not private.blocked_between(cl.user_id, v_uid)
      returning user_id
    )
    select (select count(*)::int from closed),
           coalesce((select array_agg(t.user_id) from thanked t), '{}')
      into v_closed, v_notified;

  elsif v_spot.moderation_state = 'approved' then
    -- FR-C4: need_food / need_water / broken → yarıçapı içinde notify_center'ı olan, tercihi açık
    -- kullanıcılara need_food_nearby (oluşturan ve iki yönlü engellenenler hariç).
    -- Aynı nokta için 6 saat içinde ikinci kez haber verilmez (spam önleme).
    with sent as (
      insert into public.notifications (user_id, kind, title, body, spot_id)
      select np.user_id, 'need_food_nearby'::public.notification_kind, 'Yakınında yardım gerekiyor',
             format('%s: "%s"', v_label, v_spot.title), p_spot_id
      from public.notification_prefs np
      where np.need_food_nearby
        and np.notify_center is not null
        and extensions.st_dwithin(np.notify_center, v_spot.location, 20000)   -- indeks ön-filtresi (radius_m ≤ 20 km)
        and extensions.st_dwithin(np.notify_center, v_spot.location, np.radius_m)
        and np.user_id <> v_uid
        and not private.blocked_between(np.user_id, v_uid)
        and not exists (select 1 from public.notifications n
                        where n.user_id = np.user_id and n.kind = 'need_food_nearby'
                          and n.spot_id = p_spot_id and n.created_at > now() - interval '6 hours')
      returning user_id
    )
    select coalesce(array_agg(sent.user_id), '{}') into v_notified from sent;
  end if;

  -- Takipçilere followed_spot_changed (bu check-in için zaten bildirim alanlar, tercihi kapalı olanlar,
  -- engelli ilişkiler hariç; son 1 saatte okunmamış aynı bildirim varsa birleştirilir)
  if v_spot.moderation_state = 'approved' then
    insert into public.notifications (user_id, kind, title, body, spot_id)
    select fo.user_id, 'followed_spot_changed', 'Takip ettiğin noktada yenilik',
           format('"%s": %s', v_spot.title, v_label), p_spot_id
    from public.follows fo
    left join public.notification_prefs np on np.user_id = fo.user_id
    where fo.target_type = 'spot'
      and fo.target_id = p_spot_id
      and fo.user_id <> v_uid
      and fo.user_id <> all (v_notified)
      and coalesce(np.followed_updates, true)
      and not private.blocked_between(fo.user_id, v_uid)
      and not exists (select 1 from public.notifications n
                      where n.user_id = fo.user_id and n.kind = 'followed_spot_changed'
                        and n.spot_id = p_spot_id and n.read_at is null
                        and n.created_at > now() - interval '1 hour');
  end if;

  -- PRD 9.3: konumu doğrulanmış check-in +1, fotoğraflı +1 ek; FR-P4 rozet kontrolü
  perform private.add_trust(v_uid, 1 + case when v_photo is not null then 1 else 0 end);
  perform private.maybe_promote_feeder(v_uid);

  -- Durum okuma anında hesaplanır; kalıcı sütun da tazelenir
  select public.compute_spot_status(s.last_fed_at, private.spot_has_open_request(s.id))
    into v_status
  from public.spots s where s.id = p_spot_id;
  update public.spots set status = v_status where id = p_spot_id and status is distinct from v_status;

  return jsonb_build_object(
    'status', 'ok',
    'checkin_id', v_id,
    'distance_m', v_shown,
    'closed_need_count', v_closed,
    'spot_status', v_status
  );
end
$$;

-- ---------------------------------------------------------------------------
-- report_spot_gone (FR-N6) — kullanıcı başına 1 kez; 3 farklı kullanıcı → is_active=false
-- ---------------------------------------------------------------------------
create function public.report_spot_gone(p_spot_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := private.require_uid();
  v_mod   boolean;
  v_spot  public.spots;
  v_count int;
  v_deact boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select * into v_spot from public.spots s where s.id = p_spot_id for update;
  if not found or not private.spot_visible(v_spot, v_uid, v_mod) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'spot';
  end if;

  perform private.ensure_profile(v_uid);
  insert into public.spot_gone_reports (spot_id, user_id) values (p_spot_id, v_uid)
  on conflict (spot_id, user_id) do nothing;

  select count(*)::int into v_count from public.spot_gone_reports r where r.spot_id = p_spot_id;

  v_deact := not v_spot.is_active;
  if v_count >= 3 and v_spot.is_active then
    update public.spots set is_active = false where id = p_spot_id;
    v_deact := true;
  end if;

  return jsonb_build_object('status', 'ok', 'count', v_count, 'deactivated', v_deact);
end
$$;

-- ---------------------------------------------------------------------------
-- create_need (FR-I1) — dönüş uuid; küfür → exception 'rejected_content' (dönüş tipi jsonb değil)
-- ---------------------------------------------------------------------------
create function public.create_need(
  p_spot_id     uuid,
  p_animal_id   uuid,
  p_type        public.need_type,
  p_urgency     public.need_urgency,
  p_description text,
  p_photos      text[]
)
returns uuid
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := private.require_uid();
  v_mod  boolean;
  v_desc text := nullif(btrim(coalesce(p_description, '')), '');
  v_id   uuid;
begin
  if p_spot_id is null and p_animal_id is null then
    raise exception 'p_spot_id or p_animal_id is required' using errcode = '22023';
  end if;
  if p_type is null then
    raise exception 'invalid_type' using errcode = '22023';
  end if;
  if char_length(v_desc) > 1000 or coalesce(cardinality(p_photos), 0) > 10 then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if p_spot_id is not null and not exists (
       select 1 from public.spots s where s.id = p_spot_id and private.spot_visible(s, v_uid, v_mod)) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'spot';
  end if;
  if p_animal_id is not null and not exists (select 1 from public.animals a where a.id = p_animal_id) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'animal';
  end if;

  if private.contains_profanity(v_desc) then
    raise exception 'rejected_content' using errcode = 'P0001', hint = 'profanity';
  end if;

  perform private.ensure_profile(v_uid);
  insert into public.needs (spot_id, animal_id, type, urgency, description, photos, status, created_by)
  values (p_spot_id, p_animal_id, p_type, coalesce(p_urgency, 'normal'), v_desc,
          coalesce(array(select x from unnest(p_photos) x where nullif(btrim(x), '') is not null), '{}'),
          'open', v_uid)
  returning id into v_id;

  return v_id;
end
$$;

-- ---------------------------------------------------------------------------
-- claim_need (FR-I3) — "ben ilgileniyorum"
-- ---------------------------------------------------------------------------
create function public.claim_need(p_need_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := private.require_uid();
  v_mod  boolean;
  v_need public.needs;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select * into v_need from public.needs n where n.id = p_need_id for update;
  if not found or not private.need_visible(v_need, v_uid, v_mod) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'need';
  end if;

  if v_need.status = 'resolved' then
    return jsonb_build_object('status', 'resolved');
  end if;
  if v_need.claimed_by is not null and v_need.claimed_by <> v_uid then
    return jsonb_build_object('status', 'already_claimed');
  end if;

  perform private.ensure_profile(v_uid);
  update public.needs
     set claimed_by = v_uid,
         claimed_at = coalesce(case when claimed_by = v_uid then claimed_at end, now()),
         status     = 'claimed'
   where id = p_need_id;

  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- resolve_need — oluşturan, üstlenen veya doğrulanmış besleyici (ve moderatör)
-- ---------------------------------------------------------------------------
create function public.resolve_need(p_need_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := private.require_uid();
  v_priv boolean;
  v_mod  boolean;
  v_need public.needs;
  v_what text;
begin
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;
  select * into v_need from public.needs n where n.id = p_need_id for update;
  if not found or not private.need_visible(v_need, v_uid, v_mod) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'need';
  end if;

  if not (v_need.created_by = v_uid or v_need.claimed_by = v_uid or v_priv) then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  if v_need.status = 'resolved' then
    return jsonb_build_object('status', 'ok');
  end if;

  perform private.ensure_profile(v_uid);
  update public.needs
     set status = 'resolved', resolved_at = now(), resolved_by = v_uid
   where id = p_need_id;

  -- need_resolved: oluşturana ve üstlenene (çözen kendisi değilse, engelli ilişkiler hariç)
  v_what := coalesce((select a.name from public.animals a where a.id = v_need.animal_id),
                     (select s.title from public.spots s where s.id = v_need.spot_id), 'İhtiyaç');
  insert into public.notifications (user_id, kind, title, body, spot_id, need_id)
  select distinct u, 'need_resolved'::public.notification_kind, 'İhtiyaç çözüldü',
         format('"%s" için açılan ihtiyaç çözüldü. Teşekkürler!', v_what), v_need.spot_id, v_need.id
  from unnest(array[v_need.created_by, v_need.claimed_by]) as u
  where u is not null and u <> v_uid and not private.blocked_between(u, v_uid);

  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- mark_animal_seen (FR-A3)
-- ---------------------------------------------------------------------------
create function public.mark_animal_seen(p_animal_id uuid, p_spot_id uuid)
returns void
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if not exists (select 1 from public.animals a where a.id = p_animal_id) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'animal';
  end if;
  if not exists (select 1 from public.spots s
                 where s.id = p_spot_id and s.is_active and private.spot_visible(s, v_uid, v_mod)) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'spot';
  end if;

  insert into public.animal_spots (animal_id, spot_id, seen_count, last_seen_at)
  values (p_animal_id, p_spot_id, 1, now())
  on conflict (animal_id, spot_id)
  do update set seen_count = public.animal_spots.seen_count + 1, last_seen_at = now();

  -- trigger (sync_animal_spot) burada sayacı ikinci kez artırmaz (on conflict do nothing)
  update public.animals
     set last_seen_at = now(), last_seen_spot_id = p_spot_id
   where id = p_animal_id;
end
$$;

-- ---------------------------------------------------------------------------
-- register_device_token — token başka kullanıcıdaysa bu kullanıcıya taşınır
-- ---------------------------------------------------------------------------
create function public.register_device_token(p_token text)
returns void
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := private.require_uid();
  v_token text := btrim(coalesce(p_token, ''));
begin
  if char_length(v_token) not between 8 and 512 or v_token !~ '^[0-9A-Za-z_:.-]+$' then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  perform private.ensure_profile(v_uid);
  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (v_token, v_uid, 'ios', now())
  on conflict (token) do update set user_id = excluded.user_id, updated_at = now();
end
$$;

-- ---------------------------------------------------------------------------
-- update_notify_center — 3 ondalığa yuvarlar (≈110 m), öncekinin üzerine yazar (geçmiş yok, PRD 9.5)
-- ---------------------------------------------------------------------------
create function public.update_notify_center(lat float8, lng float8)
returns void
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_pt  extensions.geography;
begin
  perform private.assert_lat_lng(update_notify_center.lat, update_notify_center.lng);
  v_pt := private.make_point(round(update_notify_center.lat::numeric, 3)::float8,
                             round(update_notify_center.lng::numeric, 3)::float8);
  perform private.ensure_profile(v_uid);
  insert into public.notification_prefs (user_id, notify_center)
  values (v_uid, v_pt)
  on conflict (user_id) do update set notify_center = excluded.notify_center;
end
$$;

-- ---------------------------------------------------------------------------
-- log_donation_click — anon OK (PRD 8.2: yalnızca "sayfaya gidildi" ölçülür)
-- ---------------------------------------------------------------------------
create function public.log_donation_click(p_ref_code text)
returns void
language sql volatile security definer
set search_path = public, extensions
as $$
  insert into public.donation_events (user_id, kind, ref_code)
  values ((select p.id from public.profiles p where p.id = auth.uid()),
          'click',
          left(nullif(btrim(coalesce(p_ref_code, '')), ''), 64));
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler
-- ---------------------------------------------------------------------------
revoke all on function public.create_spot(float8, float8, public.spot_type, public.spot_species, text, text, text, public.spot_visibility, boolean) from public, anon, authenticated;
revoke all on function public.check_in(uuid, public.checkin_kind, public.food_amount, text, float8, float8, uuid) from public, anon, authenticated;
revoke all on function public.report_spot_gone(uuid)                     from public, anon, authenticated;
revoke all on function public.create_need(uuid, uuid, public.need_type, public.need_urgency, text, text[]) from public, anon, authenticated;
revoke all on function public.claim_need(uuid)                           from public, anon, authenticated;
revoke all on function public.resolve_need(uuid)                         from public, anon, authenticated;
revoke all on function public.mark_animal_seen(uuid, uuid)               from public, anon, authenticated;
revoke all on function public.register_device_token(text)                from public, anon, authenticated;
revoke all on function public.update_notify_center(float8, float8)       from public, anon, authenticated;
revoke all on function public.log_donation_click(text)                   from public, anon, authenticated;

grant execute on function public.create_spot(float8, float8, public.spot_type, public.spot_species, text, text, text, public.spot_visibility, boolean) to authenticated;
grant execute on function public.check_in(uuid, public.checkin_kind, public.food_amount, text, float8, float8, uuid) to authenticated;
grant execute on function public.report_spot_gone(uuid)                  to authenticated;
grant execute on function public.create_need(uuid, uuid, public.need_type, public.need_urgency, text, text[]) to authenticated;
grant execute on function public.claim_need(uuid)                        to authenticated;
grant execute on function public.resolve_need(uuid)                      to authenticated;
grant execute on function public.mark_animal_seen(uuid, uuid)            to authenticated;
grant execute on function public.register_device_token(text)             to authenticated;
grant execute on function public.update_notify_center(float8, float8)    to authenticated;
grant execute on function public.log_donation_click(text)                to anon, authenticated;
