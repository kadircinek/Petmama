-- Mama Haritası — 0004: dönüş tipleri ve yardımcı fonksiyonlar
--
-- İç yardımcılar `private` şemasındadır (PostgREST'e kapalı, anon/authenticated usage yok).
-- Özellikle `private.fuzz_point` asla istemciye açılmamalı: rastgele bir konumla çağrılabilseydi
-- ofset hesaplanıp gerçek konum geri bulunabilirdi (PRD 9.1).

-- ---------------------------------------------------------------------------
-- RPC dönüş satırları (docs/backend-contract.md)
-- ---------------------------------------------------------------------------
create type public.spot_row as (
  id                uuid,
  lat               float8,
  lng               float8,
  is_location_exact boolean,
  type              public.spot_type,
  species           public.spot_species,
  title             text,
  note              text,
  photo_url         text,
  status            public.spot_status,
  last_fed_at       timestamptz,
  has_urgent_need   boolean,
  open_need_count   int,
  visibility        public.spot_visibility,
  is_active         boolean,
  created_by        uuid,
  created_at        timestamptz,
  animal_count      int,
  guardian_count    int,
  distance_m        float8
);

create type public.need_row as (
  id                uuid,
  type              public.need_type,
  urgency           public.need_urgency,
  status            public.need_status,
  description       text,
  photos            text[],
  spot_id           uuid,
  spot_title        text,
  animal_id         uuid,
  animal_name       text,
  animal_photo_url  text,
  lat               float8,
  lng               float8,
  is_location_exact boolean,
  distance_m        float8,
  created_by        uuid,
  claimed_by        uuid,
  claimed_by_name   text,
  created_at        timestamptz,
  claimed_at        timestamptz,
  resolved_at       timestamptz
);

create type public.animal_row as (
  id                uuid,
  species           public.animal_species,
  name              text,
  color_pattern     text,
  sex               public.animal_sex,
  age_estimate      public.age_estimate,
  is_neutered       boolean,
  ear_tag           boolean,
  vaccination_info  text,
  temperament_tags  text[],
  warning           public.animal_warning,
  about             text,
  photos            text[],
  last_seen_at      timestamptz,
  last_seen_spot_id uuid,
  created_by        uuid,
  created_at        timestamptz,
  seen_count        int,
  spot_last_seen_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Genel yardımcılar
-- ---------------------------------------------------------------------------
create function private.setting(p_key text)
returns text
language sql stable
set search_path = public, extensions
as $$
  select value from private.app_settings where key = p_key
$$;

-- Türkçe duyarsız katlama: İ/I/ı → i, ş → s, ğ → g, ç → c, ö → o, ü → u, şapkalılar → düz.
-- İndekste kullanıldığı için immutable ve search_path bağımsız (yalnızca pg_catalog).
create function private.tr_fold(p text)
returns text
language sql immutable parallel safe
as $$
  select pg_catalog.lower(pg_catalog.translate(p, 'İIıŞşĞğÇçÖöÜüÂâÎîÛû', 'iiissggccoouuaaiiuu'))
$$;

create index spots_title_trgm on public.spots using gin (private.tr_fold(title) extensions.gin_trgm_ops);

-- LIKE kalıbı için %, _ ve \ kaçışı
create function private.like_escape(p text)
returns text
language sql immutable parallel safe
as $$
  select pg_catalog.replace(pg_catalog.replace(pg_catalog.replace(p, '\', '\\'), '%', '\%'), '_', '\_')
$$;

create function private.istanbul_today()
returns date
language sql stable
as $$
  select (now() at time zone 'Europe/Istanbul')::date
$$;

-- İstanbul gün başlangıcı (timestamptz)
create function private.istanbul_day_start()
returns timestamptz
language sql stable
as $$
  select ((now() at time zone 'Europe/Istanbul')::date)::timestamp at time zone 'Europe/Istanbul'
$$;

create function private.assert_lat_lng(p_lat float8, p_lng float8)
returns void
language plpgsql immutable
as $$
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180
     or p_lat = 'NaN'::float8 or p_lng = 'NaN'::float8 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;
end
$$;

create function private.make_point(p_lat float8, p_lng float8)
returns extensions.geography
language sql immutable
set search_path = public, extensions
as $$
  select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
$$;

-- ---------------------------------------------------------------------------
-- Küfür filtresi (create_spot / create_need / hayvan / profil adı).
-- Katlama tr_fold'dan farklıdır: noktasız ı KORUNUR, çünkü "sık"/"sıkışmış" (kedi ağaçta sıkışmış!)
-- ile küfür kökü "sik" yalnızca bu harfle ayrılır. Kelimeler bu katlamayla yazılır.
-- prefix_match: kelimenin başı eşleşirse yeter (Türkçe ekler: "orospunun", "siktirgit").
-- Yanlış pozitif riskli kısa kökler (göt→"got", piç→"pic", mal, cunta) bilinçli olarak listede yok.
-- ---------------------------------------------------------------------------
create function private.profanity_fold(p text)
returns text
language sql immutable parallel safe
as $$
  select pg_catalog.lower(pg_catalog.translate(p, 'İIŞşĞğÇçÖöÜüÂâÎîÛû', 'iissggccoouuaaiiuu'))
$$;

create table private.profanity_words (
  word         text primary key check (word = private.profanity_fold(word) and word ~ '^[a-zı]+$'),
  prefix_match boolean not null default false
);

insert into private.profanity_words (word, prefix_match) values
  -- Türkçe
  ('amk', false), ('aq', false), ('amq', false), ('oc', false), ('sik', false), ('sikik', false),
  ('sikim', false), ('siktir', true), ('sikerim', true), ('siktim', true), ('amına', true),
  ('orospu', true), ('yarrak', true), ('yarak', false), ('pezevenk', true), ('kahpe', true),
  ('serefsiz', true), ('gavat', true), ('ibne', true), ('yavsak', true), ('surtuk', true), ('kaltak', true),
  ('pust', false), ('dallama', false), ('gerizekal', true), ('salak', false), ('gotveren', true),
  -- English
  ('fuck', true), ('motherfuck', true), ('shit', true), ('bitch', true), ('cunt', false), ('asshole', true),
  ('dick', false), ('bastard', true), ('whore', true), ('slut', true), ('wanker', true), ('retard', true)
on conflict (word) do nothing;

create function private.contains_profanity(p text)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select coalesce(p, '') <> '' and exists (
    select 1
    from private.profanity_words w
    where private.profanity_fold(p) ~ ('\m' || w.word || case when w.prefix_match then '' else '\M' end)
  )
$$;

-- ---------------------------------------------------------------------------
-- Durum hesaplama (PRD 5.2 FR-N5, 7.5)
--   needs_food ← çözülmemiş need_food / need_water / broken check-in'i var (her şeyden önce gelir)
--   fed_recent ← now - last_fed_at < 12 sa
--   fed_stale  ← 12 sa ≤ now - last_fed_at < 24 sa
--   unknown    ← last_fed_at null veya ≥ 24 sa
-- ---------------------------------------------------------------------------
create function public.compute_spot_status(
  p_last_fed_at      timestamptz,
  p_has_open_request boolean,
  p_now              timestamptz default now()
)
returns public.spot_status
language sql stable
set search_path = public, extensions
as $$
  select case
    when coalesce(p_has_open_request, false)               then 'needs_food'::public.spot_status
    when p_last_fed_at is null                             then 'unknown'::public.spot_status
    when p_now - p_last_fed_at < interval '12 hours'       then 'fed_recent'::public.spot_status
    when p_now - p_last_fed_at < interval '24 hours'       then 'fed_stale'::public.spot_status
    else 'unknown'::public.spot_status
  end
$$;

create function private.request_kinds()
returns public.checkin_kind[]
language sql immutable
as $$
  select array['need_food', 'need_water', 'broken']::public.checkin_kind[]
$$;

create function private.spot_has_open_request(p_spot_id uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.checkins c
    where c.spot_id = p_spot_id
      and c.resolved_at is null
      and c.kind = any (private.request_kinds())
  )
$$;

-- ---------------------------------------------------------------------------
-- Konum bulanıklaştırma (PRD 9.1)
-- HMAC-SHA256(spot_id, fuzz_salt) → ilk 4 bayt mesafe (50–100 m), sonraki 4 bayt yön.
-- Deterministik: aynı nokta hep aynı sahte konumda (ortalama alma saldırısı yok).
-- ---------------------------------------------------------------------------
create function private.fuzz_point(p_spot_id uuid, p_location extensions.geography)
returns extensions.geography
language plpgsql stable
set search_path = public, extensions
as $$
declare
  v_salt text := private.setting('fuzz_salt');
  v_h    bytea;
  v_u1   float8;
  v_u2   float8;
begin
  if v_salt is null or v_salt = '' then
    raise exception 'fuzz_salt is not configured in private.app_settings';
  end if;
  v_h  := extensions.hmac(p_spot_id::text, v_salt, 'sha256');
  v_u1 := ((get_byte(v_h, 0)::bigint << 24) + (get_byte(v_h, 1)::bigint << 16)
         + (get_byte(v_h, 2)::bigint << 8) + get_byte(v_h, 3)::bigint) / 4294967296.0;
  v_u2 := ((get_byte(v_h, 4)::bigint << 24) + (get_byte(v_h, 5)::bigint << 16)
         + (get_byte(v_h, 6)::bigint << 8) + get_byte(v_h, 7)::bigint) / 4294967296.0;
  return extensions.st_project(p_location, 50.0 + 50.0 * v_u1, 2.0 * pi() * v_u2);
end
$$;

-- ---------------------------------------------------------------------------
-- İzleyici (viewer) kuralları
-- ---------------------------------------------------------------------------
-- is_privileged: doğrulanmış besleyici veya moderatör → tüm noktaları tam konumla görür.
create function private.viewer_flags(p_uid uuid, out is_privileged boolean, out is_moderator boolean)
language sql stable
set search_path = public, extensions
as $$
  select coalesce(bool_or(p.is_verified_feeder or p.is_moderator), false),
         coalesce(bool_or(p.is_moderator), false)
  from public.profiles p
  where p.id = p_uid
$$;

-- Nokta bu izleyiciye hiç dönebilir mi?
--   rejected → yalnızca moderatör; pending → oluşturan + moderatör;
--   private  → anon'a asla (PRD 9.1 tablosu).
create function private.spot_visible(p_spot public.spots, p_uid uuid, p_is_mod boolean)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select coalesce(
    p_spot.id is not null
    and case p_spot.moderation_state
          when 'approved' then true
          when 'pending'  then coalesce(p_is_mod, false) or (p_uid is not null and p_spot.created_by = p_uid)
          else coalesce(p_is_mod, false)
        end
    and (p_spot.visibility <> 'private' or p_uid is not null),
    false)
$$;

-- Tam konum mu? (PRD 9.1)
--   public  : giriş yapmış herkes tam, anon bulanık
--   fuzzed  : yalnızca koruyucu / doğrulanmış besleyici (veya moderatör) / oluşturan tam
--   private : fuzzed ile aynı (anon zaten göremez)
create function private.spot_exact(p_spot public.spots, p_uid uuid, p_is_privileged boolean)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select coalesce(
    p_uid is not null and (
      p_spot.visibility = 'public'
      or coalesce(p_is_privileged, false)
      or p_spot.created_by = p_uid
      or exists (select 1 from public.guardians g where g.spot_id = p_spot.id and g.user_id = p_uid)
    ),
    false)
$$;

-- İstemciye gösterilecek nokta: tam veya bulanık
create function private.display_point(p_spot public.spots, p_exact boolean)
returns extensions.geography
language sql stable
set search_path = public, extensions
as $$
  select case when p_exact then p_spot.location else private.fuzz_point(p_spot.id, p_spot.location) end
$$;

-- Bir `spots` satırını izleyiciye göre `spot_row`'a çevirir.
-- distance_m GÖSTERİLEN noktaya göre hesaplanır; aksi halde bulanık noktalarda üçgenleme ile
-- gerçek konum bulunabilirdi.
create function private.to_spot_row(
  p_spot          public.spots,
  p_uid           uuid,
  p_is_privileged boolean,
  p_ref           extensions.geography
)
returns public.spot_row
language sql stable
set search_path = public, extensions
as $$
  select
    p_spot.id,
    extensions.st_y(d.pt::extensions.geometry),
    extensions.st_x(d.pt::extensions.geometry),
    d.exact,
    p_spot.type,
    p_spot.species,
    p_spot.title,
    p_spot.note,
    p_spot.photo_url,
    public.compute_spot_status(p_spot.last_fed_at, private.spot_has_open_request(p_spot.id)),
    p_spot.last_fed_at,
    nn.has_urgent,
    nn.open_count,
    p_spot.visibility,
    p_spot.is_active,
    p_spot.created_by,
    p_spot.created_at,
    (select count(*)::int from public.animal_spots a where a.spot_id = p_spot.id),
    (select count(*)::int from public.guardians g where g.spot_id = p_spot.id),
    case when p_ref is null then null else extensions.st_distance(d.pt, p_ref) end
  from (
    select e.exact, private.display_point(p_spot, e.exact) as pt
    from (select private.spot_exact(p_spot, p_uid, p_is_privileged) as exact) e
  ) d
  cross join lateral (
    -- noktaya veya noktadaki bir hayvana bağlı, çözülmemiş ihtiyaçlar
    select count(*)::int as open_count,
           coalesce(bool_or(n.urgency = 'urgent'), false) as has_urgent
    from public.needs n
    where n.status <> 'resolved'
      and (n.spot_id = p_spot.id
           or n.animal_id in (select a.animal_id from public.animal_spots a where a.spot_id = p_spot.id))
  ) nn
$$;

-- İhtiyaç satırı izleyiciye dönebilir mi? Bağlı olduğu nokta görünmüyorsa hayır.
create function private.need_visible(p_need public.needs, p_uid uuid, p_is_mod boolean)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select p_need.spot_id is null
      or exists (select 1 from public.spots s
                 where s.id = p_need.spot_id and private.spot_visible(s, p_uid, p_is_mod))
$$;

-- `needs` satırı → `need_row`. Konum: ihtiyacın noktası, yoksa hayvanın son görüldüğü nokta;
-- o nokta izleyiciye görünmüyorsa lat/lng/distance null.
create function private.to_need_row(
  p_need          public.needs,
  p_uid           uuid,
  p_is_privileged boolean,
  p_is_mod        boolean,
  p_ref           extensions.geography
)
returns public.need_row
language sql stable
set search_path = public, extensions
as $$
  select
    p_need.id,
    p_need.type,
    p_need.urgency,
    p_need.status,
    p_need.description,
    p_need.photos,
    p_need.spot_id,
    case when p_need.spot_id is not null and coalesce(l.visible, false) then l.title end,
    p_need.animal_id,
    a.name,
    a.photos[1],
    case when l.visible then extensions.st_y(l.pt::extensions.geometry) end,
    case when l.visible then extensions.st_x(l.pt::extensions.geometry) end,
    coalesce(l.visible and l.exact, false),
    case when l.visible and p_ref is not null then extensions.st_distance(l.pt, p_ref) end,
    p_need.created_by,
    p_need.claimed_by,
    cp.display_name,
    p_need.created_at,
    p_need.claimed_at,
    p_need.resolved_at
  from (select 1) as one
  left join public.animals a on a.id = p_need.animal_id
  left join lateral (
    select s.title, v.visible, v.exact,
           case when v.visible then private.display_point(s, v.exact) end as pt
    from public.spots s
    cross join lateral (
      select private.spot_visible(s, p_uid, p_is_mod) as visible,
             private.spot_exact(s, p_uid, p_is_privileged) as exact
    ) v
    where s.id = coalesce(p_need.spot_id, a.last_seen_spot_id)
  ) l on true
  left join public.profiles cp on cp.id = p_need.claimed_by
$$;

-- ---------------------------------------------------------------------------
-- Güven puanı / doğrulanmış besleyici (PRD 9.3, FR-P4)
-- ---------------------------------------------------------------------------
create function private.add_trust(p_uid uuid, p_delta int)
returns void
language sql
set search_path = public, extensions
as $$
  update public.profiles set trust_score = trust_score + p_delta where id = p_uid
$$;

-- "Konumu doğrulanmış" check-in: mesafe kontrolünden geçmiş (user_distance_m dolu) kayıt.
create function private.verified_checkins_30d(p_uid uuid)
returns int
language sql stable
set search_path = public, extensions
as $$
  select count(*)::int
  from public.checkins c
  where c.user_id = p_uid
    and c.user_distance_m is not null
    and c.created_at > now() - interval '30 days'
$$;

-- FR-P4: 30 günde 20+ doğrulanmış check-in → rozet. Rozet otomatik geri alınmaz (moderatör alabilir).
create function private.maybe_promote_feeder(p_uid uuid)
returns boolean
language plpgsql
set search_path = public, extensions
as $$
begin
  if private.verified_checkins_30d(p_uid) >= 20 then
    update public.profiles set is_verified_feeder = true
    where id = p_uid and not is_verified_feeder;
    return found;
  end if;
  return false;
end
$$;

-- PRD 9.3: günlük nokta oluşturma limiti — yeni kullanıcı 5, doğrulanmış besleyici 30
create function private.daily_spot_limit(p_uid uuid)
returns int
language sql stable
set search_path = public, extensions
as $$
  select case when coalesce((select is_verified_feeder from public.profiles where id = p_uid), false)
              then 30 else 5 end
$$;

-- ---------------------------------------------------------------------------
-- Engelleme ve bildirim yardımcıları
-- ---------------------------------------------------------------------------
create function private.blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.blocks b
    where (b.user_id = p_a and b.blocked_user_id = p_b)
       or (b.user_id = p_b and b.blocked_user_id = p_a)
  )
$$;

create function private.checkin_kind_label(p_kind public.checkin_kind)
returns text
language sql immutable
as $$
  select case p_kind
    when 'fed'        then 'Mama koyuldu'
    when 'water'      then 'Su koyuldu'
    when 'need_food'  then 'Mama gerekli'
    when 'need_water' then 'Su gerekli'
    when 'broken'     then 'Kap kırık / bozuk'
  end
$$;

-- İç fonksiyonların hiçbiri istemciye açık değil
revoke all on all functions in schema private from public;

-- Oturum zorunlu RPC'ler için: auth.uid() yoksa 42501 (PostgREST → 401/403)
create function private.require_uid()
returns uuid
language plpgsql stable
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return v_uid;
end
$$;

revoke all on function private.require_uid() from public;
revoke all on function public.compute_spot_status(timestamptz, boolean, timestamptz) from public, anon, authenticated;
