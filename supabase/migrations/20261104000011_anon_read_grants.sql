-- Haritayı ve detayları gezmek için giriş gerekmez (PRD FR-P1).
-- Bu okuma RPC'leri gizlilik kurallarını (PRD 9.1) kendi içinde uygular: anon için konumlar
-- bulanıktır ve `private` noktalar hiç dönmez. Bu yüzden anon rolüne de açılır.
-- Koruyucu listesi (kişi adları) ve profil istatistikleri girişe bağlı kalır.

grant execute on function public.spot_detail(uuid)                         to anon;
grant execute on function public.spot_feeding_timeline(uuid, int)          to anon;
grant execute on function public.need_detail(uuid)                         to anon;
grant execute on function public.animals_at_spot(uuid)                     to anon;
grant execute on function public.animal_spots_of(uuid)                     to anon;
grant execute on function public.neighborhood_summary(float8, float8, int) to anon;
