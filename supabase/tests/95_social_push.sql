-- Tanışma: sosyal bildirimler (buluşma, bağlantı, sohbet), hatırlatma cron'u, push_claim_batch yeni sütunları.
begin;

-- Kullanıcının bir türdeki bildirim sayısı (opsiyonel buluşma/sohbet süzgeci)
create function tests.nc(p_user uuid, p_kind notification_kind, p_ref uuid default null)
returns int
language sql
as $$
  select count(*)::int from public.notifications n
  where n.user_id = p_user and n.kind = p_kind
    and (p_ref is null or n.meetup_id = p_ref or n.conversation_id = p_ref)
$$;

-- İki kişi arasında kabul edilmiş bağlantı + bire bir sohbet (admin)
create function tests.connect_pair(p_a uuid, p_b uuid)
returns uuid
language plpgsql
set search_path = public, extensions
as $$
declare
  v_c uuid;
begin
  insert into public.connections (requester_id, addressee_id, status, responded_at)
  values (p_a, p_b, 'accepted', now()) returning id into v_c;
  return private.open_direct_conversation(v_c, p_a, p_b);
end
$$;

-- ---------------------------------------------------------------------------
-- 1) Buluşma: katılım → düzenleyene; iptal → katılımcılara; tercih / engel / çıkarılan / ayrılan
-- ---------------------------------------------------------------------------
do $$
declare
  org  uuid := tests.make_user('Duzenleyen');
  a    uuid := tests.make_user('Katilimci A');
  b    uuid := tests.make_user('Katilimci B');
  c    uuid := tests.make_user('Sessiz C');
  d    uuid := tests.make_user('Cikarilan D');
  e    uuid := tests.make_user('Ayrilan E');
  lat  float8 := tests.base_lat();
  lng  float8 := tests.base_lng();
  u    uuid;
  j    jsonb;
  m    uuid;
  r    record;
