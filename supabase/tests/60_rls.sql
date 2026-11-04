-- RLS / tablo yetkileri (docs/backend-contract.md "Doğrudan tablo erişimi")
begin;

-- spots, checkins, needs, spot_gone_reports, donation_events: anon ve authenticated için doğrudan erişim yok
do $$
declare
  u   uuid := tests.make_user('RLS');
  t   text;
  rl  text;
begin
  foreach rl in array array['anon', 'authenticated'] loop
    foreach t in array array['spots', 'checkins', 'needs', 'spot_gone_reports', 'donation_events'] loop
      if rl = 'anon' then perform tests.anon(); else perform tests.login(u); end if;
      begin
        execute format('select * from public.%I limit 1', t);
        raise exception 'FAIL: % can select %', rl, t;
      exception when insufficient_privilege then
        perform tests.check(true, format('%s cannot select * from %s', rl, t));
      end;
      perform tests.admin();
    end loop;
  end loop;

  perform tests.login(u);
  begin
    insert into public.spots (location, title) values (private.make_point(40, 29), 'x');
    raise exception 'FAIL: direct spot insert allowed';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot insert spots directly');
  end;
  begin
    insert into public.notifications (user_id, kind, title, body) values (u, 'thanks_fed', 'x', 'y');
    raise exception 'FAIL: notification insert allowed';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot insert notifications');
  end;
  begin
    perform private.fuzz_point(gen_random_uuid(), null);
    raise exception 'FAIL: private.fuzz_point callable';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot call private.fuzz_point');
  end;
  begin
    perform refresh_spot_statuses();
    raise exception 'FAIL: refresh_spot_statuses callable';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot call refresh_spot_statuses');
  end;
  begin
    perform * from push_claim_batch(1);
    raise exception 'FAIL: push_claim_batch callable';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot call push_claim_batch');
  end;
  perform tests.admin();

  perform tests.anon();
  begin
    perform * from spot_detail(gen_random_uuid());
    raise exception 'FAIL: anon spot_detail';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot call spot_detail (contract: not "anon OK")');
  end;
  begin
    perform create_spot(40, 29, 'food', 'cat', 'x', null, null, 'public');
    raise exception 'FAIL: anon create_spot';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot call create_spot');
  end;
  perform log_donation_click('ANON-REF');
  perform tests.check(true, 'anon can call log_donation_click');
  perform tests.eq((select month from donation_overview()), date_trunc('month', (now() at time zone 'Europe/Istanbul'))::date,
                   'anon donation_overview returns current Istanbul month');
  perform tests.admin();
  perform tests.eq((select count(*)::int from donation_events where ref_code = 'ANON-REF' and user_id is null), 1,
                   'anon donation click logged without user');
end
$$;

-- Kişisel tablolar: başkasınınkini göremez
do $$
declare
  a  uuid := tests.make_user('A');
  b  uuid := tests.make_user('B');
  s  uuid := tests.make_spot(tests.base_lat() + 1.0, tests.base_lng(), 'rls spot', 'public');
  n  int;
