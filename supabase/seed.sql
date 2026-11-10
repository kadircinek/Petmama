-- Mama Haritası — demo verisi: Kadıköy / Moda pilotu (≈ 40.980–40.992 K, 29.020–29.035 D)
--
-- Sabit UUID'ler + `on conflict do nothing` → tekrar çalıştırmak güvenli. Zamanlar now()'a göredir;
-- böylece her `supabase db reset` sonrası haritada yeşil / sarı / gri / turuncu noktalar görünür.
-- Demo kullanıcılar giriş yapmak için değil, veriyi doldurmak içindir (şifreleri yok).

-- ---------------------------------------------------------------------------
-- Demo kullanıcılar (auth.users → trigger profiles + notification_prefs oluşturur)
-- ---------------------------------------------------------------------------
do $$
declare
  u record;
  v_cols text;
  v_vals text;
begin
  if to_regclass('auth.users') is null then
    raise notice 'auth.users yok, demo kullanıcılar atlandı';
    return;
  end if;

  for u in
    select * from (values
      ('11111111-1111-4111-8111-111111111111'::uuid, 'ayse.demo@example.com',   'Ayşe (Moda)'),
      ('22222222-2222-4222-8222-222222222222'::uuid, 'mehmet.demo@example.com', 'Mehmet'),
      ('33333333-3333-4333-8333-333333333333'::uuid, 'zeynep.demo@example.com', 'Zeynep'),
      ('44444444-4444-4444-8444-444444444444'::uuid, 'deniz.demo@example.com',  'Deniz')
    ) as t(id, email, name)
  loop
    -- Gerçek GoTrue şemasında fazladan sütunlar var; yalnızca mevcut olanları doldur.
    select string_agg(quote_ident(c.col), ', ' order by c.ord), string_agg(c.val, ', ' order by c.ord)
      into v_cols, v_vals
    from (values
      (1, 'id',                 quote_literal(u.id) || '::uuid'),
      (2, 'instance_id',        quote_literal('00000000-0000-0000-0000-000000000000') || '::uuid'),
      (3, 'aud',                quote_literal('authenticated')),
      (4, 'role',               quote_literal('authenticated')),
      (5, 'email',              quote_literal(u.email)),
      (6, 'raw_app_meta_data',  quote_literal('{"provider":"email","providers":["email"]}') || '::jsonb'),
      (7, 'raw_user_meta_data', quote_literal(jsonb_build_object('display_name', u.name)::text) || '::jsonb'),
      (8, 'email_confirmed_at', 'now()'),
      (9, 'created_at',         'now() - interval ''40 days'''),
      (10, 'updated_at',        'now()')
    ) as c(ord, col, val)
    where exists (select 1 from information_schema.columns ic
                  where ic.table_schema = 'auth' and ic.table_name = 'users' and ic.column_name = c.col);

    execute format('insert into auth.users (%s) values (%s) on conflict (id) do nothing', v_cols, v_vals);
  end loop;
end
$$;

-- Profil ayrıntıları (trigger profilleri oluşturdu; yoksa da oluştur)
insert into public.profiles (id, display_name, neighborhood, trust_score, is_verified_feeder, is_moderator)
select v.id, v.name, v.hood, v.trust, v.verified, v.moderator
from (values
  ('11111111-1111-4111-8111-111111111111'::uuid, 'Ayşe (Moda)', 'Moda',        42, true,  true),
  ('22222222-2222-4222-8222-222222222222'::uuid, 'Mehmet',      'Caferağa',    12, false, false),
  ('33333333-3333-4333-8333-333333333333'::uuid, 'Zeynep',      'Rasimpaşa',    3, false, false),
  ('44444444-4444-4444-8444-444444444444'::uuid, 'Deniz',       'Osmanağa',    18, false, false)
) as v(id, name, hood, trust, verified, moderator)
where exists (select 1 from auth.users au where au.id = v.id)
on conflict (id) do update
  set display_name = excluded.display_name,
      neighborhood = excluded.neighborhood,
      trust_score = excluded.trust_score,
      is_verified_feeder = excluded.is_verified_feeder,
      is_moderator = excluded.is_moderator;

