-- Mama Haritası — 0007: okuma RPC'leri
--
-- Hepsi `security definer` + `set search_path = public, extensions`. Konum içeren her satır
-- private.to_spot_row / private.to_need_row üzerinden geçer: bulanıklaştırma ve görünürlük
-- (PRD 9.1) tek yerde uygulanır. Kutu/yarıçap filtreleri GÖSTERİLEN noktaya uygulanır; gerçek
-- konum yalnızca indeks ön-filtresinde (bulanıklık payıyla genişletilmiş) kullanılır.

-- ---------------------------------------------------------------------------
-- spots_in_bounds — anon OK; pasif ve rejected gizli, pending yalnızca oluşturana
-- ---------------------------------------------------------------------------
create function public.spots_in_bounds(
  min_lat float8, min_lng float8, max_lat float8, max_lng float8, max_rows int default 500
)
returns setof public.spot_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
  -- bulanık noktalar gerçek konumdan ≤100 m uzakta: ön-filtre kutusunu ~0.0015° (≈125–165 m) genişlet
  v_pad  constant float8 := 0.0015;
begin
  perform private.assert_lat_lng(spots_in_bounds.min_lat, spots_in_bounds.min_lng);
  perform private.assert_lat_lng(spots_in_bounds.max_lat, spots_in_bounds.max_lng);
  if spots_in_bounds.min_lat > spots_in_bounds.max_lat or spots_in_bounds.min_lng > spots_in_bounds.max_lng then
    raise exception 'invalid_bounds' using errcode = '22023';
  end if;
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.spots s
  cross join lateral private.to_spot_row(s, v_uid, v_priv, null) r
  where s.location && extensions.st_makeenvelope(
          spots_in_bounds.min_lng - v_pad, spots_in_bounds.min_lat - v_pad,
          spots_in_bounds.max_lng + v_pad, spots_in_bounds.max_lat + v_pad, 4326)::extensions.geography
    and s.is_active
    and private.spot_visible(s, v_uid, v_mod)
    and r.lat between spots_in_bounds.min_lat and spots_in_bounds.max_lat
    and r.lng between spots_in_bounds.min_lng and spots_in_bounds.max_lng
  order by (r.status = 'needs_food') desc, r.has_urgent_need desc, r.last_fed_at desc nulls last, r.id
  limit greatest(1, least(coalesce(spots_in_bounds.max_rows, 500), 1000));
end
$$;

-- ---------------------------------------------------------------------------
-- spots_near — anon OK; distance_m dolu, artan
-- ---------------------------------------------------------------------------
create function public.spots_near(lat float8, lng float8, radius_m int default 1000, max_rows int default 200)
returns setof public.spot_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_priv   boolean;
  v_mod    boolean;
  v_ref    extensions.geography;
  v_radius int := greatest(1, least(coalesce(spots_near.radius_m, 1000), 50000));
begin
  perform private.assert_lat_lng(spots_near.lat, spots_near.lng);
  v_ref := private.make_point(spots_near.lat, spots_near.lng);
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.spots s
  cross join lateral private.to_spot_row(s, v_uid, v_priv, v_ref) r
  where extensions.st_dwithin(s.location, v_ref, v_radius + 110)
    and s.is_active
    and private.spot_visible(s, v_uid, v_mod)
    and r.distance_m <= v_radius
  order by r.distance_m, r.id
  limit greatest(1, least(coalesce(spots_near.max_rows, 200), 1000));
end
$$;

-- ---------------------------------------------------------------------------
-- spot_detail — 0/1 satır (pasif noktalar da döner: is_active=false)
-- ---------------------------------------------------------------------------
create function public.spot_detail(p_spot_id uuid)
returns setof public.spot_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
begin
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;
  return query
  select r.*
  from public.spots s
  cross join lateral private.to_spot_row(s, v_uid, v_priv, null) r
  where s.id = p_spot_id
    and private.spot_visible(s, v_uid, v_mod);
end
$$;

