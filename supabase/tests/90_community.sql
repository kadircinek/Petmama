-- Mahalle (topluluk) — docs/backend-contract.md "Mahalle (topluluk) — v0.2" (D17)
-- Yetkiler, paylaşım/yorum kuralları, pati, "Ben bakarım", bildirimler, engelleme, otomatik gizleme,
-- hesap silme, "Bu hafta mahallende" özeti, push kuyruğu.
--
-- Her blok seed'den ve birbirinden uzak bir bölgede çalışır (enlem kaydırması ≥ 0.3° ≈ 33 km; akış
-- yarıçapı en fazla 10 km). Bölge merkezleri 0.01°'lik ızgaranın üstünde: cell yuvarlaması mesafeleri bozmaz.
begin;

-- ---------------------------------------------------------------------------
-- Yetkiler: tablolar doğrudan okunamaz; RPC'ler yalnızca authenticated (anon asla)
-- ---------------------------------------------------------------------------
do $$
declare
  u      uuid := tests.make_user('Mahalle RLS');
  u2     uuid := tests.make_user('Mahalle varsayılan');
  t      text;
  rl     text;
  q      text;
  n      int;
  v_rpcs text[] := array['community_feed', 'community_post_detail', 'community_comments_of', 'cover_volunteers_of',
                         'create_community_post', 'add_community_comment', 'toggle_post_paw',
                         'toggle_cover_volunteer', 'delete_community_post', 'delete_community_comment',
                         'community_summary'];
begin
  foreach rl in array array['anon', 'authenticated'] loop
    foreach t in array array['community_posts', 'community_comments', 'community_paws', 'cover_volunteers'] loop
      if rl = 'anon' then perform tests.anon(); else perform tests.login(u); end if;
      begin
        execute format('select * from public.%I limit 1', t);
        raise exception 'FAIL: % can select %', rl, t;
      exception when insufficient_privilege then
        perform tests.check(sqlerrm like 'permission denied for table%', format('%s cannot select * from %s', rl, t));
      end;
      perform tests.admin();
    end loop;
  end loop;

  perform tests.login(u);
  begin
    insert into public.community_posts (author_id, body, cell)
    values (u, 'x', extensions.st_setsrid(extensions.st_makepoint(29, 41), 4326)::extensions.geography);
    raise exception 'FAIL: direct community_posts insert allowed';
  exception when insufficient_privilege then
    perform tests.check(sqlerrm like 'permission denied for table%', 'authenticated cannot insert community_posts directly');
  end;
  begin
    insert into public.community_paws (post_id, user_id) values (gen_random_uuid(), u);
    raise exception 'FAIL: direct community_paws insert allowed';
  exception when insufficient_privilege then
    perform tests.check(sqlerrm like 'permission denied for table%', 'authenticated cannot insert community_paws directly');
  end;
  -- yeni tercih sütunu sütun bazlı yetkiye eklendi
  update notification_prefs set community_updates = false where user_id = u;
  get diagnostics n = row_count;
  perform tests.eq(n, 1, 'user can switch off own community_updates preference');
  perform tests.admin();
  perform tests.eq((select community_updates from notification_prefs where user_id = u2), true,
                   'community_updates defaults to true');

  -- katalog: 11 RPC, hepsi security definer + sabit search_path, yalnızca authenticated çalıştırır
  perform tests.eq((select count(*)::int from pg_proc p
                    where p.pronamespace = 'public'::regnamespace and p.proname = any (v_rpcs)),
                   11, 'all 11 community RPCs exist (no overloads)');
  perform tests.check((select bool_and(p.prosecdef and p.proconfig @> array['search_path=public, extensions'])
                       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (v_rpcs)),
                      'community RPCs are security definer with search_path = public, extensions');
  perform tests.check((select bool_and(has_function_privilege('authenticated', p.oid, 'execute')
                                       and not has_function_privilege('anon', p.oid, 'execute')
                                       and not has_function_privilege('public', p.oid, 'execute'))
                       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (v_rpcs)),
                      'community RPCs: execute granted to authenticated only (not anon, not public)');

  -- anon gerçekten çağıramaz (require_uid'e bile ulaşmadan: "permission denied for function")
  perform tests.anon();
  foreach q in array array[
    'select * from community_feed(41, 29)',
    'select * from community_post_detail(gen_random_uuid())',
    'select * from community_comments_of(gen_random_uuid())',
    'select * from cover_volunteers_of(gen_random_uuid())',
    $q$select create_community_post('note', 'x', null, null, null, 41, 29, null, null)$q$,
    $q$select add_community_comment(gen_random_uuid(), 'x')$q$,
    'select toggle_post_paw(gen_random_uuid())',
    'select toggle_cover_volunteer(gen_random_uuid())',
    'select delete_community_post(gen_random_uuid())',
    'select delete_community_comment(gen_random_uuid())',
    'select * from community_summary(41, 29)'
  ] loop
    begin
      execute q;
      raise exception 'FAIL: anon executed %', q;
    exception when insufficient_privilege then
      perform tests.check(sqlerrm like 'permission denied for function%', 'anon cannot execute: ' || q);
    end;
  end loop;
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Paylaşım oluşturma: kaba konum (2 ondalık), akışta mesafe, detay
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat  float8 := tests.base_lat() + 3.0;   -- 43.95
  b_lng  float8 := tests.base_lng();          -- 29.05
  a      uuid := tests.make_user('Mahalle Yazar', 10, true);
  v      uuid := tests.make_user('Mahalle Okur');
  an     uuid;
  r      jsonb;
  pid    uuid;
  pid2   uuid;
  pr     community_post_row;
  c      extensions.geography;
  n      int;
begin
  insert into animals (name) values ('Mahalle Pamuk') returning id into an;

  perform tests.login(a);
  r := create_community_post('note', E'  \n Pamuk bugün çok neşeliydi. \t\n', null, null, an,
                             b_lat + 0.00123, b_lng + 0.00678, current_date, current_date + 3);
  perform tests.eq(r->>'status', 'created', 'note → created');
  perform tests.eq(r->>'moderation_state', 'approved', 'trusted author → approved');
  pid := (r->>'post_id')::uuid;

  -- PostgREST adlandırılmış argümanlar; isteğe bağlı parametreler atlanabilir
  r := create_community_post(p_kind => 'supply', p_body => 'Elimde fazla mama var.', lat => b_lat, lng => b_lng);
  perform tests.eq(r->>'status', 'created', 'named args with optional params omitted → created');
  pid2 := (r->>'post_id')::uuid;

  -- nokta bağlı değilken konum zorunlu (exception)
  begin
    perform create_community_post('note', 'konumsuz', null, null, null, null, null, null, null);
    raise exception 'FAIL: post without spot and location accepted';
  exception when invalid_parameter_value then
    perform tests.check(sqlerrm = 'invalid_coordinates', 'no spot and no lat/lng → invalid_coordinates exception');
  end;
  begin
    perform create_community_post(null, 'türsüz', null, null, null, b_lat, b_lng, null, null);
    raise exception 'FAIL: null kind accepted';
  exception when invalid_parameter_value then
    perform tests.check(sqlerrm = 'invalid_kind', 'null kind → invalid_kind exception');
  end;
  begin
    perform create_community_post('note', 'hayvansız', null, null, gen_random_uuid(), b_lat, b_lng, null, null);
    raise exception 'FAIL: unknown animal accepted';
  exception when no_data_found then
    perform tests.check(sqlerrm = 'not_found', 'unknown animal → not_found exception');
  end;
  perform tests.admin();

  select cell into c from community_posts where id = pid;
  perform tests.eq(extensions.st_y(c::extensions.geometry), 43.95::float8, 'cell lat rounded to 2 decimals (43.95123 → 43.95)');
  perform tests.eq(extensions.st_x(c::extensions.geometry), 29.06::float8, 'cell lng rounded to 2 decimals (29.05678 → 29.06)');
  perform tests.eq((select body from community_posts where id = pid), 'Pamuk bugün çok neşeliydi.', 'body stored trimmed');
  perform tests.check((select cover_from is null and cover_to is null from community_posts where id = pid),
                      'p_cover_* ignored for kinds other than cover_request');
  perform tests.check(not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'community_posts'
        and (column_name in ('lat', 'lng', 'location') or (udt_name = 'geography' and column_name <> 'cell'))),
    'community_posts stores no location other than the coarse cell');
  -- doğrudan (RPC dışı) yazımda da yuvarlanır
  update community_posts set cell = private.make_point(43.98765, 29.01234) where id = pid2;
  select cell into c from community_posts where id = pid2;
  perform tests.check(extensions.st_y(c::extensions.geometry) = 43.99 and extensions.st_x(c::extensions.geometry) = 29.01,
                      'direct cell write is rounded too (trigger)');

  perform tests.login(v);
  select * into pr from community_feed(b_lat, b_lng) f where f.id = pid;
  perform tests.eq(pr.id, pid, 'feed returns the nearby post');
  perform tests.check(abs(pr.distance_m - tests.dist(b_lat, b_lng, 43.95, 29.06)) < 1,
                      'feed distance_m is measured to the coarse cell');
  perform tests.eq(pr.kind, 'note'::community_post_kind, 'row kind');
  perform tests.eq(pr.author_id, a, 'row author_id');
  perform tests.eq(pr.author_name, 'Mahalle Yazar', 'row author_name');
  perform tests.eq(pr.author_is_verified, true, 'row author_is_verified');
  perform tests.eq(pr.animal_id, an, 'row animal_id');
  perform tests.eq(pr.animal_name, 'Mahalle Pamuk', 'row animal_name');
  perform tests.check(pr.spot_id is null and pr.spot_title is null, 'row without spot: spot_id/spot_title null');
  perform tests.check(pr.paw_count = 0 and pr.comment_count = 0 and pr.volunteer_count = 0
                      and not pr.viewer_pawed and not pr.viewer_volunteered, 'fresh post: zero counters, viewer flags false');
  perform tests.eq(pr.moderation_state, 'approved'::moderation_state, 'row moderation_state');

  select * into pr from community_post_detail(pid);
  perform tests.check(pr.id = pid and pr.distance_m is null, 'detail without location → distance_m null');
  select * into pr from community_post_detail(pid, b_lat, b_lng);
  perform tests.check(abs(pr.distance_m - tests.dist(b_lat, b_lng, 43.95, 29.06)) < 1, 'detail with location → distance_m');
  select count(*)::int into n from community_post_detail(gen_random_uuid());
  perform tests.eq(n, 0, 'detail of unknown post → 0 rows');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Akış: yarıçap (varsayılan 3000, en fazla 10 000), tür filtresi, keyset sayfalama, max_rows ≤ 50
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 3.5;   -- 44.45
  b_lng float8 := tests.base_lng();
  a     uuid := tests.make_user('Akış Yazar');
  v     uuid := tests.make_user('Akış Okur');
  p1    uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid;
  ids   uuid[];
  t2    timestamptz;
  t4    timestamptz;
  n     int;