-- Bildirim merkezleri (3 ondalığa yuvarlanır)
insert into public.notification_prefs (user_id, radius_m, notify_center)
select v.id, v.radius, private.make_point(v.lat, v.lng)
from (values
  ('11111111-1111-4111-8111-111111111111'::uuid, 1500, 40.984, 29.027),
  ('22222222-2222-4222-8222-222222222222'::uuid, 1000, 40.988, 29.029),
  ('44444444-4444-4444-8444-444444444444'::uuid, 800,  40.991, 29.024)
) as v(id, radius, lat, lng)
where exists (select 1 from public.profiles p where p.id = v.id)
on conflict (user_id) do update set radius_m = excluded.radius_m, notify_center = excluded.notify_center;

-- ---------------------------------------------------------------------------
-- 25 nokta: tür / tür (kedi-köpek) / görünürlük / durum karışık
--   fed_h: son beslenmeden bu yana saat (null = hiç)  → <12 yeşil, 12–24 sarı, 24+ gri
--   req:   açık talep (need_food / need_water / broken) → turuncu
-- ---------------------------------------------------------------------------
drop table if exists pg_temp.seed_spots;
create temporary table seed_spots as
select * from (values
  -- id                                       lat      lng      type       species  title                                   note                                                     vis       fed_h  req           by   state       active
  ('a0000000-0000-4000-8000-000000000001'::uuid, 40.9813, 29.0252, 'shelter', 'cat',  'Moda Sahili kedi evleri',             'Sahil yolu, bankların arkasında üç kulübe.',            'public',  2,    null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000002'::uuid, 40.9846, 29.0268, 'food',    'cat',  'Moda Parkı girişi',                    'Çeşmenin yanındaki mama kabı.',                         'public',  5,    null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000003'::uuid, 40.9851, 29.0289, 'water',   'both', 'Moda Caddesi su kabı',                 'Fırının önünde, sabah doldurulur.',                     'public',  11,   null,         2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 40.9862, 29.0301, 'mixed',   'cat',  'Bahariye arka sokak',                  null,                                                    'public',  13,   null,         2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000005'::uuid, 40.9874, 29.0277, 'food',    'cat',  'Kadıköy Kilisesi bahçe duvarı',        'Duvarın dibinde, akşamüstü mama konuyor.',              'public',  18,   null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000006'::uuid, 40.9888, 29.0262, 'food',    'dog',  'Altıyol köpek noktası',                'Paşa ve arkadaşları burada.',                           'public',  23,   null,         4,   'approved', true),
  ('a0000000-0000-4000-8000-000000000007'::uuid, 40.9899, 29.0249, 'mixed',   'both', 'Söğütlüçeşme yolu ağaç altı',          null,                                                    'public',  30,   null,         4,   'approved', true),
  ('a0000000-0000-4000-8000-000000000008'::uuid, 40.9907, 29.0236, 'food',    'cat',  'Kadıköy Çarşı balıkçılar arkası',      'Balıkçı esnafı da besliyor.',                           'public',  72,   null,         2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000009'::uuid, 40.9915, 29.0221, 'water',   'cat',  'Rıhtım su kabı',                       null,                                                    'public',  null, null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000010'::uuid, 40.9829, 29.0233, 'food',    'cat',  'Moda İskelesi önü',                    'İskele merdivenlerinin yanında.',                       'public',  8,    'need_food',  1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000011'::uuid, 40.9837, 29.0312, 'water',   'both', 'Yeldeğirmeni yokuşu',                  null,                                                    'public',  20,   'need_water', 2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000012'::uuid, 40.9869, 29.0329, 'shelter', 'cat',  'Yoğurtçu Parkı kulübe',                'Kulübenin çatısı akıyor.',                              'public',  40,   'broken',     4,   'approved', true),
  ('a0000000-0000-4000-8000-000000000013'::uuid, 40.9893, 29.0318, 'food',    'dog',  'Yoğurtçu Parkı köpek alanı',           null,                                                    'public',  3,    null,         4,   'approved', true),
  ('a0000000-0000-4000-8000-000000000014'::uuid, 40.9821, 29.0287, 'mixed',   'cat',  'Moda Çay Bahçesi altı',                'Kayalıklara inen merdivenin başı.',                     'public',  1,    null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000015'::uuid, 40.9808, 29.0274, 'food',    'cat',  'Moda Burnu kayalıklar',                null,                                                    'public',  15,   null,         2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000016'::uuid, 40.9856, 29.0243, 'food',    'cat',  'Moda Sahnesi yan sokak',               null,                                                    'fuzzed',  6,    null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000017'::uuid, 40.9879, 29.0226, 'shelter', 'cat',  'Anne kedi ve yavruları',               'Yavrular küçük, lütfen kalabalık yapmayın.',            'fuzzed',  9,    null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000018'::uuid, 40.9902, 29.0301, 'food',    'cat',  'Osmanağa cami avlusu arkası',          null,                                                    'fuzzed',  26,   null,         4,   'approved', true),
  ('a0000000-0000-4000-8000-000000000019'::uuid, 40.9833, 29.0336, 'food',    'dog',  'Hasta köpek bakım noktası',            'Tedavi gören köpek, yalnızca koruyucular.',            'private', 4,    null,         1,   'approved', true),
  ('a0000000-0000-4000-8000-000000000020'::uuid, 40.9884, 29.0342, 'shelter', 'cat',  'Kış kulübesi (özel)',                  null,                                                    'private', 14,   null,         2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000021'::uuid, 40.9918, 29.0287, 'food',    'cat',  'Mühürdar yolu otopark',                null,                                                    'public',  null, 'need_food',  4,   'approved', true),
  ('a0000000-0000-4000-8000-000000000022'::uuid, 40.9802, 29.0219, 'water',   'both', 'Moda Deniz Kulübü önü',                null,                                                    'public',  10,   null,         2,   'approved', true),
  ('a0000000-0000-4000-8000-000000000023'::uuid, 40.9866, 29.0207, 'food',    'cat',  'Caferağa spor salonu yanı',            null,                                                    'public',  50,   null,         3,   'pending',  true),
  ('a0000000-0000-4000-8000-000000000024'::uuid, 40.9895, 29.0213, 'food',    'cat',  'Eski pazar yeri (kaldırıldı)',         'Alan inşaata girdi.',                                   'public',  200,  null,         2,   'approved', false),
  ('a0000000-0000-4000-8000-000000000025'::uuid, 40.9843, 29.0221, 'mixed',   'both', 'Moda Sahil parkı çeşme',               null,                                                    'public',  12,   null,         4,   'approved', true)
) as t(id, lat, lng, type, species, title, note, vis, fed_h, req, by_n, state, active);

insert into public.spots (id, location, type, species, title, note, visibility, status, last_fed_at,
                          created_by, is_active, moderation_state, created_at)
select s.id,
       private.make_point(s.lat, s.lng),
       s.type::public.spot_type,
       s.species::public.spot_species,
       s.title,
       s.note,
       s.vis::public.spot_visibility,
       'unknown',
       case when s.fed_h is null then null else now() - make_interval(hours => s.fed_h) end,
       (select p.id from public.profiles p
         where p.id = (array['11111111-1111-4111-8111-111111111111',
                             '22222222-2222-4222-8222-222222222222',
                             '33333333-3333-4333-8333-333333333333',
                             '44444444-4444-4444-8444-444444444444']::uuid[])[s.by_n]),
       s.active,
       s.state::public.moderation_state,
       now() - interval '20 days'
from seed_spots s
on conflict (id) do nothing;

-- Son beslenme check-in'leri (fed) ve açık talepler
insert into public.checkins (id, spot_id, user_id, kind, amount, user_distance_m, created_at)
select ('b0000000-0000-4000-8000-0000000000' || right(s.id::text, 2))::uuid,
       s.id,
       (select p.id from public.profiles p
         where p.id = (array['11111111-1111-4111-8111-111111111111',
                             '22222222-2222-4222-8222-222222222222',
                             '33333333-3333-4333-8333-333333333333',
                             '44444444-4444-4444-8444-444444444444']::uuid[])[s.by_n]),
       'fed', 'full', 12 + s.by_n * 7,
       now() - make_interval(hours => s.fed_h)
from seed_spots s
where s.fed_h is not null
on conflict (id) do nothing;

insert into public.checkins (id, spot_id, user_id, kind, user_distance_m, created_at)
select ('c0000000-0000-4000-8000-0000000000' || right(s.id::text, 2))::uuid,
       s.id,
       (select p.id from public.profiles p where p.id = '22222222-2222-4222-8222-222222222222'),
       s.req::public.checkin_kind, 35,
       now() - interval '90 minutes'
from seed_spots s
where s.req is not null
on conflict (id) do nothing;

-- "Kaldırıldı" bildirimi yapan 3 kullanıcı (FR-N6) — nokta pasif
insert into public.spot_gone_reports (spot_id, user_id)
select 'a0000000-0000-4000-8000-000000000024', p.id
from public.profiles p
where p.id in ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
               '44444444-4444-4444-8444-444444444444')
