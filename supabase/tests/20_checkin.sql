-- check_in: mesafe, hız limiti, pasif nokta, talep kapatma, güven puanı (FR-C1..C5, PRD 9.3/9.5)
begin;

-- Mesafe sınırları: fed/water 100 m (FR-C2), need_*/broken 300 m (FR-C3)
do $$
declare
  u  uuid := tests.make_user('Mesafe');
  s  uuid := tests.make_spot(tests.base_lat(), tests.base_lng(), 'mesafe noktası', 'public');
  p  record;
  r  jsonb;
begin
  perform tests.login(u);

  p := tests.project(tests.base_lat(), tests.base_lng(), 101, 45);
  r := check_in(s, 'fed', 'full', null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'too_far', 'fed at 101 m → too_far');
  perform tests.eq((r->>'max_distance_m')::int, 100, 'too_far reports max_distance_m 100');
  perform tests.eq((r->>'distance_m')::int, 101, 'too_far reports distance_m 101 (public spot, exact viewer)');

  p := tests.project(tests.base_lat(), tests.base_lng(), 99, 45);
  r := check_in(s, 'water', null, null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'ok', 'water at 99 m → ok');

  p := tests.project(tests.base_lat(), tests.base_lng(), 299, 200);
  r := check_in(s, 'need_food', null, null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'ok', 'need_food at 299 m → ok');
  perform tests.eq(r->>'spot_status', 'needs_food', 'need_food → spot_status needs_food');

  p := tests.project(tests.base_lat(), tests.base_lng(), 301, 200);
  r := check_in(s, 'broken', null, null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'too_far', 'broken at 301 m → too_far');
  perform tests.eq((r->>'max_distance_m')::int, 300, 'request kinds max_distance_m 300');

  p := tests.project(tests.base_lat(), tests.base_lng(), 250, 10);
  r := check_in(s, 'broken', null, null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'ok', 'broken at 250 m → ok');

  -- aynı kullanıcı + nokta + tür 10 dk içinde
  r := check_in(s, 'need_food', null, null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'rate_limited', 'second need_food within 10 min → rate_limited');

  perform tests.admin();
  -- PRD 9.5: kullanıcı konumu saklanmaz, yalnızca uzaklık
  perform tests.check(not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'checkins'
        and (column_name in ('lat', 'lng', 'location', 'user_lat', 'user_lng', 'user_location')
             or udt_name in ('geography', 'geometry'))),
    'checkins has no user location column');
  perform tests.eq((select array_agg(user_distance_m order by user_distance_m) from checkins where spot_id = s),
                   array[99, 250, 299], 'only distances stored (99, 250, 299 m)');

  -- pasif nokta
  update spots set is_active = false where id = s;
  perform tests.login(u);
  r := check_in(s, 'fed', 'full', null, tests.base_lat(), tests.base_lng());
  perform tests.eq(r->>'status', 'spot_inactive', 'inactive spot → spot_inactive');
  perform tests.admin();
end
$$;

-- fed: last_fed_at, açık talepleri (need_food + need_water + broken) kapatır, thanks_fed (FR-C5)
do $$
declare
  feeder uuid := tests.make_user('Besleyici');
  asker1 uuid := tests.make_user('Talep 1');
  asker2 uuid := tests.make_user('Talep 2');
  s      uuid := tests.make_spot(tests.base_lat() + 0.01, tests.base_lng() + 0.01, 'kapatma noktası', 'public',
                                 null, now() - interval '30 hours');
  r      jsonb;
  t0     int;
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at) values
    (s, asker1, 'need_food',  20, now() - interval '2 hours'),
    (s, asker1, 'broken',     20, now() - interval '2 hours'),
    (s, asker2, 'need_water', 20, now() - interval '1 hour'),
    (s, feeder, 'need_food',  20, now() - interval '3 hours');   -- kendi talebine teşekkür yok
  t0 := (select trust_score from profiles where id = feeder);

  perform tests.login(feeder);
  r := check_in(s, 'fed', 'medium', 'https://example.test/storage/v1/object/public/photos/x/y.jpg',
                tests.base_lat() + 0.01, tests.base_lng() + 0.01);
  perform tests.eq(r->>'status', 'ok', 'fed → ok');
  perform tests.eq((r->>'closed_need_count')::int, 4, 'fed closes all open need_food/need_water/broken');
  perform tests.eq(r->>'spot_status', 'fed_recent', 'fed → spot_status fed_recent');
  perform tests.check((r->>'checkin_id') is not null, 'checkin_id returned');
  perform tests.admin();

  perform tests.eq((select last_fed_at from spots where id = s), now(), 'fed sets spots.last_fed_at = now()');
  perform tests.eq((select count(*)::int from checkins where spot_id = s and resolved_at is not null
                     and resolved_by = (r->>'checkin_id')::uuid), 4, 'resolved_by = new checkin id');
  perform tests.eq((select count(*)::int from notifications where user_id = asker1 and kind = 'thanks_fed' and spot_id = s), 1,
                   'thanks_fed once per opener (asker1 had 2 requests)');
  perform tests.eq((select count(*)::int from notifications where user_id = asker2 and kind = 'thanks_fed'), 1, 'thanks_fed to asker2');
  perform tests.eq((select count(*)::int from notifications where user_id = feeder and kind = 'thanks_fed'), 0, 'no thanks_fed to self');
  perform tests.eq((select trust_score from profiles where id = feeder), t0 + 2, 'trust +1 verified, +1 photo');