-- ---------------------------------------------------------------------------
-- spot_feeding_timeline — gün Europe/Istanbul'a göre, boş günler de döner (artan)
-- ---------------------------------------------------------------------------
create function public.spot_feeding_timeline(p_spot_id uuid, days int default 7)
returns table (day date, fed_count int, need_count int, last_fed_at timestamptz)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid   uuid := auth.uid();
  v_mod   boolean;
  v_days  int := greatest(1, least(coalesce(spot_feeding_timeline.days, 7), 90));
  v_today date := private.istanbul_today();
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if not exists (select 1 from public.spots s where s.id = p_spot_id and private.spot_visible(s, v_uid, v_mod)) then
    return;
  end if;

  return query
  select d.day,
         (count(c.id) filter (where c.kind = 'fed'))::int,
         (count(c.id) filter (where c.kind = any (private.request_kinds())))::int,
         max(c.created_at) filter (where c.kind = 'fed')
  from (select v_today - i as day from generate_series(0, v_days - 1) as g(i)) d
  left join public.checkins c
    on c.spot_id = p_spot_id
   and c.created_at >= d.day::timestamp at time zone 'Europe/Istanbul'
   and c.created_at <  (d.day + 1)::timestamp at time zone 'Europe/Istanbul'
  group by d.day
  order by d.day;
end
$$;

-- ---------------------------------------------------------------------------
-- spot_guardians
-- ---------------------------------------------------------------------------
create function public.spot_guardians(p_spot_id uuid)
returns table (user_id uuid, display_name text, avatar_url text, is_verified_feeder boolean, schedule smallint[])
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_mod boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if not exists (select 1 from public.spots s where s.id = p_spot_id and private.spot_visible(s, v_uid, v_mod)) then
    return;
  end if;

  return query
  select g.user_id, p.display_name, p.avatar_url, p.is_verified_feeder, g.schedule
  from public.guardians g
  join public.profiles p on p.id = g.user_id
  where g.spot_id = p_spot_id
  order by g.created_at, g.user_id;
end
$$;

-- ---------------------------------------------------------------------------
-- Mükerrer nokta adayları (FR-N3). Gerçek konuma göre çalışmak zorunda; yarıçap 30 m ile sınırlı
-- (geniş yarıçap bulanık/özel noktaların gerçek konumunu mesafelerden çıkarmaya izin verirdi).
-- ---------------------------------------------------------------------------
create function private.duplicate_candidates(p_ref extensions.geography, p_radius_m int, p_uid uuid, p_is_mod boolean)
returns table (id uuid, title text, distance_m float8)
language sql stable
set search_path = public, extensions
as $$
  select s.id, s.title, extensions.st_distance(s.location, p_ref)
  from public.spots s
  where extensions.st_dwithin(s.location, p_ref, greatest(1, least(coalesce(p_radius_m, 15), 30)))
    and s.is_active
    and private.spot_visible(s, p_uid, p_is_mod)
  order by 3, 1
  limit 20
$$;

create function public.find_duplicate_spots(lat float8, lng float8, radius_m int default 15)
returns table (id uuid, title text, distance_m float8)
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
begin
  perform private.assert_lat_lng(find_duplicate_spots.lat, find_duplicate_spots.lng);
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  return query
  select d.id, d.title, d.distance_m
  from private.duplicate_candidates(private.make_point(find_duplicate_spots.lat, find_duplicate_spots.lng),
                                    find_duplicate_spots.radius_m, v_uid, v_mod) d;
end
$$;

-- ---------------------------------------------------------------------------
-- needs_near — anon OK. Sıra: urgent önce, sonra (gösterilen konuma) mesafe (FR-I5)
-- ---------------------------------------------------------------------------
create function public.needs_near(lat float8, lng float8, radius_m int default 5000, include_resolved boolean default false)
returns setof public.need_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_priv   boolean;
  v_mod    boolean;
  v_ref    extensions.geography;
  v_radius int := greatest(1, least(coalesce(needs_near.radius_m, 5000), 50000));
begin
  perform private.assert_lat_lng(needs_near.lat, needs_near.lng);
  v_ref := private.make_point(needs_near.lat, needs_near.lng);
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.needs n
  left join public.animals a on a.id = n.animal_id
  join public.spots ls on ls.id = coalesce(n.spot_id, a.last_seen_spot_id)
  cross join lateral private.to_need_row(n, v_uid, v_priv, v_mod, v_ref) r
  where extensions.st_dwithin(ls.location, v_ref, v_radius + 110)
    and (coalesce(needs_near.include_resolved, false) or n.status <> 'resolved')
    and private.need_visible(n, v_uid, v_mod)
    and r.distance_m is not null
    and r.distance_m <= v_radius
  order by (r.urgency = 'urgent') desc, r.distance_m, r.created_at desc, r.id
  limit 300;
