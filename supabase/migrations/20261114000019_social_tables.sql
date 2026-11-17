-- Mama Haritası — 0019: Tanışma tabloları (spec §5.5, §6)
--
-- * Hepsi RLS açık + politika yok + yetki yok: yalnızca `security definer` RPC'ler (0020+).
-- * Kişisel sosyal veri hesap silinince cascade (profiles'a `on delete cascade`). İstisna:
--   `conversations.connection_id` → `on delete set null` (bağlantıyı silen taraf ayrılınca bire bir sohbet
--   diğer kişi için kalır).
-- * `social_profiles.cell` ≈1 km'ye (2 ondalık) yuvarlanır.

-- ---------------------------------------------------------------------------
-- social_profiles
-- ---------------------------------------------------------------------------
create table public.social_profiles (
  user_id            uuid primary key references public.profiles (id) on delete cascade,
  is_visible         boolean not null default false,
  about              text not null default '' check (char_length(about) <= 300),
  interests          public.social_interest[] not null default '{}',
  -- kaba konum; trigger her yazımda 2 ondalığa yuvarlar
  cell               extensions.geography(Point, 4326),
  adult_confirmed_at timestamptz,
  terms_accepted_at  timestamptz,
  updated_at         timestamptz not null default now()
);

create index social_profiles_cell_gist on public.social_profiles using gist (cell) where is_visible;

-- ---------------------------------------------------------------------------
-- meetups ve katılımcılar
-- ---------------------------------------------------------------------------
create table public.meetups (
  id           uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references public.profiles (id) on delete cascade,
  title        text not null check (char_length(title) between 3 and 80),
  description  text not null default '' check (char_length(description) <= 600),
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  place_name   text not null check (char_length(place_name) between 1 and 80),
  location     extensions.geography(Point, 4326) not null,
  spot_id      uuid references public.spots (id) on delete set null,
  capacity     int check (capacity is null or capacity between 2 and 50),
  status       public.meetup_status not null default 'active',
  created_at   timestamptz not null default now(),
  check (ends_at - starts_at between interval '30 minutes' and interval '8 hours')
);

create index meetups_location_gist on public.meetups using gist (location);
create index meetups_starts_idx on public.meetups (starts_at) where status = 'active';
-- düzenleyenin meetup'ları + günlük limit sayımı
create index meetups_organizer_idx on public.meetups (organizer_id, created_at desc);
create index meetups_spot_idx on public.meetups (spot_id) where spot_id is not null;

create table public.meetup_participants (
  meetup_id uuid not null references public.meetups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  status    public.participant_status not null default 'joined',
  joined_at timestamptz not null default now(),
  primary key (meetup_id, user_id)
);

create index meetup_participants_user_idx on public.meetup_participants (user_id);

-- ---------------------------------------------------------------------------
-- connections (Hayvanseverler)
-- ---------------------------------------------------------------------------
create table public.connections (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  note         text not null default '' check (char_length(note) <= 200),
  status       public.connection_status not null default 'pending',
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);

-- iki kişi arasında tek kayıt (sırasız çift)
create unique index connections_pair_uniq on public.connections
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index connections_requester_idx on public.connections (requester_id, created_at desc);
create index connections_addressee_idx on public.connections (addressee_id, status);

-- ---------------------------------------------------------------------------
-- conversations, üyeler, mesajlar
-- ---------------------------------------------------------------------------
create table public.conversations (
  id            uuid primary key default gen_random_uuid(),
  kind          public.conversation_kind not null,
  meetup_id     uuid unique references public.meetups (id) on delete cascade,
  connection_id uuid unique references public.connections (id) on delete set null,
  created_at    timestamptz not null default now(),
  closed_at     timestamptz,
  check (kind <> 'meetup' or meetup_id is not null),
  check (kind <> 'direct' or meetup_id is null)
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  last_read_at    timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.chat_messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.conversations (id) on delete cascade,
  author_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null check (char_length(btrim(body)) between 1 and 1000),
  moderation_state public.moderation_state not null default 'approved',
  created_at       timestamptz not null default now()
);

create index chat_messages_conv_idx on public.chat_messages (conversation_id, created_at desc);
-- hız sınırı sayımı (dakikada 20 / günde 500)
create index chat_messages_author_idx on public.chat_messages (author_id, created_at desc);

-- ---------------------------------------------------------------------------
-- notifications: yeni sütunlar (hesap silme tetikleyicisi ve bildirimler bunları kullanır)
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column meetup_id       uuid references public.meetups (id) on delete set null,
  add column conversation_id uuid references public.conversations (id) on delete cascade;

create index notifications_meetup_idx on public.notifications (meetup_id) where meetup_id is not null;
create index notifications_conversation_idx on public.notifications (conversation_id) where conversation_id is not null;

-- ---------------------------------------------------------------------------
-- Trigger'lar
-- ---------------------------------------------------------------------------
-- cell her yazımda 2 ondalığa yuvarlanır (≈1,1 km) — RPC dışı yazımlarda da; null kalır
create function private.round_social_cell()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.cell is not null then
    new.cell := private.make_point(
      round(extensions.st_y(new.cell::extensions.geometry)::numeric, 2)::float8,
      round(extensions.st_x(new.cell::extensions.geometry)::numeric, 2)::float8);
  end if;
  return new;
end
$$;

create trigger social_profiles_round_cell
  before insert or update of cell on public.social_profiles
  for each row execute function private.round_social_cell();

create trigger social_profiles_updated_at before update on public.social_profiles
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Yardımcı: sosyal onay verilmiş mi? (18+ ve koşullar)
-- ---------------------------------------------------------------------------
create function private.social_consented(p_uid uuid)
returns boolean
language sql stable security definer
set search_path = public, extensions
as $$
  select coalesce(
    (select sp.adult_confirmed_at is not null and sp.terms_accepted_at is not null
       from public.social_profiles sp where sp.user_id = p_uid),
    false)
$$;

-- ---------------------------------------------------------------------------
-- RLS: açık, politika yok, anon/authenticated için yetki yok → doğrudan erişim YOK (yalnızca RPC)
-- ---------------------------------------------------------------------------
alter table public.social_profiles      enable row level security;
alter table public.meetups              enable row level security;
alter table public.meetup_participants  enable row level security;
alter table public.connections          enable row level security;
alter table public.conversations        enable row level security;
alter table public.conversation_members enable row level security;
alter table public.chat_messages        enable row level security;

revoke all on
  public.social_profiles, public.meetups, public.meetup_participants, public.connections,
  public.conversations, public.conversation_members, public.chat_messages
from anon, authenticated;

revoke all on all functions in schema private from public;
