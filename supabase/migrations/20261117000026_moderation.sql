-- Mama Haritası — 0026: Uygulama içi moderasyon (Faz 3.1, docs/superpowers/specs/2026-11-17-moderasyon-design.md, D21)
--
-- * Moderatör RPC'leri (`moderation_*`): hepsi `security definer`, yalnızca authenticated; moderatörlük HER çağrıda
--   `profiles.is_moderator` ile yeniden doğrulanır. Moderatör olmayana `{status:'not_allowed'}` / 0 satır / 0.
-- * Raporlar hedefe göre gruplanır. Kararlar (approve | remove) ve uzaklaştırmalar `moderation_actions`'a yazılır.
-- * Uzaklaştırma (`profiles.suspended_until`, 'infinity' = süresiz) YAZMAYI engeller, okumayı değil:
--     - `private.require_uid()` artık uzaklaştırılmış kullanıcıda 'suspended' istisnası atar (P0001, detail = bitiş).
--       Her yazma RPC'si bunu ilk iş çağırır; yeni yazma RPC'leri varsayılan olarak kapalıdır.
--     - Okuma RPC'leri ve izin verilen yazmalar (bildirim ayarları/cihaz, okundu, ayrılma/silme/geri çekme) yalnızca
--       oturumu doğrulayan `private.require_reader()`'a geçirilir (aşağıdaki DO bloğu).
--     - RPC'yi atlayan doğrudan tablo yazmaları (animals, follows, guardians, reports) RLS `with check` içinde
--       `public.assert_can_write()` ile aynı istisnayı atar. Engelleme, profil düzenleme, bildirim ayarları,
--       takipten çıkma/koruyuculuktan çıkma ve hesap silme açık kalır.
-- * `suspended_until` başkalarına görünmez: profiles okuma yetkisi sütun bazlı yapılır; kişi kendi durumunu
--   `my_suspension()` ile, moderatör `moderation_target_reports` ile görür.
-- * Sohbet gizliliği: moderatör yalnızca raporlanan mesajın metnini görür.

-- ---------------------------------------------------------------------------
-- profiles.suspended_until + sütun bazlı okuma yetkisi
-- ---------------------------------------------------------------------------
alter table public.profiles add column suspended_until timestamptz;

revoke select on public.profiles from anon, authenticated;
grant select (id, display_name, avatar_url, neighborhood, trust_score, is_verified_feeder, is_moderator, created_at)
  on public.profiles to anon, authenticated;

-- ---------------------------------------------------------------------------
-- moderation_actions: karar kaydı. Doğrudan erişim YOK (yalnızca RPC).
-- ---------------------------------------------------------------------------
create table public.moderation_actions (
  id              uuid primary key default gen_random_uuid(),
  moderator_id    uuid references public.profiles (id) on delete set null,
  target_type     public.report_target not null,
  target_id       uuid not null,
  -- sözleşmeye ek: içeriğin sahibi (içerik silinse de "son 90 günde kaldırılan" sayılabilsin)
  target_owner_id uuid references public.profiles (id) on delete set null,
  action          text not null check (action in ('approve', 'remove', 'suspend', 'unsuspend')),
  note            text check (note is null or char_length(note) <= 500),
  suspend_days    int check (suspend_days is null or suspend_days > 0),
  created_at      timestamptz not null default now()
);

create index moderation_actions_target_idx on public.moderation_actions (target_type, target_id, created_at desc);
create index moderation_actions_owner_idx on public.moderation_actions (target_owner_id, created_at desc)
  where target_owner_id is not null;
create index moderation_actions_moderator_idx on public.moderation_actions (moderator_id) where moderator_id is not null;

