-- Tanışma: Hayvanseverler listesi ve bağlantı istekleri.
begin;

do $$
declare
  lat   float8 := tests.base_lat();      -- 0,01 ızgarasında; cell yuvarlaması konumu kaydırmaz
  lng   float8 := tests.base_lng();
  v     uuid := tests.make_user('Izleyen');
  n     uuid := tests.make_user('Yakin', 10, true);
  m     uuid := tests.make_user('Orta');
  f     uuid := tests.make_user('Uzak');
  x     uuid := tests.make_user('Cok uzak');
  inv   uuid := tests.make_user('Gorunmez');
  nc    uuid := tests.make_user('Onaysiz');
  blk   uuid := tests.make_user('Engelli');
  t     uuid[] := array[]::uuid[];
  u     uuid;
  i     int;
  j     jsonb;
  req   uuid;
  conv  uuid;
  conv2 uuid;
  r     record;
  spot  uuid;
begin
  for i in 1..8 loop
    t := t || tests.make_user('Hedef ' || i);
  end loop;

  -- Herkes onaylı; görünür olanlar: n (0 km, dogs), m (≈2,2 km, cats), f (≈7,8 km, cats+dogs), x (≈12 km), t[1..8] (0 km)
  foreach u in array array[v, n, m, f, x, inv, blk] || t loop
    perform tests.login(u); perform give_social_consent();
  end loop;
  perform tests.login(n);   perform update_social_profile(true, 'Yakın hakkımda', array['dogs']::social_interest[], lat, lng);
  perform tests.login(m);   perform update_social_profile(true, 'Orta', array['cats']::social_interest[], lat + 0.02, lng);
  perform tests.login(f);   perform update_social_profile(true, 'Uzak', array['cats','dogs']::social_interest[], lat + 0.07, lng);
  perform tests.login(x);   perform update_social_profile(true, 'Çok uzak', array['cats']::social_interest[], lat + 0.11, lng);
  perform tests.login(blk); perform update_social_profile(true, 'Engelli', array['cats']::social_interest[], lat, lng);
  foreach u in array t loop
    perform tests.login(u); perform update_social_profile(true, '', array[]::social_interest[], lat, lng);
  end loop;
  perform tests.login(inv); perform update_social_profile(false, 'Gizli', array['cats']::social_interest[], lat, lng);

  -- izleyici görünmezken liste boş; görünmezken istek → not_visible
  perform tests.login(v);
  perform update_social_profile(false, '', array['cats','dogs']::social_interest[], lat, lng);
  perform tests.eq((select count(*)::int from animal_lovers_near()), 0, 'invisible viewer: 0 rows');
  perform tests.eq(send_connection_request(n)->>'status', 'not_visible', 'invisible sender → not_visible');
  perform update_social_profile(true, '', array['cats','dogs']::social_interest[], lat, lng);

  -- onaysız izleyici: 0 satır, istek consent_required
  perform tests.login(nc);
  perform tests.eq((select count(*)::int from animal_lovers_near()), 0, 'unconsented viewer: 0 rows');
  perform tests.eq(send_connection_request(n)->>'status', 'consent_required', 'unconsented → consent_required');

  -- engel
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (v, blk);

  -- liste: bantlar, hariç tutulanlar, sıra
  perform tests.login(v);
  perform tests.check(not exists (select 1 from animal_lovers_near() where user_id = v), 'self not listed');
  perform tests.check(not exists (select 1 from animal_lovers_near() where user_id in (x, inv, blk)), 'far/invisible/blocked not listed');
  perform tests.eq((select count(*)::int from animal_lovers_near()), 3 + 8, 'listed: n, m, f + 8 targets');
  perform tests.eq((select distance_band::text from animal_lovers_near() where user_id = n), 'under_1km', 'n under_1km');
  perform tests.eq((select distance_band::text from animal_lovers_near() where user_id = m), '1_3km', 'm 1_3km');
  perform tests.eq((select distance_band::text from animal_lovers_near() where user_id = f), '3_10km', 'f 3_10km');
  perform tests.eq((select user_id from animal_lovers_near() offset 10 limit 1), f, 'ordered by band: f last');
  perform tests.eq((select user_id from animal_lovers_near() offset 9 limit 1), m, 'm before f');
  perform tests.eq((select user_id from animal_lovers_near() limit 1), n, 'n first (shared interest, then name)');
  perform tests.eq((select shared_interest_count from animal_lovers_near() where user_id = f), 2, 'f shares 2 interests');
  perform tests.eq((select shared_interest_count from animal_lovers_near() where user_id = m), 1, 'm shares 1 interest');
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = n), 'none', 'state none');
  perform tests.check((select is_verified_feeder from animal_lovers_near() where user_id = n), 'verified flag returned');
  perform tests.eq((select about from animal_lovers_near() where user_id = n), 'Yakın hakkımda', 'about returned');
  perform tests.eq((select count(*)::int from animal_lovers_near('dogs')), 2, 'filter dogs: n, f');
  perform tests.check(not exists (select 1 from animal_lovers_near('dogs') where user_id = m), 'filter dogs excludes m');

  -- fed_30d: yalnızca son 30 günde 'fed'
  perform tests.admin();
  spot := tests.make_spot(lat, lng);
  insert into checkins (spot_id, user_id, kind, created_at) values
    (spot, n, 'fed', now() - interval '1 day'),
    (spot, n, 'fed', now() - interval '29 days'),
    (spot, n, 'fed', now() - interval '31 days'),
    (spot, n, 'water', now() - interval '1 day');
  perform tests.login(v);
  perform tests.eq((select fed_30d from animal_lovers_near() where user_id = n), 2, 'fed_30d counts recent fed only');

  -- istekler: hedef kontrolleri
  perform tests.eq(send_connection_request(inv)->>'status', 'not_visible', 'invisible target → not_visible');
  perform tests.eq(send_connection_request(blk)->>'status', 'not_found', 'blocked target → not_found');
  perform tests.eq(send_connection_request(gen_random_uuid())->>'status', 'not_found', 'unknown target → not_found');
  perform tests.eq(send_connection_request(n, repeat('a', 201))->>'reason', 'note_too_long', 'note 201 → note_too_long');
  perform tests.eq(send_connection_request(n, 'siktir git')->>'status', 'rejected_content', 'profane note → rejected_content');
  perform tests.eq((select count(*)::int from animal_lovers_near() where connection_state <> 'none'), 0, 'failed requests leave no rows');

  -- v → n gönderildi; tekrar → already_pending; n tarafında incoming
  j := send_connection_request(n, '  Merhaba  ');
  perform tests.eq(j->>'status', 'sent', 'v→n sent');
  req := (j->>'request_id')::uuid;
  perform tests.eq(send_connection_request(n)->>'status', 'already_pending', 'v→n again → already_pending');
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = n), 'outgoing_pending', 'v sees outgoing_pending');
  perform tests.eq((select request_id from animal_lovers_near() where user_id = n), req, 'request_id exposed');
  perform tests.login(n);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = v), 'incoming_pending', 'n sees incoming_pending');
  select * into r from incoming_connection_requests();
  perform tests.eq(r.request_id, req, 'incoming: request_id');
  perform tests.eq(r.user_id, v, 'incoming: sender');
  perform tests.eq(r.note, 'Merhaba', 'incoming: note trimmed');
  perform tests.check(r.display_name is not null and r.created_at is not null, 'incoming: name and time');

  -- karşı istek → auto_accepted, tek satır, ortak sohbet
  j := send_connection_request(v);
  perform tests.eq(j->>'status', 'auto_accepted', 'n→v auto_accepted');
  conv := (j->>'conversation_id')::uuid;
  perform tests.admin();
  perform tests.eq((select count(*)::int from connections where least(requester_id, addressee_id) = least(v, n)
                      and greatest(requester_id, addressee_id) = greatest(v, n)), 1, 'single connections row');
  perform tests.eq((select status::text from connections where id = req), 'accepted', 'row accepted');
  perform tests.check((select responded_at is not null from connections where id = req), 'responded_at set');
  perform tests.eq((select kind::text from conversations where id = conv), 'direct', 'direct conversation');
  perform tests.eq((select connection_id from conversations where id = conv), req, 'conversation linked to connection');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = conv and user_id in (v, n)), 2, 'both members');
  perform tests.login(v);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = n), 'connected', 'v sees connected');
  perform tests.eq((select conversation_id from animal_lovers_near() where user_id = n), conv, 'conversation id in list');
  perform tests.eq(send_connection_request(n)->>'status', 'already_connected', 'connected → already_connected');
  perform tests.login(n);
  perform tests.eq((select conversation_id from animal_lovers_near() where user_id = v), conv, 'n sees same conversation');
  perform tests.eq((select count(*)::int from incoming_connection_requests()), 0, 'no incoming after accept');

  -- günlük limit: n isteği (1) + m, f, t1..t7 (9) = 10; 11. → limit_reached
  perform tests.login(v);
  perform tests.eq(send_connection_request(m)->>'status', 'sent', 'v→m sent');
  perform tests.eq(send_connection_request(f)->>'status', 'sent', 'v→f sent');
  for i in 1..7 loop
    perform tests.eq(send_connection_request(t[i])->>'status', 'sent', 'v→t' || i || ' sent');
  end loop;
  j := send_connection_request(t[8]);
  perform tests.eq(j->>'status', 'limit_reached', '11th request → limit_reached');
  perform tests.eq((j->>'limit')::int, 10, 'limit value 10');
  perform tests.eq((select count(*)::int from animal_lovers_near() where connection_state = 'outgoing_pending'), 9, '9 pending outgoing');

  -- geri çekme: yalnızca gönderen; sonrasında satır yok, limit yer açılır
  perform tests.admin();
  req := (select id from connections where requester_id = v and addressee_id = t[7]);
  perform tests.login(t[7]);
  perform tests.eq(withdraw_connection_request(req)->>'status', 'not_found', 'addressee cannot withdraw');
  perform tests.login(v);
  perform tests.eq(withdraw_connection_request(req)->>'status', 'ok', 'requester withdraws');
  perform tests.eq(withdraw_connection_request(req)->>'status', 'not_found', 'withdraw twice → not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from connections where id = req), 0, 'row deleted after withdraw');
  perform tests.login(v);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = t[7]), 'none', 'state none after withdraw');
  perform tests.eq(send_connection_request(t[8])->>'status', 'limit_reached', 'withdraw does not free a slot → limit_reached');
  -- sınırdayken karşı istek yine otomatik kabul edilir (gönderim sayılmaz)
  perform tests.login(t[7]);
  perform tests.eq(send_connection_request(v)->>'status', 'sent', 't7→v sent');
  perform tests.login(v);
  j := send_connection_request(t[7]);
  perform tests.eq(j->>'status', 'auto_accepted', 'at daily limit: reciprocal request still auto_accepted');
  perform tests.check(j->>'conversation_id' is not null, 'auto_accept at limit opens conversation');
  perform tests.admin();
  perform tests.eq((select count(*)::int from connection_request_sends where user_id = v), 10, 'auto_accept not counted as send');
  perform tests.login(v);
  -- sonraki adımlar için: gönderimleri geçmiş güne al (ertesi gün)
  perform tests.admin();
  update connection_request_sends set sent_at = now() - interval '2 days' where user_id = v;
  perform tests.login(v);

  -- reddetme: m reddeder; v outgoing_pending görmeye devam eder; cooldown; 31 gün sonra yeni istek
  perform tests.admin();
  req := (select id from connections where requester_id = v and addressee_id = m);
  perform tests.login(m);
  perform tests.eq(respond_connection(req, false)->>'status', 'declined', 'm declines');
  perform tests.eq(respond_connection(req, true)->>'status', 'not_found', 'already answered → not_found');
  perform tests.admin();
  perform tests.eq((select status::text from connections where id = req), 'declined', 'row declined');
  perform tests.check((select responded_at is not null from connections where id = req), 'declined responded_at set');
  perform tests.login(m);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = v), 'none', 'decliner sees none');
  perform tests.login(v);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = m), 'outgoing_pending', 'sender still sees outgoing_pending');
  perform tests.eq(send_connection_request(m)->>'status', 'cooldown', 'retry within 30 days → cooldown');
  perform tests.admin();
  update connections set responded_at = now() - interval '31 days', created_at = now() - interval '32 days' where id = req;
  perform tests.login(v);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = m), 'none', 'after 30 days declined row ignored');
  j := send_connection_request(m);
  perform tests.eq(j->>'status', 'sent', 'after 31 days → sent');
  perform tests.eq((j->>'request_id')::uuid, req, 'declined row reused');
  perform tests.admin();
  perform tests.eq((select status::text from connections where id = req), 'pending', 'row reset to pending');
  perform tests.check((select responded_at is null from connections where id = req), 'responded_at cleared');
  perform tests.check((select created_at > now() - interval '1 minute' from connections where id = req), 'created_at reset');

  -- kabul: yalnızca alıcı; sohbet açılır
  perform tests.login(v);
  perform tests.eq(respond_connection(req, true)->>'status', 'not_found', 'sender cannot respond');
  perform tests.login(m);
  j := respond_connection(req, true);
  perform tests.eq(j->>'status', 'accepted', 'm accepts');
  perform tests.check((j->>'conversation_id')::uuid is not null, 'accept returns conversation id');

  -- remove_connection: statü removed, sohbet kapanır; yeniden istek mümkün, kabulde aynı sohbet açılır
  perform tests.login(v);
  perform tests.eq(remove_connection(gen_random_uuid())->>'status', 'not_found', 'remove stranger → not_found');
  perform tests.eq(remove_connection(n)->>'status', 'ok', 'remove connection');
  perform tests.admin();
  perform tests.eq((select status::text from connections where addressee_id = n or requester_id = n limit 1), 'removed', 'status removed');
  perform tests.check((select closed_at is not null from conversations where id = conv), 'conversation closed');
  perform tests.login(v);
  perform tests.eq((select connection_state from animal_lovers_near() where user_id = n), 'none', 'removed → none');
  perform tests.eq(remove_connection(n)->>'status', 'not_found', 'remove twice → not_found');
  perform tests.admin();
  perform tests.login(v);
  j := send_connection_request(n);
  perform tests.eq(j->>'status', 'sent', 'removed → new request sent');
  perform tests.login(n);
  j := respond_connection((select request_id from incoming_connection_requests() limit 1), true);
  perform tests.eq(j->>'status', 'accepted', 'n accepts again');
  perform tests.eq((j->>'conversation_id')::uuid, conv, 'same conversation reused');
  perform tests.admin();
  perform tests.check((select closed_at is null from conversations where id = conv), 'conversation reopened');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = conv), 2, 'still 2 members');

  -- remove sonrası karşı istekle otomatik kabul de aynı sohbeti yeniden açar
  perform tests.login(v);
  perform tests.eq(remove_connection(n)->>'status', 'ok', 'remove again');
  perform tests.eq(send_connection_request(n)->>'status', 'sent', 'v→n sent after second removal');
  perform tests.login(n);
  j := send_connection_request(v);
  perform tests.eq(j->>'status', 'auto_accepted', 'n→v auto_accepted after removal');
  perform tests.eq((j->>'conversation_id')::uuid, conv, 'auto_accept reuses same conversation');
  perform tests.admin();
  perform tests.check((select closed_at is null from conversations where id = conv), 'auto_accept reopens conversation');
  perform tests.eq((select count(*)::int from connection_request_sends where user_id = n), 0, 'auto_accepted not counted as a send');

  -- Review Focus 2: görünürlüğü kapatan alıcı önceki isteği yine de yanıtlayabilir
  perform tests.login(t[3]);
  perform tests.eq((select count(*)::int from incoming_connection_requests()), 1, 't3 has incoming from v');
  req := (select request_id from incoming_connection_requests() limit 1);
  perform update_social_profile(false, '', array[]::social_interest[]);
  perform tests.login(v);
  perform tests.check(not exists (select 1 from animal_lovers_near() where user_id = t[3]), 'hidden user vanishes immediately');
  perform tests.login(f);
  perform tests.eq(send_connection_request(t[3])->>'status', 'not_visible', 'new request to now-hidden user → not_visible');
  perform tests.login(t[3]);
  perform tests.eq(respond_connection(req, true)->>'status', 'accepted', 'hidden user can accept earlier request');

  -- engellenen taraf yanıtlayamaz
  perform tests.login(t[4]);
  req := (select request_id from incoming_connection_requests() limit 1);
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (t[4], v);
  perform tests.login(t[4]);
  perform tests.eq(respond_connection(req, true)->>'status', 'not_found', 'blocked pair: respond → not_found');
  perform tests.eq((select count(*)::int from incoming_connection_requests()), 0, 'blocked sender hidden from incoming');
  perform tests.login(v);
  perform tests.eq(send_connection_request(t[4])->>'status', 'not_found', 'blocked: send → not_found');

  -- anon yetkisi yok
  perform tests.anon();
  begin
    perform animal_lovers_near();
    raise exception 'FAIL: anon executed animal_lovers_near';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute animal_lovers_near');
  end;
  begin
    perform send_connection_request(n);
    raise exception 'FAIL: anon executed send_connection_request';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute send_connection_request');
  end;
  perform tests.admin();
  perform tests.eq(has_function_privilege('anon', 'public.respond_connection(uuid, boolean)', 'execute'), false, 'anon no respond_connection');
  perform tests.eq(has_function_privilege('anon', 'public.remove_connection(uuid)', 'execute'), false, 'anon no remove_connection');
  perform tests.eq(has_function_privilege('anon', 'public.withdraw_connection_request(uuid)', 'execute'), false, 'anon no withdraw');
  perform tests.eq(has_function_privilege('anon', 'public.incoming_connection_requests()', 'execute'), false, 'anon no incoming');
end
$$;

rollback;
