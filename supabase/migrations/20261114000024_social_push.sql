-- Mama Haritası — 0024: Tanışma bildirimleri, push yükü ve Realtime yayını (spec §5.6)
--
-- * `notifications.meetup_id / conversation_id` 0019'da eklendi; burada yalnızca üretim + push_claim_batch.
-- * Üretim AFTER trigger'larla yapılır: RPC dönüş değerleri ve Task 2–4 fonksiyonları değişmez. Hesap silme
--   yolundaki `meetup_cancelled` (0023, buluşma silinir) ayrı kalır; burada yalnızca `cancel_meetup` iptali var.
-- * Hepsi `private.notify_social` üstünden geçer: iki yönlü engel, `social_updates` tercihi (satır yoksa açık),
--   gönderen = alıcı değil. Sosyal türler need_food günlük sınırına girmez (push_logic.ts), sessiz saate uyar.

alter table public.notification_prefs
  add column social_updates boolean not null default true;
-- notification_prefs yetkileri sütun bazlı (0006): yeni sütun ayrıca verilmeli
grant insert (social_updates), update (social_updates) on public.notification_prefs to authenticated;

-- ---------------------------------------------------------------------------
-- Ortak yardımcı. p_dedupe_unread: aynı kullanıcı + aynı sohbet için okunmamış aynı tür bildirim varsa yenisi yok
-- (hareketli bir sohbet bildirim yağmuruna dönmesin; kullanıcı sohbeti ya da bildirimi okuyunca yeniden üretilir).
-- ---------------------------------------------------------------------------
create function private.notify_social(
  p_user          uuid,
  p_actor         uuid,
  p_kind          public.notification_kind,
  p_title         text,
  p_body          text,
  p_meetup_id     uuid    default null,
  p_conversation_id uuid  default null,
  p_dedupe_unread boolean default false
)
returns boolean
language plpgsql volatile security definer
set search_path = public, extensions
as $$
begin
  if p_user is null or p_user = p_actor then
    return false;
  end if;
  if p_actor is not null and private.blocked_between(p_user, p_actor) then
    return false;
  end if;
  if not coalesce((select np.social_updates from public.notification_prefs np where np.user_id = p_user), true) then
    return false;
  end if;

  if p_dedupe_unread and p_conversation_id is not null then
    -- eşzamanlı iki mesaj aynı anda "okunmamış yok" görüp çift bildirim üretmesin
    perform pg_advisory_xact_lock(hashtextextended('social_notify:' || p_user::text || ':' || p_conversation_id::text, 0));
    if exists (select 1 from public.notifications n
               where n.user_id = p_user and n.kind = p_kind
                 and n.conversation_id = p_conversation_id and n.read_at is null) then
      return false;
    end if;
  end if;

  insert into public.notifications (user_id, kind, title, body, meetup_id, conversation_id, actor_id)
  values (p_user, p_kind, p_title, p_body, p_meetup_id, p_conversation_id, p_actor);
  return true;
end
$$;

create function private.display_name_of(p_uid uuid)
returns text
language sql stable security definer
set search_path = public, extensions
as $$
  select coalesce(nullif(btrim((select p.display_name from public.profiles p where p.id = p_uid)), ''), 'Bir mama dostu')
$$;

-- ---------------------------------------------------------------------------
-- meetup_joined → düzenleyene (düzenleyenin kendi satırı, iptal/bitmiş buluşma hariç)
-- ---------------------------------------------------------------------------
create function private.notify_meetup_joined()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_m public.meetups;
begin
  if new.status <> 'joined' then
    return null;
  end if;
  select * into v_m from public.meetups m where m.id = new.meetup_id;
  if not found or v_m.status <> 'active' or v_m.ends_at <= now() or v_m.organizer_id = new.user_id then
    return null;
  end if;
  perform private.notify_social(
    v_m.organizer_id, new.user_id, 'meetup_joined', 'Buluşmana yeni katılımcı',
    format('%s "%s" buluşmasına katıldı.', private.display_name_of(new.user_id), v_m.title),
    v_m.id);
  return null;
end
$$;

create trigger meetup_participants_notify_joined
  after insert on public.meetup_participants
  for each row execute function private.notify_meetup_joined();

-- ---------------------------------------------------------------------------
-- meetup_cancelled → katılan (joined) herkese, düzenleyen hariç; cancel_meetup active → cancelled yapar
-- ---------------------------------------------------------------------------
create function private.notify_meetup_cancelled()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r record;
begin
  for r in
    select mp.user_id from public.meetup_participants mp
    where mp.meetup_id = new.id and mp.status = 'joined' and mp.user_id <> new.organizer_id
  loop
    perform private.notify_social(
      r.user_id, new.organizer_id, 'meetup_cancelled', 'Buluşma iptal edildi',
      format('"%s" buluşması iptal edildi.', new.title), new.id);
  end loop;
  return null;
