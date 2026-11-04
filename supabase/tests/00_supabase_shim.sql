-- Supabase uyumluluk katmanı — YALNIZCA TEST İÇİN.
--
-- Düz PostgreSQL (16 + PostGIS) üzerinde migration'ları çalıştırabilmek için Supabase'in sağladığı
-- asgari parçaları oluşturur: anon/authenticated/service_role rolleri, auth.users + auth.uid()/role(),
-- storage.buckets/objects + storage.foldername(), ve Supabase'in public şemasındaki varsayılan yetkileri.
-- Her parça "yoksa oluştur" şeklindedir; supabase/postgres imajında fiilen hiçbir şey yapmaz.

do $$
declare
  v_created_roles boolean := false;
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
    v_created_roles := true;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;

  if v_created_roles then
    -- Supabase: public şemasında yeni nesnelere API rollerinin hepsi otomatik yetki alır.
    -- Migration'lar bunları bilerek geri alıyor; testin anlamlı olması için aynı varsayılanı kur.
    grant usage on schema public to anon, authenticated, service_role;
    alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
    alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
    alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- auth
-- ---------------------------------------------------------------------------
create schema if not exists auth;

do $$
begin
  if to_regclass('auth.users') is null then
    execute $ddl$
create table auth.users (
  id                 uuid primary key,
  instance_id        uuid,
  aud                varchar(255),
  role               varchar(255),
  email              varchar(255) unique,
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  raw_app_meta_data  jsonb,
  raw_user_meta_data jsonb,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
)
    $ddl$;
  end if;
end
$$;

do $$
begin
  if to_regprocedure('auth.uid()') is null then
    create function auth.uid() returns uuid language sql stable as $f$
      select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
      )::uuid
    $f$;
  end if;
  if to_regprocedure('auth.role()') is null then
    create function auth.role() returns text language sql stable as $f$
      select coalesce(
        nullif(current_setting('request.jwt.claim.role', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
      )::text
    $f$;
  end if;
end
$$;

do $$
begin
  if (select nspowner::regrole::text from pg_namespace where nspname = 'auth') = current_user then
    grant usage on schema auth to anon, authenticated, service_role;
    grant execute on function auth.uid(), auth.role() to anon, authenticated, service_role;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- storage
-- ---------------------------------------------------------------------------
create schema if not exists storage;

do $$
begin
  if to_regclass('storage.buckets') is null then
    execute $ddl$
create table storage.buckets (
  id                 text primary key,
  name               text not null unique,
  owner              uuid,
  public             boolean default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
)
    $ddl$;
  end if;
end
$$;

do $$
begin
  if to_regclass('storage.objects') is null then
    execute $ddl$
create table storage.objects (
  id               uuid primary key default gen_random_uuid(),
  bucket_id        text references storage.buckets (id),
  name             text,
  owner            uuid,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata         jsonb,
  unique (bucket_id, name)
)
    $ddl$;
  end if;
end
$$;


do $$
begin
  if to_regprocedure('storage.foldername(text)') is null then
    create function storage.foldername(name text) returns text[] language plpgsql immutable as $f$
    declare
      _parts text[];
    begin
      select string_to_array(name, '/') into _parts;
      return _parts[1:array_length(_parts, 1) - 1];
    end
    $f$;
  end if;
end
$$;

do $$
begin
  -- yalnızca shim tabloları oluşturduysa (sahibi biz isek) yetki ver
  if (select relowner::regrole::text from pg_class where oid = 'storage.objects'::regclass) = current_user then
    alter table storage.objects enable row level security;
    grant usage on schema storage to anon, authenticated, service_role;
    grant all on storage.buckets, storage.objects to anon, authenticated, service_role;
  end if;
end
$$;
