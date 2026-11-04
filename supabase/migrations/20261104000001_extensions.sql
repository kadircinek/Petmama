-- Mama Haritası — 0001: şemalar, eklentiler, gizli ayarlar
--
-- * postgis / pgcrypto / pg_trgm zorunlu.
-- * pg_cron / pg_net isteğe bağlı: yoksa (ör. düz PostgreSQL üzerinde test) migration yine uygulanır,
--   zamanlanmış işler 0009'da atlanır.

create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      -- Supabase'de pg_cron pg_catalog'a kurulur ve `cron` şemasını oluşturur.
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'pg_cron kurulamadı, cron işleri atlanacak: %', sqlerrm;
    end;
  else
    raise notice 'pg_cron yok, cron işleri atlanacak';
  end if;

  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    begin
      create extension if not exists pg_net with schema extensions;
    exception when others then
      raise notice 'pg_net kurulamadı, push-dispatch tetikleyicisi devre dışı: %', sqlerrm;
    end;
  else
    raise notice 'pg_net yok, push-dispatch tetikleyicisi devre dışı';
  end if;
end
$$;

-- `private` şeması PostgREST'e açık değildir; anon/authenticated için usage yok.
-- Bulanıklaştırma tuzu, cron URL'i/sırrı ve iç yardımcı fonksiyonlar burada durur.
create schema if not exists private;
revoke all on schema private from public;
alter default privileges in schema private revoke execute on functions from public;

create table if not exists private.app_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
revoke all on private.app_settings from public;

-- PRD 9.1: bulanıklaştırma tuzu. Kurulumda rastgele üretilir; değiştirmek tüm bulanık noktaları
-- yeni bir yere taşır (eski + yeni konumun ortalaması alınabilir), bu yüzden üretimde bir kez ayarlanır.
insert into private.app_settings (key, value)
values ('fuzz_salt', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (key) do nothing;
