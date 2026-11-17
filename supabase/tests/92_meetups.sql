-- Tanışma: buluşma RPC'leri (oluştur, katıl, ayrıl, çıkar, iptal, liste/detay/katılımcılar).
begin;

do $$
declare
  org   uuid := tests.make_user('Duzenleyen');
  a     uuid := tests.make_user('Katilimci A');
  b     uuid := tests.make_user('Katilimci B');
  nc    uuid := tests.make_user('Onaysiz');
  blk   uuid := tests.make_user('Engelleyen');
  lat   float8 := tests.base_lat();
  lng   float8 := tests.base_lng();
  spot  uuid;
  j     jsonb;
  m1    uuid;
  m2    uuid;
  mc    uuid;
  conv  uuid;
  r     public.meetup_row;
  n     int;
begin
  spot := tests.make_spot(lat, lng, 'Test noktası');

  -- onaysız oluşturma
  perform tests.login(org);
  j := create_meetup('Mama dağıtımı', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'status', 'consent_required', 'create without consent → consent_required');
  perform give_social_consent();
  perform tests.login(a); perform give_social_consent();
  perform tests.login(b); perform give_social_consent();
  perform tests.login(blk); perform give_social_consent();

  -- doğrulama (sıra: metin uzunlukları, küfür, günlük limit, başlangıç, süre, kapasite, nokta)
  perform tests.login(org);
  j := create_meetup('ab', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'title_length', 'title 2 chars → title_length');
  j := create_meetup(repeat('a', 81), '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'title_length', 'title 81 chars → title_length');
  j := create_meetup('Başlık', repeat('a', 601), now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'description_too_long', 'description 601 → description_too_long');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 120, '   ', lat, lng);
  perform tests.eq(j->>'reason', 'place_name_length', 'empty place → place_name_length');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 120, repeat('a', 81), lat, lng);
  perform tests.eq(j->>'reason', 'place_name_length', 'place 81 → place_name_length');
  j := create_meetup('siktir git', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'status', 'rejected_content', 'profanity in title → rejected_content');
  j := create_meetup('Başlık', 'siktir git', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'status', 'rejected_content', 'profanity in description → rejected_content');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 120, 'siktir', lat, lng);
  perform tests.eq(j->>'status', 'rejected_content', 'profanity in place → rejected_content');
  j := create_meetup('Başlık', '', now() + interval '59 minutes', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'start_too_soon', '59 min → start_too_soon');
  j := create_meetup('Başlık', '', now() + interval '61 days', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'start_too_late', '61 days → start_too_late');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 29, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'duration_range', '29 min → duration_range');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 481, 'Moda', lat, lng);
  perform tests.eq(j->>'reason', 'duration_range', '481 min → duration_range');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 120, 'Moda', lat, lng, null, 1);
  perform tests.eq(j->>'reason', 'capacity_range', 'capacity 1 → capacity_range');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 120, 'Moda', lat, lng, null, 51);
  perform tests.eq(j->>'reason', 'capacity_range', 'capacity 51 → capacity_range');
  j := create_meetup('Başlık', '', now() + interval '3 hours', 120, 'Moda', lat, lng, gen_random_uuid());
  perform tests.eq(j->>'reason', 'spot_not_found', 'unknown spot → spot_not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from meetups where organizer_id = org), 0, 'no meetup inserted by invalid calls');
  perform tests.login(org);

  -- sınır değerleri geçerli
  j := create_meetup('  Mama dağıtımı  ', 'Açıklama', now() + interval '61 minutes', 30, 'Moda sahil', lat, lng, spot, null);
  perform tests.eq(j->>'status', 'created', 'valid meetup created (61 min, 30 min, spot)');
  m1 := (j->>'meetup_id')::uuid;
  conv := (j->>'conversation_id')::uuid;
  perform tests.check(conv is not null, 'conversation id returned');
  perform tests.admin();
  perform tests.eq((select title from meetups where id = m1), 'Mama dağıtımı', 'title trimmed');
  perform tests.eq((select ends_at - starts_at from meetups where id = m1), interval '30 minutes', 'ends_at = starts_at + duration');
  perform tests.eq((select kind::text from conversations where id = conv), 'meetup', 'conversation kind meetup');
  perform tests.eq((select meetup_id from conversations where id = conv), m1, 'conversation linked');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = conv and user_id = org), 1, 'organizer is conversation member');
  perform tests.eq((select status::text from meetup_participants where meetup_id = m1 and user_id = org), 'joined', 'organizer is participant');
  perform tests.login(org);

  j := create_meetup('Uzun', '', now() + interval '60 days', 480, 'Moda', lat, lng, null, 50);
  perform tests.eq(j->>'status', 'created', '60 days / 480 min / capacity 50 valid');
  j := create_meetup('Kapasiteli', '', now() + interval '2 hours', 120, 'Moda', lat, lng, null, 2);
  perform tests.eq(j->>'status', 'created', 'capacity 2 valid (3rd of the day)');
  m2 := (j->>'meetup_id')::uuid;

  -- günlük limit: 4. → limit_reached
  j := create_meetup('Dördüncü', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'status', 'limit_reached', '4th meetup same day → limit_reached');
  perform tests.eq((j->>'limit')::int, 3, 'limit is 3');

  -- iptal edilen de sayılır
  perform tests.admin();
  update meetups set status = 'cancelled' where id = (select id from meetups where organizer_id = org and title = 'Uzun');
  perform tests.login(org);
  j := create_meetup('Dördüncü', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  perform tests.eq(j->>'status', 'limit_reached', 'cancelled meetups still count toward daily limit');

  -- kapasite: düzenleyen + 1, sonra dolu
  perform tests.login(a);
  j := join_meetup(m2);
  perform tests.eq(j->>'status', 'joined', 'A joins capacity-2 meetup');
  perform tests.check((j->>'conversation_id')::uuid is not null, 'join returns conversation id');
  perform tests.login(b);
  j := join_meetup(m2);
  perform tests.eq(j->>'status', 'full', 'B → full');
  perform tests.admin();
  perform tests.eq((select count(*)::int from meetup_participants where meetup_id = m2 and status = 'joined'),
                   (select capacity from meetups where id = m2), 'joined count = capacity');
  perform tests.login(b);
  perform tests.eq((select participant_count from meetup_detail(m2) limit 1), 2, 'participant_count = 2');
  perform tests.eq(join_meetup(m2)->>'status', 'full', 'second join attempt still full');
  perform tests.admin();
  perform tests.eq((select count(*)::int from meetup_participants where meetup_id = m2 and status = 'joined'), 2, 'still 2 joined');

  -- idempotent join
  perform tests.login(a);
  perform tests.eq(join_meetup(m2)->>'status', 'joined', 'A joining again is idempotent');
  perform tests.admin();
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = (select id from conversations where meetup_id = m2)), 2, 'members: organizer + A');

  -- ayrıl: organizer ayrılamaz, katılımcı ayrılınca üyelik silinir, B artık girebilir
  perform tests.login(org);
  perform tests.eq(leave_meetup(m2)->>'status', 'organizer_cannot_leave', 'organizer cannot leave');
  perform tests.login(a);
  perform tests.eq(leave_meetup(m2)->>'status', 'ok', 'A leaves');
  perform tests.admin();
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = (select id from conversations where meetup_id = m2) and user_id = a), 0, 'A conversation membership deleted');
  perform tests.login(b);
  perform tests.eq(join_meetup(m2)->>'status', 'joined', 'B joins after A left');

  -- çıkarma: yalnızca düzenleyen; çıkarılan tekrar katılamaz; çıkarılan ayrılırsa kayıt silinmez
  perform tests.login(a);
  perform tests.eq(remove_meetup_participant(m2, b)->>'status', 'not_allowed', 'non-organizer cannot remove');
  perform tests.login(org);
  perform tests.eq(remove_meetup_participant(m2, org)->>'status', 'not_allowed', 'organizer cannot remove self');
  perform tests.eq(remove_meetup_participant(m2, a)->>'status', 'not_allowed', 'cannot remove non-participant');
  perform tests.eq(remove_meetup_participant(m2, b)->>'status', 'ok', 'organizer removes B');
  perform tests.admin();
  perform tests.eq((select status::text from meetup_participants where meetup_id = m2 and user_id = b), 'removed', 'B status removed');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = (select id from conversations where meetup_id = m2) and user_id = b), 0, 'B membership deleted');
  perform tests.login(b);
  perform tests.eq(join_meetup(m2)->>'status', 'removed', 'removed user cannot rejoin');
  perform tests.eq(leave_meetup(m2)->>'status', 'ok', 'removed user leave is no-op');
  perform tests.eq(join_meetup(m2)->>'status', 'removed', 'still removed after leave');
  select * into r from meetup_detail(m2);
  perform tests.eq(r.viewer_role, 'removed', 'viewer_role removed');
  perform tests.check(r.conversation_id is null, 'removed viewer: conversation_id null');

  -- onaysız join
  perform tests.login(nc);
  perform tests.eq(join_meetup(m1)->>'status', 'consent_required', 'join without consent → consent_required');
  perform tests.eq(join_meetup(gen_random_uuid())->>'status', 'consent_required', 'consent checked before lookup');

  -- bilinmeyen id
  perform tests.login(a);
  perform tests.eq(join_meetup(gen_random_uuid())->>'status', 'not_found', 'unknown meetup → not_found');

  -- viewer_role / conversation_id / participant_count / mesafe
  select * into r from meetup_detail(m1, lat, lng);
  perform tests.eq(r.viewer_role, 'none', 'non-participant viewer_role none');
  perform tests.check(r.conversation_id is null, 'non-participant: conversation_id null');
  perform tests.check(r.distance_m is not null and r.distance_m < 1, 'distance_m ~0 at same point');
  perform tests.eq(r.spot_title, 'Test noktası', 'spot_title returned');
  perform tests.eq(r.title, 'Mama dağıtımı', 'detail title');
  perform tests.eq(r.organizer_name, 'Duzenleyen', 'organizer_name');
  select * into r from meetup_detail(m1);
  perform tests.check(r.distance_m is null, 'distance_m null without coordinates');
  perform tests.login(org);
  select * into r from meetup_detail(m1);
  perform tests.eq(r.viewer_role, 'organizer', 'organizer viewer_role');
  perform tests.eq(r.conversation_id, conv, 'organizer sees conversation_id');
  perform tests.login(a);
  perform tests.eq(join_meetup(m1)->>'status', 'joined', 'A joins m1');
  select * into r from meetup_detail(m1);
  perform tests.eq(r.viewer_role, 'participant', 'participant viewer_role');
  perform tests.eq(r.conversation_id, conv, 'participant sees conversation_id');
  perform tests.eq(r.participant_count, 2, 'participant_count 2');

  -- katılımcı listesi
  select count(*)::int into n from meetup_participants(m1);
  perform tests.eq(n, 2, 'participant sees 2 participants');
  perform tests.check((select is_organizer from meetup_participants(m1) where user_id = org), 'organizer flagged');
  perform tests.login(b);
  select count(*)::int into n from meetup_participants(m1);
  perform tests.eq(n, 0, 'non-participant sees 0 participants');
  perform tests.login(b);
  select count(*)::int into n from meetup_participants(m2);
  perform tests.eq(n, 0, 'removed user sees 0 participants');

  -- meetups_near: onay gerekmez, sıralama
  perform tests.login(nc);
  select count(*)::int into n from meetups_near(lat, lng);
  perform tests.eq(n, 2, 'unconsented viewer lists 2 active meetups (m1, m2)');
  perform tests.eq((select id from meetups_near(lat, lng) limit 1), m1, 'same distance → earlier start first (m2 starts at +2h, m1 at +61m)');
  -- yarıçap dışı
  perform tests.eq((select count(*)::int from meetups_near(lat + 1, lng, 10000)), 0, 'outside radius → 0');

  -- engel: izleyen düzenleyeni engelledi
  perform tests.login(blk);
  perform tests.eq((select count(*)::int from meetups_near(lat, lng)), 2, 'blocker sees meetups before blocking');
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (blk, org);
  perform tests.login(blk);
  perform tests.eq((select count(*)::int from meetups_near(lat, lng)), 0, 'blocked organizer: meetups_near 0 rows');
  perform tests.eq(join_meetup(m1)->>'status', 'not_found', 'blocked organizer: join → not_found');
  perform tests.eq((select count(*)::int from meetup_detail(m1)), 0, 'blocked organizer: detail 0 rows');
  -- ters yön
  perform tests.admin();
  delete from blocks where user_id = blk;
  insert into blocks (user_id, blocked_user_id) values (org, blk);
  perform tests.login(blk);
  perform tests.eq(join_meetup(m1)->>'status', 'not_found', 'reverse block: join → not_found');
  perform tests.admin();
  delete from blocks where user_id = org;

  -- katılımcı listesinde engelli yok (iki katılımcı arasında)
  perform tests.login(b);
  perform tests.eq(join_meetup(m1)->>'status', 'joined', 'B joins m1');
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (a, b);
  perform tests.login(a);
  perform tests.eq((select count(*)::int from meetup_participants(m1)), 2, 'blocked pair hidden from participant list (self + organizer)');
  perform tests.check(not exists (select 1 from meetup_participants(m1) where user_id = b), 'blocked participant not listed');
  perform tests.admin();
  delete from blocks where user_id = a;
  -- katılımcı düzenleyeni engellerse buluşmadan ayrılır (0023 apply_block_to_social)
  insert into blocks (user_id, blocked_user_id) values (a, org);
  perform tests.eq((select count(*)::int from meetup_participants mp where mp.meetup_id = m1 and mp.user_id = a), 0,
                   'participant blocking organizer leaves the meetup');
  delete from blocks where user_id = a;
  perform tests.login(a);
  perform tests.eq(join_meetup(m1)->>'status', 'joined', 'A rejoins after unblock');

  -- iptal
  perform tests.login(a);
  perform tests.eq(cancel_meetup(m1)->>'status', 'not_allowed', 'non-organizer cannot cancel');
  perform tests.login(org);
  perform tests.eq(cancel_meetup(m1)->>'status', 'ok', 'organizer cancels');
  perform tests.eq(cancel_meetup(m1)->>'status', 'ok', 'cancel is idempotent');
  perform tests.admin();
  perform tests.check((select closed_at is not null from conversations where id = conv), 'conversation closed_at set');
  perform tests.login(b);
  perform tests.eq(join_meetup(m1)->>'status', 'cancelled', 'join cancelled → cancelled');
  perform tests.eq((select status from meetup_detail(m1)), 'cancelled', 'detail still returns cancelled meetup');
  perform tests.eq((select count(*)::int from meetups_near(lat, lng) where id = m1), 0, 'cancelled not in meetups_near');

  -- bitmiş buluşma
  perform tests.admin();
  mc := (select id from meetups where organizer_id = org and title = 'Kapasiteli');
  update meetups set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = mc;
  perform tests.login(b);
  perform tests.eq((select count(*)::int from meetups_near(lat, lng) where id = mc), 0, 'ended meetup not in meetups_near');
  perform tests.eq(join_meetup(mc)->>'status', 'ended', 'join ended → ended');
  perform tests.login(org);
  perform tests.eq(cancel_meetup(mc)->>'status', 'not_allowed', 'cannot cancel ended meetup');

  -- anon yetkisi yok
  perform tests.anon();
  begin
    perform * from meetups_near(lat, lng);
    raise exception 'FAIL: anon executed';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute meetups_near');
  end;
  begin
    perform join_meetup(m2);
    raise exception 'FAIL: anon executed';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute join_meetup');
  end;
  begin
    perform create_meetup('Anon', '', now() + interval '3 hours', 120, 'Moda', lat, lng);
    raise exception 'FAIL: anon executed';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute create_meetup');
  end;
end
$$;

rollback;
