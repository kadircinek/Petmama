-- create_spot (mükerrer FR-N3, günlük limit + moderasyon PRD 9.3, küfür) ve report_spot_gone (FR-N6)
begin;

do $$
declare
  b_lat float8 := tests.base_lat() + 0.30;
  b_lng float8 := tests.base_lng();
  u     uuid := tests.make_user('Kurucu');
  r     jsonb;
  first uuid;
  p     record;
begin
  perform tests.login(u);
  r := create_spot(b_lat, b_lng, 'food', 'cat', 'İlk nokta', 'not', null, 'public');
  perform tests.eq(r->>'status', 'created', 'create_spot → created');
  perform tests.eq(r->>'moderation_state', 'approved', 'trust 10 → approved');
  first := (r->>'spot_id')::uuid;

  -- 10 m ötede → duplicate
  p := tests.project(b_lat, b_lng, 10, 30);
  r := create_spot(p.lat, p.lng, 'water', 'cat', 'Yakın nokta', null, null, 'public');
  perform tests.eq(r->>'status', 'duplicate', 'spot within 15 m → duplicate');
  perform tests.eq((r->'duplicates'->0->>'id')::uuid, first, 'duplicate lists the existing spot id');
  perform tests.check(abs((r->'duplicates'->0->>'distance_m')::numeric - 10) < 0.2, 'duplicate distance_m ≈ 10');
  perform tests.eq(r->'duplicates'->0->>'title', 'İlk nokta', 'duplicate lists title');

  -- find_duplicate_spots aynı sonucu verir
  perform tests.eq((select count(*)::int from find_duplicate_spots(p.lat, p.lng)), 1, 'find_duplicate_spots finds it');
  perform tests.eq((select count(*)::int from find_duplicate_spots(p.lat, p.lng, 5)), 0, 'find_duplicate_spots radius 5 m → none');

  -- 16 m ötede → duplicate değil
  p := tests.project(b_lat, b_lng, 16, 210);
  r := create_spot(p.lat, p.lng, 'water', 'cat', 'Az ötede', null, null, 'public');
  perform tests.eq(r->>'status', 'created', 'spot 16 m away → created');

  -- p_force
  p := tests.project(b_lat, b_lng, 5, 120);
  r := create_spot(p.lat, p.lng, 'shelter', 'both', 'Zorla', null, null, 'fuzzed', true);
  perform tests.eq(r->>'status', 'created', 'p_force=true creates despite duplicate');

  -- küfür
  r := create_spot(b_lat + 0.01, b_lng, 'food', 'cat', 'Siktir git', null, null, 'public');
  perform tests.eq(r->>'status', 'rejected_content', 'profane title → rejected_content');
  r := create_spot(b_lat + 0.01, b_lng, 'food', 'cat', 'Temiz başlık', 'bu bir ORUSPU değil ama orospu', null, 'public');
  perform tests.eq(r->>'status', 'rejected_content', 'profane note → rejected_content');
  r := create_spot(b_lat + 0.01, b_lng, 'food', 'cat', 'Kedi ağaçta sıkışmış', 'sık sık geliyorlar, Moda Sitesi önü', null, 'public');
  perform tests.eq(r->>'status', 'created', 'no false positive for sık/sıkışmış/Sitesi');

  -- günlük limit: şimdiye kadar 4 oluşturuldu, 5. olur, 6. limit
  r := create_spot(b_lat + 0.02, b_lng, 'food', 'cat', 'Beşinci', null, null, 'public');
  perform tests.eq(r->>'status', 'created', '5th spot today → created');
  r := create_spot(b_lat + 0.03, b_lng, 'food', 'cat', 'Altıncı', null, null, 'public');
  perform tests.eq(r->>'status', 'limit_reached', '6th spot today → limit_reached');
  perform tests.eq((r->>'limit')::int, 5, 'limit is 5 for normal user');
  perform tests.admin();
end
$$;

