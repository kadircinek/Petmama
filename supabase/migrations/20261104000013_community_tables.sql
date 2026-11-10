-- Mama Haritası — 0013: Mahalle (topluluk) tabloları (docs/backend-contract.md "Mahalle (topluluk) — v0.2", D17)
--
-- * Özel mesajlaşma yok: paylaşım, yorum, "pati" tepkisi ve "Ben bakarım" gönüllülüğü.
-- * Dört tablo da RLS açık + politika yok + yetki yok: yalnızca `security definer` RPC'ler (0014).
--   Besleyicilerin konuşmaları ve adları girişsiz ya da doğrudan tablo okumasıyla taranamaz (PRD 9.1).
-- * Paylaşımın yalnızca kaba konumu saklanır: `cell` 2 ondalığa yuvarlanır (≈1,1 km).
-- * Hesap silinince kullanıcının paylaşım, yorum, pati ve gönüllülük kayıtları SİLİNİR (kişisel içerik,
--   PRD 9.5): hepsi profiles'a `on delete cascade`. (Nokta/hayvan kayıtlarının aksine anonimleşmez.)

-- ---------------------------------------------------------------------------
-- community_posts
-- ---------------------------------------------------------------------------
create table public.community_posts (
  id               uuid primary key default gen_random_uuid(),
  author_id        uuid not null references public.profiles (id) on delete cascade,
  kind             public.community_post_kind not null default 'note',
  body             text not null check (char_length(btrim(body)) between 1 and 600),
  photo_url        text check (photo_url is null or char_length(photo_url) <= 1024),
  -- Nokta/hayvan silinirse paylaşım kalır, bağ kopar
  spot_id          uuid references public.spots (id) on delete set null,
  animal_id        uuid references public.animals (id) on delete set null,
  -- kaba konum; trigger her yazımda 2 ondalığa yuvarlar
  cell             extensions.geography(Point, 4326) not null,
  -- "Yerime bakar mısın?" aralığı (İstanbul günü, ikisi de dahil); yalnızca cover_request'te dolu.
  -- `cover_from ≥ bugün` kuralı oluşturma anına aittir, RPC'de denetlenir.
  cover_from       date,
  cover_to         date,
  moderation_state public.moderation_state not null default 'approved',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check ((kind = 'cover_request') = (cover_from is not null)),
  check ((cover_from is null) = (cover_to is null)),
  check (cover_to >= cover_from and cover_to - cover_from <= 30)
);

create index community_posts_cell_gist on public.community_posts using gist (cell);
create index community_posts_created_idx on public.community_posts (created_at desc);
-- yazarın paylaşımları + günlük limit sayımı
create index community_posts_author_idx on public.community_posts (author_id, created_at desc);
create index community_posts_spot_idx on public.community_posts (spot_id) where spot_id is not null;
create index community_posts_animal_idx on public.community_posts (animal_id) where animal_id is not null;

-- ---------------------------------------------------------------------------
-- community_comments
-- ---------------------------------------------------------------------------
create table public.community_comments (
  id               uuid primary key default gen_random_uuid(),
  post_id          uuid not null references public.community_posts (id) on delete cascade,
  author_id        uuid not null references public.profiles (id) on delete cascade,
  body             text not null check (char_length(btrim(body)) between 1 and 300),
  moderation_state public.moderation_state not null default 'approved',
  created_at       timestamptz not null default now()
);

create index community_comments_post_idx on public.community_comments (post_id, created_at);
create index community_comments_author_idx on public.community_comments (author_id, created_at desc);

-- ---------------------------------------------------------------------------
-- community_paws ("pati bırak") ve cover_volunteers ("Ben bakarım")
-- ---------------------------------------------------------------------------
create table public.community_paws (
  post_id    uuid not null references public.community_posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index community_paws_user_idx on public.community_paws (user_id);

create table public.cover_volunteers (
  post_id    uuid not null references public.community_posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index cover_volunteers_user_idx on public.cover_volunteers (user_id);

-- ---------------------------------------------------------------------------
-- notifications / notification_prefs: yeni sütunlar
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column post_id  uuid references public.community_posts (id) on delete cascade,
  -- sözleşmeye ek: bildirimi tetikleyen kişi. Mahalle bildirimlerinin metni yorumcunun/gönüllünün adını
  -- (ve yorumdan bir alıntıyı) taşır; o kişi hesabını silince bildirim de silinir (PRD 9.5).
  add column actor_id uuid references public.profiles (id) on delete cascade;

-- "aynı paylaşım için okunmamış aynı tür bildirim var mı?" sorgusu + FK cascade
create index notifications_post_idx on public.notifications (post_id) where post_id is not null;
create index notifications_actor_idx on public.notifications (actor_id) where actor_id is not null;

alter table public.notification_prefs
  add column community_updates boolean not null default true;

-- notification_prefs yetkileri sütun bazlı (0006): yeni sütun ayrıca verilmeli
grant insert (community_updates), update (community_updates) on public.notification_prefs to authenticated;

-- ---------------------------------------------------------------------------
-- Trigger'lar
-- ---------------------------------------------------------------------------
-- cell her yazımda 2 ondalığa yuvarlanır (≈1,1 km) — RPC dışı yazımlarda da (seed, service_role);
-- notify_center'daki (0005) kalıbın aynısı.
create function private.round_post_cell()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  new.cell := private.make_point(
    round(extensions.st_y(new.cell::extensions.geometry)::numeric, 2)::float8,
    round(extensions.st_x(new.cell::extensions.geometry)::numeric, 2)::float8);
  return new;
end
$$;

create trigger community_posts_round_cell
  before insert or update of cell on public.community_posts
  for each row execute function private.round_post_cell();

create trigger community_posts_updated_at before update on public.community_posts
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: açık, politika yok, anon/authenticated için yetki yok → doğrudan erişim YOK (yalnızca RPC)
-- ---------------------------------------------------------------------------
alter table public.community_posts    enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_paws     enable row level security;
alter table public.cover_volunteers   enable row level security;

revoke all on
  public.community_posts, public.community_comments, public.community_paws, public.cover_volunteers
from anon, authenticated;

revoke all on all functions in schema private from public;
