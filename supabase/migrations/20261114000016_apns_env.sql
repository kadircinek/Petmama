-- APNs ortamı token ile birlikte saklanır.
--
-- Neden: Debug derlemeleri sandbox, TestFlight ve App Store derlemeleri production token'ı üretir. Tek bir
-- APNS_ENV ayarıyla diğer ortamın token'ları BadDeviceToken alıp push_drop_tokens ile silinirdi; Debug ve
-- TestFlight aynı backend'i paylaşamazdı. İstemci ortamı `aps-environment` entitlement'ından okuyup gönderir.

alter table public.device_tokens
  add column apns_env text not null default 'production'
  check (apns_env in ('sandbox', 'production'));

-- register_device_token(text) → register_device_token(text, text default 'production')
drop function public.register_device_token(text);

create function public.register_device_token(p_token text, p_env text default 'production')
returns void
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := private.require_uid();
  v_token text := btrim(coalesce(p_token, ''));
  v_env   text := coalesce(nullif(btrim(p_env), ''), 'production');
begin
  if char_length(v_token) not between 8 and 512 or v_token !~ '^[0-9A-Za-z_:.-]+$' then
    raise exception 'invalid_token' using errcode = '22023';
  end if;
  if v_env not in ('sandbox', 'production') then
    raise exception 'invalid_apns_env' using errcode = '22023';
  end if;
  perform private.ensure_profile(v_uid);
  insert into public.device_tokens (token, user_id, platform, apns_env, updated_at)
  values (v_token, v_uid, 'ios', v_env, now())
  on conflict (token) do update set user_id = excluded.user_id, apns_env = excluded.apns_env, updated_at = now();
end
$$;

revoke all on function public.register_device_token(text, text) from public, anon, authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;

-- push_claim_batch: `tokens` production, `sandbox_tokens` sandbox token'ları
drop function public.push_claim_batch(int);

create function public.push_claim_batch(p_limit int default 200)
returns table (
  id                     uuid,
  user_id                uuid,
  kind                   public.notification_kind,
  title                  text,
  body                   text,
  spot_id                uuid,
  need_id                uuid,
  post_id                uuid,
  created_at             timestamptz,
  quiet_start            smallint,
  quiet_end              smallint,
  need_food_pushed_today int,
  tokens                 text[],
  sandbox_tokens         text[]
)
language plpgsql volatile security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_day_start timestamptz := private.istanbul_day_start();
begin
  update public.notifications n
     set pushed_at = now(), push_status = 'expired'
   where n.pushed_at is null and n.created_at < now() - interval '30 minutes';

  return query
  with c as (
    select n.id
    from public.notifications n
    where n.pushed_at is null
    order by n.created_at
    limit greatest(1, least(coalesce(p_limit, 200), 1000))
    for update skip locked
  ),
  u as (
    update public.notifications n
       set pushed_at = now(), push_status = 'processing'
      from c
     where n.id = c.id
    returning n.id, n.user_id, n.kind, n.title, n.body, n.spot_id, n.need_id, n.post_id, n.created_at
  )
  select u.id, u.user_id, u.kind, u.title, u.body, u.spot_id, u.need_id, u.post_id, u.created_at,
         coalesce(np.quiet_start, 22::smallint),
         coalesce(np.quiet_end, 7::smallint),
         (select count(*)::int from public.notifications n2
           where n2.user_id = u.user_id and n2.kind = 'need_food_nearby'
             and n2.push_status = 'sent' and n2.pushed_at >= v_day_start),
         coalesce((select array_agg(t.token order by t.updated_at desc)
                     from public.device_tokens t
                    where t.user_id = u.user_id and t.apns_env = 'production'), '{}'),
         coalesce((select array_agg(t.token order by t.updated_at desc)
                     from public.device_tokens t
                    where t.user_id = u.user_id and t.apns_env = 'sandbox'), '{}')
  from u
  left join public.notification_prefs np on np.user_id = u.user_id
  order by u.created_at, u.id;
end
$$;

revoke all on function public.push_claim_batch(int) from public, anon, authenticated;
grant execute on function public.push_claim_batch(int) to service_role;
