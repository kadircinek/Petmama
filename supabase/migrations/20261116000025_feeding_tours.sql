-- Mama Haritası — 0025: Anlık mama turu ve Mahalle'de hayvanseverler (spec 2026-11-16-mahalle-hayvanseverler-design)
--
-- * Tur = `is_tour` buluşma: hemen başlar (normal buluşmadaki "en erken 1 saat sonra" kuralı yok), yalnızca aktif,
--   izleyene görünür ve `public` bir mama noktasından; süre 60–120 dk. Aynı anda en fazla bir açık tur, günde en
--   fazla 3 tur (buluşma limitinden ayrı: biri diğerine sayılmaz).
-- * Katıl/ayrıl/iptal ("Turu bitir"), sohbet, engel, rapor ve bildirimler buluşmalarla aynıdır (0021–0024);
--   yalnızca hatırlatma (`send_meetup_reminders`) turlara gönderilmez.
-- * `animal_lovers_near` → `fed_today` (bugün İstanbul gününde 'fed'/'water' check-in ya da tur açtı) ve
--   `on_tour_meetup_id` (kişinin şu an açık turu); sıra: turda → bugün besledi → bant → ortak ilgi → ad.
--   Kişinin anlık konumu, hangi noktada/ne zaman beslediği ya da çevrimiçi bilgisi hiçbir yerde dönmez.

alter table public.meetups
  add column is_tour boolean not null default false;

-- düzenleyenin açık turu ve günlük tur sayımı
create index meetups_tours_idx on public.meetups (organizer_id, created_at desc) where is_tour;

-- ---------------------------------------------------------------------------
-- meetup_row: sona `is_tour` eklenir (kalan sütunlar ve sıra 0021 ile aynı)
-- ---------------------------------------------------------------------------
alter type public.meetup_row add attribute is_tour boolean;

create or replace function private.to_meetup_row(
  p_m      public.meetups,
  p_uid    uuid,
  p_is_mod boolean,
  p_ref    extensions.geography
)
returns public.meetup_row
language sql stable
set search_path = public, extensions
as $$
  select
    p_m.id,
    p_m.title,
    p_m.description,
    p_m.starts_at,
    p_m.ends_at,
    p_m.place_name,
    extensions.st_y(p_m.location::extensions.geometry),
    extensions.st_x(p_m.location::extensions.geometry),
    sp.id,
    sp.title,
    p_m.capacity,
    (select count(*)::int from public.meetup_participants mp
      where mp.meetup_id = p_m.id and mp.status = 'joined'),
    p_m.status,
    p_m.organizer_id,
    au.display_name,
    au.avatar_url,
    coalesce(au.is_verified_feeder, false),
    vr.role,
    case when vr.role in ('organizer', 'participant') then
      (select c.id from public.conversations c where c.meetup_id = p_m.id) end,
    case when p_ref is not null then extensions.st_distance(p_m.location, p_ref) end,
    p_m.created_at,
    p_m.is_tour
  from (select 1) as one
  left join public.profiles au on au.id = p_m.organizer_id
  left join public.spots sp on sp.id = p_m.spot_id and private.spot_visible(sp, p_uid, p_is_mod)
  cross join lateral (
    select case
             when p_m.organizer_id = p_uid then 'organizer'
             else coalesce((select case mp.status when 'joined' then 'participant' else 'removed' end
                              from public.meetup_participants mp
                             where mp.meetup_id = p_m.id and mp.user_id = p_uid), 'none')
           end as role) vr
$$;

