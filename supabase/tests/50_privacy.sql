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

-- neighborhood_summary konum kâhini olmamalı (PRD 9.1): nokta yarıçapa izleyiciye GÖSTERİLEN konumuyla
-- girer. Aksi halde merkez kaydırılıp sayıların değiştiği sınır izlenerek bulanık bir noktanın gerçek
-- konumu bulunabilirdi. Her nokta için, gerçek ve bulanık konum 1500 m çemberinin iki yanında kalacak
-- şekilde iki merkez kurulur (bulanıklık 50–100 m → iki yanda da ≥ 25 m pay):
--   "shown" merkezi: yalnızca bulanık konum içeride   ·   "true" merkezi: yalnızca gerçek konum içeride
-- Her noktada dört sayacı da 1 yapan veri var: sayılıyorsa {1,1,1,1}, sayılmıyorsa {0,0,0,0}
-- (sıra: fed_spots_today, open_needs, needs_food_spots, active_spots_7d).
do $$
declare
  b_lat     float8 := tests.base_lat() + 0.60;
  b_lng     float8 := tests.base_lng();
  creator   uuid := tests.make_user('Özet: oluşturan');
  viewer    uuid := tests.make_user('Özet: izleyici');
  spot_vis  text[] := array['public', 'fuzzed', 'private'];   -- noktalar ≈8 km arayla: birbirini etkilemez
  shown_lat float8[] := '{}';
  shown_lng float8[] := '{}';
  true_lat  float8[] := '{}';
  true_lng  float8[] := '{}';
  sid       uuid;
  loc       extensions.geography;
  fz        extensions.geography;
  az        float8;
  mid       extensions.geography;
  c_shown   extensions.geography;
  c_true    extensions.geography;
  i         int;
  r         record;
  got       int[];
begin
  for i in 1..3 loop
    sid := tests.make_spot(b_lat, b_lng + (i - 1) * 0.1, 'özet ' || spot_vis[i], spot_vis[i]::spot_visibility,
                           creator, now());
    insert into checkins (spot_id, user_id, kind, user_distance_m) values
      (sid, creator, 'fed', 5), (sid, creator, 'need_food', 5);
    insert into needs (spot_id, type, created_by) values (sid, 'vet', creator);

    select sp.location, private.fuzz_point(sp.id, sp.location) into loc, fz from spots sp where sp.id = sid;
    az      := extensions.st_azimuth(loc, fz);
    mid     := extensions.st_project(loc, extensions.st_distance(loc, fz) / 2, az);
    c_shown := extensions.st_project(mid, 1500, az);
    c_true  := extensions.st_project(mid, 1500, az + pi());
    perform tests.check(extensions.st_distance(c_shown, fz) < 1490 and extensions.st_distance(c_shown, loc) > 1510
                        and extensions.st_distance(c_true, loc) < 1490 and extensions.st_distance(c_true, fz) > 1510,
                        format('setup (%s spot): true and displayed location straddle the 1500 m radius', spot_vis[i]));
    shown_lat := shown_lat || extensions.st_y(c_shown::extensions.geometry);
    shown_lng := shown_lng || extensions.st_x(c_shown::extensions.geometry);
    true_lat  := true_lat  || extensions.st_y(c_true::extensions.geometry);
    true_lng  := true_lng  || extensions.st_x(c_true::extensions.geometry);
  end loop;

  for r in
    select * from (values
      -- izleyici   nokta       "shown" merkezi   "true" merkezi
      ('anon',    'public',  array[1,1,1,1], array[0,0,0,0]),   -- anon: her nokta bulanık
      ('anon',    'fuzzed',  array[1,1,1,1], array[0,0,0,0]),
      ('anon',    'private', array[0,0,0,0], array[0,0,0,0]),   -- anon: private hiç sayılmaz
      ('viewer',  'public',  array[0,0,0,0], array[1,1,1,1]),   -- giriş yapmış: public tam
      ('viewer',  'fuzzed',  array[1,1,1,1], array[0,0,0,0]),   --               fuzzed/private bulanık
      ('viewer',  'private', array[1,1,1,1], array[0,0,0,0]),
      ('creator', 'fuzzed',  array[0,0,0,0], array[1,1,1,1]),   -- oluşturan: tam (haritada gördüğüyle aynı)
      ('creator', 'private', array[0,0,0,0], array[1,1,1,1])
    ) as m(who, vis, want_shown, want_true)
  loop
    i := array_position(spot_vis, r.vis);
    case r.who
      when 'anon'   then perform tests.anon();
      when 'viewer' then perform tests.login(viewer);
      else               perform tests.login(creator);
    end case;

    select array[t.fed_spots_today, t.open_needs, t.needs_food_spots, t.active_spots_7d] into got
    from neighborhood_summary(shown_lat[i], shown_lng[i], 1500) t;
    perform tests.eq(got, r.want_shown,
                     format('neighborhood_summary, %s + %s spot: only the DISPLAYED point inside the radius', r.who, r.vis));

    select array[t.fed_spots_today, t.open_needs, t.needs_food_spots, t.active_spots_7d] into got
    from neighborhood_summary(true_lat[i], true_lng[i], 1500) t;
    perform tests.eq(got, r.want_true,
                     format('neighborhood_summary, %s + %s spot: only the TRUE point inside the radius', r.who, r.vis));
  end loop;
  perform tests.admin();
end
$$;

rollback;
