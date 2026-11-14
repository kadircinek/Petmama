-- Tanışma: sosyal onay (18+), sosyal profil RPC'leri, tablolara doğrudan erişim yok, silmede cascade.
begin;

do $$
declare
  u     uuid := tests.make_user('Sosyal');
  u2    uuid := tests.make_user('Ikinci');
  r     record;
  j     jsonb;
  g     extensions.geography;
begin
  -- satır yokken: 0 satır
  perform tests.login(u);
  perform tests.eq((select count(*)::int from social_profile_me()), 0, 'no row before consent');
  perform tests.admin();
  perform tests.check(private.social_consented(u) is false, 'not consented yet');
  perform tests.login(u);

  -- onaysız güncelleme
  j := update_social_profile(true, 'Merhaba', array['cats']::social_interest[], 40.98765, 29.02512);
  perform tests.eq(j->>'status', 'consent_required', 'update without consent → consent_required');

  -- onay: idempotent
  perform tests.eq(give_social_consent()->>'status', 'ok', 'give_social_consent ok');
  perform tests.eq(give_social_consent()->>'status', 'ok', 'give_social_consent twice ok');
  perform tests.admin();
  perform tests.eq((select count(*)::int from social_profiles where user_id = u), 1, 'single row after two consents');
  perform tests.check((select adult_confirmed_at is not null and terms_accepted_at = adult_confirmed_at
                         from social_profiles where user_id = u), 'consent timestamps set equal');
  perform tests.check(private.social_consented(u), 'social_consented true');
  perform tests.check(not private.social_consented(u2), 'other user not consented');
  perform tests.login(u);
  select * into r from social_profile_me();
  perform tests.check(r.consented and r.is_visible is false, 'me: consented, invisible by default');

  -- görünür + konumsuz
  j := update_social_profile(true, 'Merhaba', array['cats']::social_interest[]);
  perform tests.eq(j->>'status', 'invalid', 'visible without location → invalid');
  perform tests.eq(j->>'reason', 'location_required', 'reason location_required');

  -- konum yuvarlama
  j := update_social_profile(true, '  Kedi sever  ', array['cats','dogs']::social_interest[], 40.98765, 29.02512);
  perform tests.eq(j->>'status', 'ok', 'visible with location ok');
  perform tests.admin();
  select cell into g from social_profiles where user_id = u;
  perform tests.eq(extensions.st_y(g::extensions.geometry)::numeric, 40.99::numeric, 'lat rounded to 2 decimals');
  perform tests.eq(extensions.st_x(g::extensions.geometry)::numeric, 29.03::numeric, 'lng rounded to 2 decimals');
  perform tests.login(u);
  select * into r from social_profile_me();
  perform tests.eq(r.about, 'Kedi sever', 'about trimmed');
  perform tests.eq(r.interests, array['cats','dogs']::social_interest[], 'interests stored');
  perform tests.check(r.is_visible, 'now visible');

  -- konum verilmeden güncelleme mevcut hücreyi korur
  j := update_social_profile(true, 'Yeni', array[]::social_interest[]);
  perform tests.eq(j->>'status', 'ok', 'visible with existing cell ok without location');

  -- kapatma konumsuz da olur
  j := update_social_profile(false, '', array[]::social_interest[]);
  perform tests.eq(j->>'status', 'ok', 'hide without location ok');

  -- 300 / 301 karakter
  j := update_social_profile(false, repeat('a', 300), array[]::social_interest[]);
  perform tests.eq(j->>'status', 'ok', '300 chars about ok');
  j := update_social_profile(false, repeat('a', 301), array[]::social_interest[]);
  perform tests.eq(j->>'status', 'invalid', '301 chars → invalid');
  perform tests.eq(j->>'reason', 'about_too_long', 'about_too_long');

  -- küfür
  j := update_social_profile(false, 'siktir git', array[]::social_interest[]);
  perform tests.eq(j->>'status', 'rejected_content', 'profanity → rejected_content');

  -- doğrudan erişim yok
  begin
    perform count(*) from social_profiles;
    raise exception 'FAIL: direct select allowed';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot select social_profiles (permission denied)');
  end;
  begin
    perform count(*) from connections;
    raise exception 'FAIL: direct select allowed';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot select connections');
  end;
  begin
    perform count(*) from chat_messages;
    raise exception 'FAIL: direct select allowed';
  exception when insufficient_privilege then
    perform tests.check(true, 'authenticated cannot select chat_messages');
  end;

  -- anon RPC'ye erişemez
  perform tests.anon();
  begin
    perform give_social_consent();
    raise exception 'FAIL: anon executed';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute give_social_consent');
  end;
  begin
    perform * from social_profile_me();
    raise exception 'FAIL: anon executed';
  exception when insufficient_privilege then
    perform tests.check(true, 'anon cannot execute social_profile_me');
  end;

  -- kullanıcı silinince satır yok
  perform tests.admin();
  delete from auth.users where id = u;
  perform tests.eq((select count(*)::int from social_profiles where user_id = u), 0, 'profile row cascades on user delete');
end
$$;

rollback;
