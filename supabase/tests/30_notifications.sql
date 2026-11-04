-- need_food_nearby fan-out (FR-C4), takipçiler, engelleme, tercih, notify_center yuvarlama
begin;

do $$
declare
  b_lat float8 := tests.base_lat() + 0.10;
  b_lng float8 := tests.base_lng();
  actor     uuid := tests.make_user('Bildiren');
  near_u    uuid := tests.make_user('Yakın');
  far_u     uuid := tests.make_user('Uzak');
  blocked_u uuid := tests.make_user('Engelli (actor engelledi)');
  blocker_u uuid := tests.make_user('Engelleyen (actor''u engelledi)');
  off_u     uuid := tests.make_user('Tercihi kapalı');
  nocenter  uuid := tests.make_user('Merkezsiz');
  follower  uuid := tests.make_user('Takipçi');
  actor2    uuid := tests.make_user('İkinci bildiren');
  s         uuid := tests.make_spot(b_lat, b_lng, 'bildirim noktası', 'public', null, now() - interval '2 hours');
  p         record;
  r         jsonb;
begin
  -- merkezler (update_notify_center üzerinden, her biri kendi oturumunda)
  p := tests.project(b_lat, b_lng, 500, 90);
  perform tests.login(near_u);    perform update_notify_center(p.lat, p.lng);
  perform tests.login(actor);     perform update_notify_center(b_lat, b_lng);
  perform tests.login(blocked_u); perform update_notify_center(b_lat, b_lng);
  perform tests.login(blocker_u); perform update_notify_center(b_lat, b_lng);
  perform tests.login(off_u);     perform update_notify_center(b_lat, b_lng);
  perform tests.login(follower);  perform update_notify_center(b_lat, b_lng);
  p := tests.project(b_lat, b_lng, 5000, 90);
  perform tests.login(far_u);     perform update_notify_center(p.lat, p.lng);
  perform tests.admin();

  update notification_prefs set need_food_nearby = false where user_id = off_u;
  update notification_prefs set need_food_nearby = false where user_id = follower;
  insert into blocks (user_id, blocked_user_id) values (actor, blocked_u), (blocker_u, actor);
  insert into follows (user_id, target_type, target_id) values (follower, 'spot', s), (near_u, 'spot', s);

  perform tests.login(actor);
  r := check_in(s, 'need_food', null, null, b_lat, b_lng);
  perform tests.eq(r->>'status', 'ok', 'need_food check-in ok');
  perform tests.admin();

  perform tests.eq((select count(*)::int from notifications where user_id = near_u and kind = 'need_food_nearby' and spot_id = s), 1,
                   'need_food_nearby for nearby user (500 m, radius 1000)');
  perform tests.eq((select count(*)::int from notifications where user_id = far_u), 0, 'no notification for far user (5 km)');
  perform tests.eq((select count(*)::int from notifications where user_id = actor), 0, 'no notification for actor');
  perform tests.eq((select count(*)::int from notifications where user_id = blocked_u), 0, 'no notification for user blocked by actor');
  perform tests.eq((select count(*)::int from notifications where user_id = blocker_u), 0, 'no notification for user who blocked actor');
  perform tests.eq((select count(*)::int from notifications where user_id = off_u), 0, 'no notification when need_food_nearby pref off');
  perform tests.eq((select count(*)::int from notifications where user_id = nocenter), 0, 'no notification without notify_center');
  perform tests.eq((select count(*)::int from notifications where user_id = follower and kind = 'followed_spot_changed'), 1,
                   'follower gets followed_spot_changed');
  perform tests.eq((select count(*)::int from notifications where user_id = near_u and kind = 'followed_spot_changed'), 0,
                   'no duplicate followed_spot_changed for user already notified nearby');
  perform tests.check((select bool_and(pushed_at is null and read_at is null) from notifications where spot_id = s),
                      'new notifications are unpushed & unread');

  -- aynı nokta için 6 saat içinde ikinci need_food_nearby yok (başka kullanıcı bildirse bile)
  perform tests.login(actor2);
  r := check_in(s, 'need_water', null, null, b_lat, b_lng);
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = near_u and kind = 'need_food_nearby'), 1,
                   'need_food_nearby deduped within 6h');
  perform tests.eq((select count(*)::int from notifications where user_id = actor and kind = 'need_food_nearby'), 1,
                   'need_water fans out too (first actor is now a recipient)');