on conflict do nothing;

-- Kalıcı status sütununu tazele
update public.spots s
   set status = public.compute_spot_status(s.last_fed_at, private.spot_has_open_request(s.id))
 where s.id::text like 'a0000000-0000-4000-8000-0000000000%';

-- ---------------------------------------------------------------------------
-- Koruyucular ve takipler
-- ---------------------------------------------------------------------------
insert into public.guardians (user_id, spot_id, schedule)
select g.uid, g.sid, g.sched
from (values
  ('11111111-1111-4111-8111-111111111111'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, '{1,3,5,7}'::smallint[]),
  ('11111111-1111-4111-8111-111111111111'::uuid, 'a0000000-0000-4000-8000-000000000017'::uuid, '{1,2,3,4,5,6,7}'::smallint[]),
  ('11111111-1111-4111-8111-111111111111'::uuid, 'a0000000-0000-4000-8000-000000000019'::uuid, '{1,2,3,4,5,6,7}'::smallint[]),
  ('22222222-2222-4222-8222-222222222222'::uuid, 'a0000000-0000-4000-8000-000000000004'::uuid, '{2,4,6}'::smallint[]),
  ('22222222-2222-4222-8222-222222222222'::uuid, 'a0000000-0000-4000-8000-000000000020'::uuid, '{6,7}'::smallint[]),
  ('44444444-4444-4444-8444-444444444444'::uuid, 'a0000000-0000-4000-8000-000000000006'::uuid, '{1,2,3,4,5}'::smallint[]),
  ('44444444-4444-4444-8444-444444444444'::uuid, 'a0000000-0000-4000-8000-000000000018'::uuid, '{}'::smallint[])
) as g(uid, sid, sched)
where exists (select 1 from public.profiles p where p.id = g.uid)
  and exists (select 1 from public.spots s where s.id = g.sid)