alter table public.moderation_actions enable row level security;
revoke all on public.moderation_actions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Yazma kapısı
-- ---------------------------------------------------------------------------
-- Uzaklaştırma bitişinin istemciye giden biçimi: 'infinity' veya ISO 8601 (UTC)
create function private.suspension_text(p_until timestamptz)
returns text
language sql immutable
set search_path = public, extensions
as $$
  select case
           when p_until is null then null
           when p_until = 'infinity'::timestamptz then 'infinity'
           else to_char(p_until at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         end
$$;

-- Yalnızca oturum: okuma RPC'leri ve uzaklaştırılmış kullanıcının da yapabileceği yazmalar
create function private.require_reader()
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

-- Yazma RPC'lerinin ilk işi: oturum + uzaklaştırma
create or replace function private.require_uid()
returns uuid
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_until timestamptz;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select p.suspended_until into v_until from public.profiles p where p.id = v_uid;
  if v_until is not null and v_until > now() then
    raise exception 'suspended' using errcode = 'P0001', detail = private.suspension_text(v_until), hint = 'suspended';
  end if;
  return v_uid;
end
$$;

-- RLS'ten çağrılabilir (private şemasına RLS'ten erişilemez, bkz. 0017): uzaklaştırılmışsa istisna, değilse true
create function public.assert_can_write()
returns boolean
language plpgsql stable security definer
set search_path = public, extensions
as $$
begin
  perform private.require_uid();
  return true;
end
$$;

-- Kişinin kendi uzaklaştırma bitişi (yoksa ya da dolduysa null)
create function public.my_suspension()
returns timestamptz
language sql stable security definer
set search_path = public, extensions
as $$
  select p.suspended_until from public.profiles p
   where p.id = auth.uid() and p.suspended_until > now()
$$;

-- ---------------------------------------------------------------------------
-- Okuma RPC'leri + izin verilen yazmalar → private.require_reader()
-- Gövdeler kopyalanmaz: canlı tanım (pg_get_functiondef) alınır, yalnızca kapı çağrısı değiştirilir.
-- Yetkiler `create or replace` ile korunur. Bu fonksiyonlar ileride yeniden tanımlanırsa
-- `private.require_reader()` kullanılmalı (supabase/tests/97_moderation.sql bunu denetler).
-- ---------------------------------------------------------------------------
do $$
declare
  v_name text;
  v_fn   record;
  v_def  text;
  v_n    int;
begin
  foreach v_name in array array[
    -- okumalar
    'find_duplicate_spots', 'followed_spots', 'community_feed', 'community_post_detail', 'community_comments_of',
    'cover_volunteers_of', 'community_summary', 'social_profile_me', 'meetups_near', 'meetup_detail',
    'meetup_participants', 'animal_lovers_near', 'incoming_connection_requests', 'my_conversations',
    'conversation_messages',
    -- izin verilen yazmalar: cihaz/bildirim, okundu, kendi kaydından çekilme
    'register_device_token', 'update_notify_center', 'mark_conversation_read', 'leave_meetup', 'cancel_meetup',
    'withdraw_connection_request', 'remove_connection', 'delete_community_post', 'delete_community_comment'
  ] loop
    v_n := 0;
    for v_fn in
      select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_name
    loop
      v_def := pg_get_functiondef(v_fn.oid);
      if position('private.require_uid()' in v_def) = 0 then
        raise exception 'public.% beklenen kapı çağrısını içermiyor', v_name;
      end if;
      execute replace(v_def, 'private.require_uid()', 'private.require_reader()');
      v_n := v_n + 1;
    end loop;
    if v_n = 0 then
      raise exception 'public.% bulunamadı', v_name;
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Doğrudan tablo yazmaları: RLS `with check` + uzaklaştırma
-- ---------------------------------------------------------------------------
drop policy animals_insert_own on public.animals;
create policy animals_insert_own on public.animals
  for insert to authenticated
  with check (created_by = (select auth.uid()) and (select public.assert_can_write()));

drop policy animals_update_owner_or_verified on public.animals;
create policy animals_update_owner_or_verified on public.animals
  for update to authenticated
  using (
    created_by = (select auth.uid())
    or exists (select 1 from public.profiles p
               where p.id = (select auth.uid()) and (p.is_verified_feeder or p.is_moderator))
  )
  with check (
    (created_by = (select auth.uid())
     or exists (select 1 from public.profiles p
                where p.id = (select auth.uid()) and (p.is_verified_feeder or p.is_moderator)))
    and (select public.assert_can_write())
  );

drop policy follows_insert_own on public.follows;
create policy follows_insert_own on public.follows
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.assert_can_write()));