-- doğrulanmış besleyici 30
do $$
declare
  u uuid := tests.make_user('Doğrulanmış', 50, true);
  r jsonb;
  i int;
begin
  perform tests.login(u);
  for i in 1..30 loop
    r := create_spot(tests.base_lat() + 0.40 + i * 0.001, tests.base_lng(), 'food', 'cat', 'V' || i, null, null, 'public');
    if r->>'status' <> 'created' then
      raise exception 'FAIL: verified spot % not created: %', i, r;
    end if;
  end loop;
  perform tests.check(true, 'verified feeder can create 30 spots/day');
  r := create_spot(tests.base_lat() + 0.50, tests.base_lng(), 'food', 'cat', 'V31', null, null, 'public');
  perform tests.eq(r->>'status', 'limit_reached', 'verified 31st → limit_reached');
  perform tests.eq((r->>'limit')::int, 30, 'limit is 30 for verified');
  perform tests.admin();
end
$$;

-- trust_score < 5 → pending; yalnızca oluşturan görür
do $$
declare
  newbie uuid := tests.make_user('Yeni', 4);
  other  uuid := tests.make_user('Diğer');
  r      jsonb;
  sid    uuid;
begin
  perform tests.login(newbie);
  r := create_spot(tests.base_lat() + 0.60, tests.base_lng(), 'food', 'cat', 'Bekleyen', null, null, 'public');
  perform tests.eq(r->>'moderation_state', 'pending', 'trust 4 → pending');
  sid := (r->>'spot_id')::uuid;
  perform tests.eq((select count(*)::int from spot_detail(sid)), 1, 'creator sees pending spot');
  perform tests.eq((select count(*)::int from spots_near(tests.base_lat() + 0.60, tests.base_lng(), 200) where id = sid), 1,
                   'creator sees pending spot on map');
  perform tests.login(other);
  perform tests.eq((select count(*)::int from spot_detail(sid)), 0, 'other user does not see pending spot');
  perform tests.anon();
  perform tests.eq((select count(*)::int from spots_near(tests.base_lat() + 0.60, tests.base_lng(), 500) where id = sid), 0,
                   'anon does not see pending spot');
  perform tests.admin();
  update spots set moderation_state = 'rejected' where id = sid;
  perform tests.login(newbie);
  perform tests.eq((select count(*)::int from spot_detail(sid)), 0, 'rejected spot hidden even from creator');
  perform tests.admin();
end
$$;

-- report_spot_gone: kullanıcı başına 1, 3 farklı kullanıcı → pasif
do $$
declare
  s  uuid := tests.make_spot(tests.base_lat() + 0.70, tests.base_lng(), 'gidecek nokta', 'public');
  u1 uuid := tests.make_user('G1');
  u2 uuid := tests.make_user('G2');
  u3 uuid := tests.make_user('G3');
  r  jsonb;
begin
  perform tests.login(u1);
  r := report_spot_gone(s);
  perform tests.eq(r, '{"status":"ok","count":1,"deactivated":false}'::jsonb, 'gone report 1');
  r := report_spot_gone(s);
  perform tests.eq((r->>'count')::int, 1, 'same user twice counts once');
  perform tests.login(u2);
  r := report_spot_gone(s);
  perform tests.eq(r, '{"status":"ok","count":2,"deactivated":false}'::jsonb, 'gone report 2');
  perform tests.login(u3);
  r := report_spot_gone(s);
  perform tests.eq(r, '{"status":"ok","count":3,"deactivated":true}'::jsonb, '3 distinct users → deactivated');
  perform tests.eq((select count(*)::int from spots_near(tests.base_lat() + 0.70, tests.base_lng(), 300) where id = s), 0,
                   'inactive spot hidden from spots_near');
  perform tests.eq((select is_active from spot_detail(s)), false, 'spot_detail still returns inactive spot (is_active=false)');
  perform tests.admin();
end
$$;

rollback;