begin
  -- created_at aynı transaction'da hep aynı olacağından satırlar doğrudan, açık zamanlarla eklenir
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', 'merkez 1', private.make_point(b_lat, b_lng), now() - interval '1 hour') returning id into p1;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'question', 'merkez 2', private.make_point(b_lat, b_lng), now() - interval '2 hours') returning id into p2;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'alert', 'merkez 3', private.make_point(b_lat, b_lng), now() - interval '3 hours') returning id into p3;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', '2 km', private.make_point(b_lat + 0.02, b_lng), now() - interval '4 hours') returning id into p4;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', '5,5 km', private.make_point(b_lat + 0.05, b_lng), now() - interval '5 hours') returning id into p5;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', '12 km', private.make_point(b_lat + 0.11, b_lng), now() - interval '6 hours') returning id into p6;

  perform tests.login(v);
  ids := array(select f.id from community_feed(b_lat, b_lng) f);
  perform tests.eq(ids, array[p1, p2, p3, p4], 'feed: default radius 3000 m, newest first');
  ids := array(select f.id from community_feed(b_lat, b_lng, 6000) f);
  perform tests.eq(ids, array[p1, p2, p3, p4, p5], 'feed: radius 6000 m includes the 5.5 km post');
  ids := array(select f.id from community_feed(b_lat, b_lng, 50000) f);
  perform tests.eq(ids, array[p1, p2, p3, p4, p5], 'feed: radius capped at 10 000 m (12 km post excluded)');
  ids := array(select f.id from community_feed(b_lat, b_lng, 1) f);
  perform tests.eq(ids, array[p1, p2, p3], 'feed: tiny radius is raised to the 1 km cell size');
  perform tests.check((select bool_and(f.distance_m <= 3000) and max(f.distance_m) > 2000 from community_feed(b_lat, b_lng) f),
                      'feed: distance_m within radius (2 km post ≈ 2.2 km)');

  ids := array(select f.id from community_feed(b_lat, b_lng, 3000, 'note') f);
  perform tests.eq(ids, array[p1, p4], 'feed: p_kind = note');
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_kind => 'question') f);
  perform tests.eq(ids, array[p2], 'feed: p_kind = question (named args)');
  select count(*)::int into n from community_feed(b_lat, b_lng, 3000, 'supply');
  perform tests.eq(n, 0, 'feed: p_kind with no posts → empty');

  -- keyset: sayfa 1 → son satırın created_at'i → sayfa 2 → boş sayfa
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, max_rows => 2) f);
  perform tests.eq(ids, array[p1, p2], 'feed page 1 (max_rows 2)');
  select f.created_at into t2 from community_feed(lat => b_lat, lng => b_lng, max_rows => 2) f where f.id = p2;
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_before => t2, max_rows => 2) f);
  perform tests.eq(ids, array[p3, p4], 'feed page 2 (p_before = last created_at of page 1): no overlap, no gap');
  select f.created_at into t4 from community_feed(b_lat, b_lng) f where f.id = p4;
  select count(*)::int into n from community_feed(lat => b_lat, lng => b_lng, p_before => t4, max_rows => 2);
  perform tests.eq(n, 0, 'feed page 3 is empty');
  ids := array(select f.id from community_feed(b_lat, b_lng, 3000, 'note', t2) f);
  perform tests.eq(ids, array[p4], 'feed: p_kind and p_before combine');
  select count(*)::int into n from community_feed(lat => b_lat, lng => b_lng, max_rows => 0);
  perform tests.eq(n, 1, 'feed: max_rows below 1 → 1 row');
  perform tests.admin();

  -- max_rows en fazla 50
  insert into community_posts (author_id, kind, body, cell, created_at)
  select a, 'note', 'dolgu ' || g, private.make_point(b_lat, b_lng), now() - make_interval(days => 1, mins => g)
  from generate_series(1, 55) g;
  perform tests.login(v);
  select count(*)::int into n from community_feed(lat => b_lat, lng => b_lng, max_rows => 1000);
  perform tests.eq(n, 50, 'feed: max_rows capped at 50');
  select count(*)::int into n from community_feed(b_lat, b_lng);
  perform tests.eq(n, 30, 'feed: default page size 30');
  perform tests.admin();
end
$$;

-- Keyset imleci milisaniye hassasiyetinde: istemci son satırın created_at'ini milisaniyeyle geri gönderir,
-- Postgres ise mikrosaniye saklar. Satırdaki created_at kırpılmış döner ve filtre aynı değere uygulanır;
-- sayfa sınırındaki satır tekrar gelmez, bir önceki milisaniyedeki satır da atlanmaz.
do $$
declare
  b_lat  float8 := tests.base_lat() + 3.75;   -- 44.70
  b_lng  float8 := tests.base_lng();
  a      uuid := tests.make_user('İmleç Yazar');
  v      uuid := tests.make_user('İmleç Okur');
  newer  uuid;
  older  uuid;
  oldest uuid;
  pr     community_post_row;
  ids    uuid[];
  cur    timestamptz;
begin
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', 'yeni (mikrosaniyeli)', private.make_point(b_lat, b_lng), '2026-11-04 10:00:00.123678+00') returning id into newer;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', 'bir önceki milisaniye', private.make_point(b_lat, b_lng), '2026-11-04 10:00:00.122999+00') returning id into older;
  insert into community_posts (author_id, kind, body, cell, created_at)
  values (a, 'note', 'en eski', private.make_point(b_lat, b_lng), '2026-11-04 09:00:00.000001+00') returning id into oldest;
  perform tests.eq((select created_at from community_posts where id = newer), timestamptz '2026-11-04 10:00:00.123678+00',
                   'stored created_at keeps its microseconds');

  perform tests.login(v);
  -- sayfa 1
  select * into pr from community_feed(lat => b_lat, lng => b_lng, max_rows => 1);
  perform tests.eq(pr.id, newer, 'cursor page 1 (max_rows 1) → newest post');
  perform tests.eq(pr.created_at, timestamptz '2026-11-04 10:00:00.123+00', 'feed created_at is truncated to milliseconds');
  perform tests.eq((select d.created_at from community_post_detail(newer) d), timestamptz '2026-11-04 10:00:00.123+00',
                   'detail created_at is truncated to milliseconds too');
  cur := pr.created_at;

  -- sayfa 2: dönen created_at aynen p_before olur
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_before => cur, max_rows => 1) f);
  perform tests.eq(ids, array[older], 'cursor page 2 → the other post (previous millisecond is not skipped)');
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_before => cur) f);
  perform tests.eq(ids, array[older, oldest], 'cursor page 2 never repeats the first post');
  -- istemcinin göndereceği metin biçimi (ISO-8601, milisaniye)
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_before => '2026-11-04T10:00:00.123Z', max_rows => 1) f);
  perform tests.eq(ids, array[older], 'cursor as ISO-8601 millisecond text gives the same page');

  -- sayfa 3 ve son
  select f.created_at into cur from community_feed(lat => b_lat, lng => b_lng, p_before => cur, max_rows => 1) f;
  perform tests.eq(cur, timestamptz '2026-11-04 10:00:00.122+00', 'page 2 cursor is truncated as well');
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_before => cur, max_rows => 1) f);
  perform tests.eq(ids, array[oldest], 'cursor page 3 → oldest post');
  select f.created_at into cur from community_feed(lat => b_lat, lng => b_lng, p_before => cur, max_rows => 1) f;
  ids := array(select f.id from community_feed(lat => b_lat, lng => b_lng, p_before => cur, max_rows => 1) f);
  perform tests.eq(coalesce(array_length(ids, 1), 0), 0, 'cursor walk ends with an empty page (3 posts, 3 pages, no repeats)');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Metin kuralları (trim sonrası 1–600), küfür filtresi
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 4.0;
  b_lng float8 := tests.base_lng();
  u     uuid := tests.make_user('Metin');
  r     jsonb;
  bad   text;