drop policy guardians_insert_own on public.guardians;
create policy guardians_insert_own on public.guardians
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.assert_can_write()) and public.can_guard_spot(spot_id));

drop policy guardians_update_own on public.guardians;
create policy guardians_update_own on public.guardians
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and (select public.assert_can_write()));

drop policy reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()) and (select public.assert_can_write()));

-- ---------------------------------------------------------------------------
-- Moderasyon yardımcıları
-- ---------------------------------------------------------------------------
create function private.is_moderator(p_uid uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select coalesce((select p.is_moderator from public.profiles p where p.id = p_uid), false)
$$;

-- Hedefin son kararı (approve | remove)
create function private.moderation_last_decision(p_type public.report_target, p_id uuid,
                                                 out action text, out created_at timestamptz)
language sql stable
set search_path = public, extensions
as $$
  select a.action, a.created_at
  from public.moderation_actions a
  where a.target_type = p_type and a.target_id = p_id and a.action in ('approve', 'remove')
  order by a.created_at desc, a.id desc
  limit 1
$$;

-- Hedefin önizlemesi ve durumu. Sohbet mesajında yalnızca o mesaj; sohbetin geri kalanı asla.
--   state: live | pending | removed | gone
create function private.moderation_preview(
  p_type public.report_target,
  p_id   uuid,
  out title     text,
  out body      text,
  out photo_url text,
  out owner_id  uuid,
  out state     text
)
language plpgsql stable
set search_path = public, extensions
as $$
declare
  v_found boolean := false;
  v_mod   public.moderation_state;
  v_last  text;
begin
  case p_type
    when 'spot' then
      select s.title, s.note, s.photo_url, s.created_by, s.moderation_state, true
        into title, body, photo_url, owner_id, v_mod, v_found
        from public.spots s where s.id = p_id;
    when 'animal' then
      select a.name, a.about, a.photos[1], a.created_by, true
        into title, body, photo_url, owner_id, v_found
        from public.animals a where a.id = p_id;
    when 'need' then
      select n.type::text, n.description, n.photos[1], n.created_by, true
        into title, body, photo_url, owner_id, v_found
        from public.needs n where n.id = p_id;
    when 'checkin', 'photo' then
      select s.title, c.kind::text, c.photo_url, c.user_id, true
        into title, body, photo_url, owner_id, v_found
        from public.checkins c join public.spots s on s.id = c.spot_id where c.id = p_id;
      if not coalesce(v_found, false) and p_type = 'photo' then
        -- fotoğraf raporu nokta fotoğrafını da hedefleyebilir
        select s.title, null::text, s.photo_url, s.created_by, true
          into title, body, photo_url, owner_id, v_found
          from public.spots s where s.id = p_id;
      end if;
    when 'user' then
      select p.display_name, null::text, p.avatar_url, p.id, true
        into title, body, photo_url, owner_id, v_found
        from public.profiles p where p.id = p_id;
    when 'post' then
      select cp.kind::text, cp.body, cp.photo_url, cp.author_id, cp.moderation_state, true
        into title, body, photo_url, owner_id, v_mod, v_found
        from public.community_posts cp where cp.id = p_id;
    when 'comment' then
      select null::text, cc.body, null::text, cc.author_id, cc.moderation_state, true
        into title, body, photo_url, owner_id, v_mod, v_found
        from public.community_comments cc where cc.id = p_id;
    when 'meetup' then
      select m.title, m.description, null::text, m.organizer_id, true
        into title, body, photo_url, owner_id, v_found
        from public.meetups m where m.id = p_id;
    when 'chat_message' then
      select null::text, cm.body, null::text, cm.author_id, cm.moderation_state, true
        into title, body, photo_url, owner_id, v_mod, v_found
        from public.chat_messages cm where cm.id = p_id;
    else
      v_found := false;
  end case;

  v_found := coalesce(v_found, false);
  title := left(title, 300);
  body := left(body, 300);
  v_last := (private.moderation_last_decision(p_type, p_id)).action;

  if p_type = 'user' then
    state := case when v_found then 'live' else 'gone' end;
  elsif v_last = 'remove' then
    state := 'removed';
  elsif not v_found then
    state := 'gone';
  elsif v_mod = 'pending' then
    state := 'pending';
  elsif v_mod = 'rejected' then
    state := 'removed';
  else
    state := 'live';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- moderation_open_count: açık raporu olan hedef sayısı (Profil rozeti)
-- ---------------------------------------------------------------------------
create function public.moderation_open_count()
returns int
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_reader();
begin
  if not private.is_moderator(v_uid) then
    return 0;
  end if;
  return (select count(*)::int from (
            select distinct r.target_type, r.target_id from public.reports r where r.status = 'open') t);
end
$$;

-- ---------------------------------------------------------------------------
-- moderation_queue: hedefe göre gruplanmış raporlar
--   Açık (varsayılan): açık raporu olan hedefler; en çok raporlanan, sonra en eski önce. Sayılar açık raporlar.
--   Kapananlar (p_closed): açık raporu kalmamış, son 30 günde kapanmış hedefler + verilen karar; yeniden eskiye.
-- ---------------------------------------------------------------------------
create function public.moderation_queue(p_closed boolean default false, max_rows int default 50)
returns table (
  target_type       public.report_target,
  target_id         uuid,
  title             text,
  body              text,
  photo_url         text,
  owner_id          uuid,
  owner_name        text,
  report_count      int,
  reasons           public.report_reason[],
  first_reported_at timestamptz,
  last_reported_at  timestamptz,
  content_state     text,
  decision          text,
  decided_at        timestamptz
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_reader();
  v_limit int := least(greatest(coalesce(max_rows, 50), 1), 200);
begin
  if not private.is_moderator(v_uid) then
    return;
  end if;

  if not coalesce(p_closed, false) then
    return query
    select g.target_type, g.target_id, pv.title, pv.body, pv.photo_url, pv.owner_id, op.display_name,
           g.n, g.reasons, g.first_at, g.last_at, pv.state, null::text, null::timestamptz
    from (
      select r.target_type, r.target_id, count(*)::int as n,
             array_agg(distinct r.reason order by r.reason) as reasons,
             min(r.created_at) as first_at, max(r.created_at) as last_at
      from public.reports r
      where r.status = 'open'
      group by r.target_type, r.target_id
    ) g
    cross join lateral private.moderation_preview(g.target_type, g.target_id) pv
    left join public.profiles op on op.id = pv.owner_id
    order by g.n desc, g.first_at asc, g.target_id
    limit v_limit;
  else
    return query
    select g.target_type, g.target_id, pv.title, pv.body, pv.photo_url, pv.owner_id, op.display_name,
           g.n, g.reasons, g.first_at, g.last_at, pv.state, d.action, coalesce(d.created_at, g.closed_at)
    from (
      select r.target_type, r.target_id, count(*)::int as n,
             array_agg(distinct r.reason order by r.reason) as reasons,
             min(r.created_at) as first_at, max(r.created_at) as last_at,
             max(r.resolved_at) as closed_at
      from public.reports r
      group by r.target_type, r.target_id
      having bool_and(r.status <> 'open') and max(r.resolved_at) >= now() - interval '30 days'
    ) g
    cross join lateral private.moderation_preview(g.target_type, g.target_id) pv
    cross join lateral private.moderation_last_decision(g.target_type, g.target_id) d
    left join public.profiles op on op.id = pv.owner_id
    order by g.closed_at desc, g.target_id
    limit v_limit;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- moderation_target_reports: tek hedefin önizlemesi, tüm raporları ve sahibinin geçmişi
-- ---------------------------------------------------------------------------
create function public.moderation_target_reports(p_target_type public.report_target, p_target_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid     uuid := private.require_reader();
  v_pv      record;
  v_last    record;
  v_reports jsonb;
  v_owner   jsonb := null;
  v_profile public.profiles;
begin
  if not private.is_moderator(v_uid) then
    return jsonb_build_object('status', 'not_allowed');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'reason', r.reason,
           'details', r.details,
           'created_at', r.created_at,
           'reporter_id', r.reporter_id,
           'reporter_name', rp.display_name,
           'status', r.status
         ) order by r.created_at desc, r.id), '[]'::jsonb)
    into v_reports
    from public.reports r
    left join public.profiles rp on rp.id = r.reporter_id
   where r.target_type = p_target_type and r.target_id = p_target_id;

  if jsonb_array_length(v_reports) = 0 then
    return jsonb_build_object('status', 'not_found');
  end if;

  select * into v_pv from private.moderation_preview(p_target_type, p_target_id);
  select * into v_last from private.moderation_last_decision(p_target_type, p_target_id);

  if v_pv.owner_id is not null then
    select * into v_profile from public.profiles p where p.id = v_pv.owner_id;
    v_owner := jsonb_build_object(
      'user_id', v_pv.owner_id,
      'display_name', v_profile.display_name,
      'is_moderator', coalesce(v_profile.is_moderator, false),
      'removed_count_90d', (select count(*)::int from public.moderation_actions a
                             where a.target_owner_id = v_pv.owner_id and a.action = 'remove'
                               and a.target_type <> 'user'
                               and a.created_at >= now() - interval '90 days'),
      'suspension_count_90d', (select count(*)::int from public.moderation_actions a
                                where a.target_type = 'user' and a.target_id = v_pv.owner_id
                                  and a.action = 'suspend' and a.created_at >= now() - interval '90 days'),
      'suspended_until', case when v_profile.suspended_until > now()
                              then private.suspension_text(v_profile.suspended_until) end
    );
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'case', jsonb_build_object(
      'target_type', p_target_type,
      'target_id', p_target_id,
      'title', v_pv.title,
      'body', v_pv.body,
      'photo_url', v_pv.photo_url,
      'owner_id', v_pv.owner_id,
      'owner_name', v_profile.display_name,
      'content_state', v_pv.state,
      'decision', v_last.action,
      'decided_at', v_last.created_at
    ),
    'reports', v_reports,
    'owner', v_owner
  );
