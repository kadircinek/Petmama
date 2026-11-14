-- Mama Haritası — 0023: Sohbet RPC'leri, engelleme ve hesap silme kancaları, mesaj saklama süresi (spec §5.3, §5.5)
--
-- Mahalle/buluşma RPC'leriyle aynı kurallar: `security definer`, ilk iş `private.require_uid()`, anon'a kapalı,
-- iş kuralı sonuçları jsonb `status` (+ `reason`). Bildirim üretimi bu dosyada YOK (yalnızca hesap silmede iptal).
--
-- Kim neyi okur (tek yerde, aşağıdaki yardımcılarla):
--   * Sohbet yalnızca üyelerine (`conversation_members`) açıktır. Buluşmadan ayrılan/çıkarılan üyelikten silinir.
--   * Bire bir sohbet, bağlantı `accepted` değilse (kaldırıldı / engel) ya da iki taraf arasında engel varsa
--     gizlidir: listede yok, mesajları 0 satır. Karşı taraf hesabını sildiyse (`connection_id` null, tek üye)
--     sohbet kalır: başlık 'Silinmiş kullanıcı', salt okunur.
--   * Mesaj: `approved` herkese (üyelere), `pending` (3 farklı rapor) yalnızca yazarına, `rejected` kimseye.
--     İki yönlü engelli kişilerin mesajları görünmez, okunmamış sayısına ve son mesaj önizlemesine girmez.
--   * Okuma RPC'leri sosyal onay yoksa boş döner; `send_chat_message` `consent_required` döner.