end
$$;

-- water da talepleri kapatır ama last_fed_at'i değiştirmez; güven puanı fotoğrafsız +1
do $$
declare
  u  uuid := tests.make_user('Sucu');
  a  uuid := tests.make_user('Susuz');
  s  uuid := tests.make_spot(tests.base_lat() + 0.02, tests.base_lng(), 'su noktası', 'public', null, null);
  r  jsonb;
  t0 int;
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m) values (s, a, 'need_water', 5);
  t0 := (select trust_score from profiles where id = u);
  perform tests.login(u);
  r := check_in(s, 'water', null, null, tests.base_lat() + 0.02, tests.base_lng());
  perform tests.eq((r->>'closed_need_count')::int, 1, 'water closes open request');
  perform tests.eq(r->>'spot_status', 'unknown', 'water does not set last_fed_at (never fed → unknown)');
  perform tests.admin();
  perform tests.check((select last_fed_at from spots where id = s) is null, 'water leaves last_fed_at null');
  perform tests.eq((select trust_score from profiles where id = u), t0 + 1, 'trust +1 without photo');
end
$$;

-- Bulanık noktada too_far mesafesi gösterilen (bulanık) noktaya göre döner (üçgenleme yok, PRD 9.1)
do $$
declare
  owner uuid := tests.make_user('Sahip');
  u     uuid := tests.make_user('Yabancı');
  s     uuid := tests.make_spot(tests.base_lat() + 0.03, tests.base_lng(), 'bulanık nokta', 'fuzzed', owner);
  p     record;
  r     jsonb;
  shown spot_row;
begin
  p := tests.project(tests.base_lat() + 0.03, tests.base_lng(), 500, 0);
  perform tests.login(u);
  select * into shown from spot_detail(s);
  r := check_in(s, 'fed', null, null, p.lat, p.lng);
  perform tests.eq(r->>'status', 'too_far', 'fuzzed spot: too_far still uses real distance');
  perform tests.eq((r->>'distance_m')::int, round(tests.dist(shown.lat, shown.lng, p.lat, p.lng))::int,
                   'fuzzed spot: reported distance is to the displayed point');
  perform tests.check((r->>'distance_m')::int <> 500, 'fuzzed spot: real distance not leaked');
  perform tests.admin();
end
$$;

-- Doğrulanmış besleyici (FR-P4): 30 günde 20 konumu doğrulanmış check-in
do $$
declare
  u uuid := tests.make_user('Yolda');
  s uuid := tests.make_spot(tests.base_lat() + 0.04, tests.base_lng(), 'rozet noktası', 'public');
  r jsonb;
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at)
  select s, u, 'fed', 10, now() - make_interval(hours => g) from generate_series(1, 19) g;
  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at)
  select s, u, 'fed', 10, now() - interval '40 days' from generate_series(1, 5);   -- 30 günden eski
  perform tests.check(not (select is_verified_feeder from profiles where id = u), 'not verified at 19 recent');
  perform tests.login(u);
  r := check_in(s, 'water', null, null, tests.base_lat() + 0.04, tests.base_lng());
  perform tests.eq(r->>'status', 'ok', '20th verified check-in ok');
  perform tests.admin();
  perform tests.check((select is_verified_feeder from profiles where id = u), 'check_in promotes to verified feeder at 20 in 30d');
