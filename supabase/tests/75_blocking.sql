-- Engelleme yalnızca Mahalle'yi değil; ihtiyaçları, hayvanları, nokta notu/fotoğrafını ve koruyucuları da gizler
-- (App Store 1.2: engellenen kullanıcının içeriği görünmemeli). Nokta haritada kalır: fiziksel mama noktası.
begin;

do $$
declare
  b_lat   float8 := tests.base_lat() + 0.20;
  b_lng   float8 := tests.base_lng();
  viewer  uuid := tests.make_user('İzleyen');
  blocked uuid := tests.make_user('Engellenen');
  blocker uuid := tests.make_user('İzleyeni engelleyen');
  other   uuid := tests.make_user('Tarafsız');
  modr    uuid := tests.make_user('Moderatör', 50, false, true);
  s       uuid := tests.make_spot(b_lat, b_lng, 'Engel noktası', 'public', blocked, now());
  an      uuid;
  n_b     uuid;
  n_c     uuid;
  r       record;
begin
  update spots set note = 'engellenenin notu', photo_url = 'https://example.test/b.jpg' where id = s;
  insert into animals (name, created_by, last_seen_spot_id) values ('Engellinin kedisi', blocked, s) returning id into an;
  insert into needs (spot_id, type, description, created_by) values (s, 'vet', 'B ihtiyacı', blocked) returning id into n_b;
  insert into needs (spot_id, type, description, created_by) values (s, 'shelter', 'C ihtiyacı', blocker) returning id into n_c;
  insert into guardians (user_id, spot_id) values (blocked, s);
  insert into blocks (user_id, blocked_user_id) values (viewer, blocked), (blocker, viewer);

  perform tests.login(viewer);
  perform tests.eq((select count(*)::int from needs_for(s)), 0, 'needs of blocked users hidden (both directions)');
  perform tests.eq((select count(*)::int from needs_near(b_lat, b_lng, 1000) n where n.spot_id = s), 0,
                   'needs_near hides blocked users'' needs');
  perform tests.eq((select count(*)::int from need_detail(n_b)), 0, 'need_detail hides blocked user''s need');
  select * into r from spot_detail(s);
  perform tests.eq(r.title, 'Engel noktası', 'spot itself stays visible');
  perform tests.check(r.note is null and r.photo_url is null, 'blocked creator''s note and photo hidden');
  perform tests.eq(r.open_need_count, 0, 'open need count excludes hidden needs');
  perform tests.eq((select count(*)::int from animals_at_spot(s)), 0, 'animals of blocked user hidden at spot');
  perform tests.eq((select count(*)::int from animals where id = an), 0, 'animal row hidden by RLS');
  perform tests.eq((select count(*)::int from spot_guardians(s)), 0, 'blocked guardian hidden');

  perform tests.login(other);
  perform tests.eq((select count(*)::int from needs_for(s)), 2, 'unrelated user sees all needs');
  select * into r from spot_detail(s);
  perform tests.eq(r.note, 'engellenenin notu', 'unrelated user sees note');
  perform tests.eq((select count(*)::int from animals_at_spot(s)), 1, 'unrelated user sees animal');
  perform tests.eq((select count(*)::int from spot_guardians(s)), 1, 'unrelated user sees guardian');

  perform tests.anon();
  perform tests.eq((select count(*)::int from needs_for(s)), 2, 'anon sees all needs');

  -- moderatör kendisi engellese de inceleyebilmeli
  perform tests.admin();
  insert into blocks (user_id, blocked_user_id) values (modr, blocked);
  perform tests.login(modr);
  perform tests.eq((select count(*)::int from needs_for(s)), 2, 'moderator still sees needs');
end
$$;

rollback;
