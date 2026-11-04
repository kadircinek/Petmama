-- Cron (refresh_spot_statuses), push kuyruğu, zamanlanmış işler, hesap silme anonimleştirmesi
begin;

-- guardian_spot_unfed: 24 sa+ beslenmemiş, koruyucu+nokta başına 24 saatte 1
do $$
declare
  b_lat float8 := tests.base_lat() + 2.0;
  b_lng float8 := tests.base_lng();
  g1 uuid := tests.make_user('Koruyucu 1');
  g2 uuid := tests.make_user('Koruyucu 2 (uyarı kapalı)');
  s_unfed uuid := tests.make_spot(b_lat, b_lng, 'aç nokta', 'public', null, now() - interval '25 hours');
  s_fed   uuid := tests.make_spot(b_lat + 0.001, b_lng, 'tok nokta', 'public', null, now() - interval '3 hours');
  s_new   uuid := tests.make_spot(b_lat + 0.002, b_lng, 'yeni nokta', 'public', null, null);   -- created_at = now()
  r jsonb;
begin
  insert into guardians (user_id, spot_id) values (g1, s_unfed), (g1, s_fed), (g1, s_new), (g2, s_unfed);
  update notification_prefs set guardian_alerts = false where user_id = g2;

  r := refresh_spot_statuses();
  perform tests.eq(r->>'status', 'ok', 'refresh_spot_statuses returns status ok');
  perform tests.eq((select count(*)::int from notifications where user_id = g1 and kind = 'guardian_spot_unfed' and spot_id = s_unfed), 1,
                   'guardian_spot_unfed for 25h unfed spot');
  perform tests.eq((select count(*)::int from notifications where user_id = g1 and kind = 'guardian_spot_unfed' and spot_id in (s_fed, s_new)), 0,
                   'no guardian_spot_unfed for fed or brand-new spot');
  perform tests.eq((select count(*)::int from notifications where user_id = g2), 0, 'guardian_alerts=false → no notification');

  perform refresh_spot_statuses();
  perform tests.eq((select count(*)::int from notifications where user_id = g1 and kind = 'guardian_spot_unfed'), 1,
                   'guardian_spot_unfed at most once per 24h');
  update notifications set created_at = now() - interval '25 hours' where user_id = g1 and kind = 'guardian_spot_unfed';
  perform refresh_spot_statuses();
  perform tests.eq((select count(*)::int from notifications where user_id = g1 and kind = 'guardian_spot_unfed'), 2,
                   'guardian_spot_unfed again after 24h');
end
$$;

-- FR-P4: cron ile doğrulanmış besleyici
do $$
declare
  u uuid := tests.make_user('Cron rozet');
  s uuid := tests.make_spot(tests.base_lat() + 2.1, tests.base_lng(), 'rozet cron', 'public');
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at)
  select s, u, 'fed', 10, now() - make_interval(hours => g) from generate_series(1, 20) g;
  perform refresh_spot_statuses();
  perform tests.check((select is_verified_feeder from profiles where id = u), 'cron promotes 20 verified check-ins in 30d');
end
$$;

-- push_claim_batch / push_complete / push_drop_tokens (service_role)
do $$
declare
  u1 uuid := tests.make_user('Push 1');
  u2 uuid := tests.make_user('Push 2');
  rows int;
  rec record;
begin
  update notifications set pushed_at = now(), push_status = 'sent' where pushed_at is null;   -- önceki testlerin artıkları
  insert into device_tokens (token, user_id) values ('aaaaaaaaaaaaaaaa', u1), ('bbbbbbbbbbbbbbbb', u1);
  insert into notifications (user_id, kind, title, body, created_at) values
    (u1, 'need_food_nearby', 't', 'b', now() - interval '1 minute'),
    (u2, 'thanks_fed', 't', 'b', now()),
    (u1, 'thanks_fed', 'old', 'b', now() - interval '2 hours');
  -- bugün zaten 2 need_food_nearby push'u gönderilmiş
  insert into notifications (user_id, kind, title, body, pushed_at, push_status) values
    (u1, 'need_food_nearby', 'x', 'y', now(), 'sent'), (u1, 'need_food_nearby', 'x', 'y', now(), 'sent');

  set local role service_role;
  select count(*)::int into rows from push_claim_batch(50);
  perform tests.eq(rows, 2, 'push_claim_batch claims fresh unpushed rows (old one expired)');
  reset role;
  perform tests.eq((select push_status from notifications where title = 'old'), 'expired', 'stale notification → expired (stays in-app)');
  perform tests.check((select bool_and(pushed_at is not null and push_status = 'processing') from notifications
                       where user_id in (u1, u2) and title = 't'), 'claimed rows marked processing with pushed_at');

  -- ikinci çağrı aynı satırları tekrar vermez
  set local role service_role;
  select count(*)::int into rows from push_claim_batch(50);
  perform tests.eq(rows, 0, 'claimed rows not returned twice');
  reset role;

  -- claim sonucu tokens + prefs + günlük sayaç içerir
  update notifications set pushed_at = null, push_status = null where title = 't';
  set local role service_role;
  select * into rec from push_claim_batch(50) where user_id = u1;
  perform tests.eq(array_length(rec.tokens, 1), 2, 'claim returns all device tokens of user');
  perform tests.eq(rec.need_food_pushed_today, 2, 'claim returns need_food_nearby pushes sent today');
  perform tests.eq(rec.quiet_start, 22::smallint, 'claim returns quiet_start default 22');
  perform tests.eq(rec.quiet_end, 7::smallint, 'claim returns quiet_end default 7');
  perform push_complete(array[rec.id], 'quiet_hours');
  perform tests.eq(push_drop_tokens(array['aaaaaaaaaaaaaaaa']), 1, 'push_drop_tokens deletes token');
  reset role;
  perform tests.eq((select push_status from notifications where id = rec.id), 'quiet_hours', 'push_complete records status');
  perform tests.eq((select count(*)::int from device_tokens where user_id = u1), 1, 'one token left');
