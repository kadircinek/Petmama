-- Engelleme: Mahalle dışındaki içerik de gizlenir (PRD 9.2, App Store 1.2).
--
--   ihtiyaçlar  : engellenen (veya izleyiciyi engellemiş) kullanıcının ihtiyaçları görünmez (iki yönlü)
--   hayvanlar   : animals_at_spot iki yönlü; tabloya doğrudan okuma (RLS) izleyicinin engellediklerini gizler
--   noktalar    : haritada KALIR (fiziksel mama noktası, başkaları da besliyor); oluşturanın notu/fotoğrafı gizlenir
--   koruyucular : engellenen koruyucu listede görünmez
-- Moderatörler (is_moderator) her şeyi görmeye devam eder. Anonim izleyicide engel yoktur.

-- ---------------------------------------------------------------------------
-- need_visible: + engel kontrolü (need_detail, needs_near, needs_for ve yazma RPC'leri bunu kullanır)
-- ---------------------------------------------------------------------------
create or replace function private.need_visible(p_need public.needs, p_uid uuid, p_is_mod boolean)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select (p_need.spot_id is null
          or exists (select 1 from public.spots s
                     where s.id = p_need.spot_id and private.spot_visible(s, p_uid, p_is_mod)))
     and (coalesce(p_is_mod, false) or p_uid is null or p_need.created_by is null
          or not private.blocked_between(p_uid, p_need.created_by))
$$;

-- ---------------------------------------------------------------------------
-- to_spot_row: engellenen oluşturanın notu/fotoğrafı null; açık ihtiyaç sayısı gizlenenleri saymaz
-- ---------------------------------------------------------------------------
create or replace function private.to_spot_row(
  p_spot          public.spots,
  p_uid           uuid,
  p_is_privileged boolean,
  p_ref           extensions.geography
)
returns public.spot_row
language sql stable
set search_path = public, extensions
as $$
  select
    p_spot.id,
    extensions.st_y(d.pt::extensions.geometry),
    extensions.st_x(d.pt::extensions.geometry),
    d.exact,
    p_spot.type,
    p_spot.species,
    p_spot.title,
    case when b.hidden then null else p_spot.note end,
    case when b.hidden then null else p_spot.photo_url end,
    public.compute_spot_status(p_spot.last_fed_at, private.spot_has_open_request(p_spot.id)),
    p_spot.last_fed_at,
    nn.has_urgent,
    nn.open_count,
    p_spot.visibility,
    p_spot.is_active,
    p_spot.created_by,
    p_spot.created_at,
    (select count(*)::int from public.animal_spots a where a.spot_id = p_spot.id),
    (select count(*)::int from public.guardians g where g.spot_id = p_spot.id),
    case when p_ref is null then null else extensions.st_distance(d.pt, p_ref) end
  from (
    select e.exact, private.display_point(p_spot, e.exact) as pt
    from (select private.spot_exact(p_spot, p_uid, p_is_privileged) as exact) e
  ) d
  cross join lateral (
    select coalesce(p_uid is not null and p_spot.created_by is not null
                    and private.blocked_between(p_uid, p_spot.created_by), false) as hidden
  ) b
  cross join lateral (
    -- noktaya veya noktadaki bir hayvana bağlı, çözülmemiş ve izleyiciden gizlenmemiş ihtiyaçlar
    select count(*)::int as open_count,
           coalesce(bool_or(n.urgency = 'urgent'), false) as has_urgent
    from public.needs n
    where n.status <> 'resolved'
      and (n.spot_id = p_spot.id
           or n.animal_id in (select a.animal_id from public.animal_spots a where a.spot_id = p_spot.id))
      and (p_uid is null or n.created_by is null or not private.blocked_between(p_uid, n.created_by))
  ) nn
$$;

-- ---------------------------------------------------------------------------
-- animals_at_spot: engellenenin hayvanları gizli
-- ---------------------------------------------------------------------------
create or replace function public.animals_at_spot(p_spot_id uuid)
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
    and (coalesce(v_mod, false) or v_uid is null or a.created_by is null
         or not private.blocked_between(v_uid, a.created_by))
  order by ap.seen_count desc, ap.last_seen_at desc, a.id;
end
$$;

-- ---------------------------------------------------------------------------
-- spot_guardians: engellenen koruyucu listede yok
-- ---------------------------------------------------------------------------
create or replace function public.spot_guardians(p_spot_id uuid)
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
    and (coalesce(v_mod, false) or v_uid is null or not private.blocked_between(v_uid, g.user_id))
  order by g.created_at, g.user_id;
end
$$;

-- ---------------------------------------------------------------------------
-- animals tablosu (hayvan detayı doğrudan okunur): izleyicinin engellediği kullanıcının hayvanları gizli.
-- RLS'den private şemaya erişilemez; blocks'un kendi RLS'i yalnızca izleyicinin satırlarını gösterir (tek yön).
-- ---------------------------------------------------------------------------
drop policy animals_select on public.animals;
-- anon'un blocks tablosuna yetkisi yok (planlamada bile hata verir): iki ayrı politika.
create policy animals_select_anon on public.animals
  for select to anon using (true);
create policy animals_select on public.animals
  for select to authenticated
  using (
    created_by is null
    or not exists (select 1 from public.blocks b
                   where b.user_id = (select auth.uid()) and b.blocked_user_id = animals.created_by)
  );