begin
  insert into follows (user_id, target_type, target_id) values (a, 'spot', s);
  insert into notifications (user_id, kind, title, body) values (a, 'thanks_fed', 'A için', 'gizli');
  insert into blocks (user_id, blocked_user_id) values (a, b);
  insert into device_tokens (token, user_id) values ('token-of-user-a', a);

  perform tests.login(b);
  perform tests.eq((select count(*)::int from follows), 0, 'B cannot read A''s follows');
  perform tests.eq((select count(*)::int from notifications), 0, 'B cannot read A''s notifications');
  perform tests.eq((select count(*)::int from blocks), 0, 'B cannot read A''s blocks');
  perform tests.eq((select count(*)::int from device_tokens), 0, 'B cannot read A''s device tokens');
  perform tests.eq((select count(*)::int from notification_prefs), 1, 'B reads only own notification_prefs');
  update notifications set read_at = now() where user_id = a;
  get diagnostics n = row_count;
  perform tests.eq(n, 0, 'B cannot mark A''s notification read');
  delete from follows where user_id = a;
  get diagnostics n = row_count;
  perform tests.eq(n, 0, 'B cannot delete A''s follows');
  begin
    insert into follows (user_id, target_type, target_id) values (a, 'spot', s);
    raise exception 'FAIL: B inserted follow for A';
  exception when insufficient_privilege then
    perform tests.check(true, 'B cannot insert follow as A (RLS)');
  end;

  perform tests.login(a);
  perform tests.eq((select count(*)::int from follows), 1, 'A reads own follows');
  perform tests.eq((select count(*)::int from notifications), 1, 'A reads own notifications');
  update notifications set read_at = now();
  get diagnostics n = row_count;
  perform tests.eq(n, 1, 'A marks own notification read');
  begin
    update notifications set title = 'hack';
    raise exception 'FAIL: notification title updatable';
  exception when insufficient_privilege then
    perform tests.check(true, 'notifications: only read_at is updatable');
  end;
  insert into follows (target_type, target_id) values ('animal', gen_random_uuid());
  perform tests.eq((select count(*)::int from follows), 2, 'follows.user_id defaults to auth.uid()');
  perform tests.admin();
end
$$;

-- profiles: herkes okur; kendi adını günceller; trust/verified/moderator güncellenemez
do $$
declare
  a uuid := tests.make_user('Profil A');
  b uuid := tests.make_user('Profil B');
  n int;
begin
  perform tests.eq((select count(*)::int from notification_prefs where user_id = a), 1, 'auth.users insert creates notification_prefs');
  perform tests.eq((select display_name from profiles where id = a), 'Profil A', 'auth.users insert creates profile from metadata');

  perform tests.anon();
  perform tests.check((select count(*) from profiles) >= 2, 'anon can read profiles');
  perform tests.login(a);
  update profiles set display_name = 'Yeni Ad' where id = a;
  get diagnostics n = row_count;
  perform tests.eq(n, 1, 'user updates own display_name');
  update profiles set display_name = 'Ele geçirildi' where id = b;
  get diagnostics n = row_count;
  perform tests.eq(n, 0, 'user cannot update another profile');
  begin
    update profiles set trust_score = 999 where id = a;
    raise exception 'FAIL: trust_score updatable';
  exception when insufficient_privilege then
    perform tests.check(true, 'user cannot update own trust_score');
  end;
  begin
    update profiles set is_verified_feeder = true, is_moderator = true where id = a;
    raise exception 'FAIL: flags updatable';
  exception when insufficient_privilege then
    perform tests.check(true, 'user cannot set is_verified_feeder / is_moderator');
  end;
  begin
    update profiles set display_name = 'amk' where id = a;
    raise exception 'FAIL: profane display_name accepted';
  exception when raise_exception then
    perform tests.check(sqlerrm = 'rejected_content', 'profane display_name → rejected_content');
  end;
  perform tests.admin();
end
$$;

-- animals: herkes okur; giriş yapmış ekler; oluşturan veya doğrulanmış besleyici günceller
do $$
declare
  a  uuid := tests.make_user('Hayvan A');
  b  uuid := tests.make_user('Hayvan B');
  v  uuid := tests.make_user('Hayvan V', 30, true);
  an uuid;
  n  int;
begin
  perform tests.login(a);
  insert into animals (name, species) values ('Test Pamuk', 'cat') returning id into an;
  perform tests.eq((select created_by from animals where id = an), a, 'animals.created_by defaults to auth.uid()');
  begin
    insert into animals (name, created_by) values ('Sahte', b);
    raise exception 'FAIL: animal inserted for another user';
  exception when insufficient_privilege then
    perform tests.check(true, 'cannot insert animal with created_by = other');
  end;
  perform tests.login(b);
  update animals set about = 'b değiştirdi' where id = an;
  get diagnostics n = row_count;
  perform tests.eq(n, 0, 'non-owner cannot update animal');
  perform tests.login(v);
  update animals set about = 'doğrulanmış besleyici güncelledi' where id = an;
  get diagnostics n = row_count;
  perform tests.eq(n, 1, 'verified feeder can update animal');
  perform tests.anon();
  perform tests.eq((select about from animals where id = an), 'doğrulanmış besleyici güncelledi', 'anon can read animals');
  perform tests.admin();
