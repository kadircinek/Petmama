-- Mama Haritası — 0012: Mahalle (topluluk) enum'ları (docs/backend-contract.md "Mahalle (topluluk) — v0.2", D17)
--
-- `alter type … add value` ile eklenen değer, eklendiği transaction commit edilmeden KULLANILAMAZ
-- (her migration tek transaction). Bu yüzden bu dosyada yalnızca tipler var; yeni değerleri kullanan
-- tablolar, fonksiyonlar ve trigger'lar sonraki dosyalarda (0013+).

alter type public.report_target     add value if not exists 'post';
alter type public.report_target     add value if not exists 'comment';
alter type public.notification_kind add value if not exists 'community_comment';
alter type public.notification_kind add value if not exists 'cover_volunteered';

-- note: paylaşım · question: soru/tavsiye · cover_request: "Yerime bakar mısın?" ·
-- supply: mama/malzeme paylaşımı · alert: mahalleye uyarı
create type public.community_post_kind as enum ('note', 'question', 'cover_request', 'supply', 'alert');
