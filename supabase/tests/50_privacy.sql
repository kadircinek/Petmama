-- Konum hassasiyeti (PRD 9.1): bulanıklaştırma deterministik, 50–100 m; görünürlük matrisi
begin;

do $$
declare
  b_lat    float8 := tests.base_lat() + 0.80;
  b_lng    float8 := tests.base_lng();
  creator  uuid := tests.make_user('Oluşturan');
  viewer   uuid := tests.make_user('İzleyici');
  guardian uuid := tests.make_user('Koruyucu');
  verified uuid := tests.make_user('Rozetli', 30, true);
  s_pub    uuid := tests.make_spot(b_lat,         b_lng,         'public nokta',  'public',  creator);
  s_fuz    uuid := tests.make_spot(b_lat + 0.002, b_lng,         'fuzzed nokta',  'fuzzed',  creator);
  s_prv    uuid := tests.make_spot(b_lat + 0.004, b_lng,         'private nokta', 'private', creator);
  a        spot_row;
  b        spot_row;
  d        float8;
  i        int;
  n_ok     int := 0;
  sid      uuid;
begin
  insert into guardians (user_id, spot_id) values (guardian, s_fuz), (guardian, s_prv);

  -- anon: public bulanık, deterministik, 50–100 m
  perform tests.anon();
  select * into a from spots_near(b_lat, b_lng, 1000) where id = s_pub;
  select * into b from spots_near(b_lat, b_lng, 1000) where id = s_pub;
  perform tests.check(a.id is not null, 'anon sees public spot');
  perform tests.check(not a.is_location_exact, 'anon: public spot is_location_exact = false');
  perform tests.check(a.lat = b.lat and a.lng = b.lng, 'anon: fuzzing deterministic across calls');
  d := tests.dist(a.lat, a.lng, b_lat, b_lng);
  perform tests.check(d between 50 and 100, format('anon: fuzz offset %s m within 50–100', round(d::numeric, 1)));
  perform tests.check(abs(a.distance_m - d) < 0.01, 'anon: distance_m measured to displayed point, not real');
  select * into b from spots_in_bounds(b_lat - 0.01, b_lng - 0.01, b_lat + 0.01, b_lng + 0.01) where id = s_pub;
  perform tests.check(a.lat = b.lat and a.lng = b.lng, 'anon: same fuzzed point in spots_in_bounds');

  -- gerçek konumun etrafındaki küçük kutu bulanık noktayı içermez → gerçek konum sızmaz
  perform tests.eq((select count(*)::int from spots_in_bounds(b_lat - 0.0001, b_lng - 0.0001, b_lat + 0.0001, b_lng + 0.0001)
                     where id = s_pub), 0, 'anon: tiny bbox around real location does not reveal spot');
  perform tests.eq((select count(*)::int from spots_near(b_lat, b_lng, 40) where id = s_pub), 0,
                   'anon: 40 m radius around real location does not reveal spot');

  -- anon: private gizli, fuzzed bulanık
  perform tests.eq((select count(*)::int from spots_near(b_lat, b_lng, 2000) where id = s_prv), 0, 'anon: private hidden (spots_near)');
  perform tests.eq((select count(*)::int from spots_in_bounds(b_lat - 0.01, b_lng - 0.01, b_lat + 0.01, b_lng + 0.01) where id = s_prv), 0,
                   'anon: private hidden (spots_in_bounds)');
  perform tests.eq((select count(*)::int from search_spots('private nokta')), 0, 'anon: private hidden (search_spots)');
  select * into a from spots_near(b_lat, b_lng, 2000) where id = s_fuz;
  perform tests.check(a.id is not null and not a.is_location_exact, 'anon: fuzzed spot shown fuzzed');

  -- giriş yapmış normal kullanıcı: public tam, fuzzed/private bulanık (anon ile aynı sahte nokta)
  perform tests.login(viewer);
  select * into b from spot_detail(s_pub);
  perform tests.check(b.is_location_exact, 'auth: public spot exact');
  perform tests.check(tests.dist(b.lat, b.lng, b_lat, b_lng) < 0.01, 'auth: public spot real coordinates');
  select * into b from spot_detail(s_fuz);
  perform tests.check(not b.is_location_exact and b.lat = a.lat and b.lng = a.lng, 'auth: fuzzed spot same fuzzed point as anon');
  select * into b from spot_detail(s_prv);
  perform tests.check(b.id is not null and not b.is_location_exact, 'auth: private spot visible but fuzzed');
  d := tests.dist(b.lat, b.lng, b_lat + 0.004, b_lng);
  perform tests.check(d between 50 and 100, 'auth: private fuzz offset within 50–100 m');

  -- oluşturan / koruyucu / doğrulanmış besleyici: tam
  perform tests.login(creator);
  perform tests.check((select is_location_exact from spot_detail(s_fuz)), 'creator: fuzzed spot exact');
  perform tests.check((select is_location_exact from spot_detail(s_prv)), 'creator: private spot exact');
  perform tests.login(guardian);
  perform tests.check((select is_location_exact from spot_detail(s_fuz)), 'guardian: fuzzed spot exact');
  perform tests.check((select is_location_exact from spot_detail(s_prv)), 'guardian: private spot exact');
  perform tests.login(verified);
  perform tests.check((select is_location_exact from spot_detail(s_prv)), 'verified feeder: private spot exact');
  perform tests.admin();

  -- 200 farklı nokta için ofset aralığı ve id başına determinizm
  for i in 1..200 loop
    sid := tests.make_spot(b_lat + 0.05, b_lng + i * 0.0001, 'toplu ' || i, 'fuzzed');
    select extensions.st_distance(private.fuzz_point(s.id, s.location), s.location) into d from spots s where s.id = sid;
    if d between 50 and 100
       and extensions.st_equals(private.fuzz_point(sid, (select location from spots where id = sid))::extensions.geometry,
                                private.fuzz_point(sid, (select location from spots where id = sid))::extensions.geometry) then
      n_ok := n_ok + 1;
    end if;
  end loop;
  perform tests.eq(n_ok, 200, 'fuzz_point: 200/200 offsets within 50–100 m and deterministic');