end
$$;

-- pg_cron işleri (pg_cron varsa) ve invoke_push_dispatch (URL/sır yoksa no-op)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform tests.eq((select schedule from cron.job where jobname = 'refresh-spot-status'), '*/15 * * * *', 'cron refresh-spot-status every 15 min');
    perform tests.eq((select schedule from cron.job where jobname = 'push-dispatch'), '* * * * *', 'cron push-dispatch every minute');
  else
    raise notice 'SKIP: pg_cron yok';
  end if;
  perform tests.check(private.invoke_push_dispatch() is null, 'invoke_push_dispatch is a no-op without URL/secret');
  perform tests.check(not exists (select 1 from private.app_settings where key in ('push_dispatch_secret', 'service_role_key')),
                      'no secrets shipped in migrations');
  perform tests.check(length(private.setting('fuzz_salt')) >= 32, 'fuzz_salt generated');
end
$$;

-- Hesap silme (delete-account → auth.admin.deleteUser): kişisel veri silinir, topluluk kaydı anonim kalır
do $$
declare
  u  uuid := tests.make_user('Silinecek');
  o  uuid := tests.make_user('Kalan');
  s  uuid;
  an uuid;
  nd uuid;
  r  jsonb;
begin
  perform tests.login(u);
  perform register_device_token('cccccccccccccccc');
  perform update_notify_center(tests.base_lat() + 2.2, tests.base_lng());
  r := create_spot(tests.base_lat() + 2.2, tests.base_lng(), 'food', 'cat', 'Silinen kullanıcının noktası', null,
                   'https://x.supabase.co/storage/v1/object/public/photos/' || u || '/a.jpg', 'public');
  s := (r->>'spot_id')::uuid;
  perform check_in(s, 'fed', 'full', null, tests.base_lat() + 2.2, tests.base_lng());
  insert into animals (name) values ('Silinenin kedisi') returning id into an;
  nd := create_need(s, an, 'vet', 'normal', 'test', null);
  insert into follows (target_type, target_id) values ('spot', s);
  insert into guardians (spot_id) values (s);
  perform tests.admin();
  insert into notifications (user_id, kind, title, body) values (u, 'thanks_fed', 'a', 'b');
  insert into blocks (user_id, blocked_user_id) values (o, u);

  delete from auth.users where id = u;

  perform tests.check(not exists (select 1 from profiles where id = u), 'profile deleted');
  perform tests.eq((select created_by from spots where id = s), null::uuid, 'spot kept, created_by → null');
  perform tests.eq((select photo_url from spots where id = s), null::text, 'photo_url pointing to deleted folder cleared');
  perform tests.eq((select count(*)::int from checkins where spot_id = s and user_id is null), 1, 'checkin kept, user_id → null');
  perform tests.eq((select created_by from animals where id = an), null::uuid, 'animal kept, created_by → null');
  perform tests.eq((select created_by from needs where id = nd), null::uuid, 'need kept, created_by → null');
  perform tests.eq((select count(*)::int from follows where user_id = u), 0, 'follows deleted');
  perform tests.eq((select count(*)::int from guardians where user_id = u), 0, 'guardians deleted');
  perform tests.eq((select count(*)::int from notifications where user_id = u), 0, 'notifications deleted');
  perform tests.eq((select count(*)::int from device_tokens where user_id = u), 0, 'device tokens deleted');
  perform tests.eq((select count(*)::int from notification_prefs where user_id = u), 0, 'notification prefs (location) deleted');
  perform tests.eq((select count(*)::int from blocks where blocked_user_id = u), 0, 'blocks involving user deleted');
end
$$;

rollback;
