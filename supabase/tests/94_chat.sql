-- Tanışma: sohbet RPC'leri, engelleme ve hesap silme kancaları, mesaj saklama süresi.
begin;

-- Test yardımcısı: iki kişi arasında kabul edilmiş bağlantı + bire bir sohbet (admin)
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
-- 1) Gönderme kuralları, okunmamış, sayfalama, rapor ile gizleme
-- ---------------------------------------------------------------------------
do $$
declare
  org   uuid := tests.make_user('Duzenleyen');
  a     uuid := tests.make_user('Katilimci A');
  b     uuid := tests.make_user('Katilimci B');
  d     uuid := tests.make_user('Cok yazan');
  rep   uuid := tests.make_user('Raporlayan');
  outs  uuid := tests.make_user('Disaridaki');
  nc    uuid := tests.make_user('Onaysiz');
  lat   float8 := tests.base_lat();
  lng   float8 := tests.base_lng();
  u     uuid;
  j     jsonb;
  m1    uuid;
  m2    uuid;
  m3    uuid;
  c1    uuid;
  c2    uuid;
  c3    uuid;
  msg   uuid;
  i     int;
  r     record;
begin
  foreach u in array array[org, a, b, d, rep, outs] loop
    perform tests.login(u); perform give_social_consent();
  end loop;

  perform tests.login(org);
  j := create_meetup('Mama dağıtımı', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m1 := (j->>'meetup_id')::uuid; c1 := (j->>'conversation_id')::uuid;
  j := create_meetup('İkinci buluşma', '', now() + interval '4 hours', 120, 'Moda', lat, lng);
  m2 := (j->>'meetup_id')::uuid; c2 := (j->>'conversation_id')::uuid;
  j := create_meetup('Bitmiş buluşma', '', now() + interval '5 hours', 120, 'Moda', lat, lng);
  m3 := (j->>'meetup_id')::uuid; c3 := (j->>'conversation_id')::uuid;
  foreach u in array array[a, b, d] loop
    perform tests.login(u); perform join_meetup(m1); perform join_meetup(m2); perform join_meetup(m3);
  end loop;

  -- üyelik ve onay
  perform tests.login(outs);
  perform tests.eq(send_chat_message(c1, 'Merhaba')->>'status', 'not_member', 'non-member send → not_member');
  perform tests.eq((select count(*)::int from conversation_messages(c1)), 0, 'non-member reads 0 messages');
  perform tests.eq((select count(*)::int from my_conversations()), 0, 'non-member lists nothing');
  perform tests.eq(send_chat_message(gen_random_uuid(), 'Merhaba')->>'status', 'not_member', 'unknown conversation → not_member');
  perform tests.login(nc);
  perform tests.eq(send_chat_message(c1, 'Merhaba')->>'status', 'consent_required', 'unconsented send → consent_required');
  perform tests.eq((select count(*)::int from my_conversations()), 0, 'unconsented lists nothing');

  -- içerik doğrulama
  perform tests.login(a);
  j := send_chat_message(c1, '   ');
  perform tests.eq(j->>'status', 'invalid', 'blank → invalid');
  perform tests.eq(j->>'reason', 'body_empty', 'blank → body_empty');
  perform tests.eq(send_chat_message(c1, null)->>'reason', 'body_empty', 'null → body_empty');
  perform tests.eq(send_chat_message(c1, repeat('a', 1001))->>'reason', 'body_too_long', '1001 chars → body_too_long');
  perform tests.eq(send_chat_message(c1, 'siktir git')->>'status', 'rejected_content', 'profanity → rejected_content');

  -- gönderim
  j := send_chat_message(c1, '  ' || repeat('a', 1000) || '  ');
  perform tests.eq(j->>'status', 'sent', '1000 chars (trimmed) → sent');
  perform tests.check(j->>'message_id' is not null and j->>'created_at' is not null, 'sent returns id and created_at');
  perform tests.admin();
  perform tests.eq((select char_length(body) from chat_messages where id = (j->>'message_id')::uuid), 1000, 'body stored trimmed');

  -- hız sınırı: sohbet başına dakikada 20
  perform tests.login(a);
  for i in 2..20 loop
    perform tests.eq(send_chat_message(c1, 'Mesaj ' || i)->>'status', 'sent', 'a msg ' || i || ' sent');
  end loop;
  perform tests.eq(send_chat_message(c1, 'Mesaj 21')->>'status', 'rate_limited', '21st message in a minute → rate_limited');
  perform tests.eq(send_chat_message(c2, 'Başka sohbet')->>'status', 'sent', 'other conversation not limited');
  -- bir dakikadan eski mesajlar sayılmaz
  perform tests.admin();
  update chat_messages set created_at = now() - interval '61 seconds' where conversation_id = c1 and author_id = a;
  perform tests.login(a);
  perform tests.eq(send_chat_message(c1, 'Yeni dakika')->>'status', 'sent', 'older than a minute → not counted');

  -- hız sınırı: kullanıcı başına günde 500 (İstanbul günü)
  perform tests.admin();
  insert into chat_messages (conversation_id, author_id, body, created_at)
  select c2, d, 'eski ' || g, private.istanbul_day_start() from generate_series(1, 500) g;
  perform tests.login(d);
  perform tests.eq(send_chat_message(c1, 'Bugün 501.')->>'status', 'rate_limited', '501st message today → rate_limited');
  perform tests.admin();
  update chat_messages set created_at = private.istanbul_day_start() - interval '1 second'
   where conversation_id = c2 and author_id = d;
  perform tests.login(d);
  perform tests.eq(send_chat_message(c1, 'Dünkü sayılmaz')->>'status', 'sent', 'yesterday''s messages not counted');
  perform tests.admin();
  delete from chat_messages where author_id = d;

  -- salt okunur: bitişten 25 saat sonra; 23 saat sonra hâlâ yazılabilir; iptal edilince
  perform tests.admin();
  update meetups set starts_at = now() - interval '25 hours', ends_at = now() - interval '23 hours' where id = m3;
  perform tests.login(a);
  perform tests.eq(send_chat_message(c3, 'Teşekkürler')->>'status', 'sent', '23h after end → still writable');
  perform tests.eq((select read_only from my_conversations() where conversation_id = c3), false, '23h after end → read_only false');
  perform tests.admin();
  update meetups set starts_at = now() - interval '27 hours', ends_at = now() - interval '25 hours' where id = m3;
  perform tests.login(a);
  perform tests.eq(send_chat_message(c3, 'Geç kaldım')->>'status', 'read_only', '25h after end → read_only');
  perform tests.eq((select read_only from my_conversations() where conversation_id = c3), true, '25h after end → listed read_only');
  perform tests.eq((select count(*)::int from conversation_messages(c3)), 1, 'read_only conversation still readable');
  -- read_only, içerik kontrolünden önce
  perform tests.eq(send_chat_message(c3, '')->>'status', 'read_only', 'read_only checked before body');
  -- closed_at
  perform tests.admin();
  update conversations set closed_at = now() where id = c2;
  perform tests.login(a);
  perform tests.eq(send_chat_message(c2, 'Kapalı')->>'status', 'read_only', 'closed_at → read_only');
  perform tests.admin();
  update conversations set closed_at = null where id = c2;

  -- liste: başlık, son mesaj, sıra
  perform tests.login(org);
  perform tests.eq(send_chat_message(c1, 'Düzenleyenden')->>'status', 'sent', 'organizer sends');
  perform tests.admin();
  update chat_messages set created_at = now() - interval '10 minutes' where conversation_id in (c2, c3);
  update chat_messages set created_at = now() - interval '1 second' where conversation_id = c1 and body = 'Yeni dakika';
  perform tests.login(b);
  perform tests.eq((select count(*)::int from my_conversations()), 3, 'b lists 3 meetup conversations');
  select * into r from my_conversations() limit 1;
  perform tests.eq(r.conversation_id, c1, 'most recent conversation first');
  perform tests.eq(r.kind::text, 'meetup', 'kind meetup');
  perform tests.eq(r.title, 'Mama dağıtımı', 'title = meetup title');
  perform tests.eq(r.meetup_id, m1, 'meetup_id returned');
  perform tests.check(r.other_user_id is null, 'meetup: other_user_id null');
  perform tests.eq(r.last_body, 'Düzenleyenden', 'last_body is latest message');
  perform tests.eq(r.read_only, false, 'active meetup not read_only');

  -- okunmamış: b'nin son okuması 1 saat önce → a'nın 21 + düzenleyenin 1 mesajı
  perform tests.admin();
  update conversation_members set last_read_at = now() - interval '1 hour' where conversation_id = c1;
  perform tests.login(b);
  perform tests.eq((select unread from my_conversations() where conversation_id = c1), 22, 'b unread 22');
  perform tests.login(a);
  perform tests.eq((select unread from my_conversations() where conversation_id = c1), 1, 'own messages not unread');
  perform tests.login(b);
  perform mark_conversation_read(c1);
  perform tests.eq((select unread from my_conversations() where conversation_id = c1), 0, 'after mark_conversation_read → 0');
  perform tests.login(a);
  perform tests.eq((select unread from my_conversations() where conversation_id = c1), 1, 'mark is per member');
  perform tests.login(outs);
  perform mark_conversation_read(c1);  -- üye değil: hiçbir şey yapmaz
  perform tests.admin();
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = c1 and user_id = outs), 0,
                   'mark by non-member creates nothing');

  -- sayfalama: eskiden yeniye, p_before ile geriye
  perform tests.admin();
  update chat_messages cm set created_at = now() - make_interval(secs => 100 - x.rn)
    from (select id, row_number() over (order by created_at, (author_id = org), id) as rn from chat_messages where conversation_id = c1) x
   where cm.id = x.id;
  perform tests.login(b);
  perform tests.eq((select count(*)::int from conversation_messages(c1)), 22, 'b reads 22 messages');
  perform tests.eq((select count(*)::int from conversation_messages(c1, null, 5)), 5, 'max_rows 5');
  perform tests.eq((select body from conversation_messages(c1, null, 5) offset 4 limit 1), 'Düzenleyenden', 'page ends with newest');
  perform tests.check((select bool_and(x.ok) from (
      select created_at >= lag(created_at) over (order by created_at) is not false as ok
      from conversation_messages(c1)) x), 'ordered oldest → newest');
  perform tests.eq((select count(*)::int from conversation_messages(c1,
      (select min(created_at) from conversation_messages(c1, null, 5)), 50)), 17, 'p_before pages backwards');
  select * into r from conversation_messages(c1, null, 1);
  perform tests.eq(r.author_id, org, 'author_id');
  perform tests.eq(r.author_name, 'Duzenleyen', 'author_name');
  perform tests.eq(r.is_pending, false, 'approved → is_pending false');

  -- 3 farklı rapor → pending: yalnızca yazarına görünür
  msg := (select id from conversation_messages(c1) where body = 'Mesaj 5');
  foreach u in array array[b, rep] loop
    perform tests.login(u);
    insert into reports (target_type, target_id, reason) values ('chat_message', msg, 'harassment');
  end loop;
  perform tests.login(b);
  insert into reports (target_type, target_id, reason) values ('chat_message', msg, 'spam');  -- aynı kişi tekrar
  perform tests.check(exists (select 1 from conversation_messages(c1) where id = msg), '2 distinct reporters → still visible');
  perform tests.login(org);
  insert into reports (target_type, target_id, reason) values ('chat_message', msg, 'harassment');
  perform tests.admin();
  perform tests.eq((select moderation_state::text from chat_messages where id = msg), 'pending', '3 distinct reporters → pending');
  perform tests.login(b);
  perform tests.check(not exists (select 1 from conversation_messages(c1) where id = msg), 'pending hidden from others');
  perform tests.login(org);
  perform tests.check(not exists (select 1 from conversation_messages(c1) where id = msg), 'pending hidden from organizer');
  perform tests.login(a);
  perform tests.eq((select is_pending from conversation_messages(c1) where id = msg), true, 'author sees own pending message');
  -- pending, okunmamış sayısına ve son mesaja girmez
  perform tests.admin();
  update chat_messages set created_at = now() where id = msg;
  update conversation_members set last_read_at = now() - interval '1 second' where conversation_id = c1 and user_id = b;
  perform tests.login(b);
  perform tests.eq((select unread from my_conversations() where conversation_id = c1), 0, 'pending not unread');
  perform tests.eq((select last_body from my_conversations() where conversation_id = c1), 'Düzenleyenden', 'pending not last_body for others');
  perform tests.login(a);
  perform tests.eq((select last_body from my_conversations() where conversation_id = c1), 'Mesaj 5', 'author sees own pending as last');
  -- mahalle raporları bozulmadı: rapor tetikleyicisi diğer hedef türlerinde de çalışır (90_community)

  -- anon yetkisi yok
  perform tests.anon();
  begin
    perform * from my_conversations();
    raise exception 'FAIL: anon executed my_conversations';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute my_conversations');
  end;
  begin
    perform send_chat_message(c1, 'x');
    raise exception 'FAIL: anon executed send_chat_message';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute send_chat_message');
  end;
  perform tests.admin();
  perform tests.eq(has_function_privilege('anon', 'public.conversation_messages(uuid, timestamptz, int)', 'execute'), false, 'anon no conversation_messages');
  perform tests.eq(has_function_privilege('anon', 'public.mark_conversation_read(uuid)', 'execute'), false, 'anon no mark_conversation_read');
  perform tests.eq(has_function_privilege('authenticated', 'public.send_chat_message(uuid, text)', 'execute'), true, 'authenticated can send');
  perform tests.eq(has_function_privilege('authenticated', 'private.purge_old_meetup_messages()', 'execute'), false, 'authenticated cannot purge');