end
$$;

create trigger meetups_notify_cancelled
  after update of status on public.meetups
  for each row
  when (old.status = 'active' and new.status = 'cancelled')
  execute function private.notify_meetup_cancelled();

-- ---------------------------------------------------------------------------
-- meetup_reminder — cron her 15 dk: 2 saat içinde başlayacak aktif buluşmaların düzenleyeni + katılanları, bir kez.
-- Dönüş: üretilen bildirim sayısı.
-- ---------------------------------------------------------------------------
create function private.send_meetup_reminders()
returns int
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_n int;
begin
  with targets as (
    select m.id as meetup_id, m.title, m.starts_at, m.organizer_id, m.organizer_id as user_id
    from public.meetups m
    where m.status = 'active' and m.starts_at > now() and m.starts_at <= now() + interval '2 hours'
    union all
    select m.id, m.title, m.starts_at, m.organizer_id, mp.user_id
    from public.meetups m
    join public.meetup_participants mp on mp.meetup_id = m.id and mp.status = 'joined'
    where m.status = 'active' and m.starts_at > now() and m.starts_at <= now() + interval '2 hours'
      and mp.user_id <> m.organizer_id
  )
  insert into public.notifications (user_id, kind, title, body, meetup_id)
  select t.user_id, 'meetup_reminder', 'Buluşma yaklaşıyor',
         format('"%s" buluşması saat %s''de başlıyor.', t.title,
                to_char(t.starts_at at time zone 'Europe/Istanbul', 'HH24:MI')),
         t.meetup_id
  from targets t
  where not private.blocked_between(t.user_id, t.organizer_id)
    and coalesce((select np.social_updates from public.notification_prefs np where np.user_id = t.user_id), true)
    and not exists (select 1 from public.notifications n
                    where n.kind = 'meetup_reminder' and n.meetup_id = t.meetup_id and n.user_id = t.user_id);
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

-- ---------------------------------------------------------------------------
-- connection_request → alıcıya (yeni istek ya da kaldırılmış/reddedilmiş bağlantının yeniden istenmesi);
-- connection_accepted → isteği ilk atana (kabul ve otomatik kabul)
-- ---------------------------------------------------------------------------
create function private.notify_connection()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status <> 'pending') then
    perform private.notify_social(
      new.addressee_id, new.requester_id, 'connection_request', 'Yeni bağlantı isteği',
      format('%s seninle hayvanseverler olarak bağlantı kurmak istiyor.', private.display_name_of(new.requester_id)));
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
    -- otomatik kabulde kabul eden, karşı tarafın bekleyen isteğini yanıtlayan kişidir; satırdaki requester ilk atandır
    perform private.notify_social(
      old.requester_id, old.addressee_id, 'connection_accepted', 'Bağlantı isteğin kabul edildi',
      format('%s isteğini kabul etti. Artık yazışabilirsiniz.', private.display_name_of(old.addressee_id)));
  end if;
  return null;
end
$$;

create trigger connections_notify
  after insert or update of status on public.connections
  for each row execute function private.notify_connection();

-- ---------------------------------------------------------------------------
-- chat_message → sohbetin diğer üyelerine (onaylı mesaj; sohbet alıcıya görünür ve yazılabilir olmalı).
-- Metin bildirime konmaz (kilit ekranında sızmasın): yalnızca kim yazdı.
-- ---------------------------------------------------------------------------
create function private.notify_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_c     public.conversations;
  v_title text;
  v_name  text;
  r       record;
begin
  if new.moderation_state <> 'approved' then
    return null;
  end if;
  select * into v_c from public.conversations c where c.id = new.conversation_id;
  if not found then
    return null;
  end if;

  v_name := private.display_name_of(new.author_id);
  v_title := case v_c.kind
               when 'meetup' then coalesce((select m.title from public.meetups m where m.id = v_c.meetup_id), 'Buluşma sohbeti')
               else v_name
             end;

  for r in
    select cm.user_id from public.conversation_members cm
    where cm.conversation_id = v_c.id and cm.user_id <> new.author_id
  loop
    if private.conversation_visible(v_c, r.user_id) and not private.conversation_read_only(v_c, r.user_id) then
      perform private.notify_social(
        r.user_id, new.author_id, 'chat_message', v_title,
        case v_c.kind when 'meetup' then format('%s yeni bir mesaj yazdı.', v_name) else 'Yeni bir mesaj gönderdi.' end,
        null, v_c.id, true);
    end if;
  end loop;
  return null;
