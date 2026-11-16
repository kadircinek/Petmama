-- Mahalle'de hayvanseverler + anlık mama turu (spec 2026-11-16): start_feeding_tour, meetup_row.is_tour,
-- turlar buluşma limitinden ayrı, hatırlatma turlara gitmez, animal_lovers_near.fed_today / on_tour_meetup_id.
begin;

do $$
declare
  lat    float8 := tests.base_lat();
  lng    float8 := tests.base_lng();
  org    uuid := tests.make_user('Zz Turcu');
  v      uuid := tests.make_user('Izleyen');
  a      uuid := tests.make_user('Yy Besleyen');
  b      uuid := tests.make_user('Aa Dun');
  c      uuid := tests.make_user('Bb Hic');
  nc     uuid := tests.make_user('Onaysiz');
  mm     uuid := tests.make_user('Bulusmaci');
  spot   uuid;
  fuzzed uuid;
  priv   uuid;
  gone   uuid;
  pend   uuid;
  longsp uuid;
  j      jsonb;
  t1     uuid;
  t2     uuid;
  t3     uuid;
  conv   uuid;
  normal uuid;
  day0   timestamptz;
  r      public.meetup_row;
  i      int;
  n      int;
begin
  spot   := tests.make_spot(lat, lng, 'Moda sahil');
  fuzzed := tests.make_spot(lat, lng, 'Bulanık nokta', 'fuzzed');
  priv   := tests.make_spot(lat, lng, 'Özel bahçe', 'private', org);
  gone   := tests.make_spot(lat, lng, 'Kaldırılmış');
  pend   := tests.make_spot(lat, lng, 'Onay bekleyen', 'public', a);
  longsp := tests.make_spot(lat, lng, repeat('ç', 80));
  update spots set is_active = false where id = gone;
  update spots set moderation_state = 'pending' where id = pend;
  day0 := private.istanbul_day_start();

  -- yetkiler
  perform tests.eq(has_function_privilege('anon', 'public.start_feeding_tour(uuid, int)', 'execute'), false, 'anon cannot start tour');
  perform tests.eq(has_function_privilege('authenticated', 'public.start_feeding_tour(uuid, int)', 'execute'), true, 'authenticated can start tour');

  -- onay
  perform tests.login(nc);
  j := start_feeding_tour(spot);
  perform tests.eq(j->>'status', 'consent_required', 'no consent → consent_required');
  perform tests.admin();
  perform tests.eq((select count(*)::int from meetups where organizer_id = nc), 0, 'no tour inserted without consent');

  foreach t1 in array array[org, v, a, b, c, mm] loop
    perform tests.login(t1); perform give_social_consent();
  end loop;

  -- süre ve nokta doğrulaması
  perform tests.login(org);
  perform tests.eq(start_feeding_tour(spot, 59)->>'reason', 'duration_range', '59 min → duration_range');
  perform tests.eq(start_feeding_tour(spot, 121)->>'reason', 'duration_range', '121 min → duration_range');
  perform tests.eq(start_feeding_tour(spot, null)->>'status', 'invalid', 'null duration → invalid');
  perform tests.eq(start_feeding_tour(gen_random_uuid())->>'status', 'spot_not_found', 'unknown spot → spot_not_found');
  perform tests.eq(start_feeding_tour(null)->>'status', 'spot_not_found', 'null spot → spot_not_found');
  perform tests.eq(start_feeding_tour(fuzzed)->>'status', 'spot_not_found', 'fuzzed spot → spot_not_found');
  perform tests.eq(start_feeding_tour(priv)->>'status', 'spot_not_found', 'private spot (even own) → spot_not_found');
  perform tests.eq(start_feeding_tour(gone)->>'status', 'spot_not_found', 'inactive spot → spot_not_found');
  perform tests.eq(start_feeding_tour(pend)->>'status', 'spot_not_found', 'pending spot of someone else → spot_not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from meetups where organizer_id = org), 0, 'no tour inserted by invalid calls');

  -- geçerli tur (varsayılan 90 dk)
  perform tests.login(org);
  j := start_feeding_tour(spot);
  perform tests.eq(j->>'status', 'started', 'valid tour started');
  t1 := (j->>'meetup_id')::uuid;
  conv := (j->>'conversation_id')::uuid;
  perform tests.check(t1 is not null and conv is not null, 'meetup_id and conversation_id returned');
  perform tests.admin();
  perform tests.check((select is_tour from meetups where id = t1), 'is_tour set');
  perform tests.eq((select starts_at from meetups where id = t1), now(), 'tour starts now');
  perform tests.eq((select ends_at - starts_at from meetups where id = t1), interval '90 minutes', 'default duration 90 min');
  perform tests.eq((select title from meetups where id = t1), 'Mama turu: Moda sahil', 'title from spot');
  perform tests.eq((select place_name from meetups where id = t1), 'Moda sahil', 'place_name = spot title');
  perform tests.eq((select spot_id from meetups where id = t1), spot, 'spot_id set');
  perform tests.check((select extensions.st_equals(m.location::extensions.geometry, s.location::extensions.geometry)
                         from meetups m, spots s where m.id = t1 and s.id = spot), 'location = spot location');
  perform tests.check((select capacity is null from meetups where id = t1), 'no capacity');
  perform tests.eq((select status::text from meetup_participants where meetup_id = t1 and user_id = org), 'joined', 'organizer is participant');
  perform tests.eq((select meetup_id from conversations where id = conv), t1, 'conversation linked');
  perform tests.eq((select kind::text from conversations where id = conv), 'meetup', 'conversation kind meetup');
  perform tests.eq((select count(*)::int from conversation_members where conversation_id = conv and user_id = org), 1, 'organizer is member');

  -- aynı anda tek tur
  perform tests.login(org);
  perform tests.eq(start_feeding_tour(spot, 60)->>'status', 'already_touring', 'active tour → already_touring');

  -- meetup_row.is_tour
  select * into r from meetup_detail(t1);
  perform tests.check(r.is_tour, 'meetup_detail: is_tour true');
  perform tests.check((select x.is_tour from meetups_near(lat, lng) x where x.id = t1), 'meetups_near: is_tour true');
  perform tests.eq((select x.viewer_role from meetups_near(lat, lng) x where x.id = t1), 'organizer', 'organizer role');

  -- başkası katılır; katılım bildirimi değişmedi
  perform tests.login(a);
  j := join_meetup(t1);
  perform tests.eq(j->>'status', 'joined', 'A joins the tour');
  perform tests.eq((j->>'conversation_id')::uuid, conv, 'join returns tour conversation');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = org and kind = 'meetup_joined' and meetup_id = t1), 1,
                   'organizer notified of join');

  -- iptal (Turu bitir) → yeni tur açılabilir; katılana iptal bildirimi
  perform tests.login(org);
  perform tests.eq(cancel_meetup(t1)->>'status', 'ok', 'organizer ends tour');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = a and kind = 'meetup_cancelled' and meetup_id = t1), 1,
                   'participant notified of cancel');
  perform tests.login(org);
  j := start_feeding_tour(longsp, 120);
  perform tests.eq(j->>'status', 'started', 'second tour after cancel');
  t2 := (j->>'meetup_id')::uuid;
  perform tests.admin();
  perform tests.eq((select char_length(title) from meetups where id = t2), 80, 'long title trimmed to 80');
  perform tests.check((select title like 'Mama turu: ç%' from meetups where id = t2), 'trimmed title keeps prefix');
  perform tests.eq((select ends_at - starts_at from meetups where id = t2), interval '120 minutes', '120 min tour');

  -- süresi dolan tur da "açık" sayılmaz
  update meetups set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = t2;
  perform tests.login(org);
  j := start_feeding_tour(spot, 60);
  perform tests.eq(j->>'status', 'started', 'third tour after the previous ended');
  t3 := (j->>'meetup_id')::uuid;
  perform cancel_meetup(t3);

  -- günlük limit 3 (iptal/bitmiş dahil)
  j := start_feeding_tour(spot);
  perform tests.eq(j->>'status', 'limit_reached', '4th tour same day → limit_reached');
  perform tests.eq((j->>'limit')::int, 3, 'tour limit is 3');

  -- turlar buluşma limitine sayılmaz
  for i in 1..3 loop
    j := create_meetup('Buluşma ' || i, '', now() + interval '3 hours', 120, 'Moda', lat, lng);
    perform tests.eq(j->>'status', 'created', 'meetup ' || i || ' created despite 3 tours today');
  end loop;
  perform tests.eq(create_meetup('Dördüncü', '', now() + interval '3 hours', 120, 'Moda', lat, lng)->>'status',
                   'limit_reached', 'meetup limit still applies');
  perform tests.eq((select x.is_tour from meetups_near(lat, lng) x where x.title = 'Buluşma 1'), false, 'meetup is_tour false');

  -- buluşmalar tur limitine sayılmaz
  perform tests.login(mm);
  for i in 1..3 loop
    perform create_meetup('MM ' || i, '', now() + interval '3 hours', 120, 'Moda', lat, lng);
  end loop;
  j := start_feeding_tour(spot);
  perform tests.eq(j->>'status', 'started', 'tour allowed after 3 meetups');
  t3 := (j->>'meetup_id')::uuid;

  -- hatırlatma turlara gitmez (normal buluşma alır)
  perform tests.admin();
  normal := (select id from meetups where organizer_id = mm and title = 'MM 1');
  update meetups set starts_at = now() + interval '30 minutes', ends_at = now() + interval '90 minutes' where id in (normal, t3);
  n := private.send_meetup_reminders();
  perform tests.eq((select count(*)::int from notifications where kind = 'meetup_reminder' and meetup_id = normal), 1,
                   'normal meetup gets reminder');
  perform tests.eq((select count(*)::int from notifications where kind = 'meetup_reminder' and meetup_id = t3), 0,
                   'tour gets no reminder');
  update meetups set starts_at = now(), ends_at = now() + interval '90 minutes' where id = t3;

  -- Hayvanseverler: fed_today ve on_tour_meetup_id
  perform tests.login(v);  perform update_social_profile(true, '', array[]::social_interest[], lat, lng);
  perform tests.login(org); perform update_social_profile(true, '', array[]::social_interest[], lat, lng);
  perform tests.login(a);  perform update_social_profile(true, '', array[]::social_interest[], lat + 0.02, lng);
  perform tests.login(b);  perform update_social_profile(true, '', array[]::social_interest[], lat, lng);
  perform tests.login(c);  perform update_social_profile(true, '', array[]::social_interest[], lat, lng);
  perform tests.login(mm); perform update_social_profile(false, '', array[]::social_interest[], lat, lng);

  perform tests.admin();
  insert into checkins (spot_id, user_id, kind, created_at) values
    (spot, a, 'water', now()),
    (spot, b, 'fed', day0 - interval '1 minute'),
    (spot, c, 'need_food', now());
  -- org'un açık turu yok (hepsi iptal/bitti) ama bugün tur açtı; yeni açık tur:
  update meetups set starts_at = now() - interval '10 minutes', ends_at = now() + interval '50 minutes', status = 'active'
   where id = t1;

  perform tests.login(v);
  perform tests.eq((select on_tour_meetup_id from animal_lovers_near() where user_id = org), t1, 'org on tour → meetup id');
  perform tests.check((select fed_today from animal_lovers_near() where user_id = org), 'started a tour today → fed_today');
  perform tests.check((select fed_today from animal_lovers_near() where user_id = a), 'water today → fed_today');
  perform tests.check((select on_tour_meetup_id is null from animal_lovers_near() where user_id = a), 'A not on tour');
  perform tests.check(not (select fed_today from animal_lovers_near() where user_id = b), 'fed yesterday → not fed_today');
  perform tests.check(not (select fed_today from animal_lovers_near() where user_id = c), 'need_food is not feeding');
  perform tests.check(not exists (select 1 from animal_lovers_near() where user_id = mm), 'invisible tourer not listed');
  -- sıra: turda → bugün besledi (1–3 km olsa da) → bant → ad
  perform tests.eq((select user_id from animal_lovers_near() limit 1), org, 'on tour first');
  perform tests.eq((select user_id from animal_lovers_near() offset 1 limit 1), a, 'fed today second (before nearer band)');
  perform tests.eq((select user_id from animal_lovers_near() offset 2 limit 1), b, 'then by band/name: b');
  perform tests.eq((select user_id from animal_lovers_near() offset 3 limit 1), c, 'then c');

  -- tur bitince "turda" değil ama "bugün besledi" kalır
  perform tests.login(org);
  perform cancel_meetup(t1);
  perform tests.login(v);
  perform tests.check((select on_tour_meetup_id is null from animal_lovers_near() where user_id = org), 'ended tour → not on tour');
  perform tests.check((select fed_today from animal_lovers_near() where user_id = org), 'still fed_today after ending tour');

  -- engel: turdaki kişi engelliyse listede yok
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (v, a);
  perform tests.login(v);
  perform tests.check(not exists (select 1 from animal_lovers_near() where user_id = a), 'blocked not listed');
end
$$;

rollback;
