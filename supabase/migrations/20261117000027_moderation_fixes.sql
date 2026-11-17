-- Mama Haritası — 0027: Moderasyon düzeltme turu 1 (Faz 3.1 incelemesi, D21)
--
-- * Depolama: uzaklaştırılmış kullanıcı `photos` bucket'ına yükleyemez ve kendi dosyasının üzerine yazamaz
--   (yayımlanmış içeriğin arkasındaki dosya). Silme açık kalır.
-- * Raporlar: moderatörün doğrudan `update` yetkisi kaldırıldı; kararlar yalnızca `moderation_decide` ile ve
--   kayıt altında verilir. Uzaklaştırılmış kullanıcı yine de rapor ekleyebilir (taciz edilen kişi bildirebilsin).
-- * Profil: uzaklaştırılmışken `display_name` ve `avatar_url` değiştirilemez (herkese görünen içerik); semt,
--   bildirim ayarları ve hesap silme açık.
-- * Güvenlik eylemleri uzaklaştırmada açık: kendini Hayvanseverler'den gizlemek (yalnızca `is_visible = false`,
--   hakkımda/ilgi değişmeden) ve gelen isteği reddetmek. Görünür olmak, metin düzenlemek ve kabul etmek kapalı.
-- * Geri alınamayan kaldırmalar (buluşma iptali, ihtiyaç/hayvan silme, fotoğraf temizleme): içerik durumu hep
--   'removed', `approve` → `{status:'invalid', reason:'not_restorable'}`; detayda `restorable` ve sahibin avatarı.

-- ---------------------------------------------------------------------------
-- Yardımcılar
-- ---------------------------------------------------------------------------
create function private.is_suspended(p_uid uuid)
returns boolean
language sql stable security definer
set search_path = public, extensions
as $$
  select coalesce((select p.suspended_until > now() from public.profiles p where p.id = p_uid), false)
$$;

