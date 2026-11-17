-- Moderasyon (Faz 3.1): moderatör RPC'leri, kararlar, uzaklaştırma ve yazma yollarının kapanması.
begin;

-- Test yardımcısı: verilen SQL 'suspended' istisnası mı atıyor? (çağıranın rolüyle çalışır)
create function tests.raises_suspended(p_sql text)
returns boolean
language plpgsql
as $$
begin
  execute p_sql;
  return false;
exception when raise_exception then
  return sqlerrm = 'suspended';
end
$$;

-- Test yardımcısı: verilen SQL yetki hatası mı atıyor?
create function tests.denied(p_sql text)
returns boolean
language plpgsql
as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
end
$$;

grant execute on all functions in schema tests to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1) Yetki: moderatör olmayan hiçbir şey göremez/yapamaz; anon çağıramaz; tablolar kapalı
-- ---------------------------------------------------------------------------
do $$
declare
  mod  uuid := tests.make_user('Moderatör', 10, false, true);
  u    uuid := tests.make_user('Sıradan');
  rep  uuid := tests.make_user('Raporlayan');
begin
  perform tests.login(rep);
  insert into reports (reporter_id, target_type, target_id, reason) values (rep, 'user', u, 'spam');

  perform tests.login(u);
  perform tests.eq(moderation_open_count(), 0, 'non-moderator open count → 0');
  perform tests.eq((select count(*)::int from moderation_queue()), 0, 'non-moderator queue → 0 rows');
  perform tests.eq((select count(*)::int from moderation_queue(true)), 0, 'non-moderator closed queue → 0 rows');
  perform tests.eq(moderation_target_reports('user', u)->>'status', 'not_allowed', 'non-moderator target reports → not_allowed');
  perform tests.eq(moderation_decide('user', u, 'approve')->>'status', 'not_allowed', 'non-moderator decide → not_allowed');
  perform tests.eq(moderation_suspend_user(rep, 7, null)->>'status', 'not_allowed', 'non-moderator suspend → not_allowed');
  perform tests.eq(moderation_unsuspend_user(rep)->>'status', 'not_allowed', 'non-moderator unsuspend → not_allowed');
  perform tests.check(tests.denied('select * from public.moderation_actions'), 'authenticated cannot read moderation_actions');
  perform tests.check(tests.denied('select suspended_until from public.profiles'), 'authenticated cannot read profiles.suspended_until');
  perform tests.check((select count(*) from profiles where id = u) = 1, 'public profile columns still readable');
  perform tests.check(tests.denied('update public.profiles set suspended_until = null where id = auth.uid()'),
                      'user cannot clear own suspended_until');
  perform tests.eq((select status::text from reports where target_id = u limit 1), null, 'non-moderator still cannot read reports');

  perform tests.anon();
  perform tests.check(tests.denied('select public.moderation_open_count()'), 'anon cannot call moderation_open_count');
  perform tests.check(tests.denied('select * from public.moderation_queue()'), 'anon cannot call moderation_queue');
  perform tests.check(tests.denied('select public.moderation_decide(''user'', gen_random_uuid(), ''approve'')'),
                      'anon cannot call moderation_decide');
  perform tests.check(tests.denied('select public.moderation_suspend_user(gen_random_uuid(), 7, null)'),
                      'anon cannot call moderation_suspend_user');
  perform tests.check(tests.denied('select suspended_until from public.profiles'), 'anon cannot read profiles.suspended_until');

  -- moderatörlük her çağrıda sunucuda yeniden doğrulanır
  perform tests.login(mod);
  perform tests.eq(moderation_open_count(), 1, 'moderator sees the open case');
  perform tests.admin();
  update profiles set is_moderator = false where id = mod;
  perform tests.login(mod);
  perform tests.eq(moderation_open_count(), 0, 'revoked moderator → 0 immediately');
  perform tests.eq(moderation_decide('user', u, 'approve')->>'status', 'not_allowed', 'revoked moderator decide → not_allowed');

  -- okuma RPC'leri asla yazma kapısından (uzaklaştırma kontrolü) geçmez
  perform tests.admin();
  perform tests.eq((select count(*)::int from pg_proc p
                    where p.pronamespace = 'public'::regnamespace and p.provolatile <> 'v'
                      and p.proname <> 'assert_can_write'
                      and p.prosrc like '%private.require_uid()%'), 0,
                   'no stable/immutable public function calls private.require_uid()');
  delete from reports;
end
$$;

-- ---------------------------------------------------------------------------
-- 2) Kuyruk: hedefe göre gruplama, önizleme, sıra, sohbet gizliliği, detay
-- ---------------------------------------------------------------------------
do $$
declare
  mod    uuid := tests.make_user('Moderatör', 10, false, true);
  author uuid := tests.make_user('Paylaşan');
  chat_a uuid := tests.make_user('Sohbetçi');
  r1     uuid := tests.make_user('Raporcu Bir');
  r2     uuid := tests.make_user('Raporcu İki');
  bad    uuid := tests.make_user('Kaba kullanıcı');
  lat    float8 := tests.base_lat();
  lng    float8 := tests.base_lng();
  post   uuid;
  meet   uuid;
  conv   uuid;
  msg    uuid;
  r      record;
  j      jsonb;