end
$$;

-- ---------------------------------------------------------------------------
-- need_detail
-- ---------------------------------------------------------------------------
create function public.need_detail(p_need_id uuid)
returns setof public.need_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
begin
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;
  return query
  select r.*
  from public.needs n
  cross join lateral private.to_need_row(n, v_uid, v_priv, v_mod, null) r
  where n.id = p_need_id
    and private.need_visible(n, v_uid, v_mod);
end
$$;

-- ---------------------------------------------------------------------------
-- needs_for — anon OK; noktaya VEYA hayvana bağlı ihtiyaçlar (distance_m null)
-- ---------------------------------------------------------------------------
create function public.needs_for(p_spot_id uuid default null, p_animal_id uuid default null, include_resolved boolean default false)
returns setof public.need_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
begin
  if p_spot_id is null and p_animal_id is null then
    raise exception 'p_spot_id or p_animal_id is required' using errcode = '22023';
  end if;
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.needs n
  cross join lateral private.to_need_row(n, v_uid, v_priv, v_mod, null) r
  where (n.spot_id = p_spot_id or n.animal_id = p_animal_id)
    and (coalesce(needs_for.include_resolved, false) or n.status <> 'resolved')
    and private.need_visible(n, v_uid, v_mod)
  order by (r.status = 'resolved'), (r.urgency = 'urgent') desc, r.created_at desc, r.id
  limit 200;
end
$$;

-- ---------------------------------------------------------------------------
-- search_spots — anon OK; başlık/not ilike, Türkçe büyük/küçük harf duyarsız (tr_fold),
-- konum verilirse (gösterilen konuma) yakından uzağa, yoksa son beslenme zamanına göre.
-- ---------------------------------------------------------------------------
create function public.search_spots(q text, lat float8 default null, lng float8 default null, max_rows int default 30)
returns setof public.spot_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
  v_q    text := btrim(coalesce(search_spots.q, ''));
  v_pat  text;
  v_ref  extensions.geography;
begin
  if char_length(v_q) < 2 then
    return;
  end if;
  if char_length(v_q) > 80 then
    v_q := left(v_q, 80);
  end if;
  v_pat := '%' || private.like_escape(private.tr_fold(v_q)) || '%';
  if search_spots.lat is not null and search_spots.lng is not null then
    perform private.assert_lat_lng(search_spots.lat, search_spots.lng);
    v_ref := private.make_point(search_spots.lat, search_spots.lng);
  end if;
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.spots s
  cross join lateral private.to_spot_row(s, v_uid, v_priv, v_ref) r
  where s.is_active
    and private.spot_visible(s, v_uid, v_mod)
    and (private.tr_fold(s.title) like v_pat or private.tr_fold(coalesce(s.note, '')) like v_pat)
  order by r.distance_m asc nulls last, r.last_fed_at desc nulls last, r.id
  limit greatest(1, least(coalesce(search_spots.max_rows, 30), 100));
end
$$;

-- ---------------------------------------------------------------------------
-- animals_at_spot — seen_count azalan
-- ---------------------------------------------------------------------------
create function public.animals_at_spot(p_spot_id uuid)
returns setof public.animal_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_mod boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if not exists (select 1 from public.spots s where s.id = p_spot_id and private.spot_visible(s, v_uid, v_mod)) then
    return;
  end if;

  return query
  select a.id, a.species, a.name, a.color_pattern, a.sex, a.age_estimate, a.is_neutered, a.ear_tag,
         a.vaccination_info, a.temperament_tags, a.warning, a.about, a.photos, a.last_seen_at,
         a.last_seen_spot_id, a.created_by, a.created_at,
         ap.seen_count, ap.last_seen_at
  from public.animal_spots ap
  join public.animals a on a.id = ap.animal_id
  where ap.spot_id = p_spot_id
  order by ap.seen_count desc, ap.last_seen_at desc, a.id;
end
$$;

