-- Durum hesaplama sınırları (PRD 5.2 FR-N5, 7.5)
begin;

do $$
declare
  t timestamptz := now();
begin
  -- saf fonksiyon
  perform tests.eq(compute_spot_status(t - interval '11 hours 59 minutes', false, t), 'fed_recent'::spot_status, 'status: 11h59 → fed_recent');
  perform tests.eq(compute_spot_status(t - interval '12 hours', false, t), 'fed_stale'::spot_status, 'status: 12h → fed_stale');
  perform tests.eq(compute_spot_status(t - interval '23 hours 59 minutes', false, t), 'fed_stale'::spot_status, 'status: 23h59 → fed_stale');
  perform tests.eq(compute_spot_status(t - interval '24 hours', false, t), 'unknown'::spot_status, 'status: 24h → unknown');
  perform tests.eq(compute_spot_status(null, false, t), 'unknown'::spot_status, 'status: never fed → unknown');
  perform tests.eq(compute_spot_status(t - interval '1 minute', true, t), 'needs_food'::spot_status, 'status: open request beats fresh feeding');
  perform tests.eq(compute_spot_status(null, true, t), 'needs_food'::spot_status, 'status: open request on never-fed spot');
end
$$;

-- RPC'ler durumu okuma anında hesaplar (kalıcı sütun bayat olsa bile)
do $$
declare
  u uuid := tests.make_user('Durum Testçi');
  s_green uuid; s_yellow uuid; s_grey uuid; s_never uuid;
  s_food uuid; s_water uuid; s_broken uuid; s_resolved uuid;
  r spot_row;
  b_lat float8 := tests.base_lat();
  b_lng float8 := tests.base_lng();
begin
  s_green  := tests.make_spot(b_lat,         b_lng,         'yeşil',  'public', u, now() - interval '11 hours 59 minutes');
  s_yellow := tests.make_spot(b_lat + 0.001, b_lng,         'sarı',   'public', u, now() - interval '12 hours');
  s_grey   := tests.make_spot(b_lat + 0.002, b_lng,         'gri',    'public', u, now() - interval '24 hours');
  s_never  := tests.make_spot(b_lat + 0.003, b_lng,         'hiç',    'public', u, null);
  s_food   := tests.make_spot(b_lat,         b_lng + 0.001, 'mama',   'public', u, now() - interval '1 hour');
  s_water  := tests.make_spot(b_lat,         b_lng + 0.002, 'su',     'public', u, now() - interval '1 hour');
  s_broken := tests.make_spot(b_lat,         b_lng + 0.003, 'kırık',  'public', u, now() - interval '1 hour');
  s_resolved := tests.make_spot(b_lat,       b_lng + 0.004, 'çözüldü','public', u, now() - interval '1 hour');

  -- kalıcı sütunu bilerek yanlış bırak
  update spots set status = 'needs_food' where id in (s_green, s_yellow, s_grey, s_never);

  insert into checkins (spot_id, user_id, kind, user_distance_m) values
    (s_food, u, 'need_food', 10), (s_water, u, 'need_water', 10), (s_broken, u, 'broken', 10);
  insert into checkins (spot_id, user_id, kind, user_distance_m, resolved_at) values
    (s_resolved, u, 'need_food', 10, now());

  perform tests.login(u);
  select * into r from spot_detail(s_green);   perform tests.eq(r.status, 'fed_recent'::spot_status, 'spot_detail: 11h59 green');
  select * into r from spot_detail(s_yellow);  perform tests.eq(r.status, 'fed_stale'::spot_status,  'spot_detail: 12h yellow');
  select * into r from spot_detail(s_grey);    perform tests.eq(r.status, 'unknown'::spot_status,    'spot_detail: 24h grey');
  select * into r from spot_detail(s_never);   perform tests.eq(r.status, 'unknown'::spot_status,    'spot_detail: never fed grey');
  select * into r from spot_detail(s_food);    perform tests.eq(r.status, 'needs_food'::spot_status, 'spot_detail: open need_food → needs_food');
  select * into r from spot_detail(s_water);   perform tests.eq(r.status, 'needs_food'::spot_status, 'spot_detail: open need_water → needs_food');
  select * into r from spot_detail(s_broken);  perform tests.eq(r.status, 'needs_food'::spot_status, 'spot_detail: open broken → needs_food');
  select * into r from spot_detail(s_resolved); perform tests.eq(r.status, 'fed_recent'::spot_status, 'spot_detail: resolved request ignored');
  perform tests.admin();

  -- cron kalıcılaştırır
  perform refresh_spot_statuses();
  perform tests.eq((select status from spots where id = s_green), 'fed_recent'::spot_status, 'refresh_spot_statuses persists status');
  perform tests.eq((select status from spots where id = s_broken), 'needs_food'::spot_status, 'refresh_spot_statuses persists needs_food');
end
$$;

-- has_urgent_need / open_need_count: noktaya veya noktadaki hayvana bağlı ihtiyaçlar
do $$
declare
  u uuid := tests.make_user('İhtiyaç Sayaç');
  s uuid := tests.make_spot(tests.base_lat() + 0.01, tests.base_lng(), 'ihtiyaç noktası', 'public', u, now());
  a uuid;
  r spot_row;
begin
  insert into animals (name, created_by, last_seen_spot_id) values ('Sayaç Kedi', u, s) returning id into a;
  perform tests.eq((select seen_count from animal_spots where animal_id = a and spot_id = s), 1, 'animals.last_seen_spot_id trigger creates animal_spots row');

  insert into needs (spot_id, type, urgency, created_by) values (s, 'shelter', 'normal', u);
  insert into needs (animal_id, type, urgency, created_by) values (a, 'vet', 'urgent', u);
  insert into needs (spot_id, type, urgency, status, created_by) values (s, 'vet', 'urgent', 'resolved', u);

  perform tests.login(u);
  select * into r from spot_detail(s);
  perform tests.eq(r.open_need_count, 2, 'open_need_count counts spot + animal needs, not resolved');
  perform tests.check(r.has_urgent_need, 'has_urgent_need via animal at spot');
  perform tests.eq(r.animal_count, 1, 'animal_count');
  perform tests.admin();
end
$$;

rollback;
