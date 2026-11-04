-- Test yardımcıları (run.sh migration + seed'den sonra yükler). `tests` şeması üretimde YOKTUR.
--
--   tests.check(cond, name)          → başarısızsa 'FAIL: name' exception, değilse 'PASS: name' notice
--   tests.eq(got, want, name)        → eşitlik + değerleri mesajda gösterir
--   tests.make_user(name, trust, verified, moderator) → auth.users'a ekler (trigger profil açar), id döner
--   tests.login(uid) / tests.anon() / tests.admin()  → rol + JWT claim'leri (set local)
--   tests.project(lat, lng, meters, azimuth_deg)     → o mesafe/yöndeki nokta (lat, lng)
--   tests.make_spot(lat, lng, title, visibility, created_by, last_fed_at) → doğrudan ekler (admin)

drop schema if exists tests cascade;
create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

create function tests.check(p_cond boolean, p_name text)
returns void
language plpgsql
as $$
begin
  if p_cond is distinct from true then
    raise exception 'FAIL: %', p_name;
  end if;
  raise notice 'PASS: %', p_name;
end
$$;

create function tests.eq(p_got anyelement, p_want anyelement, p_name text)
returns void
language plpgsql
as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAIL: % (got %, want %)', p_name, p_got, p_want;
  end if;
  raise notice 'PASS: %', p_name;
end
$$;

create function tests.make_user(
  p_name      text,
  p_trust     int default 10,
  p_verified  boolean default false,
  p_moderator boolean default false
)
returns uuid
language plpgsql
set search_path = public, extensions
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, v_id::text || '@test.local', jsonb_build_object('display_name', p_name));
  update public.profiles
     set trust_score = p_trust, is_verified_feeder = p_verified, is_moderator = p_moderator
   where id = v_id;
  return v_id;
end
$$;

create function tests.login(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end
$$;

create function tests.anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end
$$;

create function tests.admin()
returns void
language plpgsql
as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end
$$;

create function tests.project(p_lat float8, p_lng float8, p_meters float8, p_azimuth_deg float8 default 90,
                              out lat float8, out lng float8)
language sql immutable
set search_path = public, extensions
as $$
  select extensions.st_y(g::extensions.geometry), extensions.st_x(g::extensions.geometry)
  from (select extensions.st_project(
                 extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
                 p_meters, radians(p_azimuth_deg)) as g) t
$$;

create function tests.dist(p_lat1 float8, p_lng1 float8, p_lat2 float8, p_lng2 float8)
returns float8
language sql immutable
set search_path = public, extensions
as $$
  select extensions.st_distance(
    extensions.st_setsrid(extensions.st_makepoint(p_lng1, p_lat1), 4326)::extensions.geography,
    extensions.st_setsrid(extensions.st_makepoint(p_lng2, p_lat2), 4326)::extensions.geography)
$$;

create function tests.make_spot(
  p_lat         float8,
  p_lng         float8,
  p_title       text default 'Test noktası',
  p_visibility  public.spot_visibility default 'public',
  p_created_by  uuid default null,
  p_last_fed_at timestamptz default null
)
returns uuid
language sql
set search_path = public, extensions
as $$
  insert into public.spots (location, title, visibility, created_by, last_fed_at)
  values (extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
          p_title, p_visibility, p_created_by, p_last_fed_at)
  returning id
$$;

-- Test noktaları seed'den uzakta (Kadıköy'ün güneyi, deniz üstü olsa da sorun değil)
create function tests.base_lat() returns float8 language sql immutable as $$ select 40.9500::float8 $$;
create function tests.base_lng() returns float8 language sql immutable as $$ select 29.0500::float8 $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
