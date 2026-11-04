-- İhtiyaçlar (FR-I*), hayvanlar (FR-A3), arama, zaman çizelgesi, özetler
begin;

do $$
declare
  b_lat   float8 := tests.base_lat() + 1.5;
  b_lng   float8 := tests.base_lng();
  creator uuid := tests.make_user('İhtiyaç açan');
  helper  uuid := tests.make_user('Gönüllü');
  other   uuid := tests.make_user('Meraklı');
  vf      uuid := tests.make_user('Rozetli besleyici', 40, true);
  s_near  uuid := tests.make_spot(b_lat, b_lng, 'yakın ihtiyaç noktası', 'public', creator);
  s_far   uuid := tests.make_spot(b_lat + 0.02, b_lng, 'uzak ihtiyaç noktası', 'public', creator);   -- ~2.2 km
  an      uuid;
  n_norm  uuid;
  n_urg   uuid;
  n_anim  uuid;
  r       jsonb;
  ids     uuid[];
begin
  insert into animals (name, created_by, last_seen_spot_id, photos)
  values ('Test Tarçın', creator, s_near, '{https://example.test/a.jpg}') returning id into an;

  perform tests.login(creator);
  n_norm := create_need(s_near, null, 'shelter', 'normal', 'Kulübe lazım', null);
  n_urg  := create_need(s_far, null, 'vet', 'urgent', 'Acil veteriner', array['https://example.test/n.jpg']);
  n_anim := create_need(null, an, 'neuter', null, null, null);
  perform tests.check(n_norm is not null and n_urg is not null, 'create_need returns uuid');
  begin
    perform create_need(s_near, null, 'vet', 'normal', 'kahpe herif', null);
    raise exception 'FAIL: profane need accepted';
  exception when raise_exception then
    perform tests.check(sqlerrm = 'rejected_content', 'create_need profanity → rejected_content exception');
  end;
  begin
    perform create_need(null, null, 'vet', 'normal', 'boş', null);
    raise exception 'FAIL: need without target accepted';
  exception when invalid_parameter_value then
    perform tests.check(true, 'create_need without spot/animal → exception');
  end;

  -- needs_near: önce urgent (uzak olsa da), sonra mesafe (FR-I5)
  perform tests.anon();
  select array_agg(id) into ids from needs_near(b_lat, b_lng, 5000);
  perform tests.eq(ids[1], n_urg, 'needs_near: urgent first even if farther');
  perform tests.check(n_norm = any (ids) and n_anim = any (ids), 'needs_near: includes spot need and animal need (via last seen spot)');
  perform tests.eq((select animal_name from needs_near(b_lat, b_lng, 5000) where id = n_anim), 'Test Tarçın', 'need_row.animal_name');
  perform tests.eq((select animal_photo_url from needs_near(b_lat, b_lng, 5000) where id = n_anim), 'https://example.test/a.jpg', 'need_row.animal_photo_url');
  perform tests.eq((select spot_title from needs_near(b_lat, b_lng, 5000) where id = n_norm), 'yakın ihtiyaç noktası', 'need_row.spot_title');
  perform tests.eq((select count(*)::int from needs_near(b_lat, b_lng, 1000)), 2, 'needs_near radius filter (1 km excludes far)');

  -- needs_for
  perform tests.eq((select count(*)::int from needs_for(p_spot_id => s_near)), 1, 'needs_for spot');
  perform tests.eq((select count(*)::int from needs_for(p_animal_id => an)), 1, 'needs_for animal');
  perform tests.eq((select count(*)::int from needs_for(s_near, an)), 2, 'needs_for spot OR animal');
  perform tests.check((select bool_and(distance_m is null) from needs_for(s_near, an)), 'needs_for distance_m null');

  -- claim / resolve (FR-I3)
  perform tests.login(helper);
  r := claim_need(n_urg);
  perform tests.eq(r->>'status', 'ok', 'claim_need → ok');
  perform tests.eq((select claimed_by_name from need_detail(n_urg)), 'Gönüllü', 'need_row.claimed_by_name');
  perform tests.eq((select status from need_detail(n_urg)), 'claimed'::need_status, 'claimed status');
  r := claim_need(n_urg);
  perform tests.eq(r->>'status', 'ok', 'claim_need again by same user → ok');
  perform tests.login(other);
  r := claim_need(n_urg);
  perform tests.eq(r->>'status', 'already_claimed', 'claim by other → already_claimed');
  r := resolve_need(n_urg);
  perform tests.eq(r->>'status', 'not_allowed', 'resolve by stranger → not_allowed');
  perform tests.login(helper);
  r := resolve_need(n_urg);
  perform tests.eq(r->>'status', 'ok', 'resolve by claimer → ok');
  perform tests.login(other);
  r := claim_need(n_urg);
  perform tests.eq(r->>'status', 'resolved', 'claim resolved need → resolved');
  perform tests.login(vf);
  r := resolve_need(n_norm);
  perform tests.eq(r->>'status', 'ok', 'verified feeder may resolve');
  perform tests.login(creator);
  r := resolve_need(n_anim);
  perform tests.eq(r->>'status', 'ok', 'creator may resolve');
  perform tests.admin();

  perform tests.eq((select count(*)::int from notifications where user_id = creator and kind = 'need_resolved'), 2,
                   'need_resolved sent to creator when others resolve');
  perform tests.eq((select count(*)::int from notifications where user_id = helper and kind = 'need_resolved'), 0,
                   'no need_resolved to the resolver');

  perform tests.login(other);
  perform tests.eq((select count(*)::int from needs_near(b_lat, b_lng, 5000)), 0, 'needs_near hides resolved by default');
  perform tests.eq((select count(*)::int from needs_near(b_lat, b_lng, 5000, true)), 3, 'needs_near include_resolved');
  perform tests.eq((select resolved_need_count from profile_stats(helper)), 1, 'profile_stats.resolved_need_count for claimer');
  perform tests.eq((select resolved_need_count from profile_stats(vf)), 1, 'profile_stats.resolved_need_count for unclaimed resolver');
  perform tests.admin();