-- ---------------------------------------------------------------------------
-- animal_spots_of — hayvanın görüldüğü (görünür, aktif) noktalar, en son görülen önce
-- ---------------------------------------------------------------------------
create function public.animal_spots_of(p_animal_id uuid)
returns setof public.spot_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
begin
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;
  return query
  select r.*
  from public.animal_spots ap
  join public.spots s on s.id = ap.spot_id
  cross join lateral private.to_spot_row(s, v_uid, v_priv, null) r
  where ap.animal_id = p_animal_id
    and s.is_active
    and private.spot_visible(s, v_uid, v_mod)
  order by ap.last_seen_at desc, r.id;
end
$$;

-- ---------------------------------------------------------------------------
-- profile_stats
--   resolved_need_count: kullanıcının üstlenip çözülen ya da (üstlenen yokken) kendisinin kapattığı ihtiyaçlar
-- ---------------------------------------------------------------------------
create function public.profile_stats(p_user_id uuid)
returns table (fed_spot_count int, checkin_count int, resolved_need_count int, verified_checkins_30d int)
language sql stable security definer
set search_path = public, extensions
as $$
  select
    (select count(distinct c.spot_id)::int from public.checkins c where c.user_id = p_user_id and c.kind = 'fed'),
    (select count(*)::int from public.checkins c where c.user_id = p_user_id),
    (select count(*)::int from public.needs n
      where n.status = 'resolved' and coalesce(n.claimed_by, n.resolved_by) = p_user_id),
    private.verified_checkins_30d(p_user_id)
$$;

-- ---------------------------------------------------------------------------
-- neighborhood_summary — yarıçap 300–5000 m ile sınırlı (çok küçük yarıçap sayımları konum kâhinine çevirirdi)
-- ---------------------------------------------------------------------------
create function public.neighborhood_summary(lat float8, lng float8, radius_m int default 1500)
returns table (fed_spots_today int, open_needs int, needs_food_spots int, active_spots_7d int)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_ref    extensions.geography;
  v_radius int := greatest(300, least(coalesce(neighborhood_summary.radius_m, 1500), 5000));
  v_start  timestamptz := private.istanbul_day_start();
begin
  perform private.assert_lat_lng(neighborhood_summary.lat, neighborhood_summary.lng);
  v_ref := private.make_point(neighborhood_summary.lat, neighborhood_summary.lng);

  return query
  with area as (
    select s.id, s.last_fed_at
    from public.spots s
    where extensions.st_dwithin(s.location, v_ref, v_radius)
      and s.is_active
      and s.moderation_state = 'approved'
      and (s.visibility <> 'private' or v_uid is not null)
  )
  select
    (select count(*)::int from area where area.last_fed_at >= v_start),
    (select count(*)::int
       from public.needs n
       left join public.animals a on a.id = n.animal_id
       join area on area.id = coalesce(n.spot_id, a.last_seen_spot_id)
      where n.status <> 'resolved'),
    (select count(*)::int from area where private.spot_has_open_request(area.id)),
    (select count(*)::int from area
      where exists (select 1 from public.checkins c
                    where c.spot_id = area.id and c.created_at > now() - interval '7 days'));
end
$$;

-- ---------------------------------------------------------------------------
-- followed_spots — auth
-- ---------------------------------------------------------------------------
create function public.followed_spots()
returns setof public.spot_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := private.require_uid();
  v_priv boolean;
  v_mod  boolean;
begin
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;
  return query
  select r.*
  from public.follows fo
  join public.spots s on s.id = fo.target_id
  cross join lateral private.to_spot_row(s, v_uid, v_priv, null) r
  where fo.user_id = v_uid
    and fo.target_type = 'spot'
    and private.spot_visible(s, v_uid, v_mod)
  order by fo.created_at desc, r.id;
end
$$;

-- ---------------------------------------------------------------------------
-- donation_overview — anon OK, içinde bulunulan (İstanbul) ay; veri yoksa 0'larla tek satır
-- ---------------------------------------------------------------------------
create function public.donation_overview()
returns table (month date, kg_distributed numeric, donor_count int)
language sql stable security definer
set search_path = public, extensions
as $$
  select m.m, coalesce(ds.kg_distributed, 0), coalesce(ds.donor_count, 0)
  from (select date_trunc('month', private.istanbul_today())::date as m) m
  left join public.donation_stats ds on ds.month = m.m
$$;