end
$$;

-- needs: bağlı nokta görünmüyorsa ihtiyaç da dönmez; konum bulanıklığı need_row'a da uygulanır
do $$
declare
  b_lat  float8 := tests.base_lat() + 0.90;
  b_lng  float8 := tests.base_lng();
  u      uuid := tests.make_user('İhtiyaç sahibi');
  s_pub  uuid := tests.make_spot(b_lat, b_lng, 'pub', 'public', u);
  s_prv  uuid := tests.make_spot(b_lat + 0.001, b_lng, 'prv', 'private', u);
  n_pub  uuid;
  n_prv  uuid;
  nr     need_row;
begin
  insert into needs (spot_id, type, created_by) values (s_pub, 'vet', u) returning id into n_pub;
  insert into needs (spot_id, type, created_by) values (s_prv, 'vet', u) returning id into n_prv;
  perform tests.anon();
  select * into nr from needs_near(b_lat, b_lng, 1000) where id = n_pub;
  perform tests.check(nr.id is not null and not nr.is_location_exact, 'anon: need at public spot fuzzed');
  perform tests.check(tests.dist(nr.lat, nr.lng, b_lat, b_lng) between 50 and 100, 'anon: need location fuzzed 50–100 m');
  perform tests.eq((select count(*)::int from needs_near(b_lat, b_lng, 1000) where id = n_prv), 0, 'anon: need at private spot hidden (needs_near)');
  perform tests.eq((select count(*)::int from needs_for(p_spot_id => s_prv)), 0, 'anon: need at private spot hidden (needs_for)');
  perform tests.login(u);
  perform tests.check((select is_location_exact from need_detail(n_prv)), 'creator: need at private spot exact');
  perform tests.admin();
end
$$;

rollback;