on conflict do nothing;

insert into public.follows (user_id, target_type, target_id)
select f.uid, f.tt::public.follow_target, f.tid
from (values
  ('22222222-2222-4222-8222-222222222222'::uuid, 'spot',   'a0000000-0000-4000-8000-000000000010'::uuid),
  ('22222222-2222-4222-8222-222222222222'::uuid, 'spot',   'a0000000-0000-4000-8000-000000000014'::uuid),
  ('44444444-4444-4444-8444-444444444444'::uuid, 'spot',   'a0000000-0000-4000-8000-000000000012'::uuid),
  ('33333333-3333-4333-8333-333333333333'::uuid, 'animal', 'd0000000-0000-4000-8000-000000000002'::uuid)
) as f(uid, tt, tid)
where exists (select 1 from public.profiles p where p.id = f.uid)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 10 hayvan
-- ---------------------------------------------------------------------------
insert into public.animals (id, species, name, color_pattern, sex, age_estimate, is_neutered, ear_tag,
                            vaccination_info, temperament_tags, warning, about, last_seen_at,
                            last_seen_spot_id, created_by, created_at)
select a.id, a.species::public.animal_species, a.name, a.color, a.sex::public.animal_sex,
       a.age::public.age_estimate, a.neutered, a.ear_tag, a.vacc, a.tags, a.warn::public.animal_warning,
       a.about, now() - make_interval(hours => a.seen_h), a.spot,
       (select p.id from public.profiles p where p.id = a.creator), now() - interval '15 days'