end
$$;

-- ---------------------------------------------------------------------------
-- 2) Engelleme (Review Focus 3)
-- ---------------------------------------------------------------------------
select tests.admin();
do $$
declare
  ua    uuid := tests.make_user('Ayse');
  ub    uuid := tests.make_user('Burak');
  uc    uuid := tests.make_user('Cem');
  org   uuid := tests.make_user('Buluşma sahibi');
  p     uuid := tests.make_user('Katilimci P');
  q     uuid := tests.make_user('Katilimci Q');
  pr    uuid := tests.make_user('Katilimci R');
  lat   float8 := tests.base_lat();
  lng   float8 := tests.base_lng();
  u     uuid;
  j     jsonb;
  dc    uuid;
  req   uuid;
  m1    uuid;
  mc    uuid;
begin
  foreach u in array array[ua, ub, uc, org, p, q, pr] loop
    perform tests.login(u); perform give_social_consent();
  end loop;

  -- bire bir: A ve B bağlı, C'den A'ya bekleyen istek
  perform tests.admin();
  dc := tests.connect_pair(ua, ub);
  insert into connections (requester_id, addressee_id) values (uc, ua) returning id into req;
  perform tests.login(ua);
  perform tests.eq(send_chat_message(dc, 'Selam, yarın besleme var')->>'status', 'sent', 'direct: A sends');
  perform tests.login(ub);
  perform tests.eq(send_chat_message(dc, 'Geliyorum')->>'status', 'sent', 'direct: B sends');
  perform tests.eq((select t.title from my_conversations() t where t.conversation_id = dc), 'Ayse', 'direct title = other user''s name');
  perform tests.eq((select other_user_id from my_conversations() where conversation_id = dc), ua, 'direct other_user_id');
  perform tests.eq((select kind::text from my_conversations() where conversation_id = dc), 'direct', 'kind direct');
  perform tests.check((select meetup_id is null from my_conversations() where conversation_id = dc), 'direct meetup_id null');

  -- A, B'yi ve C'yi engeller (istemci yolu: blocks'a doğrudan insert, RLS)
  perform tests.login(ua);
  insert into blocks (blocked_user_id) values (ub);
  insert into blocks (blocked_user_id) values (uc);
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dc), 'blocker: direct conversation hidden');
  perform tests.eq((select count(*)::int from conversation_messages(dc)), 0, 'blocker: 0 messages');
  perform tests.eq(send_chat_message(dc, 'x')->>'status', 'read_only', 'blocker: send → read_only');
  perform tests.login(ub);
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dc), 'blocked: direct conversation hidden');
  perform tests.eq((select count(*)::int from conversation_messages(dc)), 0, 'blocked: 0 messages');
  perform tests.eq(send_chat_message(dc, 'x')->>'status', 'read_only', 'blocked: send → read_only');
  perform tests.admin();
  perform tests.eq((select status::text from connections c where c.id = (select connection_id from conversations where id = dc)),
                   'removed', 'block → connection removed');
  perform tests.check((select closed_at is not null from conversations where id = dc), 'block → conversation closed');
  perform tests.eq((select count(*)::int from connections where id = req), 0, 'block → pending request deleted');
  -- engel kalksa da bire bir sohbet kapalı ve gizli kalır (bağlantı kaldırıldı)
  delete from blocks where user_id = ua and blocked_user_id = ub;
  perform tests.login(ub);
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dc), 'unblocked: removed connection stays hidden');
  perform tests.eq((select count(*)::int from conversation_messages(dc)), 0, 'unblocked: removed connection 0 messages');

  -- buluşma: düzenleyen P'yi engeller → P çıkarılır; Q, P'yi değil — Q ile düzenleyen değil, P ile Q
  perform tests.login(org);
  j := create_meetup('Kısırlaştırma günü', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m1 := (j->>'meetup_id')::uuid; mc := (j->>'conversation_id')::uuid;
  foreach u in array array[p, q] loop
    perform tests.login(u); perform join_meetup(m1);
    perform tests.eq(send_chat_message(mc, 'Ben de varım')->>'status', 'sent', 'participant sends');
  end loop;
  perform tests.login(org);
  perform tests.eq(send_chat_message(mc, 'Hoş geldiniz')->>'status', 'sent', 'organizer sends');

  -- katılımcılar arası engel (düzenleyen değil): ikisi de kalır, birbirinin mesajı görünmez
  perform tests.login(q);
  insert into blocks (blocked_user_id) values (p);
  perform tests.admin();
  perform tests.eq((select status::text from meetup_participants where meetup_id = m1 and user_id = p), 'joined', 'non-organizer block: P stays');
  perform tests.eq((select status::text from meetup_participants where meetup_id = m1 and user_id = q), 'joined', 'non-organizer block: Q stays');
  perform tests.login(q);
  perform tests.check(exists (select 1 from my_conversations() where conversation_id = mc), 'Q still lists meetup chat');
  perform tests.check(not exists (select 1 from conversation_messages(mc) where author_id = p), 'Q does not see P''s messages');
  perform tests.eq((select count(*)::int from conversation_messages(mc)), 2, 'Q sees own + organizer messages');
  perform tests.login(p);
  perform tests.check(not exists (select 1 from conversation_messages(mc) where author_id = q), 'P does not see Q''s messages');
  perform tests.eq(send_chat_message(mc, 'Hâlâ buradayım')->>'status', 'sent', 'P can still send');
  -- engellenenin son mesajı Q'nun önizlemesinde ve okunmamışında yok
  perform tests.admin();
  update conversation_members set last_read_at = now() - interval '1 hour' where conversation_id = mc;
  update chat_messages set created_at = now() - interval '1 minute' where conversation_id = mc and author_id = org;
  update chat_messages set created_at = now() - interval '2 minutes' where conversation_id = mc and author_id = q;
  perform tests.login(q);
  perform tests.eq((select last_body from my_conversations() where conversation_id = mc), 'Hoş geldiniz', 'blocked author not last_body');
  perform tests.eq((select unread from my_conversations() where conversation_id = mc), 1, 'blocked author not counted in unread');

  -- düzenleyen P'yi engeller → P çıkarılır
  perform tests.login(org);
  insert into blocks (blocked_user_id) values (p);
  perform tests.admin();
  perform tests.eq((select status::text from meetup_participants where meetup_id = m1 and user_id = p), 'removed', 'organizer block → P removed');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = mc and user_id = p), 0, 'P no longer member');
  perform tests.login(p);
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = mc), 'P no longer lists meetup chat');
  perform tests.eq(send_chat_message(mc, 'x')->>'status', 'not_member', 'removed P → not_member');
  perform tests.eq(join_meetup(m1)->>'status', 'not_found', 'P cannot rejoin');

  -- katılımcı Q düzenleyeni engeller → Q buluşmadan leave_meetup gibi ayrılır (buluşma Q'ya gizli, "Ayrıl" yok);
  -- grup sohbeti listeden düşer, diğer katılımcıların mesajları bildirim üretmez
  perform tests.login(pr);
  perform join_meetup(m1);
  perform tests.login(q);
  insert into blocks (blocked_user_id) values (org);
  perform tests.admin();
  perform tests.eq((select count(*)::int from meetup_participants where meetup_id = m1 and user_id = q), 0,
                   'participant blocks organizer → participant row gone (like leave)');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = mc and user_id = q), 0,
                   'participant blocks organizer → no longer member');
  perform tests.eq((select status::text from meetup_participants where meetup_id = m1 and user_id = pr), 'joined',
                   'other participant R unaffected');
  perform tests.login(q);
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = mc),
                      'blocker no longer lists meetup chat');
  perform tests.eq(send_chat_message(mc, 'x')->>'status', 'not_member', 'blocker → not_member');
  perform tests.admin();
  update notifications set read_at = now() where user_id = q and kind = 'chat_message';  -- önceki mesajlardan kalan
  perform tests.login(pr);
  perform tests.eq(send_chat_message(mc, 'Yarın görüşürüz')->>'status', 'sent', 'R sends after Q left');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications
                     where user_id = q and kind = 'chat_message' and conversation_id = mc and read_at is null), 0,
                   'blocker gets no chat_message notification afterwards');
  perform tests.check(exists (select 1 from notifications
                       where user_id = org and kind = 'chat_message' and conversation_id = mc),
                      'sanity: organizer still notified');
  -- engel kalkınca yeniden katılabilir (çıkarılmadı, ayrıldı)
  perform tests.login(q);
  delete from blocks where blocked_user_id = org;
  perform tests.eq(join_meetup(m1)->>'status', 'joined', 'after unblock Q can rejoin');
