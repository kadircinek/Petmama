-- APNs ortamı token ile saklanır: Debug (sandbox) ve TestFlight/App Store (production) aynı backend'i paylaşır
begin;

do $$
declare
  u   uuid := tests.make_user('Ortam');
  dev text := repeat('d1', 16);
  prd text := repeat('p1', 16);
  rec record;
begin
  perform tests.login(u);
  perform register_device_token(dev, 'sandbox');
  perform register_device_token(prd);
  perform tests.admin();
  perform tests.eq((select apns_env from device_tokens where token = dev), 'sandbox', 'sandbox env stored with token');
  perform tests.eq((select apns_env from device_tokens where token = prd), 'production', 'env defaults to production');

  -- aynı token yeniden kaydedilince ortam güncellenir (ör. Debug → TestFlight aynı cihaz)
  perform tests.login(u);
  perform register_device_token(dev, 'production');
  perform tests.admin();
  perform tests.eq((select apns_env from device_tokens where token = dev), 'production', 'env updated on re-register');
  perform tests.login(u);
  perform register_device_token(dev, 'sandbox');

  begin
    perform register_device_token(repeat('x1', 16), 'staging');
    raise exception 'FAIL: invalid env accepted';
  exception when invalid_parameter_value then
    perform tests.check(true, 'invalid env rejected');
  end;
  perform tests.admin();

  -- push_claim_batch ortamları ayrı listeler
  update notifications set pushed_at = now(), push_status = 'sent' where pushed_at is null;
  insert into notifications (user_id, kind, title, body) values (u, 'thanks_fed', 'env', 'b');
  set local role service_role;
  select * into rec from push_claim_batch(50) where user_id = u;
  reset role;
  perform tests.eq(rec.tokens, array[prd], 'tokens are production tokens');
  perform tests.eq(rec.sandbox_tokens, array[dev], 'sandbox_tokens are sandbox tokens');
end
$$;

rollback;