end
$$;

-- FR-H8: p_client_id ile idempotent tekrar gönderim (rate_limited'dan önce, yan etkisiz)
do $$
declare
  u      uuid := tests.make_user('Çevrimdışı');
  asker  uuid := tests.make_user('Talep eden');
  other  uuid := tests.make_user('Başka cihaz');
  s      uuid := tests.make_spot(tests.base_lat() + 0.06, tests.base_lng(), 'kuyruk noktası', 'public', null, null);
  cid    uuid := gen_random_uuid();
  p      record;
  r1     jsonb;
  r2     jsonb;
  t0     int;
  n0     int;
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m) values (s, asker, 'need_food', 10);
  p := tests.project(tests.base_lat() + 0.06, tests.base_lng(), 42, 90);

  perform tests.login(u);
  r1 := check_in(s, 'fed', 'full', 'https://example.test/p.jpg', p.lat, p.lng, cid);
  perform tests.eq(r1->>'status', 'ok', 'client_id: first send ok');
  perform tests.eq((r1->>'closed_need_count')::int, 1, 'client_id: first send closes request');
  perform tests.admin();
  t0 := (select trust_score from profiles where id = u);
  n0 := (select count(*)::int from notifications);

  perform tests.login(u);
  r2 := check_in(s, 'fed', 'full', 'https://example.test/p.jpg', p.lat, p.lng, cid);
  perform tests.eq(r2->>'status', 'ok', 'client_id replay → ok (not rate_limited)');
  perform tests.eq(r2->>'checkin_id', r1->>'checkin_id', 'client_id replay returns existing checkin_id');
  perform tests.eq((r2->>'distance_m')::int, 42, 'client_id replay returns stored distance');
  perform tests.eq((r2->>'closed_need_count')::int, 0, 'client_id replay closed_need_count 0');
  perform tests.eq(r2->>'spot_status', 'fed_recent', 'client_id replay returns current spot_status');
  -- yeni client_id ile aynı tür 10 dk içinde → rate_limited (idempotency kontrolü önce çalıştı)
  perform tests.eq(check_in(s, 'fed', 'full', null, p.lat, p.lng, gen_random_uuid())->>'status', 'rate_limited',
                   'new client_id within 10 min → rate_limited');
  perform tests.admin();
  perform tests.eq((select count(*)::int from checkins where spot_id = s and user_id = u), 1, 'client_id replay: no new row');
  perform tests.eq((select trust_score from profiles where id = u), t0, 'client_id replay: trust unchanged');
  perform tests.eq((select count(*)::int from notifications), n0, 'client_id replay: no new notifications');
  perform tests.eq((select client_id from checkins where id = (r1->>'checkin_id')::uuid), cid, 'client_id stored');

  perform tests.login(other);
  begin
    perform check_in(s, 'fed', 'full', null, p.lat, p.lng, cid);
    raise exception 'FAIL: another user reused client_id';
  exception when invalid_parameter_value then
    perform tests.check(true, 'client_id of another user → exception');
  end;
  perform tests.admin();
end
$$;

-- Yetki/doğrulama ihlalleri exception
do $$
declare
  u uuid := tests.make_user('Hatalı');
  s uuid := tests.make_spot(tests.base_lat() + 0.05, tests.base_lng(), 'hata noktası', 'public');
begin
  perform tests.anon();
  begin
    perform check_in(s, 'fed', null, null, tests.base_lat() + 0.05, tests.base_lng());
    raise exception 'FAIL: anon check_in should be denied';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute check_in');
  end;
  perform tests.login(u);
  begin
    perform check_in(s, 'fed', null, null, 123, 29);
    raise exception 'FAIL: invalid coordinates accepted';
  exception when invalid_parameter_value then
    perform tests.check(true, 'invalid coordinates → exception');
  end;
  begin
    perform check_in(gen_random_uuid(), 'fed', null, null, 40, 29);
    raise exception 'FAIL: unknown spot accepted';
  exception when no_data_found then
    perform tests.check(true, 'unknown spot → exception');
  end;
  perform tests.admin();
end
$$;

rollback;
