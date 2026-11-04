-- Mama Haritası — 0005: trigger'lar

-- ---------------------------------------------------------------------------
-- auth.users → profiles + notification_prefs (otomatik)
-- E-posta profil adına KOPYALANMAZ (PRD 9.5); ad yalnızca metadata'dan gelir.
-- ---------------------------------------------------------------------------
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name text := left(btrim(coalesce(
                   new.raw_user_meta_data ->> 'display_name',
                   new.raw_user_meta_data ->> 'full_name',
                   new.raw_user_meta_data ->> 'name',
                   '')), 40);
begin
  if v_name = '' or private.contains_profanity(v_name) then
    v_name := 'Mama Dostu';
  end if;

  insert into public.profiles (id, display_name) values (new.id, v_name)
  on conflict (id) do nothing;

  insert into public.notification_prefs (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Not: istemci rolleriyle (authenticated) çalışan trigger'lar private.* yardımcılarını çağırıyorsa
-- `security definer` olmalı — o rollerin private şemasında usage yetkisi yok.

-- ---------------------------------------------------------------------------
-- updated_at
-- ---------------------------------------------------------------------------
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create trigger spots_updated_at before update on public.spots
  for each row execute function private.set_updated_at();
create trigger notification_prefs_updated_at before update on public.notification_prefs
  for each row execute function private.set_updated_at();
create trigger device_tokens_updated_at before update on public.device_tokens
  for each row execute function private.set_updated_at();
create trigger donation_stats_updated_at before update on public.donation_stats
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- notify_center her yazımda 3 ondalığa yuvarlanır (≈110 m) — doğrudan tablo yazımında da (PRD 9.5)
-- ---------------------------------------------------------------------------
create function private.round_notify_center()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.notify_center is not null then
    new.notify_center := private.make_point(
      round(extensions.st_y(new.notify_center::extensions.geometry)::numeric, 3)::float8,
      round(extensions.st_x(new.notify_center::extensions.geometry)::numeric, 3)::float8);
  end if;
  return new;
end
$$;

create trigger notification_prefs_round_center
  before insert or update of notify_center on public.notification_prefs
  for each row execute function private.round_notify_center();

-- ---------------------------------------------------------------------------
-- İçerik filtresi: profil adı ve hayvan metinleri (doğrudan tablo yazımı RLS ile serbest olduğundan)
-- ---------------------------------------------------------------------------
create function private.reject_profanity_profile()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if private.contains_profanity(new.display_name) or private.contains_profanity(new.neighborhood) then
    raise exception 'rejected_content' using errcode = 'P0001', hint = 'profanity';
  end if;
  return new;
end
$$;

create trigger profiles_content_check
  before insert or update of display_name, neighborhood on public.profiles
  for each row execute function private.reject_profanity_profile();

create function private.reject_profanity_animal()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if private.contains_profanity(new.name)
     or private.contains_profanity(new.about)
     or private.contains_profanity(new.color_pattern)
     or private.contains_profanity(new.vaccination_info) then
    raise exception 'rejected_content' using errcode = 'P0001', hint = 'profanity';
  end if;
  return new;
end
$$;

create trigger animals_content_check
  before insert or update of name, about, color_pattern, vaccination_info on public.animals
  for each row execute function private.reject_profanity_animal();

-- ---------------------------------------------------------------------------
-- animals.last_seen_spot_id → animal_spots satırı (artırmadan). mark_animal_seen sayacı kendisi artırır.
-- ---------------------------------------------------------------------------
create function private.sync_animal_spot()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.last_seen_spot_id is not null
     and (tg_op = 'INSERT' or new.last_seen_spot_id is distinct from old.last_seen_spot_id) then
    insert into public.animal_spots (animal_id, spot_id, seen_count, last_seen_at)
    values (new.id, new.last_seen_spot_id, 1, coalesce(new.last_seen_at, now()))
    on conflict (animal_id, spot_id) do nothing;
  end if;
  return new;
end
$$;

create trigger animals_sync_spot
  after insert or update of last_seen_spot_id on public.animals
  for each row execute function private.sync_animal_spot();

-- ---------------------------------------------------------------------------
-- Hesap silinirken (delete-account → auth.users cascade → profiles) kullanıcının storage
-- klasörüne işaret eden foto bağlantılarını temizler; dosyaları edge function siler (PRD 9.5).
-- ---------------------------------------------------------------------------
create function private.scrub_user_photos()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_prefix text := old.id::text || '/';
begin
  update public.spots set photo_url = null
  where photo_url is not null and position(v_prefix in photo_url) > 0;

  update public.checkins set photo_url = null
  where photo_url is not null and position(v_prefix in photo_url) > 0;

  update public.animals
  set photos = array(select p from unnest(photos) p where position(v_prefix in p) = 0)
  where exists (select 1 from unnest(photos) p where position(v_prefix in p) > 0);

  update public.needs
  set photos = array(select p from unnest(photos) p where position(v_prefix in p) = 0)
  where exists (select 1 from unnest(photos) p where position(v_prefix in p) > 0);

  return old;
end
$$;

create trigger profiles_scrub_photos
  before delete on public.profiles
  for each row execute function private.scrub_user_photos();

revoke all on all functions in schema private from public;
