-- Mama Haritası — 0009: cron işleri, push kuyruğu
--
-- Sırlar koda gömülmez. push-dispatch çağrısı için gereken iki değer şuradan okunur (öncelik sırasıyla):
--   1) Supabase Vault:        select vault.create_secret('<değer>', 'push_dispatch_url');
--                             select vault.create_secret('<değer>', 'push_dispatch_secret');
--   2) private.app_settings:  insert into private.app_settings(key, value) values ('push_dispatch_url', '...');
-- İkisi de yoksa cron işi sessizce hiçbir şey yapmaz.

create function private.secret(p_name text)
returns text
language plpgsql stable
set search_path = public, extensions
as $$
declare
  v text;
begin
  if to_regclass('vault.decrypted_secrets') is not null then
    begin
      execute 'select decrypted_secret from vault.decrypted_secrets where name = $1 order by created_at desc limit 1'
        into v using p_name;
    exception when others then
      v := null;
    end;
  end if;
  return coalesce(nullif(v, ''), private.setting(p_name));
end
$$;

-- ---------------------------------------------------------------------------
-- refresh_spot_statuses — cron her 15 dk
--   1) spots.status kalıcılaştırma (okuma RPC'leri yine okuma anında hesaplar)
--   2) koruyuculara guardian_spot_unfed: 24 sa+ beslenmemiş (hiç beslenmemişse oluşturulalı 24 sa+),
--      koruyucu+nokta başına 24 saatte en fazla 1 kez; guardian_alerts tercihi kapalıysa yok
--   3) FR-P4: 30 günde 20+ konumu doğrulanmış check-in → is_verified_feeder
-- ---------------------------------------------------------------------------
create function public.refresh_spot_statuses()
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_updated  int;
  v_notified int;
  v_promoted int;
begin
  with calc as (
    select s.id, public.compute_spot_status(s.last_fed_at, private.spot_has_open_request(s.id)) as st
    from public.spots s
    where s.is_active and s.moderation_state <> 'rejected'
  )
  update public.spots s
     set status = calc.st
    from calc
   where s.id = calc.id and s.status is distinct from calc.st;
  get diagnostics v_updated = row_count;

  insert into public.notifications (user_id, kind, title, body, spot_id)
  select g.user_id, 'guardian_spot_unfed', '24 saattir beslenmedi',
         format('Koruyucusu olduğun "%s" noktası 24 saattir beslenmedi.', s.title), s.id
  from public.guardians g
  join public.spots s on s.id = g.spot_id
  left join public.notification_prefs np on np.user_id = g.user_id
  where s.is_active
    and s.moderation_state = 'approved'
    and coalesce(s.last_fed_at, s.created_at) <= now() - interval '24 hours'
    and coalesce(np.guardian_alerts, true)
    and not exists (select 1 from public.notifications n
                    where n.user_id = g.user_id and n.kind = 'guardian_spot_unfed'
                      and n.spot_id = s.id and n.created_at > now() - interval '24 hours');
  get diagnostics v_notified = row_count;

  with q as (
    select c.user_id
    from public.checkins c
    where c.user_id is not null
      and c.user_distance_m is not null
      and c.created_at > now() - interval '30 days'
    group by c.user_id
    having count(*) >= 20
  )
  update public.profiles p
     set is_verified_feeder = true
    from q
   where p.id = q.user_id and not p.is_verified_feeder;
  get diagnostics v_promoted = row_count;

  return jsonb_build_object('status', 'ok', 'status_updated', v_updated,
                            'guardian_notified', v_notified, 'feeders_promoted', v_promoted);
end
$$;