end
$$;

create trigger chat_messages_notify
  after insert on public.chat_messages
  for each row execute function private.notify_chat_message();

-- Sohbeti okumak o sohbetin okunmamış chat_message bildirimlerini de okundu yapar (yoksa bir kez okunmamış
-- kalan bildirim o sohbetten gelecek tüm push'ları sonsuza dek bastırırdı).
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := private.require_uid();
begin
  update public.conversation_members
     set last_read_at = greatest(last_read_at, now())
   where conversation_id = p_conversation_id and user_id = v_uid;
  update public.notifications n set read_at = now()
   where n.user_id = v_uid and n.kind = 'chat_message'
     and n.conversation_id = p_conversation_id and n.read_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- push_claim_batch: dönüşe meetup_id, conversation_id eklenir (kalan sütunlar ve sıra 0016 ile aynı)
-- ---------------------------------------------------------------------------
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
  sandbox_tokens         text[],
  meetup_id              uuid,
  conversation_id        uuid
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
    returning n.id, n.user_id, n.kind, n.title, n.body, n.spot_id, n.need_id, n.post_id, n.created_at,
              n.meetup_id, n.conversation_id
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
                    where t.user_id = u.user_id and t.apns_env = 'sandbox'), '{}'),
         u.meetup_id, u.conversation_id
  from u
  left join public.notification_prefs np on np.user_id = u.user_id
  order by u.created_at, u.id;
end
$$;

revoke all on function public.push_claim_batch(int) from public, anon, authenticated;
grant execute on function public.push_claim_batch(int) to service_role;

revoke all on all functions in schema private from public;
revoke all on function public.mark_conversation_read(uuid) from public, anon, authenticated;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Zamanlama: hatırlatmalar her 15 dk (pg_cron yoksa atlanır; aynı adla tekrar uygulanabilir)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'meetup-reminders';
    perform cron.schedule('meetup-reminders', '*/15 * * * *', 'select private.send_meetup_reminders();');
  else
    raise notice 'pg_cron yok: meetup-reminders zamanlanmadı';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Realtime yayını — yalnızca `realtime.send` varsa (yerel test imajında yok → atlanır).
-- Mesaj eklenince 'conversation:<id>' özel kanalına yalnızca conversation_id yayınlanır (metin yok; istemci
-- RPC ile çeker). Kanalı yalnızca sohbet üyeleri dinleyebilir.
-- ---------------------------------------------------------------------------
create function private.broadcast_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.moderation_state = 'approved' then
    begin
      execute 'select realtime.send($1, $2, $3, $4)'
        using jsonb_build_object('conversation_id', new.conversation_id), 'message',
              'conversation:' || new.conversation_id::text, true;
    exception when others then
      -- yayın hatası mesajın kaydını asla geri almasın
      raise warning 'chat realtime broadcast failed: %', sqlerrm;
    end;
  end if;
  return null;
end
$$;

-- Kanal dinleme yetkisi: 'conversation:<uuid>' konusu, çağıranın görebildiği bir sohbete aitse true.
-- security definer: conversation_members'a doğrudan erişim yok (RLS açık, yetki yok); politika bu yardımcıyı çağırır.
-- Hatalı konu (önek/uuid biçimi, null) istisna değil false döner. realtime şemasına bağlı değil → koşulsuz kurulur.
create function public.can_listen_conversation(p_topic text)
returns boolean
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_c   public.conversations;
begin
  if v_uid is null or p_topic is null
     or p_topic !~ '^conversation:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;
  v_id := substr(p_topic, 14)::uuid;
  select * into v_c from public.conversations c where c.id = v_id;
  if not found then
    return false;
  end if;
  return private.conversation_visible(v_c, v_uid);
end
$$;

revoke all on function public.can_listen_conversation(text) from public, anon, authenticated;
grant execute on function public.can_listen_conversation(text) to authenticated;

do $$
begin
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
    execute 'create trigger chat_messages_realtime after insert on public.chat_messages
             for each row execute function private.broadcast_chat_message()';
    if to_regclass('realtime.messages') is not null and to_regprocedure('realtime.topic()') is not null then
      execute $p$
        create policy chat_members_can_listen on realtime.messages
          for select to authenticated
          using (
            realtime.messages.extension = 'broadcast'
            and public.can_listen_conversation((select realtime.topic()))
          )
      $p$;
    end if;
  else
    raise notice 'realtime.send yok: sohbet yayını kurulmadı';
  end if;
end
$$;