end
$$;

-- ---------------------------------------------------------------------------
-- moderation_decide: approve → içerik approved, açık raporlar dismissed;
--                    remove  → içerik herkesten gizlenir/iptal/silinir, açık raporlar actioned
-- ---------------------------------------------------------------------------
create function public.moderation_decide(
  p_target_type public.report_target,
  p_target_id   uuid,
  p_action      text,
  p_note        text default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := private.require_uid();
  v_note   text := nullif(private.trim_text(p_note), '');
  v_owner  uuid;
  v_closed int;
begin
  if not private.is_moderator(v_uid) then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  if p_action is null or p_action not in ('approve', 'remove') then
    return jsonb_build_object('status', 'invalid', 'reason', 'action');
  end if;
  if char_length(v_note) > 500 then
    return jsonb_build_object('status', 'invalid', 'reason', 'note_too_long');
  end if;

  -- aynı hedefe eşzamanlı kararlar ve raporlar sırayla (auto_hide_reported ile aynı kilit)
  perform pg_advisory_xact_lock(hashtextextended('report:' || p_target_id::text, 0));
  if not exists (select 1 from public.reports r where r.target_type = p_target_type and r.target_id = p_target_id) then
    return jsonb_build_object('status', 'not_found');
  end if;

  v_owner := (private.moderation_preview(p_target_type, p_target_id)).owner_id;

  if p_action = 'approve' then
    case p_target_type
      when 'spot' then update public.spots set moderation_state = 'approved' where id = p_target_id;
      when 'post' then update public.community_posts set moderation_state = 'approved' where id = p_target_id;
      when 'comment' then update public.community_comments set moderation_state = 'approved' where id = p_target_id;
      when 'chat_message' then update public.chat_messages set moderation_state = 'approved' where id = p_target_id;
      else null;
    end case;
  else
    case p_target_type
      when 'spot' then update public.spots set moderation_state = 'rejected' where id = p_target_id;
      when 'post' then update public.community_posts set moderation_state = 'rejected' where id = p_target_id;
      when 'comment' then update public.community_comments set moderation_state = 'rejected' where id = p_target_id;
      when 'chat_message' then update public.chat_messages set moderation_state = 'rejected' where id = p_target_id;
      when 'meetup' then
        update public.meetups set status = 'cancelled' where id = p_target_id and status <> 'cancelled';
        update public.conversations set closed_at = now() where meetup_id = p_target_id and closed_at is null;
      when 'need' then delete from public.needs where id = p_target_id;
      when 'animal' then delete from public.animals where id = p_target_id;
      when 'checkin' then update public.checkins set photo_url = null where id = p_target_id;
      when 'photo' then
        update public.checkins set photo_url = null where id = p_target_id;
        if not found then
          update public.spots set photo_url = null where id = p_target_id;
        end if;
      else null;  -- 'user': içerik yok, yalnızca raporlar kapanır (uzaklaştırma ayrı karar)
    end case;
  end if;

  update public.reports
     set status = case when p_action = 'approve' then 'dismissed'::public.report_status
                       else 'actioned'::public.report_status end,
         resolved_at = now()
   where target_type = p_target_type and target_id = p_target_id and status = 'open';
  get diagnostics v_closed = row_count;

  insert into public.moderation_actions (moderator_id, target_type, target_id, target_owner_id, action, note)
  values (v_uid, p_target_type, p_target_id, v_owner, p_action, v_note);

  return jsonb_build_object('status', 'ok', 'closed_reports', v_closed);
end
$$;

-- ---------------------------------------------------------------------------
-- moderation_suspend_user / moderation_unsuspend_user
--   p_days: 7 | 30 | null (süresiz). Kendini ya da bir moderatörü uzaklaştıramaz.
-- ---------------------------------------------------------------------------
create function public.moderation_suspend_user(p_user_id uuid, p_days int, p_note text default null)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := private.require_uid();
  v_note   text := nullif(private.trim_text(p_note), '');
  v_target public.profiles;
  v_until  timestamptz;
begin
  if not private.is_moderator(v_uid) then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  select * into v_target from public.profiles where id = p_user_id for update;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  if p_user_id = v_uid or v_target.is_moderator then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  if p_days is not null and p_days not in (7, 30) then
    return jsonb_build_object('status', 'invalid', 'reason', 'days');
  end if;
  if char_length(v_note) > 500 then
    return jsonb_build_object('status', 'invalid', 'reason', 'note_too_long');
  end if;

  v_until := case when p_days is null then 'infinity'::timestamptz else now() + make_interval(days => p_days) end;
  update public.profiles set suspended_until = v_until where id = p_user_id;
  insert into public.moderation_actions (moderator_id, target_type, target_id, target_owner_id, action, note, suspend_days)
  values (v_uid, 'user', p_user_id, p_user_id, 'suspend', v_note, p_days);

  return jsonb_build_object('status', 'ok', 'suspended_until', private.suspension_text(v_until));
end
$$;

create function public.moderation_unsuspend_user(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not private.is_moderator(v_uid) then
    return jsonb_build_object('status', 'not_allowed');
  end if;
  update public.profiles set suspended_until = null where id = p_user_id;
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;
  insert into public.moderation_actions (moderator_id, target_type, target_id, target_owner_id, action)
  values (v_uid, 'user', p_user_id, p_user_id, 'unsuspend');
  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.assert_can_write()                                       from public, anon, authenticated;
revoke all on function public.my_suspension()                                          from public, anon, authenticated;
revoke all on function public.moderation_open_count()                                  from public, anon, authenticated;
revoke all on function public.moderation_queue(boolean, int)                           from public, anon, authenticated;
revoke all on function public.moderation_target_reports(public.report_target, uuid)    from public, anon, authenticated;
revoke all on function public.moderation_decide(public.report_target, uuid, text, text) from public, anon, authenticated;
revoke all on function public.moderation_suspend_user(uuid, int, text)                 from public, anon, authenticated;
revoke all on function public.moderation_unsuspend_user(uuid)                          from public, anon, authenticated;

grant execute on function public.assert_can_write()                                       to authenticated;
grant execute on function public.my_suspension()                                          to authenticated;
grant execute on function public.moderation_open_count()                                  to authenticated;
grant execute on function public.moderation_queue(boolean, int)                           to authenticated;
grant execute on function public.moderation_target_reports(public.report_target, uuid)    to authenticated;
grant execute on function public.moderation_decide(public.report_target, uuid, text, text) to authenticated;
grant execute on function public.moderation_suspend_user(uuid, int, text)                 to authenticated;
grant execute on function public.moderation_unsuspend_user(uuid)                          to authenticated;