-- Kaldırma geri alınabilir mi? İptal/silme/temizleme yapılmış hedefte hayır.
create function private.moderation_restorable(p_type public.report_target, p_id uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select not (p_type in ('meetup', 'need', 'animal', 'checkin', 'photo')
              and exists (select 1 from public.moderation_actions a
                          where a.target_type = p_type and a.target_id = p_id and a.action = 'remove'))
$$;

-- ---------------------------------------------------------------------------
-- Depolama (0010 ile aynı koşullu kurulum): yükleme/üzerine yazma uzaklaştırmada kapalı
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage şeması yok, photos politikaları atlandı';
    return;
  end if;
  execute 'drop policy if exists photos_insert_own on storage.objects';
  execute 'drop policy if exists photos_update_own on storage.objects';
  execute $q$create policy photos_insert_own on storage.objects
               for insert to authenticated
               with check (bucket_id = 'photos'
                           and (storage.foldername(name))[1] = (select auth.uid())::text
                           and (select public.assert_can_write()))$q$;
  execute $q$create policy photos_update_own on storage.objects
               for update to authenticated
               using (bucket_id = 'photos'
                      and (storage.foldername(name))[1] = (select auth.uid())::text)
               with check (bucket_id = 'photos'
                           and (storage.foldername(name))[1] = (select auth.uid())::text
                           and (select public.assert_can_write()))$q$;
end
$$;

-- ---------------------------------------------------------------------------
-- Raporlar: doğrudan güncelleme yok; ekleme uzaklaştırmada da açık
-- ---------------------------------------------------------------------------
revoke update on public.reports from authenticated;
drop policy reports_update_moderator on public.reports;

drop policy reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Profil: herkese görünen ad ve fotoğraf uzaklaştırmada değişmez
-- ---------------------------------------------------------------------------
create function private.guard_profile_public_fields()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is not null and auth.uid() = new.id then
    perform private.require_uid();  -- uzaklaştırılmışsa 'suspended'
  end if;
  return new;
end
$$;

create trigger profiles_guard_public_fields
  before update of display_name, avatar_url on public.profiles
  for each row
  when (new.display_name is distinct from old.display_name or new.avatar_url is distinct from old.avatar_url)
  execute function private.guard_profile_public_fields();

-- ---------------------------------------------------------------------------
-- respond_connection: reddetmek uzaklaştırmada açık, kabul etmek kapalı.
-- Eski gövde `private.respond_connection_impl` olur (yalnızca oturum denetler); kapı sarmalayıcıda.
-- ---------------------------------------------------------------------------
alter function public.respond_connection(uuid, boolean) set schema private;
alter function private.respond_connection(uuid, boolean) rename to respond_connection_impl;
revoke all on function private.respond_connection_impl(uuid, boolean) from public, anon, authenticated;

do $$
declare
  v_def text := pg_get_functiondef('private.respond_connection_impl(uuid, boolean)'::regprocedure);
begin
  if position('private.require_uid()' in v_def) = 0 then
    raise exception 'respond_connection_impl beklenen kapı çağrısını içermiyor';
  end if;
  execute replace(v_def, 'private.require_uid()', 'private.require_reader()');
end
$$;

create function public.respond_connection(p_request_id uuid, p_accept boolean)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
begin
  if p_accept is distinct from false then
    perform private.require_uid();      -- kabul: yazma kapısı
  else
    perform private.require_reader();   -- reddetmek bir güvenlik eylemi
  end if;
  return private.respond_connection_impl(p_request_id, p_accept);
end
$$;

-- ---------------------------------------------------------------------------
-- update_social_profile: uzaklaştırılmış kişi yalnızca kendini gizleyebilir (hakkımda/ilgi aynı kalmalı).
-- Eski gövde `private.update_social_profile_impl` olur (kendi yazma kapısıyla, değişmeden).
-- ---------------------------------------------------------------------------
alter function public.update_social_profile(boolean, text, public.social_interest[], float8, float8) set schema private;
alter function private.update_social_profile(boolean, text, public.social_interest[], float8, float8)
  rename to update_social_profile_impl;
revoke all on function private.update_social_profile_impl(boolean, text, public.social_interest[], float8, float8)
  from public, anon, authenticated;

create function public.update_social_profile(
  p_is_visible boolean,
  p_about      text,
  p_interests  public.social_interest[],
  lat          float8 default null,
  lng          float8 default null
)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_reader();
  v_sp  public.social_profiles;
  v_in  public.social_interest[] := coalesce(p_interests, '{}');
begin
  if p_is_visible is distinct from false or not private.is_suspended(v_uid) then
    return private.update_social_profile_impl(p_is_visible, p_about, p_interests, lat, lng);
  end if;

  -- uzaklaştırılmış ve gizleniyor
  select * into v_sp from public.social_profiles sp where sp.user_id = v_uid;
  if not found or not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;
  if private.trim_text(p_about) is distinct from v_sp.about
     or not (v_in @> v_sp.interests and v_sp.interests @> v_in) then
    perform private.require_uid();  -- metin/ilgi düzenlemek yazmadır → 'suspended'
  end if;
  update public.social_profiles set is_visible = false where user_id = v_uid;
  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- Moderasyon: geri alınamayan kaldırmalar, detayda `restorable` ve sahip avatarı (0026 tanımlarının güncellemesi)
-- ---------------------------------------------------------------------------
create or replace function private.moderation_preview(
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
  elsif not private.moderation_restorable(p_type, p_id) then
    -- iptal/silme/temizleme geri alınamaz: sonraki bir 'approve' bunu "yayında" göstermez
    state := 'removed';
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

create or replace function public.moderation_target_reports(p_target_type public.report_target, p_target_id uuid)
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
      'avatar_url', v_profile.avatar_url,
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
      'decided_at', v_last.created_at,
      'restorable', private.moderation_restorable(p_target_type, p_target_id)
    ),
    'reports', v_reports,
    'owner', v_owner
  );
end
$$;

create or replace function public.moderation_decide(
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

  if p_action = 'approve' and not private.moderation_restorable(p_target_type, p_target_id) then
    return jsonb_build_object('status', 'invalid', 'reason', 'not_restorable');
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
-- Yetkiler
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.respond_connection(uuid, boolean) from public, anon, authenticated;
revoke all on function public.update_social_profile(boolean, text, public.social_interest[], float8, float8)
  from public, anon, authenticated;
grant execute on function public.respond_connection(uuid, boolean) to authenticated;
grant execute on function public.update_social_profile(boolean, text, public.social_interest[], float8, float8)
  to authenticated;