end
$$;

-- mark_animal_seen, animals_at_spot, animal_spots_of
do $$
declare
  b_lat float8 := tests.base_lat() + 1.6;
  b_lng float8 := tests.base_lng();
  u  uuid := tests.make_user('Gözlemci');
  s1 uuid := tests.make_spot(b_lat, b_lng, 'hayvan noktası 1', 'public');
  s2 uuid := tests.make_spot(b_lat + 0.003, b_lng, 'hayvan noktası 2', 'public');
  a1 uuid;
  a2 uuid;
  ar animal_row;
begin
  insert into animals (name, created_by) values ('Duman T', u) returning id into a1;
  insert into animals (name, created_by) values ('Zeytin T', u) returning id into a2;
  perform tests.login(u);
  perform mark_animal_seen(a1, s1);
  perform mark_animal_seen(a1, s1);
  perform mark_animal_seen(a1, s1);
  perform mark_animal_seen(a2, s1);
  perform mark_animal_seen(a1, s2);
  perform tests.admin();
  update animal_spots set last_seen_at = now() - interval '1 hour' where animal_id = a1 and spot_id = s1;
  perform tests.login(u);
  select * into ar from animals_at_spot(s1) limit 1;
  perform tests.eq(ar.id, a1, 'animals_at_spot ordered by seen_count desc');
  perform tests.eq(ar.seen_count, 3, 'mark_animal_seen increments seen_count (trigger does not double count)');
  perform tests.eq(ar.name, 'Duman T', 'animal_row carries animal columns');
  perform tests.eq((select last_seen_spot_id from animals where id = a1), s2, 'mark_animal_seen updates last_seen_spot_id');
  perform tests.eq((select array_agg(id) from animal_spots_of(a1)), array[s2, s1], 'animal_spots_of ordered by last seen');
  perform tests.eq((select animal_count from spot_detail(s1)), 2, 'spot_row.animal_count');
  perform tests.admin();
end
$$;

-- search_spots: Türkçe büyük/küçük harf, konum sıralaması, LIKE kaçışı
do $$
declare
  b_lat float8 := tests.base_lat() + 1.7;
  b_lng float8 := tests.base_lng();
  s1 uuid := tests.make_spot(b_lat, b_lng, 'Iğdır Sokağı İskele Kedileri', 'public', null, now() - interval '5 hours');
  s2 uuid := tests.make_spot(b_lat + 0.01, b_lng, 'ışıklı iskele köşesi', 'public', null, now() - interval '1 hour');
  s3 uuid := tests.make_spot(b_lat + 0.02, b_lng, 'Yüzde 100%_özel', 'public');
