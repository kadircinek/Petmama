-- Mama Haritası — 0003: tablolar ve indeksler
--
-- Silme davranışı (PRD 9.5 / delete-account): kişisel tablolar `on delete cascade`, topluluk kayıtları
-- (nokta, hayvan, check-in, ihtiyaç) `on delete set null` ile anonimleşir.

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users (id) on delete cascade,
  display_name       text not null default 'Mama Dostu'
                       check (char_length(btrim(display_name)) between 1 and 40),
  avatar_url         text check (avatar_url is null or char_length(avatar_url) <= 1024),
  neighborhood       text check (neighborhood is null or char_length(neighborhood) <= 80),
  trust_score        int not null default 10,
  is_verified_feeder boolean not null default false,
  is_moderator       boolean not null default false,
  created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- spots
-- ---------------------------------------------------------------------------
create table public.spots (
  id               uuid primary key default gen_random_uuid(),
  location         extensions.geography(Point, 4326) not null,
  type             public.spot_type not null default 'food',
  species          public.spot_species not null default 'cat',
  title            text not null check (char_length(btrim(title)) between 1 and 80),
  note             text check (note is null or char_length(note) <= 500),
  photo_url        text check (photo_url is null or char_length(photo_url) <= 1024),
  status           public.spot_status not null default 'unknown',   -- cron ile kalıcılaştırılır
  last_fed_at      timestamptz,
  created_by       uuid references public.profiles (id) on delete set null,
  visibility       public.spot_visibility not null default 'public',
  is_active        boolean not null default true,
  moderation_state public.moderation_state not null default 'approved',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index spots_location_gist on public.spots using gist (location);
create index spots_created_by_idx on public.spots (created_by, created_at desc);
create index spots_last_fed_idx on public.spots (last_fed_at) where is_active;

-- ---------------------------------------------------------------------------
-- checkins — kullanıcının konumu saklanmaz, yalnızca noktaya uzaklığı (PRD 9.5)
-- ---------------------------------------------------------------------------
create table public.checkins (
  id              uuid primary key default gen_random_uuid(),
  spot_id         uuid not null references public.spots (id) on delete cascade,
  user_id         uuid references public.profiles (id) on delete set null,
  kind            public.checkin_kind not null,
  amount          public.food_amount,
  photo_url       text check (photo_url is null or char_length(photo_url) <= 1024),
  user_distance_m int check (user_distance_m is null or user_distance_m >= 0),
  resolved_at     timestamptz,
  resolved_by     uuid references public.checkins (id) on delete set null,
  -- FR-H8: çevrimdışı kuyruğun ürettiği id; aynı check-in'in tekrar gönderimi çift kayıt açmaz
  client_id       uuid,
  created_at      timestamptz not null default now()
);

create unique index checkins_client_id_key on public.checkins (client_id) where client_id is not null;
create index checkins_spot_created_idx on public.checkins (spot_id, created_at desc);
create index checkins_user_created_idx on public.checkins (user_id, created_at desc);
-- açık talepler (need_food / need_water / broken) — durum hesabının sıcak yolu
create index checkins_open_requests_idx on public.checkins (spot_id)
  where resolved_at is null and kind in ('need_food', 'need_water', 'broken');

-- ---------------------------------------------------------------------------
-- animals
-- ---------------------------------------------------------------------------
create table public.animals (
  id                uuid primary key default gen_random_uuid(),
  species           public.animal_species not null default 'cat',
  name              text check (name is null or char_length(btrim(name)) between 1 and 40),
  color_pattern     text check (color_pattern is null or char_length(color_pattern) <= 80),
  sex               public.animal_sex not null default 'unknown',
  age_estimate      public.age_estimate not null default 'unknown',
  is_neutered       boolean,
  ear_tag           boolean not null default false,
  vaccination_info  text check (vaccination_info is null or char_length(vaccination_info) <= 300),
  temperament_tags  text[] not null default '{}',
  warning           public.animal_warning,
  about             text check (about is null or char_length(about) <= 1000),
  photos            text[] not null default '{}' check (cardinality(photos) <= 10),
  last_seen_at      timestamptz,
  last_seen_spot_id uuid references public.spots (id) on delete set null,
  created_by        uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);

create index animals_last_seen_spot_idx on public.animals (last_seen_spot_id);
create index animals_created_by_idx on public.animals (created_by);

create table public.animal_spots (
  animal_id    uuid not null references public.animals (id) on delete cascade,
  spot_id      uuid not null references public.spots (id) on delete cascade,
  seen_count   int not null default 1 check (seen_count >= 0),
  last_seen_at timestamptz not null default now(),
  primary key (animal_id, spot_id)
);

create index animal_spots_spot_idx on public.animal_spots (spot_id);

-- ---------------------------------------------------------------------------
-- needs (veteriner, kısırlaştırma, ...) — FR-I*
-- ---------------------------------------------------------------------------
create table public.needs (
  id          uuid primary key default gen_random_uuid(),
  animal_id   uuid references public.animals (id) on delete cascade,
  spot_id     uuid references public.spots (id) on delete cascade,
  type        public.need_type not null,
  urgency     public.need_urgency not null default 'normal',
  description text check (description is null or char_length(description) <= 1000),
  photos      text[] not null default '{}' check (cardinality(photos) <= 10),
  status      public.need_status not null default 'open',
  created_by  uuid references public.profiles (id) on delete set null,
  claimed_by  uuid references public.profiles (id) on delete set null,
  claimed_at  timestamptz,
  resolved_at timestamptz,
  -- sözleşmeye ek: kimin kapattığı (profile_stats.resolved_need_count için)
  resolved_by uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  check (animal_id is not null or spot_id is not null)
);

create index needs_spot_idx on public.needs (spot_id) where spot_id is not null;
create index needs_animal_idx on public.needs (animal_id) where animal_id is not null;
create index needs_open_idx on public.needs (urgency, created_at desc) where status <> 'resolved';
create index needs_claimed_by_idx on public.needs (claimed_by) where claimed_by is not null;
create index needs_resolved_by_idx on public.needs (resolved_by) where resolved_by is not null;

-- ---------------------------------------------------------------------------
-- guardians (koruyucular), follows, gone-reports
-- ---------------------------------------------------------------------------
create table public.guardians (
  user_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  spot_id    uuid not null references public.spots (id) on delete cascade,
  schedule   smallint[] not null default '{}' check (schedule <@ '{1,2,3,4,5,6,7}'::smallint[]),  -- ISO 1=Pzt..7=Paz
  created_at timestamptz not null default now(),
  primary key (user_id, spot_id)
);

create index guardians_spot_idx on public.guardians (spot_id);

create table public.follows (
  user_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  target_type public.follow_target not null,
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, target_type, target_id)
);