begin
  foreach u in array array[org, a, b, c, d, e] loop
    perform tests.login(u); perform give_social_consent();
  end loop;
  perform tests.admin();
  update notification_prefs set social_updates = false where user_id = c;

  perform tests.login(org);
  j := create_meetup('Mama dağıtımı', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m := (j->>'meetup_id')::uuid;
  perform tests.admin();
  perform tests.eq(tests.nc(org, 'meetup_joined'), 0, 'organizer is not notified of own creation');

  foreach u in array array[a, b, c, d, e] loop
    perform tests.login(u); perform join_meetup(m);
  end loop;
  perform tests.login(a); perform join_meetup(m);   -- idempotent: ikinci bildirim yok
  perform tests.admin();
  perform tests.eq(tests.nc(org, 'meetup_joined', m), 5, 'organizer gets one meetup_joined per joiner');
  select * into r from notifications where user_id = org and kind = 'meetup_joined' and actor_id = a;
  perform tests.eq(r.meetup_id, m, 'meetup_joined carries meetup_id');
  perform tests.check(position('Katilimci A' in r.body) > 0 and position('Mama dağıtımı' in r.body) > 0,
                      'meetup_joined body has joiner name and meetup title');
  perform tests.eq(tests.nc(a, 'meetup_joined'), 0, 'joiner gets no meetup_joined');

  -- social_updates = false → organizer'a bildirim yok
  update notification_prefs set social_updates = false where user_id = org;
  perform tests.login(d);
  perform leave_meetup(m); perform join_meetup(m);
  perform tests.admin();
  perform tests.eq(tests.nc(org, 'meetup_joined', m), 5, 'social_updates=false organizer: no new meetup_joined');
  update notification_prefs set social_updates = true where user_id = org;

  -- çıkarılan (d) ve ayrılan (e) iptalde bildirim almaz
  perform tests.login(org);
  perform remove_meetup_participant(m, d);
  perform tests.login(e); perform leave_meetup(m);
  perform tests.eq(tests.nc(d, 'meetup_cancelled'), 0, 'removal itself sends no meetup_cancelled');

  perform tests.login(org);
  perform tests.eq(cancel_meetup(m)->>'status', 'ok', 'cancel ok');
  perform cancel_meetup(m);                          -- idempotent
  perform tests.admin();
  perform tests.eq(tests.nc(a, 'meetup_cancelled', m), 1, 'joined participant A gets one cancel notice');
  perform tests.eq(tests.nc(b, 'meetup_cancelled', m), 1, 'joined participant B gets one cancel notice');
  perform tests.eq(tests.nc(c, 'meetup_cancelled', m), 0, 'social_updates=false participant: no cancel notice');
  perform tests.eq(tests.nc(d, 'meetup_cancelled', m), 0, 'removed participant: no cancel notice');
  perform tests.eq(tests.nc(e, 'meetup_cancelled', m), 0, 'left participant: no cancel notice');
  perform tests.eq(tests.nc(org, 'meetup_cancelled', m), 0, 'organizer gets no cancel notice');
  select * into r from notifications where user_id = a and kind = 'meetup_cancelled';
  perform tests.check(position('Mama dağıtımı' in r.body) > 0, 'cancel body has meetup title');

  -- iptal edilmiş buluşmaya yeni katılım yok → bildirim de yok
  perform tests.login(c); perform tests.eq(join_meetup(m)->>'status', 'cancelled', 'join cancelled → cancelled');
  perform tests.admin();
  perform tests.eq(tests.nc(org, 'meetup_joined', m), 5, 'no meetup_joined for cancelled meetup');
end
$$;

-- engelli çift: düzenleyeni engelleyen katılımcıya iptal bildirimi gitmez
do $$
declare
  org uuid := tests.make_user('Duzenleyen2');
  a   uuid := tests.make_user('Engelleyen');
  b   uuid := tests.make_user('Normal');
  lat float8 := tests.base_lat();
  lng float8 := tests.base_lng();
  u   uuid;
  m   uuid;
begin
  foreach u in array array[org, a, b] loop
    perform tests.login(u); perform give_social_consent();
  end loop;
  perform tests.login(org);
  m := (create_meetup('Engel testi', '', now() + interval '3 hours', 120, 'Moda', lat, lng)->>'meetup_id')::uuid;
  foreach u in array array[a, b] loop
    perform tests.login(u); perform join_meetup(m);
  end loop;
  perform tests.login(a);
  insert into blocks (blocked_user_id) values (org);
  perform tests.login(org);
  perform cancel_meetup(m);
  perform tests.admin();
  perform tests.eq(tests.nc(a, 'meetup_cancelled', m), 0, 'participant who blocked organizer: no cancel notice');
  perform tests.eq(tests.nc(b, 'meetup_cancelled', m), 1, 'other participant still notified');
end
$$;

-- ---------------------------------------------------------------------------
-- 2) Hatırlatma cron'u: 2 saat içinde başlayan aktif buluşmalar, bir kez
-- ---------------------------------------------------------------------------
do $$
declare
  org uuid := tests.make_user('Hatirlatan');
  a   uuid := tests.make_user('Hat A');
  b   uuid := tests.make_user('Hat B (sessiz)');
  c   uuid := tests.make_user('Hat C (cikarilan)');
  lat float8 := tests.base_lat();
  lng float8 := tests.base_lng();
  u   uuid;
  soon uuid;
  far  uuid;
  canc uuid;
  past uuid;
  n   int;