begin
  perform tests.admin();
  insert into community_posts (author_id, kind, body, cell)
  values (author, 'note', repeat('p', 600), private.make_point(lat, lng)) returning id into post;
  insert into meetups (organizer_id, title, starts_at, ends_at, place_name, location)
  values (chat_a, 'Sohbet buluşması', now() + interval '2 hours', now() + interval '3 hours', 'Moda', private.make_point(lat, lng))
  returning id into meet;
  insert into conversations (kind, meetup_id) values ('meetup', meet) returning id into conv;
  insert into conversation_members (conversation_id, user_id) values (conv, chat_a), (conv, r1);
  insert into chat_messages (conversation_id, author_id, body) values (conv, chat_a, 'GİZLİ ÖNCEKİ MESAJ');
  insert into chat_messages (conversation_id, author_id, body, created_at)
  values (conv, chat_a, 'Raporlanan mesaj', now() + interval '1 second') returning id into msg;
  insert into chat_messages (conversation_id, author_id, body, created_at)
  values (conv, r1, 'GİZLİ SONRAKİ MESAJ', now() + interval '2 seconds');

  perform tests.login(r1);
  insert into reports (reporter_id, target_type, target_id, reason, details) values (r1, 'post', post, 'spam', 'Reklam');
  insert into reports (reporter_id, target_type, target_id, reason) values (r1, 'chat_message', msg, 'harassment');
  insert into reports (reporter_id, target_type, target_id, reason) values (r1, 'user', bad, 'harassment');
  perform tests.login(r2);
  insert into reports (reporter_id, target_type, target_id, reason) values (r2, 'post', post, 'inappropriate');
  -- aynı transaction'da now() sabit: sırayı açıkça kur
  perform tests.admin();
  update reports set created_at = now() - interval '2 hours' where target_id = msg;
  update reports set created_at = now() - interval '1 hour' where target_id = bad;

  perform tests.login(mod);
  perform tests.eq(moderation_open_count(), 3, 'open count = distinct open targets');
  perform tests.eq((select count(*)::int from moderation_queue()), 3, 'queue grouped by target (4 reports → 3 rows)');

  select * into r from moderation_queue() limit 1;
  perform tests.eq(r.target_type::text, 'post', 'most reported first');
  perform tests.eq(r.target_id, post, 'post row id');
  perform tests.eq(r.report_count, 2, 'post report_count = 2');
  perform tests.eq(r.owner_id, author, 'post owner id');
  perform tests.eq(r.owner_name, 'Paylaşan', 'post owner name');
  perform tests.eq(char_length(r.body), 300, 'preview body capped at 300');
  perform tests.eq(r.content_state, 'live', 'post state live');
  perform tests.check(r.reasons @> array['spam', 'inappropriate']::report_reason[] and cardinality(r.reasons) = 2,
                      'post reasons = distinct reasons');
  perform tests.check(r.first_reported_at <= r.last_reported_at, 'first ≤ last reported');
  perform tests.eq(r.decision, null, 'open case has no decision');

  -- eşit rapor sayısında en eski önce
  perform tests.eq((select q.target_type::text from moderation_queue() q offset 1 limit 1), 'chat_message',
                   'equal counts → oldest first');

  select * into r from moderation_queue() q where q.target_type = 'chat_message';
  perform tests.eq(r.body, 'Raporlanan mesaj', 'chat preview = only the reported message');
  perform tests.eq(r.owner_id, chat_a, 'chat owner = author');
  select * into r from moderation_queue() q where q.target_type = 'user';
  perform tests.eq(r.owner_id, bad, 'user case owner = reported user');
  perform tests.eq(r.title, 'Kaba kullanıcı', 'user case title = display name');

  -- max_rows
  perform tests.eq((select count(*)::int from moderation_queue(false, 1)), 1, 'max_rows respected');

  -- detay: raporlar + sahip geçmişi; sohbetin geri kalanı yok
  j := moderation_target_reports('chat_message', msg);
  perform tests.eq(j->>'status', 'ok', 'target reports ok');
  perform tests.check(position('GİZLİ' in j::text) = 0, 'detail never contains other messages of the conversation');
  perform tests.eq(j->'case'->>'body', 'Raporlanan mesaj', 'detail case body');

  j := moderation_target_reports('post', post);
  perform tests.eq(jsonb_array_length(j->'reports'), 2, 'detail lists both reports');
  perform tests.check(exists (select 1 from jsonb_array_elements(j->'reports') e
                              where e->>'reporter_name' = 'Raporcu Bir' and e->>'details' = 'Reklam'
                                and e->>'reason' = 'spam' and e->>'status' = 'open'),
                      'report entry: reporter name, details, reason, status');
  perform tests.eq(j->'owner'->>'user_id', author::text, 'owner history user');
  perform tests.eq((j->'owner'->>'removed_count_90d')::int, 0, 'owner removed count 0');
  perform tests.eq((j->'owner'->>'suspension_count_90d')::int, 0, 'owner suspension count 0');
  perform tests.check(j->'owner'->'suspended_until' = 'null'::jsonb, 'owner not suspended');

  perform tests.eq(moderation_target_reports('post', gen_random_uuid())->>'status', 'not_found', 'unreported target → not_found');
  perform tests.admin();
  delete from reports;