-- ---------------------------------------------------------------------------
-- create_meetup: günlük buluşma limiti turları saymaz (gövdenin kalanı 0021 ile aynı)
-- ---------------------------------------------------------------------------
create or replace function public.create_meetup(
  p_title            text,
  p_description      text,
  p_starts_at        timestamptz,
  p_duration_minutes int,
  p_place_name       text,
  lat                float8,
  lng                float8,
  p_spot_id          uuid default null,
  p_capacity         int default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_daily_limit constant int := 3;
  v_uid   uuid := private.require_uid();
  v_title text := private.trim_text(p_title);
  v_desc  text := private.trim_text(p_description);
  v_place text := private.trim_text(p_place_name);
  v_mod   boolean;
  v_id    uuid;
  v_conv  uuid;
begin
  perform private.assert_lat_lng(lat, lng);
  if p_starts_at is null or p_duration_minutes is null then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  perform private.ensure_profile(v_uid);
  if not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;

  if char_length(v_title) not between 3 and 80 then
    return jsonb_build_object('status', 'invalid', 'reason', 'title_length');
  end if;
  if char_length(v_desc) > 600 then
    return jsonb_build_object('status', 'invalid', 'reason', 'description_too_long');
  end if;
  if char_length(v_place) not between 1 and 80 then
    return jsonb_build_object('status', 'invalid', 'reason', 'place_name_length');
  end if;
  if private.contains_profanity(v_title) or private.contains_profanity(v_desc)
     or private.contains_profanity(v_place) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  -- eşzamanlı oluşturmalarda günlük limit aşılmasın
  perform pg_advisory_xact_lock(hashtext('create_meetup:' || v_uid::text));
  if (select count(*) from public.meetups m
       where m.organizer_id = v_uid and not m.is_tour
         and m.created_at >= private.istanbul_day_start()) >= c_daily_limit then
    return jsonb_build_object('status', 'limit_reached', 'limit', c_daily_limit);
  end if;

  if p_starts_at < now() + interval '1 hour' then
    return jsonb_build_object('status', 'invalid', 'reason', 'start_too_soon');
  end if;
  if p_starts_at > now() + interval '60 days' then
    return jsonb_build_object('status', 'invalid', 'reason', 'start_too_late');
  end if;
  if p_duration_minutes not between 30 and 480 then
    return jsonb_build_object('status', 'invalid', 'reason', 'duration_range');
  end if;
  if p_capacity is not null and p_capacity not between 2 and 50 then
    return jsonb_build_object('status', 'invalid', 'reason', 'capacity_range');
  end if;
  if p_spot_id is not null then
    select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
    if not exists (select 1 from public.spots sp
                   where sp.id = p_spot_id and private.spot_visible(sp, v_uid, v_mod)) then
      return jsonb_build_object('status', 'invalid', 'reason', 'spot_not_found');
    end if;
  end if;

  insert into public.meetups (organizer_id, title, description, starts_at, ends_at, place_name,
                              location, spot_id, capacity)
  values (v_uid, v_title, v_desc, p_starts_at, p_starts_at + make_interval(mins => p_duration_minutes),
          v_place, private.make_point(lat, lng), p_spot_id, p_capacity)
  returning id into v_id;

  insert into public.meetup_participants (meetup_id, user_id) values (v_id, v_uid);
  insert into public.conversations (kind, meetup_id) values ('meetup', v_id) returning id into v_conv;
  insert into public.conversation_members (conversation_id, user_id) values (v_conv, v_uid);

  return jsonb_build_object('status', 'created', 'meetup_id', v_id, 'conversation_id', v_conv);
end
$$;

-- ---------------------------------------------------------------------------
-- start_feeding_tour — "Mama turuna çıkıyorum"
-- Sıra: onay → süre → nokta (aktif, public, onaylı, görünür) → (kilit) açık tur → günlük limit.
-- ---------------------------------------------------------------------------
create function public.start_feeding_tour(p_spot_id uuid, p_duration_minutes int default 90)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_daily_limit constant int := 3;
  v_uid  uuid := private.require_uid();
  v_mod  boolean;
  v_spot public.spots;
  v_name text;
  v_id   uuid;
  v_conv uuid;
begin
  perform private.ensure_profile(v_uid);
  if not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;

  if p_duration_minutes is null or p_duration_minutes not between 60 and 120 then
    return jsonb_build_object('status', 'invalid', 'reason', 'duration_range');
  end if;

  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select * into v_spot from public.spots sp
   where sp.id = p_spot_id and sp.is_active and sp.visibility = 'public'
     and sp.moderation_state = 'approved'   -- kendi onay bekleyen noktası da olmaz (spot_visible ona izin verir)
     and private.spot_visible(sp, v_uid, v_mod);
  if not found then
    return jsonb_build_object('status', 'spot_not_found');
  end if;

  -- eşzamanlı başlatmalarda tek açık tur ve günlük limit korunur
  perform pg_advisory_xact_lock(hashtext('start_feeding_tour:' || v_uid::text));
  if exists (select 1 from public.meetups m
             where m.organizer_id = v_uid and m.is_tour and m.status = 'active' and m.ends_at > now()) then
    return jsonb_build_object('status', 'already_touring');
  end if;
  if (select count(*) from public.meetups m
       where m.organizer_id = v_uid and m.is_tour
         and m.created_at >= private.istanbul_day_start()) >= c_daily_limit then
    return jsonb_build_object('status', 'limit_reached', 'limit', c_daily_limit);
  end if;

  v_name := left(btrim(v_spot.title), 80);
  insert into public.meetups (organizer_id, title, description, starts_at, ends_at, place_name,
                              location, spot_id, capacity, is_tour)
  values (v_uid, left('Mama turu: ' || v_name, 80), '', now(), now() + make_interval(mins => p_duration_minutes),
          v_name, v_spot.location, v_spot.id, null, true)
  returning id into v_id;

  insert into public.meetup_participants (meetup_id, user_id) values (v_id, v_uid);
  insert into public.conversations (kind, meetup_id) values ('meetup', v_id) returning id into v_conv;
  insert into public.conversation_members (conversation_id, user_id) values (v_conv, v_uid);

  return jsonb_build_object('status', 'started', 'meetup_id', v_id, 'conversation_id', v_conv);
end
$$;

-- ---------------------------------------------------------------------------
-- Hatırlatma turlara gönderilmez (gövdenin kalanı 0024 ile aynı)
-- ---------------------------------------------------------------------------
create or replace function private.send_meetup_reminders()
returns int
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_n int;
begin
  with targets as (
    select m.id as meetup_id, m.title, m.starts_at, m.organizer_id, m.organizer_id as user_id
    from public.meetups m
    where m.status = 'active' and not m.is_tour
      and m.starts_at > now() and m.starts_at <= now() + interval '2 hours'
    union all
    select m.id, m.title, m.starts_at, m.organizer_id, mp.user_id
    from public.meetups m
    join public.meetup_participants mp on mp.meetup_id = m.id and mp.status = 'joined'
    where m.status = 'active' and not m.is_tour
      and m.starts_at > now() and m.starts_at <= now() + interval '2 hours'
      and mp.user_id <> m.organizer_id
  )
  insert into public.notifications (user_id, kind, title, body, meetup_id)
  select t.user_id, 'meetup_reminder', 'Buluşma yaklaşıyor',
         format('"%s" buluşması saat %s''de başlıyor.', t.title,
                to_char(t.starts_at at time zone 'Europe/Istanbul', 'HH24:MI')),
         t.meetup_id
  from targets t
  where not private.blocked_between(t.user_id, t.organizer_id)
    and coalesce((select np.social_updates from public.notification_prefs np where np.user_id = t.user_id), true)
    and not exists (select 1 from public.notifications n
                    where n.kind = 'meetup_reminder' and n.meetup_id = t.meetup_id and n.user_id = t.user_id);
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

-- ---------------------------------------------------------------------------
-- meetup_cancelled: tur bitirilince tura özgü metin (gövdenin kalanı 0024 ile aynı)
-- ---------------------------------------------------------------------------
create or replace function private.notify_meetup_cancelled()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r record;
begin
  for r in
    select mp.user_id from public.meetup_participants mp
    where mp.meetup_id = new.id and mp.status = 'joined' and mp.user_id <> new.organizer_id
  loop
    if new.is_tour then
      perform private.notify_social(
        r.user_id, new.organizer_id, 'meetup_cancelled', 'Tur bitti',
        format('"%s" turu sona erdi.', new.title), new.id);
    else
      perform private.notify_social(
        r.user_id, new.organizer_id, 'meetup_cancelled', 'Buluşma iptal edildi',
        format('"%s" buluşması iptal edildi.', new.title), new.id);
    end if;
  end loop;
  return null;
end
$$;

-- ---------------------------------------------------------------------------
-- animal_lovers_near: dönüşe fed_today, on_tour_meetup_id eklenir (kalan sütunlar ve sıra 0022 ile aynı)
-- ---------------------------------------------------------------------------
drop function public.animal_lovers_near(public.social_interest);

create function public.animal_lovers_near(p_interest public.social_interest default null)
returns table (
  user_id               uuid,
  display_name          text,
  avatar_url            text,
  about                 text,
  interests             public.social_interest[],
  is_verified_feeder    boolean,
  fed_30d               int,
  distance_band         public.distance_band,
  shared_interest_count int,
  connection_state      text,     -- none | outgoing_pending | incoming_pending | connected
  request_id            uuid,
  conversation_id       uuid,
  fed_today             boolean,  -- bugün (İstanbul günü) 'fed'/'water' check-in ya da tur açtı
  on_tour_meetup_id     uuid      -- şu an açık turu (izleyene görünür: engel zaten süzülür), yoksa null
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_uid();
  v_cell  extensions.geography;
  v_my    public.social_interest[];
  v_day   timestamptz := private.istanbul_day_start();
begin
  select sp.cell, sp.interests into v_cell, v_my
  from public.social_profiles sp
  where sp.user_id = v_uid and sp.is_visible and sp.cell is not null
    and private.social_consented(v_uid);
  if v_cell is null then
    return;
  end if;

  return query
  select
    t.user_id, t.display_name, t.avatar_url, t.about, t.interests, t.is_verified_feeder, t.fed_30d,
    t.band, t.shared, t.state,
    case when t.state <> 'none' then t.conn_id end,
    case when t.state = 'connected' then
      (select c.id from public.conversations c where c.connection_id = t.conn_id) end,
    t.fed_today,
    t.tour_id
  from (
    select
      sp.user_id,
      pr.display_name,
      pr.avatar_url,
      sp.about,
      sp.interests,
      pr.is_verified_feeder,
      (select count(*)::int from public.checkins ck
        where ck.user_id = sp.user_id and ck.kind = 'fed' and ck.created_at >= now() - interval '30 days') as fed_30d,
      case when d.m < 1000 then 'under_1km'::public.distance_band
           when d.m < 3000 then '1_3km'::public.distance_band
           else '3_10km'::public.distance_band end as band,
      (select count(*)::int from unnest(sp.interests) i where i = any (v_my)) as shared,
      cn.id as conn_id,
      case
        when cn.id is null then 'none'
        when cn.status = 'accepted' then 'connected'
        when cn.status = 'pending' and cn.requester_id = v_uid then 'outgoing_pending'
        when cn.status = 'pending' then 'incoming_pending'
        when cn.status = 'declined' and cn.requester_id = v_uid
             and cn.responded_at > now() - interval '30 days' then 'outgoing_pending'
        else 'none'
      end as state,
      (exists (select 1 from public.checkins ck
                where ck.user_id = sp.user_id and ck.kind in ('fed', 'water') and ck.created_at >= v_day)
       or exists (select 1 from public.meetups m
                   where m.organizer_id = sp.user_id and m.is_tour and m.created_at >= v_day)) as fed_today,
      (select m.id from public.meetups m
        where m.organizer_id = sp.user_id and m.is_tour and m.status = 'active'
          and m.starts_at <= now() and m.ends_at > now()
        order by m.starts_at desc, m.id
        limit 1) as tour_id,
      d.m
    from public.social_profiles sp
    join public.profiles pr on pr.id = sp.user_id
    cross join lateral (select extensions.st_distance(sp.cell, v_cell) as m) d
    left join lateral (
      select c.* from public.connections c
      where least(c.requester_id, c.addressee_id) = least(v_uid, sp.user_id)
        and greatest(c.requester_id, c.addressee_id) = greatest(v_uid, sp.user_id)) cn on true
    where sp.user_id <> v_uid
      and sp.is_visible
      and sp.cell is not null
      and private.social_consented(sp.user_id)
      and d.m <= 10000
      and (p_interest is null or p_interest = any (sp.interests))
      and not private.blocked_between(v_uid, sp.user_id)
  ) t
  order by (t.tour_id is not null) desc, t.fed_today desc, t.band, t.shared desc, t.display_name, t.user_id
  limit 100;
end
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.start_feeding_tour(uuid, int)                 from public, anon, authenticated;
revoke all on function public.animal_lovers_near(public.social_interest)    from public, anon, authenticated;
grant execute on function public.start_feeding_tour(uuid, int)              to authenticated;
grant execute on function public.animal_lovers_near(public.social_interest) to authenticated;