-- ---------------------------------------------------------------------------
-- Yardımcılar
-- ---------------------------------------------------------------------------
-- Mesaj bu izleyiciye görünür mü?
create function private.chat_message_visible(p_state public.moderation_state, p_author uuid, p_uid uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select case p_state
           when 'approved' then true
           when 'pending'  then p_author = p_uid
           else false
         end
     and (p_author = p_uid or not private.blocked_between(p_uid, p_author))
$$;

-- Bire bir sohbette izleyicinin karşısındaki üye (yoksa — hesap silinmiş — null)
create function private.direct_other_member(p_conversation_id uuid, p_uid uuid)
returns uuid
language sql stable
set search_path = public, extensions
as $$
  select cm.user_id from public.conversation_members cm
  where cm.conversation_id = p_conversation_id and cm.user_id <> p_uid
  order by cm.user_id
  limit 1
$$;

-- Sohbet izleyiciye görünür mü? (üyelik + bire bir için bağlantı/engel durumu)
create function private.conversation_visible(p_c public.conversations, p_uid uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select exists (select 1 from public.conversation_members cm
                 where cm.conversation_id = p_c.id and cm.user_id = p_uid)
     and (p_c.kind = 'meetup'
          or ((p_c.connection_id is null
               or exists (select 1 from public.connections cn
                          where cn.id = p_c.connection_id and cn.status = 'accepted'))
              and not coalesce(private.blocked_between(p_uid, private.direct_other_member(p_c.id, p_uid)), false)))
$$;

-- Sohbet salt okunur mu? closed_at; buluşmada iptal veya bitişten 24 saat sonrası; bire bir'de 2'den az üye,
-- bağlantı kabul edilmiş değil ya da taraflar arasında engel.
create function private.conversation_read_only(p_c public.conversations, p_uid uuid)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select p_c.closed_at is not null
      or case p_c.kind
           when 'meetup' then
             coalesce((select m.status = 'cancelled' or m.ends_at + interval '24 hours' < now()
                         from public.meetups m where m.id = p_c.meetup_id), true)
           else
             (select count(*) from public.conversation_members cm where cm.conversation_id = p_c.id) < 2
             or coalesce((select cn.status <> 'accepted' from public.connections cn where cn.id = p_c.connection_id), false)
             or coalesce(private.blocked_between(p_uid, private.direct_other_member(p_c.id, p_uid)), false)
         end
$$;

-- ---------------------------------------------------------------------------
-- Okuma
-- ---------------------------------------------------------------------------
-- İzleyicinin sohbetleri, son görünür mesaja göre (mesaj yoksa sohbetin açılışına göre) yeniden eskiye
create function public.my_conversations()
returns table (
  conversation_id  uuid,
  kind             public.conversation_kind,
  title            text,     -- buluşma başlığı veya karşı tarafın adı; silinmişse 'Silinmiş kullanıcı'
  meetup_id        uuid,
  other_user_id    uuid,
  other_avatar_url text,
  last_body        text,
  last_at          timestamptz,
  unread           int,
  read_only        boolean
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
  select
    c.id,
    c.kind,
    case when c.kind = 'meetup' then m.title
         else coalesce(op.display_name, 'Silinmiş kullanıcı') end,
    c.meetup_id,
    op.id,
    op.avatar_url,
    lm.body,
    lm.created_at,
    (select count(*)::int from public.chat_messages msg
      where msg.conversation_id = c.id
        and msg.created_at > me.last_read_at
        and msg.author_id <> v_uid
        and private.chat_message_visible(msg.moderation_state, msg.author_id, v_uid)),
    private.conversation_read_only(c, v_uid)
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id
  left join public.meetups m on m.id = c.meetup_id
  left join public.profiles op
         on c.kind = 'direct' and op.id = private.direct_other_member(c.id, v_uid)
  left join lateral (
    select msg.body, msg.created_at
    from public.chat_messages msg
    where msg.conversation_id = c.id
      and private.chat_message_visible(msg.moderation_state, msg.author_id, v_uid)
    order by msg.created_at desc, msg.id desc
    limit 1
  ) lm on true
  where me.user_id = v_uid
    and private.conversation_visible(c, v_uid)
  order by coalesce(lm.created_at, c.created_at) desc, c.id desc
  limit 200;
end
$$;

-- Sohbet mesajları, eskiden yeniye. Sayfalama keyset: `p_before` (dönen created_at milisaniyeye kırpılmış,
-- community_feed ile aynı) → ondan eski en yeni `max_rows` mesaj. Üye değil / görünmüyor → 0 satır.
create function public.conversation_messages(
  p_conversation_id uuid,
  p_before          timestamptz default null,
  max_rows          int default 50
)
returns table (
  id                uuid,
  author_id         uuid,
  author_name       text,
  author_avatar_url text,
  body              text,
  created_at        timestamptz,
  is_pending        boolean
)
language plpgsql stable security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := private.require_uid();
begin
  if not private.social_consented(v_uid)
     or not exists (select 1 from public.conversations c
                    where c.id = p_conversation_id and private.conversation_visible(c, v_uid)) then
    return;
  end if;

  return query
  select page.id, page.author_id, pr.display_name, pr.avatar_url, page.body,
         date_trunc('milliseconds', page.created_at), page.moderation_state = 'pending'
  from (
    select msg.*
    from public.chat_messages msg
    where msg.conversation_id = p_conversation_id
      and (p_before is null or date_trunc('milliseconds', msg.created_at) < p_before)
      and private.chat_message_visible(msg.moderation_state, msg.author_id, v_uid)
    order by msg.created_at desc, msg.id desc
    limit greatest(1, least(coalesce(conversation_messages.max_rows, 50), 100))
  ) page
  left join public.profiles pr on pr.id = page.author_id
  order by page.created_at, page.id;
end
$$;

-- ---------------------------------------------------------------------------
-- Yazma
-- ---------------------------------------------------------------------------
-- Sıra: onay → üyelik → salt okunur → metin → küfür → hız sınırları → ekle
create function public.send_chat_message(p_conversation_id uuid, p_body text)
returns jsonb
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  c_max_body     constant int := 1000;
  c_per_minute   constant int := 20;
  c_per_day      constant int := 500;
  v_uid  uuid := private.require_uid();
  v_body text := private.trim_text(p_body);
  v_c    public.conversations;
  v_id   uuid;
  v_at   timestamptz;
begin
  if not private.social_consented(v_uid) then
    return jsonb_build_object('status', 'consent_required');
  end if;

  select c.* into v_c from public.conversations c
  where c.id = p_conversation_id
    and exists (select 1 from public.conversation_members cm
                where cm.conversation_id = c.id and cm.user_id = v_uid);
  if not found then
    return jsonb_build_object('status', 'not_member');
  end if;
  if private.conversation_read_only(v_c, v_uid) or not private.conversation_visible(v_c, v_uid) then
    return jsonb_build_object('status', 'read_only');
  end if;

  if char_length(v_body) = 0 then
    return jsonb_build_object('status', 'invalid', 'reason', 'body_empty');
  end if;
  if char_length(v_body) > c_max_body then
    return jsonb_build_object('status', 'invalid', 'reason', 'body_too_long');
  end if;
  if private.contains_profanity(v_body) then
    return jsonb_build_object('status', 'rejected_content');
  end if;

  -- eşzamanlı gönderimler sınırı aşmasın
  perform pg_advisory_xact_lock(hashtext('chat_send:' || v_uid::text));
  if (select count(*) from public.chat_messages msg
       where msg.conversation_id = v_c.id and msg.author_id = v_uid
         and msg.created_at > now() - interval '1 minute') >= c_per_minute
     or (select count(*) from public.chat_messages msg
          where msg.author_id = v_uid and msg.created_at >= private.istanbul_day_start()) >= c_per_day then
    return jsonb_build_object('status', 'rate_limited');
  end if;

  insert into public.chat_messages (conversation_id, author_id, body)
  values (v_c.id, v_uid, v_body)
  returning id, created_at into v_id, v_at;

  return jsonb_build_object('status', 'sent', 'message_id', v_id,
                            'created_at', date_trunc('milliseconds', v_at));
end
$$;

-- Okundu işareti (yalnızca kendi üyeliği; üye değilse hiçbir şey yapmaz)
create function public.mark_conversation_read(p_conversation_id uuid)
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
end
$$;

-- ---------------------------------------------------------------------------
-- Engelleme kancası: blocks insert → aradaki bekleyen istek silinir; bağlantı `removed` + bire bir sohbet kapanır;
-- engelleyen düzenleyense engellenen onun buluşmalarından çıkarılır (`removed`, sohbet üyeliği silinir).
-- Diğer durumlarda (ortak buluşmada iki katılımcı, ya da engellenen düzenleyen) ikisi de kalır; mesajlar
-- birbirine görünmez (private.chat_message_visible).
-- ---------------------------------------------------------------------------
create function private.apply_block_to_social()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.connections c
   where least(c.requester_id, c.addressee_id) = least(new.user_id, new.blocked_user_id)
     and greatest(c.requester_id, c.addressee_id) = greatest(new.user_id, new.blocked_user_id)
     and c.status = 'pending';

  update public.connections c set status = 'removed'
   where least(c.requester_id, c.addressee_id) = least(new.user_id, new.blocked_user_id)
     and greatest(c.requester_id, c.addressee_id) = greatest(new.user_id, new.blocked_user_id)
     and c.status = 'accepted';

  update public.conversations cv set closed_at = coalesce(cv.closed_at, now())
    from public.connections c
   where cv.connection_id = c.id
     and least(c.requester_id, c.addressee_id) = least(new.user_id, new.blocked_user_id)
     and greatest(c.requester_id, c.addressee_id) = greatest(new.user_id, new.blocked_user_id);

  update public.meetup_participants mp set status = 'removed'
    from public.meetups m
   where m.id = mp.meetup_id and m.organizer_id = new.user_id
     and mp.user_id = new.blocked_user_id and mp.status = 'joined';

  delete from public.conversation_members cm
   using public.conversations cv, public.meetups m
   where cv.id = cm.conversation_id and cv.meetup_id = m.id
     and m.organizer_id = new.user_id and cm.user_id = new.blocked_user_id;

  return null;
end
$$;

create trigger blocks_apply_to_social
  after insert on public.blocks
  for each row execute function private.apply_block_to_social();

-- ---------------------------------------------------------------------------
-- Hesap silme kancası (profiles before delete; cascade'lerden önce çalışır):
--   * düzenlediği aktif, bitmemiş buluşmaların katılımcılarına `meetup_cancelled` bildirimi (düzenleyeni
--     engellemiş olanlar hariç). `actor_id` boş: bildirim silinen kişiyle birlikte gitmesin; `meetup_id`
--     buluşma cascade ile silinince null olur.
--   * karşı taraftan zaten gizli olan bire bir sohbetler (bağlantı kabul edilmiş değil: kaldırıldı/engel) tümden
--     silinir — aksi halde `connection_id` null olunca 'Silinmiş kullanıcı' olarak yeniden görünürlerdi.
-- ---------------------------------------------------------------------------
create function private.cancel_meetups_of_deleted()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.notifications (user_id, kind, title, body, meetup_id)
  select mp.user_id, 'meetup_cancelled', 'Buluşma iptal edildi',
         format('"%s" buluşması iptal edildi.', m.title), m.id
  from public.meetups m
  join public.meetup_participants mp on mp.meetup_id = m.id and mp.status = 'joined'
  -- aynı komutta silinmiş diğer profiller (toplu silme) görünmez
  join public.profiles pr on pr.id = mp.user_id
  where m.organizer_id = old.id
    and m.status = 'active'
    and m.ends_at > now()
    and mp.user_id <> old.id
    and not private.blocked_between(mp.user_id, old.id);

  delete from public.conversations cv
   using public.connections c
   where cv.connection_id = c.id
     and old.id in (c.requester_id, c.addressee_id)
     and c.status <> 'accepted';

  return old;
end
$$;

create trigger profiles_cancel_meetups
  before delete on public.profiles
  for each row execute function private.cancel_meetups_of_deleted();

-- ---------------------------------------------------------------------------
-- Rapor → otomatik gizleme: 0014'teki tanımın kopyası + `chat_message`
-- ---------------------------------------------------------------------------
create or replace function private.auto_hide_reported()
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
    elsif new.target_type = 'comment' then
      update public.community_comments set moderation_state = 'pending'
      where id = new.target_id and moderation_state = 'approved';
    elsif new.target_type = 'chat_message' then
      update public.chat_messages set moderation_state = 'pending'
      where id = new.target_id and moderation_state = 'approved';
    end if;
  end if;
  return null;
end
$$;

drop trigger reports_auto_hide_community on public.reports;
create trigger reports_auto_hide_community
  after insert on public.reports
  for each row
  when (new.target_type in ('post', 'comment', 'chat_message'))
  execute function private.auto_hide_reported();

-- ---------------------------------------------------------------------------
-- Saklama: buluşma bitişinden 30 gün sonra sohbet mesajları silinir (sohbet satırı kalır). Cron günlük.
-- ---------------------------------------------------------------------------
create function private.purge_old_meetup_messages()
returns int
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_n int;
begin
  delete from public.chat_messages msg
   using public.conversations c, public.meetups m
   where c.id = msg.conversation_id
     and m.id = c.meetup_id
     and m.ends_at + interval '30 days' < now();
  get diagnostics v_n = row_count;
  return v_n;
end
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'social-chat-retention';
    perform cron.schedule('social-chat-retention', '20 3 * * *', 'select private.purge_old_meetup_messages();');
  else
    raise notice 'pg_cron yok: social-chat-retention zamanlanmadı';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: yalnızca authenticated — anon ASLA
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public;

revoke all on function public.my_conversations()                                from public, anon, authenticated;
revoke all on function public.conversation_messages(uuid, timestamptz, int)     from public, anon, authenticated;
revoke all on function public.send_chat_message(uuid, text)                     from public, anon, authenticated;
revoke all on function public.mark_conversation_read(uuid)                      from public, anon, authenticated;

grant execute on function public.my_conversations()                             to authenticated;
grant execute on function public.conversation_messages(uuid, timestamptz, int)  to authenticated;
grant execute on function public.send_chat_message(uuid, text)                  to authenticated;
grant execute on function public.mark_conversation_read(uuid)                   to authenticated;
