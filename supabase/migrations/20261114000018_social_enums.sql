-- Mama Haritası — 0018: Tanışma (buluşmalar + Hayvanseverler) enum'ları
-- (docs/superpowers/specs/2026-11-14-tanisma-design.md §6)
--
-- `alter type … add value` ile eklenen değer, eklendiği transaction commit edilmeden KULLANILAMAZ
-- (her migration tek transaction). Bu yüzden bu dosyada yalnızca tipler var; yeni değerleri kullanan
-- tablolar ve fonksiyonlar sonraki dosyalarda (0019+).

alter type public.report_target     add value if not exists 'meetup';
alter type public.report_target     add value if not exists 'chat_message';
alter type public.notification_kind add value if not exists 'meetup_joined';
alter type public.notification_kind add value if not exists 'meetup_cancelled';
alter type public.notification_kind add value if not exists 'meetup_reminder';
alter type public.notification_kind add value if not exists 'connection_request';
alter type public.notification_kind add value if not exists 'connection_accepted';
alter type public.notification_kind add value if not exists 'chat_message';

-- Sabit ilgi etiketleri
create type public.social_interest as enum (
  'cats', 'dogs', 'birds', 'neutering', 'fostering', 'vet_transport', 'food_donation', 'photography');

create type public.meetup_status      as enum ('active', 'cancelled');
create type public.participant_status as enum ('joined', 'removed');
create type public.connection_status  as enum ('pending', 'accepted', 'declined', 'removed');
create type public.conversation_kind  as enum ('meetup', 'direct');
-- Hayvanseverler listesinde mesafe bandı (kesin mesafe asla dönmez)
create type public.distance_band      as enum ('under_1km', '1_3km', '3_10km');