begin
  perform tests.login(u);
  foreach bad in array array['', '     ', E' \n\t\r\n '] loop
    r := create_community_post('note', bad, null, null, null, b_lat, b_lng, null, null);
    perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'body_empty', 'blank body → invalid/body_empty');
  end loop;
  r := create_community_post('note', null, null, null, null, b_lat, b_lng, null, null);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'body_empty', 'null body → invalid/body_empty');

  r := create_community_post('note', repeat('a', 601), null, null, null, b_lat, b_lng, null, null);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'body_too_long', '601 chars → invalid/body_too_long');
  r := create_community_post('note', E'  \n' || repeat('ş', 600) || E'\n  ', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'created', '600 chars after trim → created');

  r := create_community_post('note', 'Siktir git buradan', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'rejected_content', 'profanity → rejected_content');
  perform tests.check(not (r ? 'post_id'), 'rejected_content carries no post_id');
  r := create_community_post('question', 'Yavru kedi ağaçta sıkışmış, kim yardım edebilir?', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'created', '"sıkışmış" is not profanity → created');
  perform tests.admin();
  perform tests.eq((select count(*)::int from community_posts where author_id = u), 2, 'only valid posts are stored');
end
$$;

-- ---------------------------------------------------------------------------
-- Günlük limitler (İstanbul günü): 10 paylaşım, 60 yorum
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 4.3;
  b_lng float8 := tests.base_lng();
  u     uuid := tests.make_user('Limit');
  o     uuid := tests.make_user('Limit Diğer');
  pid   uuid;
  r     jsonb;
begin
  -- dün atılan paylaşımlar/yorumlar bugünün limitine sayılmaz
  insert into community_posts (author_id, kind, body, cell, created_at)
  select u, 'note', 'dün ' || g, private.make_point(b_lat, b_lng), private.istanbul_day_start() - interval '1 minute'
  from generate_series(1, 5) g;
  insert into community_posts (author_id, kind, body, cell)
  select u, 'note', 'bugün ' || g, private.make_point(b_lat, b_lng) from generate_series(1, 9) g;
  insert into community_posts (author_id, kind, body, cell) values (o, 'note', 'yorumlanacak', private.make_point(b_lat, b_lng))
  returning id into pid;

  perform tests.login(u);
  r := create_community_post('note', 'onuncu', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'created', '10th post today → created');
  r := create_community_post('note', 'on birinci', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'limit_reached', '11th post today → limit_reached');
  perform tests.eq((r->>'limit')::int, 10, 'post limit_reached reports limit 10');
  perform tests.login(o);
  r := create_community_post('note', 'başkası', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'created', 'post limit is per user');
  perform tests.admin();

  insert into community_comments (post_id, author_id, body, created_at)
  select pid, u, 'dün ' || g, private.istanbul_day_start() - interval '1 minute' from generate_series(1, 5) g;
  insert into community_comments (post_id, author_id, body)
  select pid, u, 'bugün ' || g from generate_series(1, 59) g;

  perform tests.login(u);
  r := add_community_comment(pid, 'altmışıncı');
  perform tests.eq(r->>'status', 'created', '60th comment today → created');
  r := add_community_comment(pid, 'altmış birinci');
  perform tests.eq(r->>'status', 'limit_reached', '61st comment today → limit_reached');
  perform tests.eq((r->>'limit')::int, 60, 'comment limit_reached reports limit 60');
  perform tests.login(o);
  r := add_community_comment(pid, 'başkasının yorumu');
  perform tests.eq(r->>'status', 'created', 'comment limit is per user');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- "Yerime bakar mısın?": görünür nokta zorunlu, tarih kuralları, cell noktadan
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat  float8 := tests.base_lat() + 4.6;   -- 45.55
  b_lng  float8 := tests.base_lng();
  o      uuid := tests.make_user('Emanet eden');
  o2     uuid := tests.make_user('Emanet eden 2');
  other  uuid := tests.make_user('Başka nokta sahibi');
  s_pub  uuid := tests.make_spot(b_lat + 0.00412, b_lng + 0.00389, 'Emanet noktası', 'public', o);
  s_fuz  uuid := tests.make_spot(b_lat + 0.02,    b_lng,           'Bulanık emanet', 'fuzzed', other);
  s_prv  uuid := tests.make_spot(b_lat + 0.03,    b_lng,           'Özel emanet',    'private', other);
  s_pend uuid := tests.make_spot(b_lat + 0.01,    b_lng,           'Başkasının onaysız noktası', 'public', other);
  today  date := private.istanbul_today();
  r      jsonb;
  pid    uuid;
  pr     community_post_row;
  c      extensions.geography;
  fz     extensions.geography;
  loc    extensions.geography;
begin
  update spots set moderation_state = 'pending' where id = s_pend;

  -- Bulanık noktayı, gerçek konumu ile GÖSTERİLEN (bulanık) konumu ızgaranın farklı hücrelerine düşecek
  -- şekilde yerleştir: bulanıklık ofseti yalnızca nokta id'sine bağlıdır, bu yüzden ikisinin orta
  -- noktası bir hücre köşesine (x.xx5, y.yy5) getirilir.
  select s.location, private.fuzz_point(s.id, s.location) into loc, fz from spots s where s.id = s_fuz;
  update spots
     set location = private.make_point(
           (b_lat + 0.025) - (extensions.st_y(fz::extensions.geometry) - extensions.st_y(loc::extensions.geometry)) / 2,
           (b_lng + 0.005) - (extensions.st_x(fz::extensions.geometry) - extensions.st_x(loc::extensions.geometry)) / 2)
   where id = s_fuz;

  perform tests.login(o);
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, null, null, b_lat, b_lng, today, today + 2);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'cover_needs_spot', 'cover_request without spot → cover_needs_spot');
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, null, null, null, null, today, today + 2);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'cover_needs_spot',
                      'cover_request without spot and location → cover_needs_spot (not an exception)');

  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, s_pub, null, null, null, null, null);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'cover_dates', 'missing dates → cover_dates');
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, s_pub, null, null, null, today, null);
  perform tests.check(r->>'reason' = 'cover_dates', 'missing cover_to → cover_dates');
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, s_pub, null, null, null, today - 1, today + 2);
  perform tests.check(r->>'reason' = 'cover_dates', 'cover_from in the past → cover_dates');
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, s_pub, null, null, null, today + 3, today + 2);
  perform tests.check(r->>'reason' = 'cover_dates', 'cover_to before cover_from → cover_dates');
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, s_pub, null, null, null, today + 1, today + 32);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'cover_dates', '31-day span → cover_dates');

  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, s_pend, null, null, null, today, today + 2);
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'spot_not_found',
                      'spot not visible to the author (someone else''s pending spot) → spot_not_found');
  r := create_community_post('cover_request', 'Yerime bakar mısın?', null, gen_random_uuid(), null, null, null, today, today + 2);
  perform tests.check(r->>'reason' = 'spot_not_found', 'unknown spot → spot_not_found');
  r := create_community_post('note', 'Bu noktada yeni kap var', null, s_pend, null, b_lat, b_lng, null, null);
  perform tests.check(r->>'reason' = 'spot_not_found', 'any kind linked to an invisible spot → spot_not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from community_posts where author_id = o), 0, 'invalid cover requests store nothing');

  perform tests.login(o);
  r := create_community_post('cover_request', 'Hafta sonu yokum, bakabilecek var mı?', null, s_pub, null, null, null, today + 1, today + 31);
  perform tests.eq(r->>'status', 'created', '30-day span with a visible spot → created (lat/lng not needed)');
  pid := (r->>'post_id')::uuid;
  r := create_community_post('cover_request', 'Bugünlük bakar mısınız?', null, s_pub, null, 10, 10, today, today);
  perform tests.eq(r->>'status', 'created', 'cover_from = cover_to = today → created');
  perform tests.admin();

  select cell into c from community_posts where id = pid;
  perform tests.check(extensions.st_y(c::extensions.geometry) = 45.55 and extensions.st_x(c::extensions.geometry) = 29.05,
                      'cell derived from the spot location, rounded to 2 decimals');
  perform tests.check((select bool_and(extensions.st_y(cell::extensions.geometry) = 45.55) from community_posts where author_id = o),
                      'client lat/lng ignored when a spot is linked');
  perform tests.check((select cover_from = today + 1 and cover_to = today + 31 from community_posts where id = pid),
                      'cover dates stored');

  perform tests.login(o2);
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.spot_id = s_pub and pr.spot_title = 'Emanet noktası', 'cover request row carries spot_id and spot_title');
  perform tests.check(pr.cover_from = today + 1 and pr.cover_to = today + 31, 'cover request row carries dates');

  -- private noktalar giriş yapmış herkese (bulanık) görünür: bağlanabilir. Bulanık/özel noktalarda cell
  -- GÖSTERİLEN konumdan türetilir (PRD 9.1).
  r := create_community_post('cover_request', 'Özel noktaya bakacak var mı?', null, s_prv, null, null, null, today, today + 1);
  perform tests.eq(r->>'status', 'created', 'private spot is visible to signed-in users → created');
  r := create_community_post('cover_request', 'Bulanık noktaya bakacak var mı?', null, s_fuz, null, null, null, today, today + 1);
  perform tests.eq(r->>'status', 'created', 'fuzzed spot → created');
  pid := (r->>'post_id')::uuid;
  perform tests.admin();
  select cell into c from community_posts where id = pid;
  select s.location, private.fuzz_point(s.id, s.location) into loc, fz from spots s where s.id = s_fuz;
  perform tests.check(round(extensions.st_y(loc::extensions.geometry)::numeric, 2) <> round(extensions.st_y(fz::extensions.geometry)::numeric, 2)
                      or round(extensions.st_x(loc::extensions.geometry)::numeric, 2) <> round(extensions.st_x(fz::extensions.geometry)::numeric, 2),
                      'setup: true and displayed location of the fuzzed spot fall into different cells');
  perform tests.check(extensions.st_y(c::extensions.geometry) = round(extensions.st_y(fz::extensions.geometry)::numeric, 2)::float8
                      and extensions.st_x(c::extensions.geometry) = round(extensions.st_x(fz::extensions.geometry)::numeric, 2)::float8,
                      'fuzzed spot: cell derived from the displayed (fuzzed) point, not the true location (PRD 9.1)');