end
$$;

-- broken da fan-out yapar; pending noktada fan-out yok
do $$
declare
  b_lat float8 := tests.base_lat() + 0.20;
  b_lng float8 := tests.base_lng();
  actor  uuid := tests.make_user('Kırık bildiren');
  near_u uuid := tests.make_user('Kırık yakın');
  s      uuid := tests.make_spot(b_lat, b_lng, 'kırık kap', 'public');
  s2     uuid := tests.make_spot(b_lat + 0.001, b_lng, 'onaysız', 'public', actor);
begin
  update spots set moderation_state = 'pending' where id = s2;
  perform tests.login(near_u); perform update_notify_center(b_lat, b_lng);
  perform tests.login(actor);
  perform check_in(s, 'broken', null, null, b_lat, b_lng);
  perform check_in(s2, 'need_food', null, null, b_lat + 0.001, b_lng);
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = near_u and spot_id = s and kind = 'need_food_nearby'), 1,
                   'broken triggers need_food_nearby');
  perform tests.eq((select count(*)::int from notifications where user_id = near_u and spot_id = s2), 0,
                   'pending spot: no fan-out');
end
$$;

-- update_notify_center: 3 ondalık, üzerine yazar (geçmiş yok)
do $$
declare
  u uuid := tests.make_user('Merkez');
  c extensions.geography;
begin
  perform tests.login(u);
  perform update_notify_center(40.987654, 29.023456);
  perform update_notify_center(40.981234, 29.031987);
  perform tests.admin();
  select notify_center into c from notification_prefs where user_id = u;
  perform tests.eq(extensions.st_y(c::extensions.geometry), 40.981::float8, 'notify_center lat rounded to 3 decimals');
  perform tests.eq(extensions.st_x(c::extensions.geometry), 29.032::float8, 'notify_center lng rounded to 3 decimals (overwritten)');
  perform tests.eq((select count(*)::int from notification_prefs where user_id = u), 1, 'single prefs row per user');

  -- doğrudan tablo yazımı da yuvarlanır
  perform tests.login(u);
  update notification_prefs set notify_center = private_point
    from (select extensions.st_setsrid(extensions.st_makepoint(29.0277777, 40.9855555), 4326)::extensions.geography as private_point) x
   where user_id = u;
  perform tests.admin();
  select notify_center into c from notification_prefs where user_id = u;
  perform tests.eq(extensions.st_y(c::extensions.geometry), 40.986::float8, 'direct notify_center write is rounded too');
end
$$;

-- register_device_token: upsert, başka kullanıcıya taşınır; kullanıcı kendi token'ını siler
do $$
declare
  u1 uuid := tests.make_user('Cihaz 1');
  u2 uuid := tests.make_user('Cihaz 2');
  tok text := repeat('ab', 32);
begin
  perform tests.login(u1);
  perform register_device_token(tok);
  perform register_device_token(tok);
  perform tests.login(u2);
  perform register_device_token(tok);
  perform tests.eq((select count(*)::int from device_tokens), 1, 'user sees only own device tokens');
  perform tests.admin();
  perform tests.eq((select user_id from device_tokens where token = tok), u2, 'token moved to latest user');
  perform tests.login(u1);
  delete from device_tokens where token = tok;
  perform tests.admin();
  perform tests.eq((select count(*)::int from device_tokens where token = tok), 1, 'other user cannot delete the token');
  perform tests.login(u2);
  delete from device_tokens where token = tok;
  perform tests.admin();
  perform tests.eq((select count(*)::int from device_tokens where token = tok), 0, 'owner deletes own token');
end
$$;

rollback;
