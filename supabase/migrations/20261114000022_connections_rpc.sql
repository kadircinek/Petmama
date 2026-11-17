-- Mama Haritası — 0022: Hayvanseverler ve bağlantı RPC'leri (spec §5.2, §6)
--
-- Mahalle/buluşma RPC'leriyle aynı kurallar: `security definer`, ilk iş `private.require_uid()`, anon'a kapalı,
-- iş kuralı sonuçları jsonb `status` (+ `reason`). Bildirimler bu dosyada YOK (0024, AFTER trigger'larla).
--
-- * `connections` iki kişi arasında tek satırdır (sırasız çift). Yaşam döngüsü:
--     pending → accepted | declined;  accepted → removed;  pending → (geri çekilince satır silinir).
-- * `declined` satır, `responded_at + 30 gün` sonra yok sayılır; `removed` satır hemen yok sayılır. Yeni istek
--   aynı satırı sıfırlar (gönderen/alıcı, not, `created_at = now()`, statü `pending`) — çift tekilliği korunur.
-- * Günlük istek limiti kalıcı `connection_request_sends` kayıtlarıyla sayılır: geri çekme ve satır sıfırlama
--   sayımı etkilemez (gönder-geri çek döngüsüyle limit aşılamaz). Otomatik kabul gönderim sayılmaz, sınıra takılmaz.
-- * Kabul (elle ya da karşı istekle otomatik) bire bir sohbet açar; kaldırılmış bağlantı yeniden kabul edilirse
--   mevcut sohbet yeniden açılır (`connection_id` tekil).
-- * Okuma RPC'leri sosyal onay yoksa boş döner; yazma RPC'leri `consent_required` ister.

-- Gönderilen isteklerin kalıcı kaydı (günlük limit sayımı); yalnızca RPC'ler yazar/okur
create table public.connection_request_sends (
  user_id uuid not null references public.profiles (id) on delete cascade,
  sent_at timestamptz not null default now()
);
create index connection_request_sends_user_idx on public.connection_request_sends (user_id, sent_at);
alter table public.connection_request_sends enable row level security;
revoke all on public.connection_request_sends from anon, authenticated;

-- Yardımcı: bağlantının bire bir sohbetini aç (varsa yeniden aç) ve iki üyeyi ekle
create function private.open_direct_conversation(p_connection_id uuid, p_a uuid, p_b uuid)
returns uuid
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_conv uuid;
begin
  select c.id into v_conv from public.conversations c where c.connection_id = p_connection_id for update;
  if v_conv is null then
    insert into public.conversations (kind, connection_id) values ('direct', p_connection_id)
    returning id into v_conv;
  else
    update public.conversations set closed_at = null where id = v_conv;
  end if;
  insert into public.conversation_members (conversation_id, user_id)
  values (v_conv, p_a), (v_conv, p_b)
  on conflict do nothing;
  return v_conv;
end
$$;

-- ---------------------------------------------------------------------------
-- Okuma
-- ---------------------------------------------------------------------------
-- Yakındaki (≤10 km, izleyicinin kendi kaba hücresinden) görünür hayvanseverler. İzleyici görünür ve konumlu olmalı.
create function public.animal_lovers_near(p_interest public.social_interest default null)
returns table (
  user_id               uuid,
  display_name          text,
  avatar_url            text,
  about                 text,
  interests             public.social_interest[],
  is_verified_feeder    boolean,
  fed_30d               int,
  distance_band         public.distance_band,
  shared_interest_count int,
  connection_state      text,     -- none | outgoing_pending | incoming_pending | connected
  request_id            uuid,
  conversation_id       uuid
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid   uuid := private.require_uid();
  v_cell  extensions.geography;
  v_my    public.social_interest[];
begin
  select sp.cell, sp.interests into v_cell, v_my
  from public.social_profiles sp
  where sp.user_id = v_uid and sp.is_visible and sp.cell is not null
    and private.social_consented(v_uid);
  if v_cell is null then
    return;
  end if;

  return query
  select
    t.user_id, t.display_name, t.avatar_url, t.about, t.interests, t.is_verified_feeder, t.fed_30d,
    t.band, t.shared, t.state,
    case when t.state <> 'none' then t.conn_id end,
    case when t.state = 'connected' then
      (select c.id from public.conversations c where c.connection_id = t.conn_id) end
  from (
    select
      sp.user_id,
      pr.display_name,
      pr.avatar_url,
      sp.about,
      sp.interests,
      pr.is_verified_feeder,
      (select count(*)::int from public.checkins ck
        where ck.user_id = sp.user_id and ck.kind = 'fed' and ck.created_at >= now() - interval '30 days') as fed_30d,
      case when d.m < 1000 then 'under_1km'::public.distance_band
           when d.m < 3000 then '1_3km'::public.distance_band
           else '3_10km'::public.distance_band end as band,
      (select count(*)::int from unnest(sp.interests) i where i = any (v_my)) as shared,
      cn.id as conn_id,
      case
        when cn.id is null then 'none'
        when cn.status = 'accepted' then 'connected'
        when cn.status = 'pending' and cn.requester_id = v_uid then 'outgoing_pending'
        when cn.status = 'pending' then 'incoming_pending'
        when cn.status = 'declined' and cn.requester_id = v_uid
             and cn.responded_at > now() - interval '30 days' then 'outgoing_pending'
        else 'none'
      end as state,
      d.m
    from public.social_profiles sp
    join public.profiles pr on pr.id = sp.user_id
    cross join lateral (select extensions.st_distance(sp.cell, v_cell) as m) d
    left join lateral (
      select c.* from public.connections c
      where least(c.requester_id, c.addressee_id) = least(v_uid, sp.user_id)
        and greatest(c.requester_id, c.addressee_id) = greatest(v_uid, sp.user_id)) cn on true
    where sp.user_id <> v_uid
      and sp.is_visible
      and sp.cell is not null
      and private.social_consented(sp.user_id)
      and d.m <= 10000
      and (p_interest is null or p_interest = any (sp.interests))
      and not private.blocked_between(v_uid, sp.user_id)
  ) t
  order by t.band, t.shared desc, t.display_name, t.user_id
  limit 100;
end
$$;

-- Bana gelen bekleyen istekler (gönderen görünür olmak zorunda değil; engelliler süzülür)
create function public.incoming_connection_requests()
returns table (
  request_id         uuid,
  user_id            uuid,
  display_name       text,
  avatar_url         text,
  about              text,
  interests          public.social_interest[],
  is_verified_feeder boolean,
  note               text,
  created_at         timestamptz
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
begin
  if not private.social_consented(v_uid) then
    return;
  end if;

  return query
  select c.id, c.requester_id, pr.display_name, pr.avatar_url,
         coalesce(sp.about, ''), coalesce(sp.interests, '{}'), pr.is_verified_feeder, c.note, c.created_at
  from public.connections c
  join public.profiles pr on pr.id = c.requester_id
  left join public.social_profiles sp on sp.user_id = c.requester_id
  where c.addressee_id = v_uid
    and c.status = 'pending'
    and not private.blocked_between(v_uid, c.requester_id)
  order by c.created_at desc, c.id
  limit 100;
end
$$;

-- ---------------------------------------------------------------------------
-- Yazma
-- ---------------------------------------------------------------------------
create function public.send_connection_request(p_user_id uuid, p_note text default null)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_daily_limit constant int := 10;
  c_max_note    constant int := 200;
  v_uid    uuid := private.require_uid();
  v_note   text := private.trim_text(p_note);
  v_c      public.connections;
  v_stale  boolean := false;
  v_id     uuid;
  v_conv   uuid;
begin
  if p_user_id is null then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  perform private.ensure_profile(v_uid);
  if not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;
  if not exists (select 1 from public.social_profiles sp where sp.user_id = v_uid and sp.is_visible) then
    return jsonb_build_object('status', 'not_visible');
  end if;

  if p_user_id = v_uid
     or not exists (select 1 from public.profiles pr where pr.id = p_user_id)
     or private.blocked_between(v_uid, p_user_id) then
    return jsonb_build_object('status', 'not_found');
  end if;
  if not exists (select 1 from public.social_profiles sp
                 where sp.user_id = p_user_id and sp.is_visible and private.social_consented(sp.user_id)) then
    return jsonb_build_object('status', 'not_visible');
  end if;

  -- aynı çiftin eşzamanlı istekleri ve gönderenin günlük sayımı sıraya girer
  perform pg_advisory_xact_lock(hashtext('connection_pair:' || least(v_uid, p_user_id)::text
                                         || ':' || greatest(v_uid, p_user_id)::text));
  perform pg_advisory_xact_lock(hashtext('connection_send:' || v_uid::text));

  select c.* into v_c
  from public.connections c
  where least(c.requester_id, c.addressee_id) = least(v_uid, p_user_id)
    and greatest(c.requester_id, c.addressee_id) = greatest(v_uid, p_user_id)
  for update;

  if found then
    if v_c.status = 'accepted' then
      return jsonb_build_object('status', 'already_connected');
    end if;
    if v_c.status = 'declined' and v_c.requester_id = v_uid
       and v_c.responded_at > now() - interval '30 days' then
      return jsonb_build_object('status', 'cooldown');
    end if;
    if v_c.status = 'pending' and v_c.requester_id = v_uid then
      return jsonb_build_object('status', 'already_pending');
    end if;
    -- kalan: karşı tarafın bekleyen isteği (otomatik kabul) ya da yok sayılan satır (removed / eski declined /
    -- benim reddettiğim)
    v_stale := v_c.status in ('removed', 'declined');
  end if;

  if char_length(v_note) > c_max_note then
    return jsonb_build_object('status', 'invalid', 'reason', 'note_too_long');
  end if;
  if private.contains_profanity(v_note) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  -- karşı taraf zaten istek atmışsa: otomatik kabul (gönderim sayılmaz; günlük sınırdan önce)
  if v_c.id is not null and v_c.status = 'pending' and v_c.requester_id = p_user_id then
    update public.connections set status = 'accepted', responded_at = now() where id = v_c.id;
    v_conv := private.open_direct_conversation(v_c.id, v_uid, p_user_id);
    return jsonb_build_object('status', 'auto_accepted', 'conversation_id', v_conv);
  end if;

  if (select count(*) from public.connection_request_sends s
       where s.user_id = v_uid and s.sent_at >= private.istanbul_day_start()) >= c_daily_limit then
    return jsonb_build_object('status', 'limit_reached', 'limit', c_daily_limit);
  end if;

  if v_stale then
    update public.connections
       set requester_id = v_uid, addressee_id = p_user_id, note = v_note,
           status = 'pending', created_at = now(), responded_at = null
     where id = v_c.id
    returning id into v_id;
  else
    insert into public.connections (requester_id, addressee_id, note)
    values (v_uid, p_user_id, v_note)
    returning id into v_id;
  end if;

  insert into public.connection_request_sends (user_id) values (v_uid);
  return jsonb_build_object('status', 'sent', 'request_id', v_id);
end
$$;

-- Yalnızca alıcı yanıtlar; görünürlüğü kapalı olsa da yanıtlayabilir. Engel varsa `not_found`.
create function public.respond_connection(p_request_id uuid, p_accept boolean)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := private.require_uid();
  v_c    public.connections;
  v_conv uuid;
begin
  if p_request_id is null or p_accept is null then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  select c.* into v_c
  from public.connections c
  where c.id = p_request_id and c.addressee_id = v_uid and c.status = 'pending'
  for update;
  if not found or private.blocked_between(v_uid, v_c.requester_id) then
    return jsonb_build_object('status', 'not_found');
  end if;

  if p_accept then
    update public.connections set status = 'accepted', responded_at = now() where id = v_c.id;
    v_conv := private.open_direct_conversation(v_c.id, v_c.requester_id, v_uid);
    return jsonb_build_object('status', 'accepted', 'conversation_id', v_conv);
  end if;

  update public.connections set status = 'declined', responded_at = now() where id = v_c.id;
  return jsonb_build_object('status', 'declined');
end
$$;

-- Bekleyen isteği geri çek (yalnızca gönderen): satır silinir
create function public.withdraw_connection_request(p_request_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_n   int;
begin
  if p_request_id is null then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;
  delete from public.connections c
   where c.id = p_request_id and c.requester_id = v_uid and c.status = 'pending';
  get diagnostics v_n = row_count;
  return jsonb_build_object('status', case when v_n > 0 then 'ok' else 'not_found' end);
end
$$;

-- Bağlantıyı kaldır (iki taraftan biri): statü removed, sohbet kapanır
create function public.remove_connection(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
  v_id  uuid;
begin
  if p_user_id is null then
    raise exception 'invalid_parameter' using errcode = '22023';
  end if;

  select c.id into v_id
  from public.connections c
  where least(c.requester_id, c.addressee_id) = least(v_uid, p_user_id)
    and greatest(c.requester_id, c.addressee_id) = greatest(v_uid, p_user_id)
    and c.status = 'accepted'
  for update;
  if v_id is null then
    return jsonb_build_object('status', 'not_found');
  end if;

  update public.connections set status = 'removed' where id = v_id;
  update public.conversations set closed_at = coalesce(closed_at, now()) where connection_id = v_id;
  return jsonb_build_object('status', 'ok');
end
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.animal_lovers_near(public.social_interest)        from public, anon, authenticated;
revoke all on function public.incoming_connection_requests()                    from public, anon, authenticated;
revoke all on function public.send_connection_request(uuid, text)               from public, anon, authenticated;
revoke all on function public.respond_connection(uuid, boolean)                 from public, anon, authenticated;
revoke all on function public.withdraw_connection_request(uuid)                 from public, anon, authenticated;
revoke all on function public.remove_connection(uuid)                           from public, anon, authenticated;

grant execute on function public.animal_lovers_near(public.social_interest)     to authenticated;
grant execute on function public.incoming_connection_requests()                 to authenticated;
grant execute on function public.send_connection_request(uuid, text)            to authenticated;
grant execute on function public.respond_connection(uuid, boolean)              to authenticated;
grant execute on function public.withdraw_connection_request(uuid)              to authenticated;
grant execute on function public.remove_connection(uuid)                        to authenticated;