end
$$;

-- guardians: public noktaya herkes; fuzzed/private noktaya ancak kanıtla (PRD 9.1 koruması)
do $$
declare
  u    uuid := tests.make_user('Koruyucu adayı');
  s1   uuid := tests.make_spot(tests.base_lat() + 1.1, tests.base_lng(), 'pub g', 'public');
  s2   uuid := tests.make_spot(tests.base_lat() + 1.2, tests.base_lng(), 'fuz g', 'fuzzed');
  s3   uuid := tests.make_spot(tests.base_lat() + 1.3, tests.base_lng(), 'fuz g2', 'fuzzed');
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m) values (s3, u, 'fed', 12);
  perform tests.login(u);
  insert into guardians (spot_id, schedule) values (s1, '{1,3}');
  perform tests.check(true, 'can become guardian of public spot');
  begin
    insert into guardians (spot_id) values (s2);
    raise exception 'FAIL: guardian of fuzzed spot without proof';
  exception when insufficient_privilege then
    perform tests.check(true, 'cannot self-assign guardian of fuzzed spot without a verified check-in');
  end;
  insert into guardians (spot_id) values (s3);
  perform tests.check(true, 'can become guardian of fuzzed spot after verified check-in');
  perform tests.eq((select count(*)::int from spot_guardians(s1)), 1, 'spot_guardians lists guardian');
  delete from guardians where spot_id = s1;
  perform tests.eq((select count(*)::int from spot_guardians(s1)), 0, 'guardian removes self');
  perform tests.admin();
end
$$;

-- reports: kendi adına ekler, yalnızca moderatör okur
do $$
declare
  u   uuid := tests.make_user('Şikayetçi');
  m   uuid := tests.make_user('Moderatör', 50, false, true);
begin
  perform tests.login(u);
  insert into reports (target_type, target_id, reason, details) values ('spot', gen_random_uuid(), 'spam', 'reklam');
  perform tests.eq((select count(*)::int from reports), 0, 'reporter cannot read reports');
  perform tests.login(m);
  perform tests.eq((select count(*)::int from reports where reporter_id = u), 1, 'moderator reads reports');
  update reports set status = 'actioned', resolved_at = now() where reporter_id = u;
  perform tests.admin();
  perform tests.eq((select status from reports where reporter_id = u), 'actioned'::report_status, 'moderator updates report');
end
$$;

-- storage: yalnızca kendi klasörüne yükleme
do $$
declare
  u uuid := tests.make_user('Fotoğrafçı');
  o uuid := tests.make_user('Başkası');
begin
  perform tests.check(exists (select 1 from storage.buckets where id = 'photos'), 'photos bucket exists');
  if exists (select 1 from information_schema.columns
             where table_schema = 'storage' and table_name = 'buckets' and column_name = 'public') then
    perform tests.check((select (to_jsonb(b) ->> 'public')::boolean from storage.buckets b where id = 'photos'), 'photos bucket is public');
  end if;
  perform tests.login(u);
  insert into storage.objects (bucket_id, name, owner) values ('photos', u::text || '/' || gen_random_uuid() || '.jpg', u);
  perform tests.check(true, 'user uploads into own folder');
  begin
    insert into storage.objects (bucket_id, name, owner) values ('photos', o::text || '/x.jpg', u);
    raise exception 'FAIL: upload into other folder';
  exception when insufficient_privilege then
    perform tests.check(true, 'user cannot upload into another user''s folder');
  end;
  begin
    insert into storage.objects (bucket_id, name, owner) values ('photos', 'x.jpg', u);
    raise exception 'FAIL: upload into bucket root';
  exception when insufficient_privilege then
    perform tests.check(true, 'user cannot upload into bucket root');
  end;
  perform tests.anon();
  begin
    insert into storage.objects (bucket_id, name) values ('photos', 'anon/x.jpg');
    raise exception 'FAIL: anon upload';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot upload');
  end;
  perform tests.admin();
end
$$;

rollback;