end
$$;

-- ---------------------------------------------------------------------------
-- Düşük güven puanı (trust_score < 5) → pending: yalnızca yazarına (ve moderatöre) görünür
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 4.9;
  b_lng float8 := tests.base_lng();
  low   uuid := tests.make_user('Düşük güven', 4);
  edge  uuid := tests.make_user('Sınırda güven', 5);
  other uuid := tests.make_user('Sıradan okur');
  m     uuid := tests.make_user('Mahalle moderatörü', 50, false, true);
  r     jsonb;
  pid   uuid;
  pr    community_post_row;
  n     int;
begin
  perform tests.login(edge);
  r := create_community_post('note', 'Güven puanım tam 5', null, null, null, b_lat + 0.3, b_lng, null, null);
  perform tests.eq(r->>'moderation_state', 'approved', 'trust_score = 5 → approved');

  perform tests.login(low);
  r := create_community_post('note', 'İlk paylaşımım', null, null, null, b_lat, b_lng, null, null);
  perform tests.eq(r->>'status', 'created', 'low-trust post → created');
  perform tests.eq(r->>'moderation_state', 'pending', 'trust_score < 5 → moderation_state pending');
  pid := (r->>'post_id')::uuid;

  select * into pr from community_feed(b_lat, b_lng) f where f.id = pid;
  perform tests.check(pr.id = pid and pr.moderation_state = 'pending', 'author sees own pending post in the feed (flagged pending)');
  select count(*)::int into n from community_post_detail(pid);
  perform tests.eq(n, 1, 'author sees own pending post detail');
  r := add_community_comment(pid, 'Kendi paylaşımıma not');
  perform tests.eq(r->>'status', 'created', 'author can comment on own pending post');

  perform tests.login(other);
  select count(*)::int into n from community_feed(b_lat, b_lng);
  perform tests.eq(n, 0, 'others do not see a pending post in the feed');
  select count(*)::int into n from community_post_detail(pid);
  perform tests.eq(n, 0, 'others get 0 rows from detail of a pending post');
  select count(*)::int into n from community_comments_of(pid);
  perform tests.eq(n, 0, 'others get no comments of a pending post');
  perform tests.eq(add_community_comment(pid, 'göremediğim paylaşım')->>'status', 'post_not_found', 'comment on hidden post → post_not_found');
  perform tests.eq(toggle_post_paw(pid)->>'status', 'post_not_found', 'paw on hidden post → post_not_found');
  perform tests.eq((select posts_7d from community_summary(b_lat, b_lng)), 0, 'pending post not counted in posts_7d');

  perform tests.login(m);
  select count(*)::int into n from community_post_detail(pid);
  perform tests.eq(n, 1, 'moderator sees pending post');
  perform tests.admin();

  -- moderatör reddederse yazarına da görünmez
  update community_posts set moderation_state = 'rejected' where id = pid;
  perform tests.login(low);
  select count(*)::int into n from community_post_detail(pid);
  perform tests.eq(n, 0, 'rejected post is hidden from its author');
  perform tests.login(m);
  select count(*)::int into n from community_post_detail(pid);
  perform tests.eq(n, 1, 'moderator still sees rejected post');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Pati: aç/kapat, sayaç, viewer_pawed
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 5.2;
  b_lng float8 := tests.base_lng();
  a     uuid := tests.make_user('Pati Yazar');
  u1    uuid := tests.make_user('Pati 1');
  u2    uuid := tests.make_user('Pati 2');
  r     jsonb;
  pid   uuid;
  pr    community_post_row;
begin
  perform tests.login(a);
  pid := (create_community_post('note', 'Pati bekleyen paylaşım', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;

  perform tests.login(u1);
  r := toggle_post_paw(pid);
  perform tests.check(r->>'status' = 'ok' and (r->>'pawed')::boolean and (r->>'paw_count')::int = 1, 'first paw → pawed, count 1');
  perform tests.login(u2);
  r := toggle_post_paw(pid);
  perform tests.check((r->>'pawed')::boolean and (r->>'paw_count')::int = 2, 'second user paw → count 2');
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.paw_count = 2 and pr.viewer_pawed, 'row: paw_count 2, viewer_pawed true for a user who pawed');

  perform tests.login(a);
  select * into pr from community_feed(b_lat, b_lng) f where f.id = pid;
  perform tests.check(pr.paw_count = 2 and not pr.viewer_pawed, 'row: viewer_pawed false for a user who did not');
  r := toggle_post_paw(pid);
  perform tests.check((r->>'pawed')::boolean and (r->>'paw_count')::int = 3, 'author may paw own post');

  perform tests.login(u1);
  r := toggle_post_paw(pid);
  perform tests.check(r->>'status' = 'ok' and not (r->>'pawed')::boolean and (r->>'paw_count')::int = 2, 'toggle again → paw removed, count 2');
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.paw_count = 2 and not pr.viewer_pawed, 'row after un-paw: viewer_pawed false');
  perform tests.eq(toggle_post_paw(gen_random_uuid())->>'status', 'post_not_found', 'paw on unknown post → post_not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from community_paws where post_id = pid), 2, 'two paw rows stored');
  perform tests.eq((select count(*)::int from notifications where user_id = a), 0, 'paws do not notify');
end
$$;

-- ---------------------------------------------------------------------------
-- "Ben bakarım": toggle sonuçları, viewer_volunteered, cover_volunteers_of, cover_volunteered bildirimi
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat  float8 := tests.base_lat() + 5.5;
  b_lng  float8 := tests.base_lng();
  o      uuid := tests.make_user('Tatile giden');
  quiet  uuid := tests.make_user('Bildirim istemeyen');
  v1     uuid := tests.make_user('Gönüllü Bir', 10, true);
  v2     uuid := tests.make_user('Gönüllü İki');
  s      uuid := tests.make_spot(b_lat, b_lng, 'Sahil kulübesi', 'public', o);
  today  date := private.istanbul_today();
  r      jsonb;
  pid    uuid;
  note   uuid;
  qpid   uuid;
  pr     community_post_row;
  nt     notifications;
  n      int;
begin
  perform tests.login(o);
  pid := (create_community_post('cover_request', 'Üç gün yokum, bakar mısınız?', null, s, null, null, null, today, today + 3)->>'post_id')::uuid;
  note := (create_community_post('note', 'Sıradan paylaşım', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.eq(toggle_cover_volunteer(pid)->>'status', 'own_post', 'author volunteering on own request → own_post');
  perform tests.login(quiet);
  qpid := (create_community_post('cover_request', 'Bana bildirim gelmesin', null, s, null, null, null, today, today + 1)->>'post_id')::uuid;
  perform tests.admin();
  update notification_prefs set community_updates = false where user_id = quiet;

  perform tests.login(v1);
  perform tests.eq(toggle_cover_volunteer(note)->>'status', 'not_cover_request', 'volunteering on a note → not_cover_request');
  perform tests.eq(toggle_cover_volunteer(gen_random_uuid())->>'status', 'post_not_found', 'volunteering on unknown post → post_not_found');
  r := toggle_cover_volunteer(pid);
  perform tests.check(r->>'status' = 'ok' and (r->>'volunteered')::boolean and (r->>'volunteer_count')::int = 1,
                      'first volunteer → ok, volunteered, count 1');
  perform toggle_cover_volunteer(qpid);
  perform tests.admin();

  -- yazara cover_volunteered (post_id ve spot_id dolu)
  perform tests.eq((select count(*)::int from notifications where user_id = o and kind = 'cover_volunteered'), 1,
                   'author gets one cover_volunteered notification');
  select * into nt from notifications where user_id = o and kind = 'cover_volunteered';
  perform tests.eq(nt.post_id, pid, 'cover_volunteered carries post_id');
  perform tests.eq(nt.spot_id, s, 'cover_volunteered carries spot_id');
  perform tests.eq(nt.title, 'Yerine bakacak biri var!', 'cover_volunteered title');
  perform tests.eq(nt.body, 'Gönüllü Bir, Sahil kulübesi için "Ben bakarım" dedi.', 'cover_volunteered body');
  perform tests.check(nt.read_at is null and nt.pushed_at is null, 'cover_volunteered is unread and queued for push');
  perform tests.eq((select count(*)::int from notifications where user_id = quiet), 0,
                   'community_updates = false → no cover_volunteered');
  perform tests.eq((select count(*)::int from notifications where user_id = v1), 0, 'volunteer gets no notification');

  perform tests.login(v2);
  r := toggle_cover_volunteer(pid);
  perform tests.check((r->>'volunteered')::boolean and (r->>'volunteer_count')::int = 2, 'second volunteer → count 2');
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.volunteer_count = 2 and pr.viewer_volunteered, 'row: volunteer_count 2, viewer_volunteered true');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = o and kind = 'cover_volunteered'), 1,
                   'no second cover_volunteered while one is unread for the same post');

  perform tests.login(o);
  select * into pr from community_feed(b_lat, b_lng) f where f.id = pid;
  perform tests.check(pr.volunteer_count = 2 and not pr.viewer_volunteered, 'row for the author: viewer_volunteered false');
  select count(*)::int into n from cover_volunteers_of(pid);
  perform tests.eq(n, 2, 'cover_volunteers_of lists both volunteers');
  perform tests.check((select bool_or(cv.user_id = v1 and cv.display_name = 'Gönüllü Bir' and cv.is_verified_feeder)
                              and bool_or(cv.user_id = v2 and cv.display_name = 'Gönüllü İki' and not cv.is_verified_feeder)
                       from cover_volunteers_of(pid) cv), 'cover_volunteers_of returns names and verified flags');
  select count(*)::int into n from cover_volunteers_of(note);
  perform tests.eq(n, 0, 'cover_volunteers_of on a note → empty');
  update notifications set read_at = now() where user_id = o;   -- yazar bildirimi okudu

  -- vazgeç → tekrar gönüllü ol: okunmamış bildirim kalmadığı için yenisi gelir
  perform tests.login(v2);
  r := toggle_cover_volunteer(pid);
  perform tests.check(r->>'status' = 'ok' and not (r->>'volunteered')::boolean and (r->>'volunteer_count')::int = 1,
                      'toggle again → withdrawn, count 1');
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.volunteer_count = 1 and not pr.viewer_volunteered, 'row after withdrawing: viewer_volunteered false');
  perform toggle_cover_volunteer(pid);
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = o and kind = 'cover_volunteered'), 2,
                   'new cover_volunteered once the previous one was read');

  -- engel: gönüllü listesi ve sayısı izleyiciye göre
  insert into blocks (user_id, blocked_user_id) values (v1, v2);
  perform tests.login(v1);
  select * into pr from community_post_detail(pid);
  perform tests.eq(pr.volunteer_count, 1, 'volunteer_count skips volunteers blocked with the viewer');
  perform tests.eq((select array_agg(cv.user_id) from cover_volunteers_of(pid) cv), array[v1],
                   'cover_volunteers_of hides volunteers blocked with the viewer');
  perform tests.admin();
  delete from blocks where user_id = v1;

  -- bitiş günü dahil açık; geçince closed
  update community_posts set cover_from = today - 3, cover_to = today where id = pid;
  perform tests.login(v1);
  perform tests.eq(toggle_cover_volunteer(pid)->>'status', 'ok', 'cover_to = today → still open');
  perform tests.admin();
  update community_posts set cover_from = today - 4, cover_to = today - 1 where id = pid;
  perform tests.login(v1);
  perform tests.eq(toggle_cover_volunteer(pid)->>'status', 'closed', 'cover_to in the past → closed');
  perform tests.login(v2);
  perform tests.eq(toggle_cover_volunteer(pid)->>'status', 'closed', 'closed for withdrawing too');
  perform tests.admin();
  perform tests.eq((select count(*)::int from cover_volunteers where post_id = pid), 1, 'closed toggle changes nothing');
