-- Mama Haritası — 0021: Buluşma RPC'leri (spec §5.1, §6)
--
-- Mahalle RPC'leriyle aynı kurallar: `security definer`, ilk iş `private.require_uid()`, anon'a kapalı,
-- iş kuralı sonuçları jsonb `status` (+ `reason`). Bildirimler bu dosyada YOK (0022+).
--
-- * Doğrulama, tablo CHECK'lerine düşmeden önce `{status:'invalid', reason}` olarak döner.
-- * Okuma RPC'leri (meetups_near, meetup_detail) sosyal onay istemez; yazma RPC'leri ister.
-- * Düzenleyen ya da herhangi bir katılımcıyla (iki yönlü) engel varsa buluşma izleyiciye görünmez
--   (yalnızca düzenleyenle engel kontrol edilir; katılımcı listesi ayrıca süzülür).

create type public.meetup_row as (
  id                    uuid,
  title                 text,
  description           text,
  starts_at             timestamptz,
  ends_at               timestamptz,
  place_name            text,
  lat                   float8,
  lng                   float8,
  spot_id               uuid,     -- nokta izleyene görünür değilse spot_id ve spot_title null
  spot_title            text,
  capacity              int,
  participant_count     int,      -- düzenleyen dahil, `joined` olanlar
  status                public.meetup_status,
  organizer_id          uuid,
  organizer_name        text,
  organizer_avatar_url  text,
  organizer_is_verified boolean,
  viewer_role           text,     -- organizer | participant | removed | none
  conversation_id       uuid,     -- yalnızca organizer/participant için dolu
  distance_m            float8,   -- izleyicinin verdiği konumdan; konum verilmediyse null
  created_at            timestamptz
);