from (values
  ('d0000000-0000-4000-8000-000000000001'::uuid, 'cat', 'Pamuk',   'Bembeyaz, mavi gözlü',      'female',  'adult',  true,  true,  'Kuduz 2026-03',  '{friendly,calm}'::text[],           null,              'Sahilin maskotu, kucağa gelir.',                         2,  'a0000000-0000-4000-8000-000000000001'::uuid, '11111111-1111-4111-8111-111111111111'::uuid),
  ('d0000000-0000-4000-8000-000000000002'::uuid, 'cat', 'Tarçın',  'Turuncu tekir',             'male',    'young',  false, false, null,             '{energetic,friendly}'::text[],      null,              'Arka sol bacağını aksatıyor.',                           5,  'a0000000-0000-4000-8000-000000000010'::uuid, '22222222-2222-4222-8222-222222222222'::uuid),
  ('d0000000-0000-4000-8000-000000000003'::uuid, 'cat', 'Zeytin',  'Simsiyah',                  'female',  'adult',  false, false, null,             '{shy}'::text[],                     'skittish',        'Çok ürkek, mamayı bırakıp uzaklaşın.',                   20, 'a0000000-0000-4000-8000-000000000002'::uuid, '11111111-1111-4111-8111-111111111111'::uuid),
  ('d0000000-0000-4000-8000-000000000004'::uuid, 'cat', 'Duman',   'Gri, kısa tüylü',           'male',    'senior', true,  true,  'Karma aşı 2025', '{calm}'::text[],                    null,              'Yaşlı, yumuşak mama tercih ediyor.',                     30, 'a0000000-0000-4000-8000-000000000005'::uuid, '44444444-4444-4444-8444-444444444444'::uuid),
  ('d0000000-0000-4000-8000-000000000005'::uuid, 'dog', 'Karamel', 'Açık kahve, orta boy',      'female',  'adult',  true,  true,  'Kuduz 2026-01',  '{friendly,good_with_kids}'::text[], null,              'Altıyol''un neşesi.',                                    3,  'a0000000-0000-4000-8000-000000000006'::uuid, '44444444-4444-4444-8444-444444444444'::uuid),
  ('d0000000-0000-4000-8000-000000000006'::uuid, 'dog', 'Paşa',    'Siyah-beyaz, iri',          'male',    'adult',  true,  true,  null,             '{may_be_aggressive}'::text[],       'do_not_approach', 'Başka köpeklere karşı korumacı, mesafeli olun.',         6,  'a0000000-0000-4000-8000-000000000006'::uuid, '44444444-4444-4444-8444-444444444444'::uuid),
  ('d0000000-0000-4000-8000-000000000007'::uuid, 'cat', 'Boncuk',  'Üç renkli (calico)',        'female',  'young',  null,  false, null,             '{friendly}'::text[],                null,              null,                                                     10, 'a0000000-0000-4000-8000-000000000014'::uuid, '11111111-1111-4111-8111-111111111111'::uuid),
  ('d0000000-0000-4000-8000-000000000008'::uuid, 'cat', 'Fıstık',  'Krem, kısa kuyruklu',       'unknown', 'baby',   false, false, null,             '{energetic}'::text[],               null,              'Anne kedinin yavrularından.',                            9,  'a0000000-0000-4000-8000-000000000017'::uuid, '11111111-1111-4111-8111-111111111111'::uuid),
  ('d0000000-0000-4000-8000-000000000009'::uuid, 'cat', 'Minnoş',  'Beyaz-gri patili',          'female',  'adult',  true,  true,  null,             '{calm,good_with_kids}'::text[],     null,              null,                                                     14, 'a0000000-0000-4000-8000-000000000003'::uuid, '22222222-2222-4222-8222-222222222222'::uuid),
  ('d0000000-0000-4000-8000-000000000010'::uuid, 'dog', 'Limon',   'Sarı, kulakları dik',       'male',    'young',  false, false, null,             '{energetic,friendly}'::text[],      'may_bite',        'Oyunbaz ama elleri ısırabilir.',                         4,  'a0000000-0000-4000-8000-000000000013'::uuid, '44444444-4444-4444-8444-444444444444'::uuid)
) as a(id, species, name, color, sex, age, neutered, ear_tag, vacc, tags, warn, about, seen_h, spot, creator)
on conflict (id) do nothing;