end
$$;

-- ---------------------------------------------------------------------------
-- 3) Kararlar: approve / remove her hedef türünde; kayıt; Kapananlar sekmesi
-- ---------------------------------------------------------------------------
do $$
declare
  mod    uuid := tests.make_user('Moderatör', 10, false, true);
  author uuid := tests.make_user('İçerik sahibi');
  viewer uuid := tests.make_user('İzleyen');
  r1     uuid := tests.make_user('R1');
  r2     uuid := tests.make_user('R2');
  r3     uuid := tests.make_user('R3');
  lat    float8 := tests.base_lat();
  lng    float8 := tests.base_lng();
  spot   uuid;
  post   uuid;
  cmt    uuid;
  meet   uuid;
  conv   uuid;
  msg    uuid;
  need   uuid;
  animal uuid;
  ci     uuid;
  u      uuid;
  j      jsonb;
  r      record;
begin
  perform tests.admin();
  spot := tests.make_spot(lat, lng, 'Raporlu nokta', 'public', author);
  insert into community_posts (author_id, kind, body, cell)
  values (author, 'note', 'Raporlu paylaşım', private.make_point(lat, lng)) returning id into post;
  insert into community_comments (post_id, author_id, body) values (post, author, 'Raporlu yorum') returning id into cmt;
  insert into meetups (organizer_id, title, starts_at, ends_at, place_name, location)
  values (author, 'Raporlu buluşma', now() + interval '2 hours', now() + interval '3 hours', 'Moda', private.make_point(lat, lng))
  returning id into meet;
  insert into conversations (kind, meetup_id) values ('meetup', meet) returning id into conv;
  insert into conversation_members (conversation_id, user_id) values (conv, author), (conv, viewer);
  insert into chat_messages (conversation_id, author_id, body) values (conv, author, 'Raporlu mesaj') returning id into msg;
  insert into needs (spot_id, type, description, created_by) values (spot, 'vet', 'Raporlu ihtiyaç', author) returning id into need;
  insert into animals (name, created_by) values ('Raporlu kedi', author) returning id into animal;
  insert into checkins (spot_id, user_id, kind, photo_url) values (spot, author, 'fed', 'https://x.test/a.jpg') returning id into ci;

  -- sohbet mesajı 3 raporla otomatik gizlenir
  foreach u in array array[r1, r2, r3] loop
    perform tests.login(u);
    insert into reports (reporter_id, target_type, target_id, reason) values (u, 'chat_message', msg, 'spam');
  end loop;
  perform tests.login(r1);
  insert into reports (reporter_id, target_type, target_id, reason) values
    (r1, 'spot', spot, 'wrong_location'), (r1, 'post', post, 'spam'), (r1, 'comment', cmt, 'spam'),
    (r1, 'meetup', meet, 'spam'), (r1, 'need', need, 'spam'), (r1, 'animal', animal, 'spam'),
    (r1, 'checkin', ci, 'inappropriate'), (r1, 'user', author, 'harassment');
  perform tests.login(r2);
  insert into reports (reporter_id, target_type, target_id, reason) values (r2, 'post', post, 'spam');

  perform tests.login(mod);
  perform tests.eq((select content_state from moderation_queue() q where q.target_id = msg), 'pending',
                   'auto-hidden message shows pending');

  -- doğrulama
  j := moderation_decide('post', post, 'suspend');
  perform tests.eq(j->>'status', 'invalid', 'decide with suspend → invalid');
  perform tests.eq(j->>'reason', 'action', 'decide invalid action reason');
  perform tests.eq(moderation_decide('post', post, 'remove', repeat('n', 501))->>'reason', 'note_too_long', 'note > 500 → note_too_long');
  perform tests.eq(moderation_decide('post', gen_random_uuid(), 'remove')->>'status', 'not_found', 'unreported target → not_found');
  perform tests.eq((select count(*)::int from reports where target_id = post and status = 'open'), 2, 'invalid decide changed nothing');

  -- paylaşım: kaldır
  j := moderation_decide('post', post, 'remove', '  Reklam  ');
  perform tests.eq(j->>'status', 'ok', 'remove post ok');
  perform tests.eq((j->>'closed_reports')::int, 2, 'remove post closes 2 reports');
  perform tests.admin();
  perform tests.eq((select moderation_state::text from community_posts where id = post), 'rejected', 'removed post → rejected');
  perform tests.eq((select count(*)::int from reports where target_id = post and status = 'actioned' and resolved_at is not null), 2,
                   'post reports → actioned with resolved_at');
  select * into r from moderation_actions where target_id = post;
  perform tests.eq(r.moderator_id, mod, 'action logs moderator');
  perform tests.eq(r.action, 'remove', 'action logs decision');
  perform tests.eq(r.note, 'Reklam', 'action note trimmed');
  perform tests.eq(r.target_type::text, 'post', 'action target type');
  perform tests.login(viewer);
  perform tests.eq((select count(*)::int from community_post_detail(post, lat, lng)), 0, 'removed post hidden from others');
  perform tests.login(author);
  perform tests.eq((select count(*)::int from community_post_detail(post, lat, lng)), 0, 'removed post hidden from author (rejected)');

  perform tests.login(mod);
  perform tests.eq((select count(*)::int from moderation_queue() q where q.target_id = post), 0, 'decided post leaves open tab');
  select * into r from moderation_queue(true) q where q.target_id = post;
  perform tests.eq(r.decision, 'remove', 'closed tab shows decision');
  perform tests.eq(r.content_state, 'removed', 'closed tab state removed');
  perform tests.eq(r.report_count, 2, 'closed tab report count');
  perform tests.check(r.decided_at is not null, 'closed tab decided_at');

  -- yorum, nokta, sohbet mesajı
  perform tests.eq(moderation_decide('comment', cmt, 'remove')->>'status', 'ok', 'remove comment ok');
  perform tests.eq(moderation_decide('spot', spot, 'remove')->>'status', 'ok', 'remove spot ok');
  j := moderation_decide('chat_message', msg, 'approve');
  perform tests.eq((j->>'closed_reports')::int, 3, 'approve message closes 3 reports');
  perform tests.admin();
  perform tests.eq((select moderation_state::text from community_comments where id = cmt), 'rejected', 'removed comment → rejected');
  perform tests.eq((select moderation_state::text from spots where id = spot), 'rejected', 'removed spot → rejected');
  perform tests.eq((select moderation_state::text from chat_messages where id = msg), 'approved', 'approved message → approved again');
  perform tests.eq((select count(*)::int from reports where target_id = msg and status = 'dismissed'), 3, 'approve → reports dismissed');
  perform tests.login(viewer);
  perform give_social_consent();
  perform tests.eq((select count(*)::int from conversation_messages(conv) m where m.id = msg), 1, 'approved message visible again');
  perform tests.eq((select count(*)::int from spot_detail(spot)), 0, 'removed spot hidden');

  -- buluşma: iptal; ihtiyaç ve hayvan: silinir; check-in: fotoğraf temizlenir; kullanıcı: yalnızca raporlar
  perform tests.login(mod);
  perform tests.eq(moderation_decide('meetup', meet, 'remove')->>'status', 'ok', 'remove meetup ok');
  perform tests.eq(moderation_decide('need', need, 'remove')->>'status', 'ok', 'remove need ok');
  perform tests.eq(moderation_decide('animal', animal, 'remove')->>'status', 'ok', 'remove animal ok');
  perform tests.eq(moderation_decide('checkin', ci, 'remove')->>'status', 'ok', 'remove checkin ok');
  perform tests.eq(moderation_decide('user', author, 'remove')->>'status', 'ok', 'remove on user ok');
  perform tests.admin();
  perform tests.eq((select status::text from meetups where id = meet), 'cancelled', 'removed meetup → cancelled');
  perform tests.check((select closed_at is not null from conversations where id = conv), 'removed meetup → conversation closed');
  perform tests.eq((select count(*)::int from needs where id = need), 0, 'removed need → deleted');
  perform tests.eq((select count(*)::int from animals where id = animal), 0, 'removed animal → deleted');
  perform tests.eq((select photo_url from checkins where id = ci), null, 'removed checkin → photo cleared');
  perform tests.check(exists (select 1 from checkins where id = ci), 'checkin row kept');
  perform tests.check(exists (select 1 from profiles where id = author), 'user remove keeps the profile');
  perform tests.eq((select suspended_until from profiles where id = author), null, 'user remove does not suspend');
  perform tests.eq((select target_owner_id from moderation_actions where target_id = need), author, 'action keeps owner of deleted content');

  perform tests.login(mod);
  perform tests.eq(moderation_open_count(), 0, 'all cases decided');
  perform tests.eq((select content_state from moderation_queue(true) q where q.target_id = need), 'removed',
                   'deleted-by-moderator content shows removed');
  perform tests.eq((select content_state from moderation_queue(true) q where q.target_id = msg), 'live', 'approved message live');
  perform tests.eq((select decision from moderation_queue(true) q where q.target_id = msg), 'approve', 'closed tab approve decision');

  -- sahip geçmişi: son 90 gündeki kaldırmalar (kullanıcı raporu sayılmaz)
  perform tests.login(r3);
  insert into reports (reporter_id, target_type, target_id, reason) values (r3, 'user', author, 'spam');
  perform tests.login(mod);
  j := moderation_target_reports('user', author);
  perform tests.eq((j->'owner'->>'removed_count_90d')::int, 7, 'owner removed count (post, comment, spot, meetup, need, animal, checkin)');
  perform tests.eq(jsonb_array_length(j->'reports'), 2, 'user detail lists open and closed reports');
  perform tests.admin();
  update moderation_actions set created_at = now() - interval '91 days' where target_id in (post, cmt);
  perform tests.login(mod);
  perform tests.eq((moderation_target_reports('user', author)->'owner'->>'removed_count_90d')::int, 5, 'older than 90 days not counted');

  -- Kapananlar: son 30 gün
  perform tests.admin();
  update reports set resolved_at = now() - interval '31 days' where target_id = spot;
  perform tests.login(mod);
  perform tests.eq((select count(*)::int from moderation_queue(true) q where q.target_id = spot), 0, 'closed > 30 days ago not listed');
  perform tests.eq((select count(*)::int from moderation_queue(true) q where q.target_id = author), 0,
                   'target with an open report is not in closed tab');
  perform tests.admin();
  delete from reports;
