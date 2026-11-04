-- Girişsiz gezinme (FR-P1): detay RPC'leri anon'a açık ama gizlilik kuralları geçerli (PRD 9.1).
begin;

do $$
declare
  b_lat    float8 := tests.base_lat() + 0.90;
  b_lng    float8 := tests.base_lng();
  creator  uuid := tests.make_user('Anon testi oluşturan');
  s_pub    uuid := tests.make_spot(b_lat,         b_lng, 'anon public', 'public',  creator, now() - interval '2 hours');
  s_prv    uuid := tests.make_spot(b_lat + 0.003, b_lng, 'anon private', 'private', creator);
  r        spot_row;
  n        int;
begin
  perform tests.anon();

  select * into r from public.spot_detail(s_pub);
  perform tests.check(r.id = s_pub, 'anon: spot_detail public noktayı döner');
  perform tests.check(r.is_location_exact = false, 'anon: spot_detail konumu bulanık');
  perform tests.eq(r.status::text, 'fed_recent', 'anon: spot_detail durumu hesaplanır');

  select count(*) into n from public.spot_detail(s_prv);
  perform tests.eq(n, 0, 'anon: private nokta detayı dönmez');

  select count(*) into n from public.spot_feeding_timeline(s_pub, 7);
  perform tests.eq(n, 7, 'anon: 7 günlük çizelge okunur');

  select count(*) into n from public.animals_at_spot(s_pub);
  perform tests.check(n >= 0, 'anon: animals_at_spot çağrılabilir');

  select count(*) into n from public.neighborhood_summary(b_lat, b_lng, 1500);
  perform tests.eq(n, 1, 'anon: neighborhood_summary tek satır döner');

  begin
    perform * from public.spot_guardians(s_pub);
    perform tests.check(false, 'anon: spot_guardians reddedilmeli');
  exception when insufficient_privilege then
    perform tests.check(true, 'anon: koruyucu listesi (kişi adları) girişe bağlı');
  end;
end
$$;

rollback;