-- Görülme sayıları (trigger son görülen nokta için 1 ile başlattı)
insert into public.animal_spots (animal_id, spot_id, seen_count, last_seen_at)
select v.aid, v.sid, v.cnt, now() - make_interval(hours => v.h)
from (values
  ('d0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 42, 2),
  ('d0000000-0000-4000-8000-000000000001'::uuid, 'a0000000-0000-4000-8000-000000000014'::uuid, 7,  30),
  ('d0000000-0000-4000-8000-000000000002'::uuid, 'a0000000-0000-4000-8000-000000000010'::uuid, 15, 5),
  ('d0000000-0000-4000-8000-000000000003'::uuid, 'a0000000-0000-4000-8000-000000000002'::uuid, 9,  20),
  ('d0000000-0000-4000-8000-000000000004'::uuid, 'a0000000-0000-4000-8000-000000000005'::uuid, 21, 30),
  ('d0000000-0000-4000-8000-000000000005'::uuid, 'a0000000-0000-4000-8000-000000000006'::uuid, 33, 3),
  ('d0000000-0000-4000-8000-000000000006'::uuid, 'a0000000-0000-4000-8000-000000000006'::uuid, 28, 6),
  ('d0000000-0000-4000-8000-000000000007'::uuid, 'a0000000-0000-4000-8000-000000000014'::uuid, 5,  10),
  ('d0000000-0000-4000-8000-000000000008'::uuid, 'a0000000-0000-4000-8000-000000000017'::uuid, 4,  9),
  ('d0000000-0000-4000-8000-000000000009'::uuid, 'a0000000-0000-4000-8000-000000000003'::uuid, 11, 14),
  ('d0000000-0000-4000-8000-000000000010'::uuid, 'a0000000-0000-4000-8000-000000000013'::uuid, 8,  4)
) as v(aid, sid, cnt, h)
where exists (select 1 from public.animals a where a.id = v.aid)
on conflict (animal_id, spot_id) do update
  set seen_count = greatest(public.animal_spots.seen_count, excluded.seen_count),
      last_seen_at = excluded.last_seen_at;

-- ---------------------------------------------------------------------------
-- İhtiyaçlar (biri acil veteriner)
-- ---------------------------------------------------------------------------
insert into public.needs (id, animal_id, spot_id, type, urgency, description, status, created_by,
                          claimed_by, claimed_at, resolved_at, resolved_by, created_at)
select n.id, n.aid, n.sid, n.type::public.need_type, n.urg::public.need_urgency, n.descr,
       n.st::public.need_status,
       (select p.id from public.profiles p where p.id = n.creator),
       (select p.id from public.profiles p where p.id = n.claimer),
       case when n.claimer is not null then now() - interval '3 hours' end,
       case when n.st = 'resolved' then now() - interval '1 day' end,
       case when n.st = 'resolved' then (select p.id from public.profiles p where p.id = n.claimer) end,
       now() - make_interval(hours => n.age_h)
from (values
  ('e0000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-000000000002'::uuid, 'a0000000-0000-4000-8000-000000000010'::uuid,
   'vet', 'urgent', 'Tarçın arka sol bacağına basamıyor, bugün veterinere götürülmesi gerekiyor.', 'open',
   '22222222-2222-4222-8222-222222222222'::uuid, null::uuid, 4),
  ('e0000000-0000-4000-8000-000000000002'::uuid, 'd0000000-0000-4000-8000-000000000003'::uuid, null::uuid,
   'neuter', 'normal', 'Zeytin kısırlaştırılmamış, belediye randevusu için yardım lazım.', 'claimed',
   '11111111-1111-4111-8111-111111111111'::uuid, '44444444-4444-4444-8444-444444444444'::uuid, 48),
  ('e0000000-0000-4000-8000-000000000003'::uuid, null::uuid, 'a0000000-0000-4000-8000-000000000012'::uuid,
   'shelter', 'normal', 'Kulübenin çatısı akıyor, kış öncesi branda gerekli.', 'open',
   '44444444-4444-4444-8444-444444444444'::uuid, null::uuid, 30),
  ('e0000000-0000-4000-8000-000000000004'::uuid, 'd0000000-0000-4000-8000-000000000008'::uuid, 'a0000000-0000-4000-8000-000000000017'::uuid,
   'vaccine', 'normal', 'Yavrular için ilk karma aşı.', 'open',
   '11111111-1111-4111-8111-111111111111'::uuid, null::uuid, 12),
  ('e0000000-0000-4000-8000-000000000005'::uuid, 'd0000000-0000-4000-8000-000000000004'::uuid, 'a0000000-0000-4000-8000-000000000005'::uuid,
   'meds', 'normal', 'Duman için böbrek mamaları alındı.', 'resolved',
   '44444444-4444-4444-8444-444444444444'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 96)
) as n(id, aid, sid, type, urg, descr, st, creator, claimer, age_h)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Bağış istatistikleri (ortak dernekten aylık toplam, PRD 8.2)
-- ---------------------------------------------------------------------------
insert into public.donation_stats (month, kg_distributed, donor_count)
values
  (date_trunc('month', private.istanbul_today())::date, 420.5, 87),
  ((date_trunc('month', private.istanbul_today()) - interval '1 month')::date, 1180, 212)
on conflict (month) do nothing;

-- ---------------------------------------------------------------------------
-- Mahalle (topluluk) — demo paylaşımlar (D17): paylaşım, soru + 2 yorum, açık "Yerime bakar mısın?"
-- + 1 gönüllü, mama paylaşımı, uyarı ve düşük güven puanlı kullanıcının inceleme bekleyen paylaşımı.
-- Noktaya bağlı olanlarda kaba konum noktadan gelir; trigger 2 ondalığa yuvarlar (≈1,1 km).
-- ---------------------------------------------------------------------------
insert into public.community_posts (id, author_id, kind, body, spot_id, animal_id, cell,
                                    cover_from, cover_to, moderation_state, created_at)
select v.id, pr.id, v.kind::public.community_post_kind, v.body, sp.id, an.id,
       coalesce(sp.location, private.make_point(v.lat, v.lng)),
       case when v.kind = 'cover_request' then private.istanbul_today() + v.from_d end,
       case when v.kind = 'cover_request' then private.istanbul_today() + v.to_d end,
       v.state::public.moderation_state,
       now() - make_interval(hours => v.age_h)
from (values
  ('f0000000-0000-4000-8000-000000000001'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'note',
   'Moda Sahili''ndeki kulübelere kış için yeni battaniye koyduk. Pamuk hemen sahiplendi, keyfi yerinde.',
   'a0000000-0000-4000-8000-000000000001'::uuid, 'd0000000-0000-4000-8000-000000000001'::uuid,
   40.9813, 29.0252, null::int, null::int, 'approved', 3),
  ('f0000000-0000-4000-8000-000000000002'::uuid, '22222222-2222-4222-8222-222222222222'::uuid, 'question',
   'Duman artık kuru mamayı zor yiyor. Yaşlı kediler için önerebileceğiniz yumuşak bir mama var mı?',
   null::uuid, 'd0000000-0000-4000-8000-000000000004'::uuid,
   40.9874, 29.0277, null, null, 'approved', 8),
  ('f0000000-0000-4000-8000-000000000003'::uuid, '44444444-4444-4444-8444-444444444444'::uuid, 'cover_request',
   'Hafta sonu şehir dışındayım. Altıyol''daki köpeklere iki gün bakabilecek biri var mı? Mama torbası köşedeki bakkalda duruyor.',
   'a0000000-0000-4000-8000-000000000006'::uuid, null::uuid,
   40.9888, 29.0262, 2, 4, 'approved', 5),
  ('f0000000-0000-4000-8000-000000000004'::uuid, '11111111-1111-4111-8111-111111111111'::uuid, 'supply',
   'Elimde açılmamış 2 kg yavru kedi maması var. İhtiyacı olan Moda Parkı girişinden alabilir.',
   'a0000000-0000-4000-8000-000000000002'::uuid, null::uuid,
   40.9846, 29.0268, null, null, 'approved', 20),
  ('f0000000-0000-4000-8000-000000000005'::uuid, '22222222-2222-4222-8222-222222222222'::uuid, 'alert',
   'Bahariye arka sokakta akşamları motorlar çok hızlı geçiyor. Mama kaplarını kaldırımın iç tarafına koyalım.',
   'a0000000-0000-4000-8000-000000000004'::uuid, null::uuid,
   40.9862, 29.0301, null, null, 'approved', 30),
  ('f0000000-0000-4000-8000-000000000006'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 'note',
   'Mahalleye yeni taşındım. Rasimpaşa tarafında besleme yapan var mı? Ben de katılmak isterim.',
   null::uuid, null::uuid,
   40.9905, 29.0300, null, null, 'pending', 1)
) as v(id, author, kind, body, spot, animal, lat, lng, from_d, to_d, state, age_h)
join public.profiles pr on pr.id = v.author
left join public.spots sp on sp.id = v.spot
left join public.animals an on an.id = v.animal
on conflict (id) do nothing;

insert into public.community_comments (id, post_id, author_id, body, created_at)
select v.id, po.id, pr.id, v.body, now() - make_interval(hours => v.age_h)
from (values
  ('f1000000-0000-4000-8000-000000000001'::uuid, 'f0000000-0000-4000-8000-000000000002'::uuid,
   '11111111-1111-4111-8111-111111111111'::uuid,
   'Veterinerimiz yaşlı kediler için pate mama önermişti. Ilık suyla biraz yumuşatınca daha rahat yiyorlar.', 6),
  ('f1000000-0000-4000-8000-000000000002'::uuid, 'f0000000-0000-4000-8000-000000000002'::uuid,
   '44444444-4444-4444-8444-444444444444'::uuid,
   'Bende iki kutu yaş mama var, yarın sabah kilise bahçesine bırakırım.', 5)
) as v(id, post, author, body, age_h)
join public.community_posts po on po.id = v.post
join public.profiles pr on pr.id = v.author
on conflict (id) do nothing;

insert into public.community_paws (post_id, user_id)
select po.id, pr.id
from (values
  ('f0000000-0000-4000-8000-000000000001'::uuid, '22222222-2222-4222-8222-222222222222'::uuid),
  ('f0000000-0000-4000-8000-000000000001'::uuid, '44444444-4444-4444-8444-444444444444'::uuid),
  ('f0000000-0000-4000-8000-000000000002'::uuid, '11111111-1111-4111-8111-111111111111'::uuid),
  ('f0000000-0000-4000-8000-000000000004'::uuid, '44444444-4444-4444-8444-444444444444'::uuid)
) as v(post, usr)
join public.community_posts po on po.id = v.post
join public.profiles pr on pr.id = v.usr
on conflict do nothing;

-- "Ben bakarım": Mehmet, Deniz'in Altıyol isteğine gönüllü
insert into public.cover_volunteers (post_id, user_id)
select po.id, pr.id
from (values
  ('f0000000-0000-4000-8000-000000000003'::uuid, '22222222-2222-4222-8222-222222222222'::uuid)
) as v(post, usr)
join public.community_posts po on po.id = v.post
join public.profiles pr on pr.id = v.usr
on conflict do nothing;

drop table if exists pg_temp.seed_spots;