end
$$;

-- ---------------------------------------------------------------------------
-- 3) Hesap silme (Review Focus 5) ve saklama süresi
-- ---------------------------------------------------------------------------
select tests.admin();
do $$
declare
  ua    uuid := tests.make_user('Kalan');
  ub    uuid := tests.make_user('Silinen');
  ux    uuid := tests.make_user('Kaldirilmis bag');
  od    uuid := tests.make_user('Silinen duzenleyen');
  p     uuid := tests.make_user('Bildirim alan');
  pb    uuid := tests.make_user('Engelli katilimci');
  o2    uuid := tests.make_user('Eski duzenleyen');
  lat   float8 := tests.base_lat();
  lng   float8 := tests.base_lng();
  u     uuid;
  j     jsonb;
  dc    uuid;
  dx    uuid;
  mf    uuid;
  mp    uuid;
  m31   uuid;
  m29   uuid;
  c31   uuid;
  c29   uuid;
  n     int;
  r     record;
begin
  foreach u in array array[ua, ub, ux, od, p, pb, o2] loop
    perform tests.login(u); perform give_social_consent();
  end loop;

  -- bire bir sohbet: B hesabını siler → A için 'Silinmiş kullanıcı', salt okunur
  perform tests.admin();
  dc := tests.connect_pair(ua, ub);
  perform tests.login(ub);
  perform tests.eq(send_chat_message(dc, 'Görüşürüz')->>'status', 'sent', 'B sends before deleting');
  perform tests.login(ua);
  perform tests.eq(send_chat_message(dc, 'Tamam')->>'status', 'sent', 'A sends');
  -- kaldırılmış bağlantı: X silinince sohbet A'ya geri dönmemeli
  perform tests.admin();
  dx := tests.connect_pair(ua, ux);
  perform tests.login(ua);
  perform remove_connection(ux);
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dx), 'removed connection hidden');

  perform tests.admin();
  delete from auth.users where id in (ub, ux);
  perform tests.login(ua);
  select * into r from my_conversations() where conversation_id = dc;
  perform tests.check(r.conversation_id is not null, 'deleted user: conversation kept for A');
  perform tests.eq(r.title, 'Silinmiş kullanıcı', 'deleted user: title');
  perform tests.check(r.other_user_id is null, 'deleted user: other_user_id null');
  perform tests.check(r.other_avatar_url is null, 'deleted user: avatar null');
  perform tests.eq(r.read_only, true, 'deleted user: read_only');
  perform tests.eq(r.last_body, 'Tamam', 'deleted user''s messages gone; A''s remain');
  perform tests.eq((select count(*)::int from conversation_messages(dc)), 1, 'only A''s message remains');
  perform tests.eq(send_chat_message(dc, 'Orada mısın?')->>'status', 'read_only', 'deleted user: send → read_only');
  perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dx), 'removed connection stays hidden after deletion');
  perform tests.admin();
  perform tests.eq((select count(*)::int from conversations where id = dx), 0, 'removed connection conversation purged on deletion');

  -- düzenleyen silinir → gelecek buluşmanın katılımcısına meetup_cancelled; bitmiş buluşma için yok
  perform tests.login(od);
  j := create_meetup('Gelecek buluşma', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  mf := (j->>'meetup_id')::uuid;
  j := create_meetup('Geçmiş buluşma', '', now() + interval '4 hours', 120, 'Moda', lat, lng);
  mp := (j->>'meetup_id')::uuid;
  foreach u in array array[p, pb] loop
    perform tests.login(u); perform join_meetup(mf); perform join_meetup(mp);
  end loop;
  perform tests.login(pb);
  insert into blocks (blocked_user_id) values (od);   -- katılımcı düzenleyeni engelledi: bildirim gitmez
  perform tests.admin();
  update meetups set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = mp;
  delete from auth.users where id = od;
  perform tests.eq((select count(*)::int from meetups where id in (mf, mp)), 0, 'organizer''s meetups deleted');
  perform tests.eq((select count(*)::int from notifications where user_id = p and kind = 'meetup_cancelled'), 1,
                   'participant gets one meetup_cancelled (future meetup only)');
  select * into r from notifications where user_id = p and kind = 'meetup_cancelled';
  perform tests.check(r.meetup_id is null, 'notification meetup_id set null by cascade');
  perform tests.check(r.body like '%Gelecek buluşma%', 'notification names the meetup');
  perform tests.check(r.actor_id is null, 'notification has no actor (survives deletion)');
  perform tests.eq((select count(*)::int from notifications where user_id = pb and kind = 'meetup_cancelled'), 0,
                   'participant who blocked organizer gets none');

  -- saklama: bitişten 31 gün sonra mesajlar silinir, 29 gün sonra kalır; bire bir dokunulmaz
  perform tests.login(o2);
  j := create_meetup('31 gün önce', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m31 := (j->>'meetup_id')::uuid; c31 := (j->>'conversation_id')::uuid;
  j := create_meetup('29 gün önce', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  m29 := (j->>'meetup_id')::uuid; c29 := (j->>'conversation_id')::uuid;
  perform send_chat_message(c31, 'Eski mesaj');
  perform send_chat_message(c29, 'Yeni mesaj');
  perform tests.admin();
  update meetups set starts_at = now() - interval '31 days 2 hours', ends_at = now() - interval '31 days' where id = m31;
  update meetups set starts_at = now() - interval '29 days 2 hours', ends_at = now() - interval '29 days' where id = m29;
  n := private.purge_old_meetup_messages();
  perform tests.check(n >= 1, 'purge returns deleted count');
  perform tests.eq((select count(*)::int from chat_messages where conversation_id = c31), 0, '31-day-old meetup chat emptied');
  perform tests.eq((select count(*)::int from chat_messages where conversation_id = c29), 1, '29-day-old meetup chat kept');
  perform tests.eq((select count(*)::int from chat_messages where conversation_id = dc), 1, 'direct chat untouched');
  perform tests.eq((select count(*)::int from conversations where id = c31), 1, 'conversation row kept');

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform tests.eq((select count(*)::int from cron.job where jobname = 'social-chat-retention'), 1, 'cron social-chat-retention scheduled');
  else
    raise notice 'SKIP: pg_cron yok';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 4) Kaldırılmış bağlantının geçmişi geri görünmez (yeniden istek → geri çekme / engel)
-- ---------------------------------------------------------------------------
select tests.admin();
do $$
declare
  ua   uuid := tests.make_user('Ilk');
  ub   uuid := tests.make_user('Ikinci');
  uc   uuid := tests.make_user('Ucuncu');
  ud   uuid := tests.make_user('Dorduncu');
  lat  float8 := tests.base_lat();
  lng  float8 := tests.base_lng();
  u    uuid;
  j    jsonb;
  dc   uuid;
  dc2  uuid;
  req  uuid;
begin
  foreach u in array array[ua, ub, uc, ud] loop
    perform tests.login(u); perform give_social_consent();
    perform update_social_profile(true, '', array[]::social_interest[], lat, lng);
  end loop;

  -- (a) kaldır → yeniden istek → geri çek
  perform tests.admin();
  dc := tests.connect_pair(ua, ub);
  perform tests.login(ua);
  perform tests.eq(send_chat_message(dc, 'Eski geçmiş')->>'status', 'sent', '(a) history message');
  perform tests.eq(remove_connection(ub)->>'status', 'ok', '(a) A removes connection');
  perform tests.login(ub);
  j := send_connection_request(ua);
  perform tests.eq(j->>'status', 'sent', '(a) B re-requests');
  req := (j->>'request_id')::uuid;
  perform tests.eq(withdraw_connection_request(req)->>'status', 'ok', '(a) B withdraws');
  foreach u in array array[ua, ub] loop
    perform tests.login(u);
    perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dc), '(a) not listed');
    perform tests.eq((select count(*)::int from conversation_messages(dc)), 0, '(a) 0 messages');
    perform tests.eq(send_chat_message(dc, 'x')->>'status', 'not_member', '(a) send → not_member');
  end loop;
  perform tests.admin();
  perform tests.eq((select count(*)::int from conversations where id = dc), 0, '(a) old conversation row gone');
  perform tests.eq((select count(*)::int from chat_messages where conversation_id = dc), 0, '(a) old messages gone');
  -- sonra yeni bağlantı: yeni, boş sohbet
  perform tests.login(ub);
  perform send_connection_request(ua);
  perform tests.login(ua);
  j := send_connection_request(ub);
  perform tests.eq(j->>'status', 'auto_accepted', '(a) reconnect');
  dc2 := (j->>'conversation_id')::uuid;
  perform tests.check(dc2 <> dc, '(a) new conversation');
  perform tests.eq((select count(*)::int from conversation_messages(dc2)), 0, '(a) new conversation has no old history');
  perform tests.eq((select count(*)::int from my_conversations() where kind = 'direct'), 1, '(a) exactly one direct chat listed');

  -- (b) kaldır → yeniden istek → engel → engeli kaldır
  perform tests.admin();
  dc := tests.connect_pair(uc, ud);
  perform tests.login(uc);
  perform tests.eq(send_chat_message(dc, 'Eski geçmiş')->>'status', 'sent', '(b) history message');
  perform remove_connection(ud);
  perform tests.login(ud);
  perform tests.eq(send_connection_request(uc)->>'status', 'sent', '(b) D re-requests');
  perform tests.login(uc);
  insert into blocks (blocked_user_id) values (ud);
  delete from blocks where blocked_user_id = ud;
  foreach u in array array[uc, ud] loop
    perform tests.login(u);
    perform tests.check(not exists (select 1 from my_conversations() where conversation_id = dc), '(b) not listed after unblock');
    perform tests.eq((select count(*)::int from conversation_messages(dc)), 0, '(b) 0 messages after unblock');
  end loop;
  perform tests.admin();
  perform tests.eq((select count(*)::int from conversations where id = dc), 0, '(b) old conversation row gone');
end
$$;

rollback;