begin
  foreach u in array array[org, a, b, c] loop
    perform tests.login(u); perform give_social_consent();
  end loop;
  perform tests.login(org);
  soon := (create_meetup('Yakında', '', now() + interval '90 minutes', 120, 'Moda', lat, lng)->>'meetup_id')::uuid;
  far  := (create_meetup('Uzakta', '', now() + interval '5 hours', 120, 'Moda', lat, lng)->>'meetup_id')::uuid;
  canc := (create_meetup('İptal', '', now() + interval '100 minutes', 120, 'Moda', lat, lng)->>'meetup_id')::uuid;
  past := (create_meetup('Geçmiş', '', now() + interval '3 hours', 120, 'Moda', lat, lng)->>'meetup_id')::uuid;
  foreach u in array array[a, b, c] loop
    perform tests.login(u);
    perform join_meetup(soon); perform join_meetup(far); perform join_meetup(canc); perform join_meetup(past);
  end loop;
  perform tests.login(org);
  perform remove_meetup_participant(soon, c);
  perform cancel_meetup(canc);
  perform tests.admin();
  update notification_prefs set social_updates = false where user_id = b;
  -- başlamış buluşma: başlangıcı geçmişe çek (kontrol kısıtı süreyi korur)
  update meetups set starts_at = now() - interval '10 minutes', ends_at = now() + interval '110 minutes' where id = past;

  n := private.send_meetup_reminders();
  perform tests.eq(n, 2, 'reminders created: organizer + A for the soon meetup');
  perform tests.eq(tests.nc(org, 'meetup_reminder', soon), 1, 'organizer gets reminder');
  perform tests.eq(tests.nc(a, 'meetup_reminder', soon), 1, 'participant A gets reminder');
  perform tests.eq(tests.nc(b, 'meetup_reminder', soon), 0, 'social_updates=false: no reminder');
  perform tests.eq(tests.nc(c, 'meetup_reminder', soon), 0, 'removed participant: no reminder');
  perform tests.eq((select count(*)::int from notifications where kind = 'meetup_reminder' and meetup_id = far),
                   0, 'meetup > 2h away: no reminder');
  perform tests.eq((select count(*)::int from notifications where kind = 'meetup_reminder' and meetup_id = canc),
                   0, 'cancelled meetup: no reminder');
  perform tests.eq((select count(*)::int from notifications where kind = 'meetup_reminder' and meetup_id = past),
                   0, 'already started meetup: no reminder');

  perform tests.eq(private.send_meetup_reminders(), 0, 'second run: idempotent (no duplicates)');
  perform tests.eq(tests.nc(org, 'meetup_reminder', soon), 1, 'still one reminder after second run');

  -- yaklaşan buluşmaya sonradan katılan, bir sonraki turda hatırlatma alır
  perform tests.login(b);
  perform tests.admin();
  update notification_prefs set social_updates = true where user_id = b;
  perform tests.eq(private.send_meetup_reminders(), 1, 'late social_updates=true participant reminded once');
  select count(*) into n from notifications where kind = 'meetup_reminder' and user_id = b and meetup_id = soon;
  perform tests.eq(n, 1, 'B reminded');

  -- sıradan kullanıcı çağıramaz
  perform tests.login(a);
  begin
    perform private.send_meetup_reminders();
    raise exception 'FAIL: authenticated can call send_meetup_reminders';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot call send_meetup_reminders');
  end;
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- 3) Bağlantılar: istek → alıcı; kabul → isteği atan; red → yok; otomatik kabul; tercih; yeniden istek
-- ---------------------------------------------------------------------------
do $$
declare
  lat float8 := tests.base_lat();
  lng float8 := tests.base_lng();
  a   uuid := tests.make_user('Istek A');
  b   uuid := tests.make_user('Istek B');
  c   uuid := tests.make_user('Istek C');
  d   uuid := tests.make_user('Istek D');
  e   uuid := tests.make_user('Istek E');
  f   uuid := tests.make_user('Sessiz F');
  g   uuid := tests.make_user('Istek G');
  u   uuid;
  j   jsonb;
  r   record;