-- `meetups` satırı → izleyiciye göre `meetup_row`
create function private.to_meetup_row(
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
    p_m.created_at
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
-- Okuma
-- ---------------------------------------------------------------------------
-- Yakındaki aktif, bitmemiş buluşmalar; yakından uzağa, sonra başlangıca göre. Onay gerekmez.
create function public.meetups_near(lat float8, lng float8, radius_m int default 10000)
returns setof public.meetup_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
  v_ref extensions.geography;
begin
  perform private.assert_lat_lng(lat, lng);
  if radius_m is null or radius_m < 1 or radius_m > 50000 then
    raise exception 'invalid_radius' using errcode = '22023';
  end if;
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  v_ref := private.make_point(lat, lng);

  return query
  select r.*
  from public.meetups m
  cross join lateral private.to_meetup_row(m, v_uid, v_mod, v_ref) r
  where m.status = 'active'
    and m.ends_at > now()
    and extensions.st_dwithin(m.location, v_ref, radius_m)
    and not private.blocked_between(v_uid, m.organizer_id)
  order by r.distance_m, m.starts_at, m.id
  limit 100;
end
$$;

-- Tek buluşma (iptal edilmiş olsa da döner); düzenleyenle engel varsa 0 satır
create function public.meetup_detail(p_meetup_id uuid, lat float8 default null, lng float8 default null)
returns setof public.meetup_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
  v_ref extensions.geography;
begin
  if (lat is null) <> (lng is null) then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;
  if lat is not null then
    perform private.assert_lat_lng(lat, lng);
    v_ref := private.make_point(lat, lng);
  end if;
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.meetups m
  cross join lateral private.to_meetup_row(m, v_uid, v_mod, v_ref) r
  where m.id = p_meetup_id
    and not private.blocked_between(v_uid, m.organizer_id);
end
$$;

-- Katılımcılar: yalnızca düzenleyen ve katılımcılar görür; izleyiciyle engelli olanlar süzülür
create function public.meetup_participants(p_meetup_id uuid)
returns table (user_id uuid, display_name text, avatar_url text, is_verified_feeder boolean, is_organizer boolean)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
begin
  if not exists (select 1 from public.meetup_participants mp
                 where mp.meetup_id = p_meetup_id and mp.user_id = v_uid and mp.status = 'joined') then
    return;
  end if;

  return query
  select mp.user_id, pr.display_name, pr.avatar_url, pr.is_verified_feeder,
         (mp.user_id = m.organizer_id)
  from public.meetup_participants mp
  join public.meetups m on m.id = mp.meetup_id
  join public.profiles pr on pr.id = mp.user_id
  where mp.meetup_id = p_meetup_id
    and mp.status = 'joined'
    and (mp.user_id = v_uid or not private.blocked_between(v_uid, mp.user_id))
  order by (mp.user_id = m.organizer_id) desc, mp.joined_at, mp.user_id
  limit 100;
end
$$;

-- ---------------------------------------------------------------------------
-- Yazma
-- ---------------------------------------------------------------------------
create function public.create_meetup(
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
       where m.organizer_id = v_uid and m.created_at >= private.istanbul_day_start()) >= c_daily_limit then
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

-- Katıl. Satır kilidi (`for update`) kapasite denetimini eşzamanlı katılımlara karşı korur.
create function public.join_meetup(p_meetup_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := private.require_uid();
  v_m      public.meetups;
  v_pstat  public.participant_status;
  v_conv   uuid;
begin
  perform private.ensure_profile(v_uid);
  if not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;

  select * into v_m from public.meetups where id = p_meetup_id for update;
  if not found or private.blocked_between(v_uid, v_m.organizer_id) then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_m.status = 'cancelled' then
    return jsonb_build_object('status', 'cancelled');
  end if;
  if v_m.ends_at <= now() then
    return jsonb_build_object('status', 'ended');
  end if;

  select c.id into v_conv from public.conversations c where c.meetup_id = v_m.id;
  select mp.status into v_pstat from public.meetup_participants mp
   where mp.meetup_id = v_m.id and mp.user_id = v_uid;
  if v_pstat = 'removed' then
    return jsonb_build_object('status', 'removed');
  end if;
  if v_pstat = 'joined' then   -- idempotent
    return jsonb_build_object('status', 'joined', 'conversation_id', v_conv);
  end if;

  if v_m.capacity is not null
     and (select count(*) from public.meetup_participants mp
           where mp.meetup_id = v_m.id and mp.status = 'joined') >= v_m.capacity then
    return jsonb_build_object('status', 'full');
  end if;

  insert into public.meetup_participants (meetup_id, user_id) values (v_m.id, v_uid);
  insert into public.conversation_members (conversation_id, user_id) values (v_conv, v_uid)
    on conflict do nothing;
  return jsonb_build_object('status', 'joined', 'conversation_id', v_conv);
end
$$;

-- Ayrıl. Düzenleyen ayrılamaz (iptal eder). Çıkarılmış kullanıcının `removed` kaydı korunur.
create function public.leave_meetup(p_meetup_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_m   public.meetups;
begin
  select * into v_m from public.meetups where id = p_meetup_id for update;
  if not found then
    return jsonb_build_object('status', 'ok');
  end if;
  if v_m.organizer_id = v_uid then
    return jsonb_build_object('status', 'organizer_cannot_leave');
  end if;

  delete from public.meetup_participants mp
   where mp.meetup_id = v_m.id and mp.user_id = v_uid and mp.status = 'joined';
  delete from public.conversation_members cm
   using public.conversations c
   where c.meetup_id = v_m.id and cm.conversation_id = c.id and cm.user_id = v_uid;
  return jsonb_build_object('status', 'ok');
end
$$;

-- Katılımcıyı çıkar (yalnızca düzenleyen); çıkarılan tekrar katılamaz
create function public.remove_meetup_participant(p_meetup_id uuid, p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_m   public.meetups;
begin
  select * into v_m from public.meetups where id = p_meetup_id for update;
  if not found or v_m.organizer_id <> v_uid or p_user_id is null or p_user_id = v_uid then
    return jsonb_build_object('status', 'not_allowed');
  end if;

  update public.meetup_participants mp set status = 'removed'
   where mp.meetup_id = v_m.id and mp.user_id = p_user_id and mp.status = 'joined';
  if not found then
    return jsonb_build_object('status', 'not_allowed');
  end if;

  delete from public.conversation_members cm
   using public.conversations c
   where c.meetup_id = v_m.id and cm.conversation_id = c.id and cm.user_id = p_user_id;
  return jsonb_build_object('status', 'ok');
end
$$;

-- İptal (yalnızca düzenleyen, bitmemiş buluşma); idempotent. Sohbet kapanır (salt okunur).
create function public.cancel_meetup(p_meetup_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_m   public.meetups;
begin
  select * into v_m from public.meetups where id = p_meetup_id for update;
  if not found or v_m.organizer_id <> v_uid then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  if v_m.status = 'cancelled' then
    return jsonb_build_object('status', 'ok');
  end if;
  if v_m.ends_at <= now() then
    return jsonb_build_object('status', 'not_allowed');
  end if;

  update public.meetups set status = 'cancelled' where id = v_m.id;
  update public.conversations set closed_at = now() where meetup_id = v_m.id;
  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.meetups_near(float8, float8, int)            from public, anon, authenticated;
revoke all on function public.meetup_detail(uuid, float8, float8)          from public, anon, authenticated;
revoke all on function public.meetup_participants(uuid)                    from public, anon, authenticated;
revoke all on function public.create_meetup(text, text, timestamptz, int, text, float8, float8, uuid, int) from public, anon, authenticated;
revoke all on function public.join_meetup(uuid)                            from public, anon, authenticated;
revoke all on function public.leave_meetup(uuid)                           from public, anon, authenticated;
revoke all on function public.remove_meetup_participant(uuid, uuid)        from public, anon, authenticated;
revoke all on function public.cancel_meetup(uuid)                          from public, anon, authenticated;

grant execute on function public.meetups_near(float8, float8, int)            to authenticated;
grant execute on function public.meetup_detail(uuid, float8, float8)          to authenticated;
grant execute on function public.meetup_participants(uuid)                    to authenticated;
grant execute on function public.create_meetup(text, text, timestamptz, int, text, float8, float8, uuid, int) to authenticated;
grant execute on function public.join_meetup(uuid)                            to authenticated;
grant execute on function public.leave_meetup(uuid)                           to authenticated;
grant execute on function public.remove_meetup_participant(uuid, uuid)        to authenticated;
grant execute on function public.cancel_meetup(uuid)                          to authenticated;
