-- Mama Haritası — 0014: Mahalle (topluluk) RPC'leri (docs/backend-contract.md "Mahalle (topluluk) — v0.2", D17)
--
-- * Hepsi `security definer` + `set search_path = public, extensions`, ilk iş `private.require_uid()`.
--   Hiçbiri anon'a açık değil: besleyicilerin konuşmaları ve adları girişsiz taranamaz (PRD 9.1).
-- * Kullanıcı kimliği her zaman auth.uid()'den gelir; istemciden kullanıcı id'si alınmaz.
-- * İş kuralı sonuçları jsonb `status` (+ `reason`) ile döner; geçersiz parametre exception'dır.
-- * Görünürlük tek yerde: private.community_visible (inceleme durumu + iki yönlü engel).

-- ---------------------------------------------------------------------------
-- RPC dönüş satırları
-- ---------------------------------------------------------------------------
create type public.community_post_row as (
  id                 uuid,
  kind               public.community_post_kind,
  body               text,
  photo_url          text,
  author_id          uuid,
  author_name        text,
  author_avatar_url  text,
  author_is_verified boolean,
  spot_id            uuid,     -- nokta izleyene görünür değilse spot_id ve spot_title null
  spot_title         text,
  animal_id          uuid,
  animal_name        text,
  cover_from         date,
  cover_to           date,
  volunteer_count    int,
  viewer_volunteered boolean,
  paw_count          int,
  viewer_pawed       boolean,
  comment_count      int,      -- yalnızca izleyiciye görünür yorumlar
  distance_m         float8,   -- izleyicinin konumundan cell'e; konum verilmediyse null
  moderation_state   public.moderation_state,
  created_at         timestamptz   -- milisaniyeye kırpılmış (community_feed'in `p_before` imleci)
);

create type public.community_comment_row as (
  id                 uuid,
  post_id            uuid,
  body               text,
  author_id          uuid,
  author_name        text,
  author_avatar_url  text,
  author_is_verified boolean,
  created_at         timestamptz
);

-- ---------------------------------------------------------------------------
-- Yardımcılar
-- ---------------------------------------------------------------------------
-- Kullanıcı metni: baştaki/sondaki boşluk ve satır sonları atılır (uzunluk kuralları bundan sonra)
create function private.trim_text(p text)
returns text
language sql immutable parallel safe
as $$
  select pg_catalog.btrim(coalesce(p, ''), E' \t\r\n')
$$;

-- Paylaşım/yorum bu izleyiciye görünür mü? (noktalardaki private.spot_visible ile aynı mantık)
--   approved → herkes; pending → yazarı + moderatör (düşük güven puanı ya da 3 rapor sonrası);
--   rejected → yalnızca moderatör. İki yönde engel varsa hiç görünmez.
create function private.community_visible(
  p_state  public.moderation_state,
  p_author uuid,
  p_uid    uuid,
  p_is_mod boolean
)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select coalesce(
    case p_state
      when 'approved' then true
      when 'pending'  then coalesce(p_is_mod, false) or p_author = p_uid
      else coalesce(p_is_mod, false)
    end
    and not private.blocked_between(p_uid, p_author),
    false)
$$;

-- `community_posts` satırı → izleyiciye göre `community_post_row`.
--   * spot_id / spot_title yalnızca nokta izleyene görünürse (ör. başkasının onay bekleyen noktası değilse).
--   * comment_count ve volunteer_count izleyiciye göredir: engelli kişilerin yorumu/gönüllülüğü sayılmaz
--     (liste RPC'leriyle tutarlı). paw_count anonim toplamdır.
--   * distance_m kaba konuma (cell) göredir.
--   * created_at milisaniyeye kırpılır: istemci bu değeri `p_before` olarak milisaniye hassasiyetiyle
--     geri gönderir; mikrosaniyeli dönseydi sayfa sınırındaki satır tekrar gelebilir ya da atlanabilirdi.
create function private.to_post_row(
  p_post   public.community_posts,
  p_uid    uuid,
  p_is_mod boolean,
  p_ref    extensions.geography
)
returns public.community_post_row
language sql stable
set search_path = public, extensions
as $$
  select
    p_post.id,
    p_post.kind,
    p_post.body,
    p_post.photo_url,
    p_post.author_id,
    au.display_name,
    au.avatar_url,
    coalesce(au.is_verified_feeder, false),
    sp.id,
    sp.title,
    an.id,
    an.name,
    p_post.cover_from,
    p_post.cover_to,
    (select count(*)::int from public.cover_volunteers v
      where v.post_id = p_post.id and not private.blocked_between(p_uid, v.user_id)),
    exists (select 1 from public.cover_volunteers v where v.post_id = p_post.id and v.user_id = p_uid),
    (select count(*)::int from public.community_paws w where w.post_id = p_post.id),
    exists (select 1 from public.community_paws w where w.post_id = p_post.id and w.user_id = p_uid),
    (select count(*)::int from public.community_comments c
      where c.post_id = p_post.id
        and private.community_visible(c.moderation_state, c.author_id, p_uid, p_is_mod)),
    case when p_ref is not null then extensions.st_distance(p_post.cell, p_ref) end,
    p_post.moderation_state,
    date_trunc('milliseconds', p_post.created_at)
  from (select 1) as one
  left join public.profiles au on au.id = p_post.author_id
  left join public.spots sp on sp.id = p_post.spot_id and private.spot_visible(sp, p_uid, p_is_mod)
  left join public.animals an on an.id = p_post.animal_id
$$;

-- Paylaşımın yazarına bildirim (community_comment / cover_volunteered). Şu durumlarda GÖNDERİLMEZ:
-- aktör yazarın kendisiyse, taraflar engelliyse, yazar `community_updates` tercihini kapattıysa
-- (tercih satırı yoksa varsayılan açık) veya aynı paylaşım için aynı türden okunmamış bildirim zaten
-- varsa (hareketli bir paylaşım bildirim yağmuruna dönmesin).
create function private.notify_post_author(
  p_post    public.community_posts,
  p_actor   uuid,
  p_kind    public.notification_kind,
  p_title   text,
  p_body    text,
  p_spot_id uuid default null
)
returns boolean
language plpgsql volatile
set search_path = public, extensions
as $$
begin
  if p_post.author_id = p_actor or private.blocked_between(p_post.author_id, p_actor) then
    return false;
  end if;
  if not coalesce((select np.community_updates from public.notification_prefs np
                   where np.user_id = p_post.author_id), true) then
    return false;
  end if;

  -- Eşzamanlı iki yorum/gönüllü aynı anda "okunmamış yok" görüp çift bildirim üretmesin
  perform pg_advisory_xact_lock(hashtextextended('community_notify:' || p_post.id::text, 0));
  if exists (select 1 from public.notifications n
             where n.post_id = p_post.id and n.user_id = p_post.author_id
               and n.kind = p_kind and n.read_at is null) then
    return false;
  end if;

  insert into public.notifications (user_id, kind, title, body, spot_id, post_id, actor_id)
  values (p_post.author_id, p_kind, p_title, p_body, p_spot_id, p_post.id, p_actor);
  return true;
end
$$;

-- ---------------------------------------------------------------------------
-- community_feed — yakındaki paylaşımlar, yeniden eskiye. Sayfalama keyset: bir sonraki sayfa için
-- son satırın created_at'i `p_before` olarak gönderilir. Satırdaki created_at milisaniyeye kırpılmıştır
-- ve filtre aynı kırpılmış değere uygulanır: sayfa sınırındaki satır asla tekrar gelmez. (İmleçle aynı
-- milisaniyeye düşen başka bir paylaşım varsa o atlanır; tek mahallede pratikte görülmez.)
-- Yarıçap 1000–10 000 m'ye sıkıştırılır (cell ≈1,1 km'lik ızgara olduğundan daha küçük yarıçap
-- kullanıcının kendi paylaşımını bile kaçırırdı).
-- ---------------------------------------------------------------------------
create function public.community_feed(
  lat      float8,
  lng      float8,
  radius_m int default 3000,
  p_kind   public.community_post_kind default null,
  p_before timestamptz default null,
  max_rows int default 30
)
returns setof public.community_post_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := private.require_uid();
  v_mod    boolean;
  v_ref    extensions.geography;
  v_radius int := greatest(1000, least(coalesce(community_feed.radius_m, 3000), 10000));
begin
  perform private.assert_lat_lng(community_feed.lat, community_feed.lng);
  v_ref := private.make_point(community_feed.lat, community_feed.lng);
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from (
    -- önce sayfa seçilir; sayaçlar (to_post_row) yalnızca dönen satırlar için hesaplanır
    select p as post
    from public.community_posts p
    where extensions.st_dwithin(p.cell, v_ref, v_radius)
      and (p_kind is null or p.kind = p_kind)
      and (p_before is null or date_trunc('milliseconds', p.created_at) < p_before)
      and private.community_visible(p.moderation_state, p.author_id, v_uid, v_mod)
    order by p.created_at desc, p.id desc
    limit greatest(1, least(coalesce(community_feed.max_rows, 30), 50))
  ) page
  cross join lateral private.to_post_row(page.post, v_uid, v_mod, v_ref) r
  -- saklanan (mikrosaniyeli) zamana göre: aynı milisaniyedeki satırların sırası da kararlı
  order by (page.post).created_at desc, (page.post).id desc;
end
$$;

-- ---------------------------------------------------------------------------
-- community_post_detail — 0/1 satır; gizli (inceleme bekleyen) / engelli / yok → 0 satır
-- ---------------------------------------------------------------------------
create function public.community_post_detail(p_post_id uuid, lat float8 default null, lng float8 default null)
returns setof public.community_post_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
  v_ref extensions.geography;
begin
  if community_post_detail.lat is not null and community_post_detail.lng is not null then
    perform private.assert_lat_lng(community_post_detail.lat, community_post_detail.lng);
    v_ref := private.make_point(community_post_detail.lat, community_post_detail.lng);
  end if;
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;

  return query
  select r.*
  from public.community_posts p
  cross join lateral private.to_post_row(p, v_uid, v_mod, v_ref) r
  where p.id = p_post_id
    and private.community_visible(p.moderation_state, p.author_id, v_uid, v_mod);
end
$$;

-- ---------------------------------------------------------------------------
-- community_comments_of — created_at artan, en fazla 200; paylaşım görünmüyorsa 0 satır
-- ---------------------------------------------------------------------------
create function public.community_comments_of(p_post_id uuid)
returns setof public.community_comment_row
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if not exists (select 1 from public.community_posts p
                 where p.id = p_post_id
                   and private.community_visible(p.moderation_state, p.author_id, v_uid, v_mod)) then
    return;
  end if;

  return query
  select c.id, c.post_id, c.body, c.author_id, au.display_name, au.avatar_url, au.is_verified_feeder,
         c.created_at
  from public.community_comments c
  join public.profiles au on au.id = c.author_id
  where c.post_id = p_post_id
    and private.community_visible(c.moderation_state, c.author_id, v_uid, v_mod)
  order by c.created_at, c.id
  limit 200;
end
$$;

-- ---------------------------------------------------------------------------
-- cover_volunteers_of — "Ben bakarım" diyenler (ilk gönüllü önce). İzleyiciyle engelli olanlar
-- listelenmez: gönüllülük kimin, hangi günlerde, hangi noktada olacağını söyler.
-- ---------------------------------------------------------------------------
create function public.cover_volunteers_of(p_post_id uuid)
returns table (user_id uuid, display_name text, avatar_url text, is_verified_feeder boolean)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
  v_mod boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  if not exists (select 1 from public.community_posts p
                 where p.id = p_post_id
                   and private.community_visible(p.moderation_state, p.author_id, v_uid, v_mod)) then
    return;
  end if;

  return query
  select v.user_id, pr.display_name, pr.avatar_url, pr.is_verified_feeder
  from public.cover_volunteers v
  join public.profiles pr on pr.id = v.user_id
  where v.post_id = p_post_id
    and not private.blocked_between(v_uid, v.user_id)
  order by v.created_at, v.user_id
  limit 200;
end
$$;

-- ---------------------------------------------------------------------------
-- create_community_post
-- Sıra: metin → küfür → günlük limit → nokta → "Yerime bakar mısın?" kuralları → konum → ekleme.
-- İsteğe bağlı parametrelerin `default null`'u sözleşmenin üst kümesidir (hepsi gönderilse de olur).
-- ---------------------------------------------------------------------------
create function public.create_community_post(
  p_kind       public.community_post_kind,
  p_body       text,
  p_photo_url  text default null,
  p_spot_id    uuid default null,
  p_animal_id  uuid default null,
  lat          float8 default null,
  lng          float8 default null,
  p_cover_from date default null,
  p_cover_to   date default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_max_body    constant int := 600;
  c_daily_limit constant int := 10;
  c_max_cover   constant int := 30;   -- gün (cover_to - cover_from)
  v_uid   uuid := private.require_uid();
  v_mod   boolean;
  v_body  text := private.trim_text(p_body);
  v_photo text := nullif(btrim(coalesce(p_photo_url, '')), '');
  v_cover boolean := (p_kind = 'cover_request');
  v_today date := private.istanbul_today();
  v_spot  public.spots;
  v_pt    extensions.geography;
  v_count int;
  v_trust int;
  v_state public.moderation_state;
  v_id    uuid;
begin
  if p_kind is null then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if char_length(v_photo) > 1024 then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  if v_body = '' then
    return jsonb_build_object('status', 'invalid', 'reason', 'body_empty');
  end if;
  if char_length(v_body) > c_max_body then
    return jsonb_build_object('status', 'invalid', 'reason', 'body_too_long');
  end if;

  perform private.ensure_profile(v_uid);
  -- Aynı kullanıcının eşzamanlı istekleri sırayla: günlük limit yarışsız
  perform pg_advisory_xact_lock(hashtextextended('community_post:' || v_uid::text, 0));

  if private.contains_profanity(v_body) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  -- Günlük limit (İstanbul günü)
  select count(*) into v_count
  from public.community_posts p
  where p.author_id = v_uid and p.created_at >= private.istanbul_day_start();
  if v_count >= c_daily_limit then
    return jsonb_build_object('status', 'limit_reached', 'limit', c_daily_limit);
  end if;

  -- Yalnızca yazara görünür bir nokta bağlanabilir
  if p_spot_id is not null then
    select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
    select * into v_spot from public.spots s where s.id = p_spot_id;
    if not found or not private.spot_visible(v_spot, v_uid, v_mod) then
      return jsonb_build_object('status', 'invalid', 'reason', 'spot_not_found');
    end if;
  end if;

  if v_cover then
    if p_spot_id is null then
      return jsonb_build_object('status', 'invalid', 'reason', 'cover_needs_spot');
    end if;
    -- cover_from ≥ bugün (İstanbul), cover_to ≥ cover_from, süre ≤ 30 gün
    if p_cover_from is null or p_cover_to is null
       or p_cover_from < v_today or p_cover_to < p_cover_from
       or p_cover_to - p_cover_from > c_max_cover then
      return jsonb_build_object('status', 'invalid', 'reason', 'cover_dates');
    end if;
  end if;

  if p_animal_id is not null and not exists (select 1 from public.animals a where a.id = p_animal_id) then
    raise exception 'not_found' using errcode = 'P0002', detail = 'animal';
  end if;

  -- Kaba konum (trigger 2 ondalığa yuvarlar). Noktaya bağlıysa noktadan türetilir; `public` olmayan
  -- noktalarda GÖSTERİLEN (bulanık) konumdan — aksi halde cell, bulanık noktanın gerçekte ızgaranın
  -- hangi hücresinde olduğunu ele verebilirdi (PRD 9.1). Bağlı değilse istemcinin konumu zorunludur.
  if p_spot_id is not null then
    v_pt := case when v_spot.visibility = 'public' then v_spot.location
                 else private.fuzz_point(v_spot.id, v_spot.location) end;
  else
    perform private.assert_lat_lng(create_community_post.lat, create_community_post.lng);
    v_pt := private.make_point(create_community_post.lat, create_community_post.lng);
  end if;

  -- trust_score < 5 → inceleme kuyruğu; paylaşım yalnızca yazarına görünür (PRD 9.3)
  select p.trust_score into v_trust from public.profiles p where p.id = v_uid;
  v_state := case when coalesce(v_trust, 0) < 5 then 'pending' else 'approved' end;

  insert into public.community_posts (author_id, kind, body, photo_url, spot_id, animal_id, cell,
                                      cover_from, cover_to, moderation_state)
  values (v_uid, p_kind, v_body, v_photo, p_spot_id, p_animal_id, v_pt,
          case when v_cover then p_cover_from end,     -- diğer türlerde p_cover_* yok sayılır
          case when v_cover then p_cover_to end,
          v_state)
  returning id into v_id;

  return jsonb_build_object('status', 'created', 'post_id', v_id, 'moderation_state', v_state);
end
$$;

-- ---------------------------------------------------------------------------
-- add_community_comment
-- Sıra: metin → küfür → paylaşım görünür mü → günlük limit → ekleme → yazara bildirim
-- ---------------------------------------------------------------------------
create function public.add_community_comment(p_post_id uuid, p_body text)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_max_body    constant int := 300;
  c_daily_limit constant int := 60;
  v_uid     uuid := private.require_uid();
  v_mod     boolean;
  v_body    text := private.trim_text(p_body);
  v_post    public.community_posts;
  v_count   int;
  v_id      uuid;
  v_name    text;
  v_excerpt text;
begin
  if v_body = '' then
    return jsonb_build_object('status', 'invalid', 'reason', 'body_empty');
  end if;
  if char_length(v_body) > c_max_body then
    return jsonb_build_object('status', 'invalid', 'reason', 'body_too_long');
  end if;
  if private.contains_profanity(v_body) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select * into v_post from public.community_posts p where p.id = p_post_id;
  if not found or not private.community_visible(v_post.moderation_state, v_post.author_id, v_uid, v_mod) then
    return jsonb_build_object('status', 'post_not_found');
  end if;

  perform private.ensure_profile(v_uid);
  perform pg_advisory_xact_lock(hashtextextended('community_comment:' || v_uid::text, 0));

  -- Günlük limit (İstanbul günü)
  select count(*) into v_count
  from public.community_comments c
  where c.author_id = v_uid and c.created_at >= private.istanbul_day_start();
  if v_count >= c_daily_limit then
    return jsonb_build_object('status', 'limit_reached', 'limit', c_daily_limit);
  end if;

  insert into public.community_comments (post_id, author_id, body)
  values (p_post_id, v_uid, v_body)
  returning id into v_id;

  -- Bildirim metni: "{ad}: {yorumun ilk ~80 karakteri}" (satır sonları tek boşluğa iner)
  select p.display_name into v_name from public.profiles p where p.id = v_uid;
  v_excerpt := regexp_replace(v_body, '\s+', ' ', 'g');
  if char_length(v_excerpt) > 80 then
    v_excerpt := rtrim(left(v_excerpt, 80)) || '…';
  end if;
  perform private.notify_post_author(
    v_post, v_uid, 'community_comment', 'Paylaşımına yorum geldi',
    format('%s: %s', coalesce(v_name, 'Bir mama dostu'), v_excerpt));

  return jsonb_build_object('status', 'created', 'comment_id', v_id);
end
$$;

-- ---------------------------------------------------------------------------
-- toggle_post_paw — "pati bırak" / geri al
-- ---------------------------------------------------------------------------
create function public.toggle_post_paw(p_post_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := private.require_uid();
  v_mod   boolean;
  v_post  public.community_posts;
  v_pawed boolean;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select * into v_post from public.community_posts p where p.id = p_post_id;
  if not found or not private.community_visible(v_post.moderation_state, v_post.author_id, v_uid, v_mod) then
    return jsonb_build_object('status', 'post_not_found');
  end if;

  delete from public.community_paws w where w.post_id = p_post_id and w.user_id = v_uid;
  v_pawed := not found;
  if v_pawed then
    perform private.ensure_profile(v_uid);
    insert into public.community_paws (post_id, user_id) values (p_post_id, v_uid)
    on conflict (post_id, user_id) do nothing;   -- çift dokunuş
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'pawed', v_pawed,
    'paw_count', (select count(*)::int from public.community_paws w where w.post_id = p_post_id));
end
$$;

-- ---------------------------------------------------------------------------
-- toggle_cover_volunteer — "Ben bakarım" / vazgeç. Bitiş günü (dahil) geçtiyse `closed`.
-- ---------------------------------------------------------------------------
create function public.toggle_cover_volunteer(p_post_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid         uuid := private.require_uid();
  v_mod         boolean;
  v_post        public.community_posts;
  v_volunteered boolean;
  v_name        text;
  v_title       text;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select * into v_post from public.community_posts p where p.id = p_post_id;
  if not found or not private.community_visible(v_post.moderation_state, v_post.author_id, v_uid, v_mod) then
    return jsonb_build_object('status', 'post_not_found');
  end if;
  if v_post.kind <> 'cover_request' then
    return jsonb_build_object('status', 'not_cover_request');
  end if;
  if v_post.author_id = v_uid then
    return jsonb_build_object('status', 'own_post');
  end if;
  if v_post.cover_to < private.istanbul_today() then
    return jsonb_build_object('status', 'closed');
  end if;

  delete from public.cover_volunteers v where v.post_id = p_post_id and v.user_id = v_uid;
  v_volunteered := not found;
  if v_volunteered then
    perform private.ensure_profile(v_uid);
    insert into public.cover_volunteers (post_id, user_id) values (p_post_id, v_uid)
    on conflict (post_id, user_id) do nothing;

    select p.display_name into v_name from public.profiles p where p.id = v_uid;
    select s.title into v_title from public.spots s where s.id = v_post.spot_id;
    perform private.notify_post_author(
      v_post, v_uid, 'cover_volunteered', 'Yerine bakacak biri var!',
      format('%s, %s için "Ben bakarım" dedi.', coalesce(v_name, 'Bir gönüllü'), coalesce(v_title, 'noktan')),
      v_post.spot_id);
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'volunteered', v_volunteered,
    'volunteer_count', (select count(*)::int from public.cover_volunteers v
                         where v.post_id = p_post_id and not private.blocked_between(v_uid, v.user_id)));
end
$$;

-- ---------------------------------------------------------------------------
-- delete_community_post — yazar veya moderatör. Yorumlar, patiler, gönüllüler ve paylaşıma bağlı
-- bildirimler FK cascade ile gider. Paylaşım yoksa exception (not_found), izin yoksa `not_allowed`.
-- ---------------------------------------------------------------------------
create function public.delete_community_post(p_post_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := private.require_uid();
  v_mod    boolean;
  v_author uuid;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select p.author_id into v_author from public.community_posts p where p.id = p_post_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002', detail = 'post';
  end if;
  if v_author <> v_uid and not v_mod then
    return jsonb_build_object('status', 'not_allowed');
  end if;

  delete from public.community_posts p where p.id = p_post_id;
  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- delete_community_comment — yorumun yazarı, paylaşımın yazarı (kendi paylaşımının altını
-- temizleyebilir) veya moderatör
-- ---------------------------------------------------------------------------
create function public.delete_community_comment(p_comment_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid         uuid := private.require_uid();
  v_mod         boolean;
  v_author      uuid;
  v_post_author uuid;
begin
  select f.is_moderator into v_mod from private.viewer_flags(v_uid) f;
  select c.author_id, p.author_id into v_author, v_post_author
  from public.community_comments c
  join public.community_posts p on p.id = c.post_id
  where c.id = p_comment_id
  for update of c;
  if not found then
    raise exception 'not_found' using errcode = 'P0002', detail = 'comment';
  end if;
  if v_author <> v_uid and v_post_author <> v_uid and not v_mod then
    return jsonb_build_object('status', 'not_allowed');
  end if;

  delete from public.community_comments c where c.id = p_comment_id;
  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- community_summary — "Bu hafta mahallende" kartı (son 7 gün = now() - 7 gün, neighborhood_summary gibi)
--   fed_spot_days_7d    : yarıçaptaki aktif noktalarda `fed` check-in'i olan farklı (nokta, İstanbul günü)
--                         sayısı — ürünün kuzey yıldızı metriği (beslenmiş nokta-gün)
--   active_feeders_7d   : o noktalarda `fed`/`water` check-in'i yapan farklı kullanıcı
--   open_cover_requests : yarıçaptaki onaylı, bitişi geçmemiş (cover_to ≥ bugün) "Yerime bakar mısın?"
--   posts_7d            : yarıçaptaki onaylı paylaşımlar
-- Paylaşım sayıları akışla tutarlı olsun diye engelli yazarlar sayılmaz. Yarıçap, akıştaki gibi
-- 1000–10 000 m'ye sıkıştırılır.
-- Noktalar yarıçapa GÖSTERİLEN konumlarıyla girer (public → gerçek, fuzzed/private → bulanık): aksi halde
-- merkez kaydırılıp sayının değiştiği sınır izlenerek gizli bir noktanın gerçek konumu bulunabilirdi
-- (PRD 9.1). Gerçek konum yalnızca indeks ön-filtresinde (bulanıklık payıyla) kullanılır.
-- ---------------------------------------------------------------------------
create function public.community_summary(lat float8, lng float8, radius_m int default 3000)
returns table (fed_spot_days_7d int, active_feeders_7d int, open_cover_requests int, posts_7d int)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid    uuid := private.require_uid();
  v_ref    extensions.geography;
  v_radius int := greatest(1000, least(coalesce(community_summary.radius_m, 3000), 10000));
  v_since  timestamptz := now() - interval '7 days';
  v_today  date := private.istanbul_today();
begin
  perform private.assert_lat_lng(community_summary.lat, community_summary.lng);
  v_ref := private.make_point(community_summary.lat, community_summary.lng);

  return query
  with area as (
    select s.id
    from public.spots s
    where extensions.st_dwithin(s.location, v_ref, v_radius + 110)
      and s.is_active
      and s.moderation_state = 'approved'
      and extensions.st_dwithin(
            case when s.visibility = 'public' then s.location
                 else private.fuzz_point(s.id, s.location) end,
            v_ref, v_radius)
  ),
  feedings as (
    select c.spot_id, c.user_id, c.kind, (c.created_at at time zone 'Europe/Istanbul')::date as day
    from public.checkins c
    join area on area.id = c.spot_id
    where c.created_at > v_since
      and c.kind in ('fed', 'water')
  ),
  nearby as (
    select p.kind, p.cover_to, p.created_at
    from public.community_posts p
    where extensions.st_dwithin(p.cell, v_ref, v_radius)
      and p.moderation_state = 'approved'
      and not private.blocked_between(v_uid, p.author_id)
  )
  select
    (select count(*)::int from (select distinct f.spot_id, f.day from feedings f where f.kind = 'fed') d),
    (select count(distinct f.user_id)::int from feedings f),
    (select count(*)::int from nearby n where n.kind = 'cover_request' and n.cover_to >= v_today),
    (select count(*)::int from nearby n where n.created_at > v_since);
end
$$;

-- ---------------------------------------------------------------------------
-- Otomatik gizleme: bir paylaşım veya yorum 3 FARKLI kullanıcı tarafından raporlanırsa `pending` olur
-- (yalnızca yazarına ve moderatöre görünür). Yalnızca AÇIK raporlar sayılır: moderatör raporları
-- kapatıp (dismissed/actioned) içeriği yeniden onayladıysa tek bir yeni rapor tekrar gizlemez.
-- `rejected` içerik `pending`e geri çekilmez.
-- reports tablosuna istemci doğrudan yazar (RLS); trigger gizli tablolara dokunduğu için security definer.
-- ---------------------------------------------------------------------------
create function private.auto_hide_reported()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_reporters int;
begin
  -- aynı hedefe eşzamanlı raporlar sırayla sayılsın
  perform pg_advisory_xact_lock(hashtextextended('report:' || new.target_id::text, 0));

  select count(distinct r.reporter_id) into v_reporters
  from public.reports r
  where r.target_type = new.target_type
    and r.target_id = new.target_id
    and r.status = 'open';

  if v_reporters >= 3 then
    if new.target_type = 'post' then
      update public.community_posts set moderation_state = 'pending'
      where id = new.target_id and moderation_state = 'approved';
    else
      update public.community_comments set moderation_state = 'pending'
      where id = new.target_id and moderation_state = 'approved';
    end if;
  end if;
  return null;
end
$$;

create trigger reports_auto_hide_community
  after insert on public.reports
  for each row
  when (new.target_type in ('post', 'comment'))
  execute function private.auto_hide_reported();

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.community_feed(float8, float8, int, public.community_post_kind, timestamptz, int) from public, anon, authenticated;
revoke all on function public.community_post_detail(uuid, float8, float8)   from public, anon, authenticated;
revoke all on function public.community_comments_of(uuid)                   from public, anon, authenticated;
revoke all on function public.cover_volunteers_of(uuid)                     from public, anon, authenticated;
revoke all on function public.create_community_post(public.community_post_kind, text, text, uuid, uuid, float8, float8, date, date) from public, anon, authenticated;
revoke all on function public.add_community_comment(uuid, text)             from public, anon, authenticated;
revoke all on function public.toggle_post_paw(uuid)                         from public, anon, authenticated;
revoke all on function public.toggle_cover_volunteer(uuid)                  from public, anon, authenticated;
revoke all on function public.delete_community_post(uuid)                   from public, anon, authenticated;
revoke all on function public.delete_community_comment(uuid)                from public, anon, authenticated;
revoke all on function public.community_summary(float8, float8, int)        from public, anon, authenticated;

grant execute on function public.community_feed(float8, float8, int, public.community_post_kind, timestamptz, int) to authenticated;
grant execute on function public.community_post_detail(uuid, float8, float8)  to authenticated;
grant execute on function public.community_comments_of(uuid)                  to authenticated;
grant execute on function public.cover_volunteers_of(uuid)                    to authenticated;
grant execute on function public.create_community_post(public.community_post_kind, text, text, uuid, uuid, float8, float8, date, date) to authenticated;
grant execute on function public.add_community_comment(uuid, text)            to authenticated;
grant execute on function public.toggle_post_paw(uuid)                        to authenticated;
grant execute on function public.toggle_cover_volunteer(uuid)                 to authenticated;
grant execute on function public.delete_community_post(uuid)                  to authenticated;
grant execute on function public.delete_community_comment(uuid)               to authenticated;
grant execute on function public.community_summary(float8, float8, int)       to authenticated;