-- ---------------------------------------------------------------------------
-- push-dispatch kuyruğu (yalnızca service_role; edge function çağırır)
--
-- pushed_at semantiği: satır push-dispatch tarafından İŞLENDİĞİNDE dolar — gönderilmese bile.
-- push_status sonucu söyler: sent | quiet_hours | daily_cap | no_token | failed | expired.
-- Sessiz saatte ve günlük limit aşımında push ERTELENMEZ; bildirim yalnızca uygulama içinde kalır
-- (read_at null). 30 dk'dan eski, hiç işlenmemiş satırlar `expired` olur (geç push anlamsız).
-- ---------------------------------------------------------------------------
create function public.push_claim_batch(p_limit int default 200)
returns table (
  id                     uuid,
  user_id                uuid,
  kind                   public.notification_kind,
  title                  text,
  body                   text,
  spot_id                uuid,
  need_id                uuid,
  created_at             timestamptz,
  quiet_start            smallint,
  quiet_end              smallint,
  need_food_pushed_today int,
  tokens                 text[]
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
    returning n.id, n.user_id, n.kind, n.title, n.body, n.spot_id, n.need_id, n.created_at
  )
  select u.id, u.user_id, u.kind, u.title, u.body, u.spot_id, u.need_id, u.created_at,
         coalesce(np.quiet_start, 22::smallint),
         coalesce(np.quiet_end, 7::smallint),
         (select count(*)::int from public.notifications n2
           where n2.user_id = u.user_id and n2.kind = 'need_food_nearby'
             and n2.push_status = 'sent' and n2.pushed_at >= v_day_start),
         coalesce((select array_agg(t.token order by t.updated_at desc)
                     from public.device_tokens t where t.user_id = u.user_id), '{}')
  from u
  left join public.notification_prefs np on np.user_id = u.user_id
  order by u.created_at, u.id;
end
$$;

create function public.push_complete(p_ids uuid[], p_status text)
returns int
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_n int;
begin
  if p_status not in ('sent', 'quiet_hours', 'daily_cap', 'no_token', 'failed') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  update public.notifications
     set push_status = p_status, pushed_at = coalesce(pushed_at, now())
   where id = any (p_ids);
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

-- APNs 410 / BadDeviceToken / Unregistered → token silinir
create function public.push_drop_tokens(p_tokens text[])
returns int
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_n int;
begin
  delete from public.device_tokens where token = any (p_tokens);
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

-- pg_cron → pg_net → edge function. URL/sır yoksa, pg_net yoksa veya kuyruk boşsa hiçbir şey yapmaz.
create function private.invoke_push_dispatch()
returns bigint
language plpgsql volatile
set search_path = public, extensions
as $$
declare
  v_url    text := private.secret('push_dispatch_url');
  v_secret text := private.secret('push_dispatch_secret');
  v_req    bigint;
begin
  if v_url is null or v_secret is null or to_regnamespace('net') is null then
    return null;
  end if;
  if not exists (select 1 from public.notifications where pushed_at is null) then
    return null;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 30000)'
    into v_req
    using v_url,
          jsonb_build_object('source', 'pg_cron'),
          jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', v_secret);
  return v_req;
end
$$;

revoke all on function private.secret(text)              from public;
revoke all on function private.invoke_push_dispatch()    from public;
revoke all on function public.refresh_spot_statuses()    from public, anon, authenticated;
revoke all on function public.push_claim_batch(int)      from public, anon, authenticated;
revoke all on function public.push_complete(uuid[], text) from public, anon, authenticated;
revoke all on function public.push_drop_tokens(text[])   from public, anon, authenticated;
grant execute on function public.refresh_spot_statuses()     to service_role;
grant execute on function public.push_claim_batch(int)       to service_role;
grant execute on function public.push_complete(uuid[], text) to service_role;
grant execute on function public.push_drop_tokens(text[])    to service_role;

-- ---------------------------------------------------------------------------
-- Zamanlama (pg_cron yoksa atlanır). Aynı adla tekrar uygulanabilir.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname in ('refresh-spot-status', 'push-dispatch');
    perform cron.schedule('refresh-spot-status', '*/15 * * * *', 'select public.refresh_spot_statuses();');
    perform cron.schedule('push-dispatch', '* * * * *', 'select private.invoke_push_dispatch();');
  else
    raise notice 'pg_cron yok: refresh-spot-status ve push-dispatch zamanlanmadı';
  end if;
end
$$;