end
$$;

-- ---------------------------------------------------------------------------
-- Yorumlar: kurallar, sıra, community_comment bildirimi ve bastırma koşulları
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat   float8 := tests.base_lat() + 5.8;
  b_lng   float8 := tests.base_lng();
  a       uuid := tests.make_user('Yorum Yazar');
  quiet   uuid := tests.make_user('Yorum sessiz');
  noprefs uuid := tests.make_user('Yorum tercihsiz');
  c1      uuid := tests.make_user('Yorumcu Bir', 10, true);
  c2      uuid := tests.make_user('Yorumcu İki');
  blk     uuid := tests.make_user('Yorum engelli');
  r       jsonb;
  pid     uuid;
  qpid    uuid;
  npid    uuid;
  cid1    uuid;
  cid2    uuid;
  cid3    uuid;
  nt      notifications;
  pr      community_post_row;
  cr      community_comment_row;
  long_c  text := 'Bu çok uzun bir yorum:' || E'\n\n' || repeat('mama ', 40);
begin
  perform tests.login(a);
  pid := (create_community_post('question', 'Yaşlı kediler için mama öneriniz var mı?', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.login(quiet);
  qpid := (create_community_post('note', 'Bildirim istemiyorum', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.login(noprefs);
  npid := (create_community_post('note', 'Tercih satırım yok', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.admin();
  update notification_prefs set community_updates = false where user_id = quiet;
  delete from notification_prefs where user_id = noprefs;
  insert into blocks (user_id, blocked_user_id) values (a, blk);

  -- metin kuralları
  perform tests.login(c1);
  r := add_community_comment(pid, E' \n ');
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'body_empty', 'blank comment → invalid/body_empty');
  r := add_community_comment(pid, repeat('a', 301));
  perform tests.check(r->>'status' = 'invalid' and r->>'reason' = 'body_too_long', '301 chars → invalid/body_too_long');
  r := add_community_comment(pid, 'orospu çocuğu');
  perform tests.eq(r->>'status', 'rejected_content', 'profane comment → rejected_content');
  r := add_community_comment(gen_random_uuid(), 'kayıp paylaşım');
  perform tests.eq(r->>'status', 'post_not_found', 'comment on unknown post → post_not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = a), 0, 'rejected comments do not notify');

  perform tests.login(c1);
  r := add_community_comment(pid, E'  Pate mama deneyin.\n');
  perform tests.eq(r->>'status', 'created', 'comment → created');
  cid1 := (r->>'comment_id')::uuid;
  perform tests.admin();

  -- yazara community_comment (post_id dolu)
  perform tests.eq((select count(*)::int from notifications where user_id = a and kind = 'community_comment'), 1,
                   'post author gets one community_comment notification');
  select * into nt from notifications where user_id = a and kind = 'community_comment';
  perform tests.eq(nt.post_id, pid, 'community_comment carries post_id');
  perform tests.eq(nt.title, 'Paylaşımına yorum geldi', 'community_comment title');
  perform tests.eq(nt.body, 'Yorumcu Bir: Pate mama deneyin.', 'community_comment body = "{name}: {comment}"');
  perform tests.check(nt.read_at is null and nt.pushed_at is null and nt.spot_id is null, 'community_comment is unread, unpushed, no spot');

  -- aynı paylaşım için okunmamış bildirim varken ikincisi gelmez
  perform tests.login(c2);
  r := add_community_comment(pid, repeat('b', 300));
  perform tests.eq(r->>'status', 'created', '300-char comment → created');
  cid2 := (r->>'comment_id')::uuid;
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = a and kind = 'community_comment'), 1,
                   'no second community_comment while one is unread for the same post');

  -- yazar okudu → sonraki yorum yeniden bildirir (uzun yorum ~80 karaktere kısalır)
  perform tests.login(a);
  update notifications set read_at = now() where user_id = a;
  perform tests.login(c2);
  cid3 := (add_community_comment(pid, long_c)->>'comment_id')::uuid;
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = a and kind = 'community_comment'), 2,
                   'new community_comment once the previous one was read');
  select * into nt from notifications where user_id = a and kind = 'community_comment' and read_at is null;
  perform tests.check(nt.body like 'Yorumcu İki: Bu çok uzun bir yorum: mama mama%' and right(nt.body, 1) = '…'
                      and char_length(nt.body) <= char_length('Yorumcu İki: ') + 81,
                      'long comment is excerpted to ~80 chars on one line');

  -- kendi paylaşımına yorum: bildirim yok
  update notifications set read_at = now() where user_id = a;
  perform tests.login(a);
  perform tests.eq(add_community_comment(pid, 'Teşekkürler!')->>'status', 'created', 'author comments on own post');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = a and read_at is null), 0,
                   'own comment → no notification');

  -- tercih kapalı → yok; tercih satırı yok → varsayılan açık
  perform tests.login(c1);
  perform add_community_comment(qpid, 'Sessiz paylaşıma yorum');
  perform add_community_comment(npid, 'Tercihsiz paylaşıma yorum');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = quiet), 0, 'community_updates = false → no community_comment');
  perform tests.eq((select count(*)::int from notifications where user_id = noprefs and kind = 'community_comment' and post_id = npid), 1,
                   'missing prefs row defaults to community_updates = true');

  -- engelli taraf paylaşımı göremez, yorum yazamaz, bildirim üretemez
  perform tests.login(blk);
  perform tests.eq(add_community_comment(pid, 'Engelliyim ama yazıyorum')->>'status', 'post_not_found',
                   'blocked user commenting → post_not_found');
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = a and read_at is null), 0, 'blocked user → no notification');
  perform tests.eq((select count(*)::int from community_comments where author_id = blk), 0, 'blocked user → no comment stored');

  -- sıra (created_at artan) ve satır şekli
  update community_comments set created_at = now() - interval '3 minutes' where id = cid1;
  update community_comments set created_at = now() - interval '2 minutes' where id = cid2;
  update community_comments set created_at = now() - interval '1 minute'  where id = cid3;
  perform tests.login(c2);
  perform tests.eq((select array_agg(c.id) from (select cc.id from community_comments_of(pid) cc limit 3) c), array[cid1, cid2, cid3],
                   'community_comments_of ordered by created_at ascending');
  select * into cr from community_comments_of(pid) cc where cc.id = cid1;
  perform tests.check(cr.post_id = pid and cr.body = 'Pate mama deneyin.' and cr.author_id = c1
                      and cr.author_name = 'Yorumcu Bir' and cr.author_is_verified, 'comment row: trimmed body + author fields');
  select * into pr from community_post_detail(pid);
  perform tests.eq(pr.comment_count, 4, 'row comment_count counts visible comments');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Engelleme: iki yönde paylaşım ve yorum görünmez, comment_count'a girmez
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 6.1;
  b_lng float8 := tests.base_lng();
  a     uuid := tests.make_user('Engel Yazar');
  x     uuid := tests.make_user('A''yı engelleyen');
  y     uuid := tests.make_user('A''nın engellediği');
  z     uuid := tests.make_user('Tarafsız');
  pa    uuid;
  px    uuid;
  pz    uuid;
  pr    community_post_row;
  n     int;