end
$$;

-- ---------------------------------------------------------------------------
-- 4) Uzaklaştırma: yazma yolları kapanır, okuma açık kalır; süre, süresiz, kaldırma
-- ---------------------------------------------------------------------------
do $$
declare
  mod    uuid := tests.make_user('Moderatör', 10, false, true);
  mod2   uuid := tests.make_user('Diğer moderatör', 10, false, true);
  s      uuid := tests.make_user('Uzaklaştırılan');
  other  uuid := tests.make_user('Diğeri');
  lat    float8 := tests.base_lat();
  lng    float8 := tests.base_lng();
  spot   uuid;
  post   uuid;
  meet   uuid;
  conv   uuid;
  animal uuid;
  j      jsonb;
  v_until timestamptz;
begin
  perform tests.admin();
  spot := tests.make_spot(lat, lng, 'Açık nokta', 'public', other);
  insert into community_posts (author_id, kind, body, cell)
  values (other, 'note', 'Bir paylaşım', private.make_point(lat, lng)) returning id into post;
  insert into animals (name, created_by) values ('Kendi kedisi', s) returning id into animal;
  perform tests.login(s); perform give_social_consent();
  perform tests.login(other); perform give_social_consent();
  j := create_meetup('Buluşma', '', now() + interval '3 hours', 60, 'Moda', lat, lng);
  meet := (j->>'meetup_id')::uuid; conv := (j->>'conversation_id')::uuid;
  perform tests.login(s);
  perform tests.eq(join_meetup(meet)->>'status', 'joined', 'join before suspension');

  -- doğrulama
  perform tests.login(mod);
  perform tests.eq(moderation_suspend_user(mod, 7, null)->>'status', 'not_allowed', 'cannot suspend self');
  perform tests.eq(moderation_suspend_user(mod2, 7, null)->>'status', 'not_allowed', 'cannot suspend a moderator');
  perform tests.eq(moderation_suspend_user(gen_random_uuid(), 7, null)->>'status', 'not_found', 'unknown user → not_found');
  j := moderation_suspend_user(s, 10, null);
  perform tests.eq(j->>'status', 'invalid', 'p_days 10 → invalid');
  perform tests.eq(j->>'reason', 'days', 'p_days invalid reason');
  perform tests.eq(moderation_suspend_user(s, 7, repeat('n', 501))->>'reason', 'note_too_long', 'suspend note too long');

  j := moderation_suspend_user(s, 7, 'Taciz');
  perform tests.eq(j->>'status', 'ok', 'suspend 7 days ok');
  perform tests.admin();
  v_until := (select suspended_until from profiles where id = s);
  perform tests.check(v_until between now() + interval '7 days' - interval '1 minute' and now() + interval '7 days' + interval '1 minute',
                      'suspended_until ≈ now + 7 days');
  perform tests.check(exists (select 1 from moderation_actions where target_type = 'user' and target_id = s
                                and action = 'suspend' and suspend_days = 7 and note = 'Taciz' and moderator_id = mod),
                      'suspension logged');

  -- yazma RPC'leri
  perform tests.login(s);
  perform tests.check(tests.raises_suspended(format(
    'select create_spot(%s, %s, ''food'', ''cat'', ''Yeni'', null, null, ''public'', true)', lat + 0.01, lng)), 'create_spot blocked');
  perform tests.check(tests.raises_suspended(format(
    'select check_in(%L, ''fed'', null, null, %s, %s, null)', spot, lat, lng)), 'check_in blocked');
  perform tests.check(tests.raises_suspended(format(
    'select create_community_post(''note'', ''Merhaba'', null, null, null, %s, %s, null, null)', lat, lng)), 'create_community_post blocked');
  perform tests.check(tests.raises_suspended(format('select add_community_comment(%L, ''Yorum'')', post)), 'add_community_comment blocked');
  perform tests.check(tests.raises_suspended(format('select toggle_post_paw(%L)', post)), 'toggle_post_paw blocked');
  perform tests.check(tests.raises_suspended(format('select send_chat_message(%L, ''Selam'')', conv)), 'send_chat_message blocked');
  perform tests.check(tests.raises_suspended(format(
    'select create_meetup(''Yeni buluşma'', '''', now() + interval ''3 hours'', 60, ''Moda'', %s, %s)', lat, lng)), 'create_meetup blocked');
  perform tests.check(tests.raises_suspended(format('select start_feeding_tour(%L, 60)', spot)), 'start_feeding_tour blocked');
  perform tests.check(tests.raises_suspended(format('select send_connection_request(%L, null)', other)), 'send_connection_request blocked');
  perform tests.check(tests.raises_suspended(format(
    'select create_need(%L, null, ''vet'', ''normal'', ''Yardım'', ''{}'')', spot)), 'create_need blocked');
  perform tests.check(tests.raises_suspended(format('select report_spot_gone(%L)', spot)), 'report_spot_gone blocked');
  perform tests.check(tests.raises_suspended('select update_social_profile(true, '''', ''{}'', null, null)'), 'update_social_profile blocked');

  -- doğrudan tablo yazmaları (RLS)
  perform tests.check(tests.raises_suspended('insert into animals (name, created_by) values (''Yeni'', auth.uid())'),
                      'animals insert blocked');
  perform tests.check(tests.raises_suspended(format('update animals set name = ''Değişti'' where id = %L', animal)),
                      'animals update blocked');
  perform tests.check(tests.raises_suspended(format(
    'insert into follows (user_id, target_type, target_id) values (auth.uid(), ''spot'', %L)', spot)), 'follows insert blocked');
  perform tests.check(tests.raises_suspended(format(
    'insert into guardians (user_id, spot_id) values (auth.uid(), %L)', spot)), 'guardians insert blocked');
  -- taciz edilen uzaklaştırılmış kullanıcı yine de raporlayabilir (fix M4)
  perform tests.check(not tests.raises_suspended(format(
    'insert into reports (reporter_id, target_type, target_id, reason) values (auth.uid(), ''post'', %L, ''spam'')', post)),
    'suspended can still report');

  -- okumalar açık
  perform tests.check((select count(*) from spots_near(lat, lng, 1000, 50)) >= 1, 'suspended can read spots');
  perform tests.check((select count(*) from community_feed(lat, lng, 5000, null, null, 20)) >= 1, 'suspended can read feed');
  perform tests.eq((select count(*)::int from my_conversations() c where c.conversation_id = conv), 1, 'suspended can list conversations');
  perform tests.check((select count(*) from conversation_messages(conv)) >= 0, 'suspended can read messages');
  perform tests.check((select count(*) from meetups_near(lat, lng, 5000)) >= 1, 'suspended can read meetups');
  perform tests.check(social_profile_me() is not null, 'suspended can read own social profile');

  -- izin verilen yazmalar: engel, bildirim ayarları, profil, okundu, ayrılma
  insert into blocks (user_id, blocked_user_id) values (s, mod2);
  perform tests.check(exists (select 1 from blocks where user_id = s and blocked_user_id = mod2), 'suspended can block');
  update notification_prefs set radius_m = 900 where user_id = s;
  update profiles set neighborhood = 'Moda' where id = s;
  perform tests.eq((select neighborhood from profiles where id = s), 'Moda', 'suspended can edit own neighborhood');
  perform tests.check(tests.raises_suspended(format('update profiles set display_name = ''Yeni adım'' where id = %L', s)),
                      'suspended cannot change display_name');
  perform tests.check(tests.raises_suspended(format('update profiles set avatar_url = ''https://x.test/a.jpg'' where id = %L', s)),
                      'suspended cannot change avatar_url');
  perform mark_conversation_read(conv);
  perform tests.eq(leave_meetup(meet)->>'status', 'ok', 'suspended can leave a meetup');
  delete from follows where user_id = s;

  -- kendi durumunu görür
  perform tests.check(my_suspension() between now() + interval '6 days' and now() + interval '8 days', 'my_suspension returns until');
  perform tests.login(other);
  perform tests.eq(my_suspension(), null, 'not suspended → null');

  -- sahip geçmişi
  perform tests.login(other);
  insert into reports (reporter_id, target_type, target_id, reason) values (other, 'user', s, 'spam');
  perform tests.login(mod);
  j := moderation_target_reports('user', s);
  perform tests.eq((j->'owner'->>'suspension_count_90d')::int, 1, 'owner suspension count 1');
  perform tests.check(j->'owner'->>'suspended_until' is not null, 'owner suspended_until shown to moderator');

  -- süre dolunca yazabilir
  perform tests.admin();
  update profiles set suspended_until = now() - interval '1 second' where id = s;
  perform tests.login(s);
  perform tests.check(not tests.raises_suspended(format('select toggle_post_paw(%L)', post)), 'expired suspension → writes allowed');
  perform tests.eq(my_suspension(), null, 'expired suspension → my_suspension null');

  -- süresiz
  perform tests.login(mod);
  j := moderation_suspend_user(s, null, null);
  perform tests.eq(j->>'status', 'ok', 'indefinite suspension ok');
  perform tests.eq(j->>'suspended_until', 'infinity', 'indefinite → infinity');
  perform tests.login(s);
  perform tests.check(tests.raises_suspended(format('select toggle_post_paw(%L)', post)), 'indefinite suspension blocks writes');
  perform tests.eq(my_suspension(), 'infinity'::timestamptz, 'my_suspension infinity');

  -- kaldırma
  perform tests.login(mod);
  perform tests.eq(moderation_unsuspend_user(gen_random_uuid())->>'status', 'not_found', 'unsuspend unknown → not_found');
  perform tests.eq(moderation_unsuspend_user(s)->>'status', 'ok', 'unsuspend ok');
  perform tests.admin();
  perform tests.eq((select suspended_until from profiles where id = s), null, 'unsuspend clears suspended_until');
  perform tests.check(exists (select 1 from moderation_actions where target_id = s and action = 'unsuspend'), 'unsuspend logged');
  perform tests.login(s);
  perform tests.check(not tests.raises_suspended(format('select toggle_post_paw(%L)', post)), 'unsuspended → writes allowed');
  update profiles set display_name = 'Serbest ad' where id = s;
  perform tests.eq((select display_name from profiles where id = s), 'Serbest ad', 'unsuspended → display_name editable');
  insert into animals (name, created_by) values ('Serbest', s);
  perform tests.check(exists (select 1 from animals where name = 'Serbest'), 'unsuspended → direct insert allowed');

  -- hesap silme moderatör kaydını bozmaz
  perform tests.admin();
  delete from auth.users where id = mod;
  perform tests.check(exists (select 1 from moderation_actions where target_id = s and moderator_id is null),
                      'deleted moderator → actions kept, moderator_id null');
end
$$;

-- ---------------------------------------------------------------------------
-- 5) Düzeltme turu 1: izin verilen yazmalar, güvenlik eylemleri, depolama, rapor güncelleme, geri alınamayan içerik
-- ---------------------------------------------------------------------------
do $$
declare
  mod    uuid := tests.make_user('Moderatör', 10, false, true);
  s      uuid := tests.make_user('Uzaklaştırılan');
  a      uuid := tests.make_user('Bağlantı A');
  b      uuid := tests.make_user('Bağlantı B');
  c      uuid := tests.make_user('İstek C');
  d      uuid := tests.make_user('İstek D');
  lat    float8 := tests.base_lat();
  lng    float8 := tests.base_lng();
  fn     text;
  def    text;
  j      jsonb;
  meet   uuid;
  post   uuid;
  cmt    uuid;
  r_out  uuid;
  r_in   uuid;
  r_in2  uuid;
  need   uuid;
  animal uuid;
  rep    uuid := tests.make_user('Raporcu');