begin
  foreach u in array array[a, b, c, d, e, f, g] loop
    perform tests.login(u); perform give_social_consent();
    perform update_social_profile(true, '', array['cats']::social_interest[], lat, lng);
  end loop;
  perform tests.admin();
  update notification_prefs set social_updates = false where user_id = f;

  -- A → B: B bir istek bildirimi alır
  perform tests.login(a);
  j := send_connection_request(b, 'Selam');
  perform tests.eq(j->>'status', 'sent', 'A→B sent');
  perform tests.admin();
  perform tests.eq(tests.nc(b, 'connection_request'), 1, 'addressee gets connection_request');
  select * into r from notifications where user_id = b and kind = 'connection_request';
  perform tests.eq(r.actor_id, a, 'connection_request actor = requester');
  perform tests.check(position('Istek A' in r.body) > 0, 'connection_request body has requester name');
  perform tests.eq(tests.nc(a, 'connection_request'), 0, 'requester gets no request notification');

  -- B kabul → A'ya bildirim
  perform tests.login(b);
  perform tests.eq(respond_connection((j->>'request_id')::uuid, true)->>'status', 'accepted', 'B accepts');
  perform tests.admin();
  perform tests.eq(tests.nc(a, 'connection_accepted'), 1, 'requester gets connection_accepted');
  perform tests.eq(tests.nc(b, 'connection_accepted'), 0, 'accepter gets none');
  select * into r from notifications where user_id = a and kind = 'connection_accepted';
  perform tests.eq(r.actor_id, b, 'connection_accepted actor = accepter');

  -- C → D, D reddeder: C'ye bildirim yok
  perform tests.login(c);
  j := send_connection_request(d);
  perform tests.login(d);
  perform tests.eq(respond_connection((j->>'request_id')::uuid, false)->>'status', 'declined', 'D declines');
  perform tests.admin();
  perform tests.eq(tests.nc(c, 'connection_accepted'), 0, 'declined: requester not notified');

  -- E ↔ D... karşılıklı istek: C (zaten reddedilmiş) yerine yeni çift: E → G sonra G → E (otomatik kabul)
  perform tests.login(e);
  perform tests.eq(send_connection_request(g)->>'status', 'sent', 'E→G sent');
  perform tests.login(g);
  perform tests.eq(send_connection_request(e)->>'status', 'auto_accepted', 'G→E auto_accepted');
  perform tests.admin();
  perform tests.eq(tests.nc(g, 'connection_request'), 1, 'G got E''s request');
  perform tests.eq(tests.nc(e, 'connection_accepted'), 1, 'original requester E notified of auto accept');
  perform tests.eq(tests.nc(g, 'connection_accepted'), 0, 'auto-accepter G gets no accepted notice');
  perform tests.eq(tests.nc(e, 'connection_request'), 0, 'E gets no request notification');

  -- social_updates = false → istek bildirimi yok
  perform tests.login(a);
  perform tests.eq(send_connection_request(f)->>'status', 'sent', 'A→F sent');
  perform tests.admin();
  perform tests.eq(tests.nc(f, 'connection_request'), 0, 'social_updates=false: no connection_request');

  -- kaldırılmış bağlantı yeniden istenince yeni bildirim
  perform tests.login(a);
  perform remove_connection(b);
  perform tests.eq(send_connection_request(b)->>'status', 'sent', 'A→B again after removal');
  perform tests.admin();
  perform tests.eq(tests.nc(b, 'connection_request'), 2, 're-request after removal notifies again');

  -- engel: engelli çiftte bildirim üretilmez (yardımcı doğrudan)
  insert into blocks (user_id, blocked_user_id) values (c, a);
  perform tests.eq(private.notify_social(c, a, 'connection_request', 't', 'b'), false, 'blocked pair: notify_social false');
  perform tests.eq(private.notify_social(a, c, 'connection_request', 't', 'b'), false, 'blocked pair (reverse): false');
end
$$;