-- ---------------------------------------------------------------------------
-- can_guard_spot (sözleşmeye ek) — koruyucu olabilir mi? Koruyucu tam konumu görür (PRD 9.1),
-- bu yüzden: nokta görünür olmalı VE (public nokta | oluşturan | doğrulanmış besleyici/moderatör |
-- son 90 günde noktada konumu doğrulanmış check-in'i var). guardians insert politikası bunu kullanır.
-- ---------------------------------------------------------------------------
create function public.can_guard_spot(p_spot_id uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_priv boolean;
  v_mod  boolean;
  v_spot public.spots;
begin
  if v_uid is null then
    return false;
  end if;
  select f.is_privileged, f.is_moderator into v_priv, v_mod from private.viewer_flags(v_uid) f;
  select * into v_spot from public.spots where id = p_spot_id;
  if not found or not private.spot_visible(v_spot, v_uid, v_mod) then
    return false;
  end if;
  return v_spot.visibility = 'public'
      or v_spot.created_by = v_uid
      or v_priv
      or exists (select 1 from public.checkins c
                 where c.spot_id = p_spot_id and c.user_id = v_uid
                   and c.user_distance_m is not null
                   and c.created_at > now() - interval '90 days');
end
$$;

create policy guardians_insert_own on public.guardians
  for insert to authenticated
  with check (user_id = (select auth.uid()) and public.can_guard_spot(spot_id));

-- ---------------------------------------------------------------------------
-- Yetkiler: anon yalnızca sözleşmede "anon OK" olanlar
-- ---------------------------------------------------------------------------
revoke all on function public.spots_in_bounds(float8, float8, float8, float8, int)  from public, anon, authenticated;
revoke all on function public.spots_near(float8, float8, int, int)                  from public, anon, authenticated;
revoke all on function public.spot_detail(uuid)                                      from public, anon, authenticated;
revoke all on function public.spot_feeding_timeline(uuid, int)                       from public, anon, authenticated;
revoke all on function public.spot_guardians(uuid)                                   from public, anon, authenticated;
revoke all on function public.find_duplicate_spots(float8, float8, int)              from public, anon, authenticated;
revoke all on function public.needs_near(float8, float8, int, boolean)               from public, anon, authenticated;
revoke all on function public.need_detail(uuid)                                      from public, anon, authenticated;
revoke all on function public.needs_for(uuid, uuid, boolean)                         from public, anon, authenticated;
revoke all on function public.search_spots(text, float8, float8, int)                from public, anon, authenticated;
revoke all on function public.animals_at_spot(uuid)                                  from public, anon, authenticated;
revoke all on function public.animal_spots_of(uuid)                                  from public, anon, authenticated;
revoke all on function public.profile_stats(uuid)                                    from public, anon, authenticated;
revoke all on function public.neighborhood_summary(float8, float8, int)              from public, anon, authenticated;
revoke all on function public.followed_spots()                                       from public, anon, authenticated;
revoke all on function public.donation_overview()                                    from public, anon, authenticated;
revoke all on function public.can_guard_spot(uuid)                                   from public, anon, authenticated;
revoke all on function private.duplicate_candidates(extensions.geography, int, uuid, boolean) from public;

grant execute on function public.spots_in_bounds(float8, float8, float8, float8, int) to anon, authenticated;
grant execute on function public.spots_near(float8, float8, int, int)                 to anon, authenticated;
grant execute on function public.needs_near(float8, float8, int, boolean)              to anon, authenticated;
grant execute on function public.needs_for(uuid, uuid, boolean)                        to anon, authenticated;
grant execute on function public.search_spots(text, float8, float8, int)               to anon, authenticated;
grant execute on function public.donation_overview()                                   to anon, authenticated;

grant execute on function public.spot_detail(uuid)                                     to authenticated;
grant execute on function public.spot_feeding_timeline(uuid, int)                      to authenticated;
grant execute on function public.spot_guardians(uuid)                                  to authenticated;
grant execute on function public.find_duplicate_spots(float8, float8, int)             to authenticated;
grant execute on function public.need_detail(uuid)                                     to authenticated;
grant execute on function public.animals_at_spot(uuid)                                 to authenticated;
grant execute on function public.animal_spots_of(uuid)                                 to authenticated;
grant execute on function public.profile_stats(uuid)                                   to authenticated;
grant execute on function public.neighborhood_summary(float8, float8, int)             to authenticated;
grant execute on function public.followed_spots()                                      to authenticated;
grant execute on function public.can_guard_spot(uuid)                                  to authenticated;
