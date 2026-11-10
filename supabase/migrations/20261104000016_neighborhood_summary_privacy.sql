-- Mama Haritası — 0016: neighborhood_summary konum kâhini olmasın (PRD 9.1)
--
-- 0007'deki sürüm noktaları yarıçapa GERÇEK konumlarıyla alıyordu. RPC anon ve authenticated'a açık ve
-- dört sayı da (fed_spots_today, open_needs, needs_food_spots, active_spots_7d) tam olarak gerçek konum
-- yarıçap sınırını geçtiğinde değişiyordu: merkez kaydırılıp sayının değiştiği noktalar bulunarak, bulanık
-- gösterilen bir noktanın gerçek konumu üçgenlenebiliyordu. 300 m alt sınırı yalnızca çok küçük yarıçapı
-- engeller, sınır yoklamasını değil.
--
-- Düzeltme (spots_near / needs_near / community_summary ile aynı kalıp): yarıçap testi noktanın izleyiciye
-- GÖSTERİLEN konumuna uygulanır — private.spot_exact + private.display_point, yani haritadakiyle aynı kural:
--   anon                                                  → her nokta bulanık (private zaten hiç sayılmaz)
--   giriş yapmış                                          → public tam, fuzzed/private bulanık
--   oluşturan / koruyucu / doğrulanmış besleyici / moderatör → tam
-- Gerçek konum yalnızca indeks ön-filtresinde, bulanıklık payıyla (ofset < 100 m → +110 m) kullanılır.
-- Böylece özet, aynı izleyicinin aynı yarıçapta haritada gördüğü noktalarla da tutarlıdır.
--
-- İmza, dönüş şekli, security definer ve search_path 0007 ile aynı: `create or replace` yeter.

create or replace function public.neighborhood_summary(lat float8, lng float8, radius_m int default 1500)
returns table (fed_spots_today int, open_needs int, needs_food_spots int, active_spots_7d int)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_priv   boolean;
  v_ref    extensions.geography;
  v_radius int := greatest(300, least(coalesce(neighborhood_summary.radius_m, 1500), 5000));
  v_start  timestamptz := private.istanbul_day_start();
begin
  perform private.assert_lat_lng(neighborhood_summary.lat, neighborhood_summary.lng);
  v_ref := private.make_point(neighborhood_summary.lat, neighborhood_summary.lng);
  select f.is_privileged into v_priv from private.viewer_flags(v_uid) f;

  return query
  with area as (
    select s.id, s.last_fed_at
    from public.spots s
    where extensions.st_dwithin(s.location, v_ref, v_radius + 110)   -- yalnızca indeks ön-filtresi
      and s.is_active
      and s.moderation_state = 'approved'
      and (s.visibility <> 'private' or v_uid is not null)
      and extensions.st_dwithin(private.display_point(s, private.spot_exact(s, v_uid, v_priv)), v_ref, v_radius)
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

-- `create or replace` mevcut yetkileri korur; son durum yine de açıkça yazılır (0007 + 0011 ile aynı:
-- sözleşmede "anon OK").
revoke all on function public.neighborhood_summary(float8, float8, int) from public;
grant execute on function public.neighborhood_summary(float8, float8, int) to anon, authenticated;