-- ---------------------------------------------------------------------------
-- 4) Sohbet: alıcı başına, okunmamış varsa yenisi yok; engel / tercih / bekleyen mesaj; okuyunca yeniden
-- ---------------------------------------------------------------------------
do $$
declare
  lat float8 := tests.base_lat();
  lng float8 := tests.base_lng();
  org uuid := tests.make_user('Sohbet Duz');
  a   uuid := tests.make_user('Yazan A');
  b   uuid := tests.make_user('Okuyan B');
  s   uuid := tests.make_user('Sessiz S');
  x   uuid := tests.make_user('Engelleyen X');
  p   uuid := tests.make_user('Direkt P');
  q   uuid := tests.make_user('Direkt Q');
  u   uuid;
  m   uuid;
  mc  uuid;
  dc  uuid;
  j   jsonb;
  r   record;
begin
  foreach u in array array[org, a, b, s, x, p, q] loop
    perform tests.login(u); perform give_social_consent();
  end loop;
  perform tests.login(org);
  j := create_meetup('Sohbet buluşması', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m := (j->>'meetup_id')::uuid; mc := (j->>'conversation_id')::uuid;
  foreach u in array array[a, b, s, x] loop
    perform tests.login(u); perform join_meetup(m);
  end loop;
  perform tests.admin();
  update notification_prefs set social_updates = false where user_id = s;
  perform tests.login(x);
  insert into blocks (blocked_user_id) values (a);   -- ortak buluşmada ikisi de kalır

  perform tests.login(a);
  perform tests.eq(send_chat_message(mc, 'Merhaba herkese')->>'status', 'sent', 'A sends');
  perform tests.eq(send_chat_message(mc, 'İkinci mesaj')->>'status', 'sent', 'A sends again');
  perform tests.admin();
  perform tests.eq(tests.nc(org, 'chat_message', mc), 1, 'organizer: one chat_message for two messages');
  perform tests.eq(tests.nc(b, 'chat_message', mc), 1, 'B: one chat_message for two messages');
  perform tests.eq(tests.nc(a, 'chat_message'), 0, 'author gets none');
  perform tests.eq(tests.nc(s, 'chat_message'), 0, 'social_updates=false: none');
  perform tests.eq(tests.nc(x, 'chat_message'), 0, 'blocker X: none from blocked author');
  select * into r from notifications where user_id = b and kind = 'chat_message';
  perform tests.eq(r.conversation_id, mc, 'chat_message carries conversation_id');
  perform tests.eq(r.actor_id, a, 'chat_message actor = author');
  perform tests.check(position('Yazan A' in r.body) > 0 or position('Yazan A' in r.title) > 0,
                      'chat_message mentions author name');
  perform tests.check(position('Merhaba' in r.body) = 0, 'chat_message does not leak message text');

  -- B okunmamış bildirimi okuyunca yeni mesaj yeni bildirim üretir
  perform tests.login(b);
  perform mark_conversation_read(mc);
  perform tests.login(a);
  perform send_chat_message(mc, 'Üçüncü mesaj');
  perform tests.admin();
  perform tests.eq(tests.nc(b, 'chat_message', mc), 2, 'after reading conversation a new message notifies again');
  perform tests.eq(tests.nc(org, 'chat_message', mc), 1, 'organizer still has the unread one: no duplicate');
  -- bildirimi doğrudan okundu yapmak da yeniden üretmeyi açar
  update notifications set read_at = now() where user_id = org and kind = 'chat_message';
  perform tests.login(a);
  perform send_chat_message(mc, 'Dördüncü mesaj');
  perform tests.admin();
  perform tests.eq(tests.nc(org, 'chat_message', mc), 2, 'read notification → next message notifies');

  -- bekleyen (moderasyon) mesaj bildirim üretmez
  update notifications set read_at = now() where kind = 'chat_message';
  insert into chat_messages (conversation_id, author_id, body, moderation_state) values (mc, a, 'bekleyen', 'pending');
  perform tests.eq(tests.nc(b, 'chat_message', mc), 2, 'pending message: no notification');
  insert into chat_messages (conversation_id, author_id, body) values (mc, a, 'onaylı');
  perform tests.eq(tests.nc(b, 'chat_message', mc), 3, 'approved direct insert notifies');

  -- iptal edilmiş buluşmanın sohbetinde (salt okunur) bildirim yok
  perform tests.login(org); perform cancel_meetup(m);
  perform tests.admin();
  update notifications set read_at = now() where kind = 'chat_message';
  insert into chat_messages (conversation_id, author_id, body) values (mc, a, 'iptal sonrası');
  perform tests.eq(tests.nc(b, 'chat_message', mc), 3, 'cancelled meetup chat: no notification');

  -- bire bir sohbet
  dc := tests.connect_pair(p, q);
  perform tests.login(p);
  perform send_chat_message(dc, 'Selam Q');
  perform tests.admin();
  perform tests.eq(tests.nc(q, 'chat_message', dc), 1, 'direct: recipient notified');
  perform tests.eq(tests.nc(p, 'chat_message', dc), 0, 'direct: author not notified');
end
$$;

-- ---------------------------------------------------------------------------
-- 5) push_claim_batch yeni sütunları + yetki
-- ---------------------------------------------------------------------------
do $$
declare
  u    uuid := tests.make_user('Push Alici');
  v    uuid := tests.make_user('Push Gonderen');
  m    uuid;
  conv uuid;
  lat  float8 := tests.base_lat();
  lng  float8 := tests.base_lng();
  rec  record;
  j    jsonb;