create index follows_target_idx on public.follows (target_type, target_id);

create table public.spot_gone_reports (
  spot_id    uuid not null references public.spots (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (spot_id, user_id)
);

-- ---------------------------------------------------------------------------
-- moderation & safety
-- ---------------------------------------------------------------------------
create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid default auth.uid() references public.profiles (id) on delete set null,
  target_type public.report_target not null,
  target_id   uuid not null,
  reason      public.report_reason not null,
  details     text check (details is null or char_length(details) <= 1000),
  status      public.report_status not null default 'open',
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);

create index reports_status_idx on public.reports (status, created_at desc);
create index reports_target_idx on public.reports (target_type, target_id);

create table public.blocks (
  user_id         uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (user_id, blocked_user_id),
  check (user_id <> blocked_user_id)
);

create index blocks_blocked_idx on public.blocks (blocked_user_id);

-- ---------------------------------------------------------------------------
-- notifications & push
-- ---------------------------------------------------------------------------
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        public.notification_kind not null,
  title       text not null,
  body        text not null,
  spot_id     uuid references public.spots (id) on delete set null,
  need_id     uuid references public.needs (id) on delete set null,
  read_at     timestamptz,
  pushed_at   timestamptz,   -- push-dispatch satırı işlediğinde dolar (gönderilmese bile)
  -- sözleşmeye ek: push sonucunu açıklar; uygulama içi bildirimi etkilemez
  push_status text check (push_status in ('processing', 'sent', 'quiet_hours', 'daily_cap',
                                          'no_token', 'failed', 'expired')),
  created_at  timestamptz not null default now()
);

create index notifications_user_created_idx on public.notifications (user_id, created_at desc);
create index notifications_unpushed_idx on public.notifications (created_at) where pushed_at is null;
create index notifications_dedupe_idx on public.notifications (user_id, kind, spot_id, created_at desc);

create table public.device_tokens (
  token      text primary key check (char_length(token) between 8 and 512),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  platform   text not null default 'ios' check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.notification_prefs (
  user_id          uuid primary key default auth.uid() references public.profiles (id) on delete cascade,
  radius_m         int not null default 1000 check (radius_m between 100 and 20000),
  quiet_start      smallint not null default 22 check (quiet_start between 0 and 23),
  quiet_end        smallint not null default 7 check (quiet_end between 0 and 23),
  need_food_nearby boolean not null default true,
  followed_updates boolean not null default true,
  guardian_alerts  boolean not null default true,
  -- yalnızca SON kaba konum (3 ondalık ≈ 110 m); geçmiş tutulmaz. Trigger yuvarlar.
  notify_center    extensions.geography(Point, 4326),
  updated_at       timestamptz not null default now()
);

create index notification_prefs_center_gist on public.notification_prefs using gist (notify_center)
  where notify_center is not null and need_food_nearby;

-- ---------------------------------------------------------------------------
-- donations (PRD 8.2)
-- ---------------------------------------------------------------------------
create table public.donation_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.profiles (id) on delete set null,
  kind       text not null check (char_length(kind) between 1 and 32),
  ref_code   text check (ref_code is null or char_length(ref_code) <= 64),
  created_at timestamptz not null default now()
);

create table public.donation_stats (
  month          date primary key check (month = date_trunc('month', month)::date),
  kg_distributed numeric not null default 0 check (kg_distributed >= 0),
  donor_count    int not null default 0 check (donor_count >= 0),
  updated_at     timestamptz not null default now()
);
