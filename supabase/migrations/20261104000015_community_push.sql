-- Mama Haritası — 0015: push kuyruğu `post_id` döndürür (Mahalle bildirimleri)
--
-- push-dispatch APNs payload'una `post_id` ekler; uygulama bildirime dokununca paylaşımı açar.
-- `community_comment` ve `cover_volunteered` sessiz saat kuralına uyar; günlük 3 push limiti yalnızca
-- `need_food_nearby` içindir (kural _shared/push_logic.ts'te, burada değişen bir şey yok).
--
-- Dönüş tipi değiştiği için `create or replace` yetmez: fonksiyon düşürülüp yeniden oluşturulur
-- (aynı transaction içinde; yetkiler de yeniden verilir). Gövde 0009 ile aynı, yalnızca post_id eklendi.

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
    returning n.id, n.user_id, n.kind, n.title, n.body, n.spot_id, n.need_id, n.post_id, n.created_at
  )
  select u.id, u.user_id, u.kind, u.title, u.body, u.spot_id, u.need_id, u.post_id, u.created_at,
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

revoke all on function public.push_claim_batch(int) from public, anon, authenticated;
grant execute on function public.push_claim_batch(int) to service_role;