begin
  perform tests.login(u); perform give_social_consent();
  perform tests.login(v); perform give_social_consent();
  perform tests.login(u);
  perform register_device_token(repeat('a9', 16), 'sandbox');
  perform tests.login(v);
  perform register_device_token(repeat('b9', 16));
  perform tests.login(u);
  j := create_meetup('Push buluşması', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m := (j->>'meetup_id')::uuid; conv := (j->>'conversation_id')::uuid;
  perform tests.login(v); perform join_meetup(m);
  perform tests.admin();
  update notifications set pushed_at = now(), push_status = 'sent' where pushed_at is null and user_id not in (u);
  update notifications set pushed_at = now(), push_status = 'sent' where pushed_at is null and kind <> 'meetup_joined';

  set local role service_role;
  select * into rec from push_claim_batch(50) where user_id = u and kind = 'meetup_joined';
  reset role;
  perform tests.eq(rec.meetup_id, m, 'push_claim_batch returns meetup_id');
  perform tests.check(rec.conversation_id is null, 'meetup_joined has no conversation_id');
  perform tests.eq(rec.sandbox_tokens, array[repeat('a9', 16)], 'push_claim_batch keeps sandbox_tokens');

  perform tests.login(v);
  perform send_chat_message(conv, 'Merhaba');
  perform tests.admin();
  update notifications set pushed_at = now(), push_status = 'sent' where pushed_at is null and kind <> 'chat_message';
  set local role service_role;
  select * into rec from push_claim_batch(50) where user_id = u and kind = 'chat_message';
  reset role;
  perform tests.eq(rec.conversation_id, conv, 'push_claim_batch returns conversation_id');
  perform tests.check(rec.meetup_id is null, 'chat_message has no meetup_id');
  perform tests.eq(rec.need_food_pushed_today, 0, 'need_food counter unaffected by social kinds');

  -- yetki: yalnızca service_role
  perform tests.login(u);
  begin
    perform push_claim_batch(1);
    raise exception 'FAIL: authenticated can call push_claim_batch';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot call push_claim_batch');
  end;
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- 6) Realtime: realtime.send yoksa (yerel imaj) tetikleyici hiçbir şey yapmaz; varsa politika ve tetikleyici kurulur
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    perform tests.check(not exists (select 1 from pg_trigger where tgname = 'chat_messages_realtime'),
                        'no realtime.send: no broadcast trigger installed');
  else
    perform tests.check(exists (select 1 from pg_trigger where tgname = 'chat_messages_realtime'),
                        'realtime.send present: broadcast trigger installed');
  end if;
end
$$;

rollback;