begin
  -- M1: yeniden yazılan izinli fonksiyonlar require_reader kullanır
  foreach fn in array array['register_device_token', 'update_notify_center', 'mark_conversation_read', 'leave_meetup',
                            'cancel_meetup', 'withdraw_connection_request', 'remove_connection',
                            'delete_community_post', 'delete_community_comment'] loop
    for def in select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = fn loop
      perform tests.check(position('private.require_reader()' in def) > 0 and position('private.require_uid()' in def) = 0,
                          fn || ' uses require_reader only');
    end loop;
  end loop;

  -- hazırlık (uzaklaştırmadan önce)
  foreach fn in array array[s::text, a::text, b::text, c::text, d::text] loop
    perform tests.login(fn::uuid); perform give_social_consent();
  end loop;
  perform tests.login(s);
  perform tests.eq(update_social_profile(true, 'Merhaba', '{cats}', lat, lng)->>'status', 'ok', 'visible before suspension');
  j := create_meetup('Kendi buluşmam', '', now() + interval '3 hours', 60, 'Moda', lat, lng);
  meet := (j->>'meetup_id')::uuid;
  perform tests.admin();
  insert into community_posts (author_id, kind, body, cell) values (s, 'note', 'Kendi paylaşımım', private.make_point(lat, lng))
  returning id into post;
  insert into community_comments (post_id, author_id, body) values (post, s, 'Kendi yorumum') returning id into cmt;
  insert into connections (requester_id, addressee_id, status, responded_at) values (s, a, 'accepted', now());
  insert into connections (requester_id, addressee_id) values (s, b) returning id into r_out;
  insert into connections (requester_id, addressee_id) values (c, s) returning id into r_in;
  insert into connections (requester_id, addressee_id) values (d, s) returning id into r_in2;

  perform tests.login(mod);
  perform tests.eq(moderation_suspend_user(s, 30, null)->>'status', 'ok', 'suspend for fix round');

  -- M1: izin verilen yazmalar
  perform tests.login(s);
  perform tests.check(not tests.raises_suspended('select register_device_token(''tok-fix-round-1'', ''sandbox'')'),
                      'suspended can register device token');
  perform tests.check(not tests.raises_suspended(format('select update_notify_center(%s, %s)', lat, lng)),
                      'suspended can update notify center');
  perform tests.eq(cancel_meetup(meet)->>'status', 'ok', 'suspended can cancel own meetup');
  perform withdraw_connection_request(r_out);
  perform remove_connection(a);
  perform tests.admin();
  perform tests.eq((select count(*)::int from connections where id = r_out), 0, 'suspended can withdraw request');
  perform tests.eq((select status::text from connections where least(requester_id, addressee_id) = least(s, a)
                      and greatest(requester_id, addressee_id) = greatest(s, a)), 'removed', 'suspended can remove connection');
  perform tests.login(s);
  perform tests.eq(delete_community_comment(cmt)->>'status', 'ok', 'suspended can delete own comment');
  perform tests.eq(delete_community_post(post)->>'status', 'ok', 'suspended can delete own post');

  -- M4: güvenlik eylemleri
  perform tests.eq(respond_connection(r_in, false)->>'status', 'declined', 'suspended can decline a request');
  perform tests.check(tests.raises_suspended(format('select respond_connection(%L, true)', r_in2)), 'suspended cannot accept');
  perform tests.check(tests.raises_suspended(format('select update_social_profile(true, ''Merhaba'', ''{cats}'', %s, %s)', lat, lng)),
                      'suspended cannot stay/become visible');
  perform tests.check(tests.raises_suspended('select update_social_profile(false, ''Yeni metin'', ''{cats}'', null, null)'),
                      'suspended cannot edit about while hiding');
  perform tests.eq(update_social_profile(false, 'Merhaba', '{cats}', null, null)->>'status', 'ok', 'suspended can hide');
  perform tests.admin();
  perform tests.eq((select is_visible from social_profiles where user_id = s), false, 'hidden after suspension');
  perform tests.eq((select about from social_profiles where user_id = s), 'Merhaba', 'about unchanged');
  perform tests.login(s);

  -- Important: depolama yazmaları
  perform tests.check(tests.raises_suspended(format(
    'insert into storage.objects (bucket_id, name, owner) values (''photos'', %L, %L)', s::text || '/yeni.jpg', s)),
    'suspended cannot upload to photos');
  perform tests.admin();
  insert into storage.objects (bucket_id, name, owner) values ('photos', s::text || '/eski.jpg', s);
  perform tests.login(s);
  perform tests.check(tests.raises_suspended(format(
    'update storage.objects set name = %L where name = %L', s::text || '/degisti.jpg', s::text || '/eski.jpg')),
    'suspended cannot overwrite own photo');
  delete from storage.objects where name = s::text || '/eski.jpg';
  perform tests.admin();
  perform tests.eq((select count(*)::int from storage.objects where name = s::text || '/eski.jpg'), 0, 'suspended can delete own photo');
  perform tests.login(a);
  insert into storage.objects (bucket_id, name, owner) values ('photos', a::text || '/ok.jpg', a);
  perform tests.check(exists (select 1 from storage.objects where name = a::text || '/ok.jpg'), 'non-suspended upload still works');

  -- M2: raporlar doğrudan güncellenemez (karar yalnızca moderation_decide ile, kayıtlı)
  perform tests.login(rep);
  insert into reports (reporter_id, target_type, target_id, reason) values (rep, 'user', b, 'spam');
  perform tests.login(mod);
  perform tests.check(tests.denied('update public.reports set status = ''dismissed'', resolved_at = now()'),
                      'moderator cannot PATCH reports directly');
  perform tests.admin();
  perform tests.eq((select status::text from reports where target_id = b), 'open', 'report still open');

  -- M5: iptal/silme/temizleme geri alınamaz
  perform tests.admin();
  insert into needs (type, description, created_by, spot_id) values ('vet', 'Raporlu', b, tests.make_spot(lat, lng, 'N', 'public', b))
  returning id into need;
  insert into animals (name, created_by) values ('Raporlu', b) returning id into animal;
  perform tests.login(rep);
  insert into reports (reporter_id, target_type, target_id, reason) values (rep, 'need', need, 'spam'), (rep, 'animal', animal, 'spam');
  perform tests.login(mod);
  perform tests.eq((moderation_target_reports('need', need)->'case'->>'restorable')::boolean, true, 'live need restorable');
  perform tests.eq(moderation_decide('need', need, 'remove')->>'status', 'ok', 'remove need');
  perform tests.eq(moderation_target_reports('need', need)->'case'->>'content_state', 'removed', 'removed need state');
  perform tests.eq((moderation_target_reports('need', need)->'case'->>'restorable')::boolean, false, 'removed need not restorable');
  j := moderation_decide('need', need, 'approve');
  perform tests.eq(j->>'status', 'invalid', 'approve after remove → invalid');
  perform tests.eq(j->>'reason', 'not_restorable', 'approve after remove → not_restorable');
  perform tests.eq(moderation_target_reports('need', need)->'case'->>'content_state', 'removed', 'still removed');
  -- yeni bir rapor gelse de kaldırılmış kalır
  perform tests.login(a);
  insert into reports (reporter_id, target_type, target_id, reason) values (a, 'animal', animal, 'other');
  perform tests.login(mod);
  perform tests.eq(moderation_decide('animal', animal, 'remove')->>'status', 'ok', 'remove animal');
  perform tests.eq(moderation_decide('animal', animal, 'approve')->>'reason', 'not_restorable', 'animal approve not_restorable');
  perform tests.eq((select content_state from moderation_queue(true) q where q.target_id = animal), 'removed', 'closed tab removed');
  -- sahip avatarı detayda
  perform tests.check((moderation_target_reports('user', b)->'owner') ? 'avatar_url', 'owner avatar_url present');
end
$$;

rollback;