begin
  perform tests.login(a);
  pa := (create_community_post('note', 'A''nın paylaşımı', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.login(x);
  px := (create_community_post('note', 'X''in paylaşımı', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.login(z);
  pz := (create_community_post('note', 'Z''nin paylaşımı', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform add_community_comment(pz, 'Z''nin yorumu');
  perform tests.login(a);
  perform add_community_comment(pz, 'A''nın yorumu');
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (x, a), (a, y);

  -- x, a'yı engelledi: x a'yı görmez, a da x'i görmez
  perform tests.login(x);
  perform tests.eq(array(select f.id from community_feed(b_lat, b_lng) f where f.id in (pa, px, pz) order by f.id),
                   array(select u from unnest(array[px, pz]) u order by u), 'blocker does not see the blocked author''s post in the feed');
  select count(*)::int into n from community_post_detail(pa);
  perform tests.eq(n, 0, 'blocker gets 0 rows from detail');
  perform tests.eq(toggle_post_paw(pa)->>'status', 'post_not_found', 'blocker cannot paw the hidden post');
  select count(*)::int into n from community_comments_of(pz);
  perform tests.eq(n, 1, 'blocker does not see the blocked user''s comment');
  select * into pr from community_post_detail(pz);
  perform tests.eq(pr.comment_count, 1, 'comment_count excludes the blocked user''s comment');
  perform tests.eq((select posts_7d from community_summary(b_lat, b_lng)), 2, 'summary posts_7d excludes blocked authors');

  perform tests.login(a);
  select count(*)::int into n from community_feed(b_lat, b_lng) f where f.id = px;
  perform tests.eq(n, 0, 'blocked author does not see the blocker''s post either');
  select count(*)::int into n from community_post_detail(px);
  perform tests.eq(n, 0, 'blocked author gets 0 rows from the blocker''s post detail');

  -- a, y'yi engelledi: aynı kurallar ters yönde
  perform tests.login(y);
  select count(*)::int into n from community_feed(b_lat, b_lng) f where f.id = pa;
  perform tests.eq(n, 0, 'user blocked by the author does not see the post');
  select count(*)::int into n from community_post_detail(pa);
  perform tests.eq(n, 0, 'user blocked by the author gets 0 rows from detail');
  select count(*)::int into n from community_comments_of(pz);
  perform tests.eq(n, 1, 'user blocked by a commenter does not see that comment');
  select * into pr from community_feed(b_lat, b_lng) f where f.id = pz;
  perform tests.eq(pr.comment_count, 1, 'comment_count excludes comments of the user who blocked the viewer');

  perform tests.login(z);
  select count(*)::int into n from community_feed(b_lat, b_lng) f where f.id in (pa, px, pz);
  perform tests.eq(n, 3, 'neutral user sees all posts');
  select * into pr from community_post_detail(pz);
  perform tests.eq(pr.comment_count, 2, 'neutral user: comment_count counts both comments');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Bağlı nokta izleyene görünmüyorsa spot_id / spot_title null
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 6.4;
  b_lng float8 := tests.base_lng();
  a     uuid := tests.make_user('Nokta sahibi yazar');
  v     uuid := tests.make_user('Noktayı göremeyen');
  m     uuid := tests.make_user('Nokta moderatörü', 50, false, true);
  s     uuid := tests.make_spot(b_lat, b_lng, 'Onay bekleyen gizli nokta', 'public', a);
  pid   uuid;
  pr    community_post_row;
begin
  update spots set moderation_state = 'pending' where id = s;

  perform tests.login(a);
  pid := (create_community_post('note', 'Yeni noktama mama koydum', null, s, null, null, null, null, null)->>'post_id')::uuid;
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.spot_id = s and pr.spot_title = 'Onay bekleyen gizli nokta', 'author (spot creator) sees spot_id and spot_title');

  perform tests.login(v);
  select * into pr from community_feed(b_lat, b_lng) f where f.id = pid;
  perform tests.check(pr.id = pid and pr.spot_id is null and pr.spot_title is null,
                      'viewer who cannot see the spot: post visible, spot_id and spot_title null');
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.spot_id is null and pr.spot_title is null, 'detail hides the invisible spot too');

  perform tests.login(m);
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.spot_id = s and pr.spot_title is not null, 'moderator sees the linked pending spot');
  perform tests.admin();

  -- nokta onaylanınca herkese görünür; silinince bağ kopar, paylaşım kalır
  update spots set moderation_state = 'approved' where id = s;
  perform tests.login(v);
  select * into pr from community_post_detail(pid);
  perform tests.eq(pr.spot_title, 'Onay bekleyen gizli nokta', 'spot_title appears once the spot is visible');
  perform tests.admin();
  delete from spots where id = s;
  perform tests.login(v);
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.id = pid and pr.spot_id is null, 'deleting the spot keeps the post (spot_id → null)');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Silme yetkileri
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat    float8 := tests.base_lat() + 6.7;
  b_lng    float8 := tests.base_lng();
  a        uuid := tests.make_user('Silme Yazar');
  c        uuid := tests.make_user('Silme Yorumcu');
  stranger uuid := tests.make_user('Silme Yabancı');
  m        uuid := tests.make_user('Silme Moderatör', 50, false, true);
  s        uuid := tests.make_spot(b_lat, b_lng, 'Silme noktası', 'public', a);
  today    date := private.istanbul_today();
  p1       uuid;
  p2       uuid;
  c1       uuid;
  c2       uuid;
  c3       uuid;
begin
  perform tests.login(a);
  p1 := (create_community_post('cover_request', 'Silinecek istek', null, s, null, null, null, today, today + 1)->>'post_id')::uuid;
  p2 := (create_community_post('note', 'Moderatörün sileceği paylaşım', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.login(c);
  c1 := (add_community_comment(p1, 'Kendi sileceğim yorum')->>'comment_id')::uuid;
  c2 := (add_community_comment(p1, 'Paylaşım sahibinin sileceği yorum')->>'comment_id')::uuid;
  perform toggle_post_paw(p1);
  perform toggle_cover_volunteer(p1);
  perform tests.login(stranger);
  c3 := (add_community_comment(p1, 'Moderatörün sileceği yorum')->>'comment_id')::uuid;

  perform tests.eq(delete_community_post(p1)->>'status', 'not_allowed', 'stranger deleting a post → not_allowed');
  perform tests.eq(delete_community_comment(c1)->>'status', 'not_allowed', 'stranger deleting someone else''s comment → not_allowed');
  perform tests.login(c);
  perform tests.eq(delete_community_post(p1)->>'status', 'not_allowed', 'commenter deleting the post → not_allowed');
  perform tests.eq(delete_community_comment(c3)->>'status', 'not_allowed', 'commenter deleting another commenter''s comment → not_allowed');
  perform tests.admin();
  perform tests.eq((select count(*)::int from community_comments where post_id = p1), 3, 'not_allowed deletes nothing');

  perform tests.login(c);
  perform tests.eq(delete_community_comment(c1)->>'status', 'ok', 'comment author deletes own comment');
  perform tests.login(a);
  perform tests.eq(delete_community_comment(c2)->>'status', 'ok', 'post author deletes a comment under own post');
  perform tests.login(m);
  perform tests.eq(delete_community_comment(c3)->>'status', 'ok', 'moderator deletes any comment');
  perform tests.eq(delete_community_post(p2)->>'status', 'ok', 'moderator deletes any post');
  begin
    perform delete_community_comment(c3);
    raise exception 'FAIL: deleting a missing comment succeeded';
  exception when no_data_found then
    perform tests.check(sqlerrm = 'not_found', 'deleting an unknown comment → not_found exception');
  end;
  perform tests.admin();
  perform tests.eq((select count(*)::int from community_comments where post_id = p1), 0, 'all three comments deleted');
  perform tests.check((select count(*) from notifications where post_id = p1) > 0, 'post has notifications before deletion');

  perform tests.login(a);
  perform tests.eq(delete_community_post(p1)->>'status', 'ok', 'author deletes own post');
  begin
    perform delete_community_post(p1);
    raise exception 'FAIL: deleting a missing post succeeded';
  exception when no_data_found then
    perform tests.check(sqlerrm = 'not_found', 'deleting an unknown post → not_found exception');
  end;
  perform tests.admin();
  perform tests.check(not exists (select 1 from community_posts where id in (p1, p2)), 'posts are gone');
  perform tests.check(not exists (select 1 from community_paws where post_id = p1)
                      and not exists (select 1 from cover_volunteers where post_id = p1)
                      and not exists (select 1 from notifications where post_id = p1),
                      'deleting a post cascades to paws, volunteers and its notifications');
end
$$;

-- ---------------------------------------------------------------------------
-- Otomatik gizleme: 3 FARKLI kullanıcının raporu → pending (reports insert trigger'ı)
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 7.0;
  b_lng float8 := tests.base_lng();
  a     uuid := tests.make_user('Raporlanan');
  z     uuid := tests.make_user('Rapor tarafsız');
  r1    uuid := tests.make_user('Raporcu 1');
  r2    uuid := tests.make_user('Raporcu 2');
  r3    uuid := tests.make_user('Raporcu 3');
  r4    uuid := tests.make_user('Raporcu 4');
  m     uuid := tests.make_user('Rapor moderatörü', 50, false, true);
  pid   uuid;
  zpid  uuid;
  cid   uuid;
  pr    community_post_row;
  n     int;
begin
  perform tests.login(a);
  pid := (create_community_post('alert', 'Raporlanacak paylaşım', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform tests.login(z);
  zpid := (create_community_post('note', 'Altına yorum yazılacak', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  perform add_community_comment(zpid, 'Zararsız yorum');
  perform tests.login(a);
  cid := (add_community_comment(zpid, 'Raporlanacak yorum')->>'comment_id')::uuid;

  -- istemci yolu: reports tablosuna doğrudan insert (RLS), trigger security definer
  perform tests.login(r1);
  insert into reports (target_type, target_id, reason) values ('post', pid, 'spam');
  insert into reports (target_type, target_id, reason, details) values ('post', pid, 'harassment', 'aynı kişi, ikinci rapor');
  insert into reports (target_type, target_id, reason) values ('spot', pid, 'spam');      -- başka hedef türü sayılmaz
  insert into reports (target_type, target_id, reason) values ('comment', cid, 'inappropriate');
  perform tests.login(r2);
  insert into reports (target_type, target_id, reason) values ('post', pid, 'inappropriate');
  insert into reports (target_type, target_id, reason) values ('comment', cid, 'spam');
  perform tests.admin();
  perform tests.eq((select moderation_state from community_posts where id = pid), 'approved'::moderation_state,
                   '2 distinct reporters (3 reports) → post still approved');
  perform tests.eq((select moderation_state from community_comments where id = cid), 'approved'::moderation_state,
                   '2 distinct reporters → comment still approved');

  perform tests.login(r3);
  insert into reports (target_type, target_id, reason) values ('post', pid, 'spam');
  insert into reports (target_type, target_id, reason) values ('comment', cid, 'harassment');
  perform tests.admin();
  perform tests.eq((select moderation_state from community_posts where id = pid), 'pending'::moderation_state,
                   '3 distinct reporters → post auto-hidden (pending)');
  perform tests.eq((select moderation_state from community_comments where id = cid), 'pending'::moderation_state,
                   '3 distinct reporters → comment auto-hidden (pending)');
  perform tests.eq((select moderation_state from community_posts where id = zpid), 'approved'::moderation_state,
                   'unreported post untouched');

  perform tests.login(z);
  select count(*)::int into n from community_feed(b_lat, b_lng) f where f.id = pid;
  perform tests.eq(n, 0, 'auto-hidden post disappears from the feed');
  select count(*)::int into n from community_comments_of(zpid);
  perform tests.eq(n, 1, 'auto-hidden comment disappears from the thread');
  select * into pr from community_post_detail(zpid);
  perform tests.eq(pr.comment_count, 1, 'auto-hidden comment leaves comment_count');
  perform tests.login(a);
  select * into pr from community_post_detail(pid);
  perform tests.check(pr.id = pid and pr.moderation_state = 'pending', 'author still sees own auto-hidden post (pending)');
  select count(*)::int into n from community_comments_of(zpid);
  perform tests.eq(n, 2, 'author still sees own auto-hidden comment');

  -- moderatör raporları kapatıp yeniden onaylarsa tek yeni rapor tekrar gizlemez; reddedilen geri dönmez
  perform tests.login(m);
  update reports set status = 'dismissed', resolved_at = now() where target_id = pid;
  perform tests.admin();
  update community_posts set moderation_state = 'approved' where id = pid;
  update community_comments set moderation_state = 'rejected' where id = cid;
  perform tests.login(r4);
  insert into reports (target_type, target_id, reason) values ('post', pid, 'other');
  insert into reports (target_type, target_id, reason) values ('comment', cid, 'other');
  perform tests.admin();
  perform tests.eq((select moderation_state from community_posts where id = pid), 'approved'::moderation_state,
                   'dismissed reports no longer count: one new report does not re-hide');
  perform tests.eq((select moderation_state from community_comments where id = cid), 'rejected'::moderation_state,
                   'rejected content is never moved back to pending');
end
$$;

-- ---------------------------------------------------------------------------
-- Hesap silme: paylaşım, yorum, pati, gönüllülük ve kişinin tetiklediği bildirimler silinir (PRD 9.5)
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat float8 := tests.base_lat() + 7.3;
  b_lng float8 := tests.base_lng();
  u     uuid := tests.make_user('Mahalleden ayrılan');
  o     uuid := tests.make_user('Mahallede kalan');
  s     uuid := tests.make_spot(b_lat, b_lng, 'Kalanın noktası', 'public', o);
  today date := private.istanbul_today();
  pu    uuid;
  po    uuid;
  pc    uuid;
begin
  perform tests.login(u);
  pu := (create_community_post('note', 'Ayrılanın paylaşımı', null, s, null, null, null, null, null)->>'post_id')::uuid;
  perform tests.login(o);
  po := (create_community_post('note', 'Kalanın paylaşımı', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  pc := (create_community_post('cover_request', 'Kalanın isteği', null, s, null, null, null, today, today + 2)->>'post_id')::uuid;
  perform add_community_comment(pu, 'Kalanın, ayrılanın paylaşımına yorumu');
  perform add_community_comment(po, 'Kalanın kendi yorumu');
  perform toggle_post_paw(pu);
  perform tests.login(u);
  perform add_community_comment(po, 'Ayrılanın yorumu');
  perform toggle_post_paw(po);
  perform toggle_cover_volunteer(pc);
  perform tests.admin();
  perform tests.eq((select count(*)::int from notifications where user_id = o and actor_id = u), 2,
                   'before deletion: two notifications triggered by the leaving user');
  perform tests.eq((select count(*)::int from notifications where user_id = u and post_id = pu), 1,
                   'before deletion: leaving user has a notification about own post');

  delete from auth.users where id = u;

  perform tests.check(not exists (select 1 from profiles where id = u), 'profile deleted');
  perform tests.check(not exists (select 1 from community_posts where id = pu), 'deleted user''s posts are deleted');
  perform tests.eq((select count(*)::int from community_comments where post_id = pu), 0, 'comments under the deleted post go with it');
  perform tests.eq((select count(*)::int from community_paws where post_id = pu), 0, 'paws on the deleted post go with it');
  perform tests.eq((select array_agg(body) from community_comments where post_id = po), array['Kalanın kendi yorumu'],
                   'deleted user''s comments are deleted, others stay');
  perform tests.eq((select count(*)::int from community_paws where post_id = po), 0, 'deleted user''s paws are deleted');
  perform tests.eq((select count(*)::int from cover_volunteers where post_id = pc), 0, 'deleted user''s volunteering is deleted');
  perform tests.eq((select count(*)::int from community_posts where id in (po, pc)), 2, 'other users'' posts are kept');
  perform tests.eq((select count(*)::int from notifications where user_id = o), 0,
                   'notifications quoting the deleted user (name + comment excerpt) are deleted');

  perform tests.login(o);
  perform tests.eq((select comment_count from community_post_detail(po)), 1, 'comment_count reflects the deletion');
  perform tests.eq((select volunteer_count from community_post_detail(pc)), 0, 'volunteer_count reflects the deletion');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- community_summary — "Bu hafta mahallende"
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat  float8 := tests.base_lat() + 7.6;   -- 48.55
  b_lng  float8 := tests.base_lng();
  viewer uuid := tests.make_user('Özet okur');
  blk    uuid := tests.make_user('Özet engelli');
  low    uuid := tests.make_user('Özet düşük güven', 2);
  f1     uuid := tests.make_user('Besleyici 1');
  f2     uuid := tests.make_user('Besleyici 2');
  f3     uuid := tests.make_user('Sucu 3');
  f4     uuid := tests.make_user('Talep eden 4');
  f5     uuid := tests.make_user('Eski besleyici 5');
  f6     uuid := tests.make_user('Uzak besleyici 6');
  f7     uuid := tests.make_user('Pasif nokta besleyicisi 7');
  s1     uuid := tests.make_spot(b_lat, b_lng, 'özet 1', 'public');
  s2     uuid := tests.make_spot(b_lat + 0.01, b_lng, 'özet 2 (özel)', 'private');
  s_far  uuid := tests.make_spot(b_lat + 0.06, b_lng, 'özet uzak', 'public');          -- ≈ 6,7 km
  s_off  uuid := tests.make_spot(b_lat, b_lng + 0.005, 'özet pasif', 'public');
  s_pend uuid := tests.make_spot(b_lat, b_lng + 0.006, 'özet onaysız', 'public');
  today  date := private.istanbul_today();
  d1_am  timestamptz := ((today - 1)::timestamp + time '10:00') at time zone 'Europe/Istanbul';
  d1_pm  timestamptz := ((today - 1)::timestamp + time '15:00') at time zone 'Europe/Istanbul';
  d2     timestamptz := ((today - 2)::timestamp + time '12:00') at time zone 'Europe/Istanbul';
  d3     timestamptz := ((today - 3)::timestamp + time '12:00') at time zone 'Europe/Istanbul';
  sm     record;
  n      int;
begin
  update spots set is_active = false where id = s_off;
  update spots set moderation_state = 'pending' where id = s_pend;
  insert into blocks (user_id, blocked_user_id) values (viewer, blk);

  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at) values
    (s1,     f1,   'fed',       10, d1_am),                        -- s1 · dün
    (s1,     f2,   'fed',       10, d1_pm),                        -- s1 · dün (aynı nokta-gün)
    (s1,     f1,   'fed',       10, d2),                           -- s1 · önceki gün
    (s2,     f1,   'fed',       10, d1_am),                        -- s2 · dün
    (s2,     null, 'fed',       10, d2),                           -- s2 · önceki gün (hesabı silinmiş besleyici)
    (s1,     f3,   'water',     10, d3),                           -- su: beslenmiş nokta-gün değil, ama aktif besleyici
    (s1,     f4,   'need_food', 10, d3),                           -- talep: sayılmaz
    (s1,     f5,   'fed',       10, now() - interval '8 days'),    -- 7 günden eski
    (s_far,  f6,   'fed',       10, d1_am),                        -- yarıçap dışı
    (s_off,  f7,   'fed',       10, d1_am),                        -- pasif nokta
    (s_pend, f7,   'fed',       10, d1_am);                        -- onaysız nokta

  insert into community_posts (author_id, kind, body, cell, spot_id, cover_from, cover_to, moderation_state, created_at) values
    (f1,  'note',          'özet paylaşım',        private.make_point(b_lat, b_lng), null, null, null, 'approved', now() - interval '1 hour'),
    (f1,  'cover_request', 'açık istek',           private.make_point(b_lat, b_lng), s1, today - 2, today, 'approved', now() - interval '2 days'),
    (f2,  'cover_request', 'kapanmış istek',       private.make_point(b_lat, b_lng), s1, today - 3, today - 1, 'approved', now() - interval '3 days'),
    (low, 'cover_request', 'onay bekleyen istek',  private.make_point(b_lat, b_lng), s1, today, today + 1, 'pending', now()),
    (f2,  'note',          'eski paylaşım',        private.make_point(b_lat, b_lng), null, null, null, 'approved', now() - interval '8 days'),
    (f2,  'cover_request', 'eski ama açık istek',  private.make_point(b_lat, b_lng), s1, today, today + 5, 'approved', now() - interval '9 days'),
    (f2,  'note',          'uzak paylaşım',        private.make_point(b_lat + 0.06, b_lng), null, null, null, 'approved', now()),
    (blk, 'cover_request', 'engellinin isteği',    private.make_point(b_lat, b_lng), s1, today, today + 1, 'approved', now());

  perform tests.login(viewer);
  select count(*)::int into n from community_summary(b_lat, b_lng);
  perform tests.eq(n, 1, 'community_summary returns a single row');
  select * into sm from community_summary(b_lat, b_lng);
  perform tests.eq(sm.fed_spot_days_7d, 4, 'fed_spot_days_7d = distinct (spot, Istanbul day) with a fed check-in in 7 days');
  perform tests.eq(sm.active_feeders_7d, 3, 'active_feeders_7d = distinct users with fed/water check-ins');
  perform tests.eq(sm.open_cover_requests, 2, 'open_cover_requests = approved cover requests with cover_to ≥ today');
  perform tests.eq(sm.posts_7d, 3, 'posts_7d = approved posts in the last 7 days');

  select * into sm from community_summary(lat => b_lat, lng => b_lng, radius_m => 8000);
  perform tests.eq(sm.fed_spot_days_7d, 5, 'summary: wider radius includes the far spot');
  perform tests.eq(sm.active_feeders_7d, 4, 'summary: wider radius includes the far feeder');
  perform tests.eq(sm.posts_7d, 4, 'summary: wider radius includes the far post');
  select * into sm from community_summary(b_lat, b_lng, 1000000);
  perform tests.eq(sm.fed_spot_days_7d, 5, 'summary: radius capped at 10 000 m');
  select * into sm from community_summary(b_lat + 1.5, b_lng);
  perform tests.check(sm.fed_spot_days_7d = 0 and sm.active_feeders_7d = 0 and sm.open_cover_requests = 0 and sm.posts_7d = 0,
                      'summary of an empty neighbourhood is all zeros');

  perform tests.login(blk);
  select * into sm from community_summary(b_lat, b_lng);
  perform tests.check(sm.open_cover_requests = 3 and sm.posts_7d = 4, 'summary is viewer-relative only for blocks');
  perform tests.admin();
end
$$;

-- Özet konum kâhini olmamalı (PRD 9.1): bulanık nokta yarıçapa GÖSTERİLEN konumuyla girer.
-- Merkezler, gerçek ve bulanık konum 3000 m çemberinin iki yanında kalacak şekilde seçilir.
do $$
declare
  b_lat  float8 := tests.base_lat() + 8.2;
  b_lng  float8 := tests.base_lng();
  viewer uuid := tests.make_user('Kâhin deneyen');
  feeder uuid := tests.make_user('Gizli nokta besleyicisi');
  s      uuid := tests.make_spot(b_lat, b_lng, 'özet bulanık', 'fuzzed');
  loc    extensions.geography;
  fz     extensions.geography;
  az     float8;
  mid    extensions.geography;
  c_in   extensions.geography;   -- bulanık konum içeride (≈2975 m), gerçek konum dışarıda (≈3025 m)
  c_out  extensions.geography;   -- gerçek konum içeride, bulanık konum dışarıda
begin
  insert into checkins (spot_id, user_id, kind, user_distance_m, created_at) values (s, feeder, 'fed', 5, now() - interval '1 hour');
  select sp.location, private.fuzz_point(sp.id, sp.location) into loc, fz from spots sp where sp.id = s;
  az    := extensions.st_azimuth(loc, fz);
  mid   := extensions.st_project(loc, extensions.st_distance(loc, fz) / 2, az);
  c_in  := extensions.st_project(mid, 3000, az);
  c_out := extensions.st_project(mid, 3000, az + pi());
  perform tests.check(extensions.st_distance(c_in, fz) < 2990 and extensions.st_distance(c_in, loc) > 3010
                      and extensions.st_distance(c_out, loc) < 2990 and extensions.st_distance(c_out, fz) > 3010,
                      'setup: true and displayed location straddle the 3000 m radius');

  perform tests.login(viewer);
  perform tests.eq((select fed_spot_days_7d from community_summary(extensions.st_y(c_in::extensions.geometry),
                                                                   extensions.st_x(c_in::extensions.geometry))), 1,
                   'summary counts a fuzzed spot when its DISPLAYED location is inside the radius');
  perform tests.eq((select active_feeders_7d from community_summary(extensions.st_y(c_out::extensions.geometry),
                                                                    extensions.st_x(c_out::extensions.geometry))), 0,
                   'summary ignores a fuzzed spot whose displayed location is outside (true location is not an oracle)');
  perform tests.admin();
end
$$;

-- ---------------------------------------------------------------------------
-- Push kuyruğu: push_claim_batch post_id döndürür (service_role)
-- ---------------------------------------------------------------------------
do $$
declare
  b_lat   float8 := tests.base_lat() + 7.9;
  b_lng   float8 := tests.base_lng();
  a       uuid := tests.make_user('Push Yazar');
  c       uuid := tests.make_user('Push Yorumcu');
  s       uuid := tests.make_spot(b_lat, b_lng, 'Push noktası', 'public', a);
  today   date := private.istanbul_today();
  p1      uuid;
  p2      uuid;
  claimed jsonb;
  j       jsonb;
begin
  update notifications set pushed_at = now(), push_status = 'sent' where pushed_at is null;   -- önceki blokların artıkları
  insert into device_tokens (token, user_id) values ('mahalle-push-token-1', a);

  perform tests.login(a);
  p1 := (create_community_post('note', 'Push testi', null, null, null, b_lat, b_lng, null, null)->>'post_id')::uuid;
  p2 := (create_community_post('cover_request', 'Push emanet', null, s, null, null, null, today, today + 1)->>'post_id')::uuid;
  perform tests.login(c);
  perform add_community_comment(p1, 'Push yorumu');
  perform toggle_cover_volunteer(p2);
  perform tests.admin();
  insert into notifications (user_id, kind, title, body, spot_id) values (a, 'thanks_fed', 'Teşekkürler!', 'b', s);

  -- edge function'ın göreceği JSON (PostgREST satırı sütun adlarıyla nesneye çevirir)
  set local role service_role;
  select jsonb_agg(to_jsonb(x)) into claimed from push_claim_batch(50) x;
  reset role;

  perform tests.eq(jsonb_array_length(claimed), 3, 'push_claim_batch claims the community notifications');
  select e into j from jsonb_array_elements(claimed) e where e->>'kind' = 'community_comment';
  perform tests.check(j ? 'post_id' and (j->>'post_id')::uuid = p1 and j->>'spot_id' is null and j->>'need_id' is null,
                      'claim: community_comment row has post_id');
  perform tests.check((j->>'user_id')::uuid = a and j->'tokens' = '["mahalle-push-token-1"]'::jsonb
                      and (j->>'quiet_start')::int = 22 and (j->>'quiet_end')::int = 7 and (j->>'need_food_pushed_today')::int = 0,
                      'claim: recipient, tokens, quiet hours and daily counter for a community notification');
  select e into j from jsonb_array_elements(claimed) e where e->>'kind' = 'cover_volunteered';
  perform tests.check((j->>'post_id')::uuid = p2 and (j->>'spot_id')::uuid = s, 'claim: cover_volunteered row has post_id and spot_id');
  select e into j from jsonb_array_elements(claimed) e where e->>'kind' = 'thanks_fed';
  perform tests.check(j ? 'post_id' and j->>'post_id' is null and (j->>'spot_id')::uuid = s, 'claim: other kinds have null post_id');
  perform tests.check((select bool_and(push_status = 'processing') from notifications where user_id = a),
                      'claimed community notifications are marked processing');
  perform tests.check(not has_function_privilege('authenticated', 'public.push_claim_batch(int)', 'execute')
                      and not has_function_privilege('anon', 'public.push_claim_batch(int)', 'execute')
                      and has_function_privilege('service_role', 'public.push_claim_batch(int)', 'execute'),
                      'recreated push_claim_batch is still service_role only');
end
$$;

rollback;