begin
  perform tests.anon();
  perform tests.eq((select count(*)::int from search_spots('İSKELE') where id in (s1, s2)), 2, 'search İSKELE matches İskele and iskele');
  perform tests.eq((select count(*)::int from search_spots('iskele') where id in (s1, s2)), 2, 'search iskele matches İskele');
  perform tests.eq((select count(*)::int from search_spots('ISIKLI') where id = s2), 1, 'search ISIKLI matches ışıklı');
  perform tests.eq((select count(*)::int from search_spots('iğdır sokağı') where id = s1), 1, 'search iğdır sokağı matches Iğdır Sokağı');
  perform tests.eq((select id from search_spots('iskele', b_lat + 0.011, b_lng) limit 1), s2, 'search ordered by distance when lat/lng given');
  perform tests.eq((select id from search_spots('iskele kedi') limit 1), s1, 'search substring');
  perform tests.eq((select array_agg(id) from search_spots('iskele') where id in (s1, s2)), array[s2, s1], 'search without location: last_fed_at desc');
  perform tests.eq((select count(*)::int from search_spots('_%')), 0, 'LIKE wildcards are escaped');
  perform tests.eq((select count(*)::int from search_spots('100%_')), 1, 'literal % and _ searchable');
  perform tests.eq((select count(*)::int from search_spots('a')), 0, 'query shorter than 2 chars → empty');
  perform tests.check((select bool_and(distance_m is null) from search_spots('iskele')), 'distance_m null without location');
  perform tests.admin();
end
$$;

-- spot_feeding_timeline, neighborhood_summary, profile_stats, followed_spots
do $$
declare
  b_lat float8 := tests.base_lat() + 1.8;
  b_lng float8 := tests.base_lng();
  u  uuid := tests.make_user('Zaman');
  s  uuid := tests.make_spot(b_lat, b_lng, 'zaman noktası', 'public', null, now());
  s2 uuid := tests.make_spot(b_lat + 0.001, b_lng, 'özet 2', 'public', null, now() - interval '3 days');
  t  record;
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at) values
    (s, u, 'fed', 10, now()),
    (s, u, 'fed', 10, now() - interval '2 days'),
    (s, u, 'need_food', 10, now() - interval '2 days'),   -- (aşağıda çözüldü)
    (s2, u, 'need_water', 10, now() - interval '1 day');
  update checkins set resolved_at = now() - interval '1 day' where spot_id = s and kind = 'need_food';
  insert into follows (user_id, target_type, target_id) values (u, 'spot', s2);

  perform tests.login(u);
  perform tests.eq((select count(*)::int from spot_feeding_timeline(s)), 7, 'timeline returns 7 days by default (empty days included)');
  perform tests.eq((select count(*)::int from spot_feeding_timeline(s, 3)), 3, 'timeline days param');
  select * into t from spot_feeding_timeline(s, 7) order by day desc limit 1;
  perform tests.eq(t.day, (now() at time zone 'Europe/Istanbul')::date, 'timeline last row is today (Istanbul)');
  perform tests.eq(t.fed_count, 1, 'timeline today fed_count');
  perform tests.eq((select sum(fed_count)::int from spot_feeding_timeline(s, 7)), 2, 'timeline total fed');
  perform tests.eq((select sum(need_count)::int from spot_feeding_timeline(s, 7)), 1, 'timeline total need');

  select * into t from neighborhood_summary(b_lat, b_lng, 500);
  perform tests.eq(t.fed_spots_today, 1, 'neighborhood_summary.fed_spots_today');
  perform tests.eq(t.needs_food_spots, 1, 'neighborhood_summary.needs_food_spots');
  perform tests.eq(t.active_spots_7d, 2, 'neighborhood_summary.active_spots_7d');

  select * into t from profile_stats(u);
  perform tests.eq(t.checkin_count, 4, 'profile_stats.checkin_count');
  perform tests.eq(t.fed_spot_count, 1, 'profile_stats.fed_spot_count');
  perform tests.eq(t.verified_checkins_30d, 4, 'profile_stats.verified_checkins_30d');

  perform tests.eq((select array_agg(id) from followed_spots()), array[s2], 'followed_spots');
  perform tests.eq((select status from followed_spots()), 'needs_food'::spot_status, 'followed_spots computes status');
  perform tests.admin();
end
$$;

rollback;
