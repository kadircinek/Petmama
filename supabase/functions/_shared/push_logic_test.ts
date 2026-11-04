// deno test supabase/functions/_shared/
// Harici bağımlılık yok (ağsız çalışır).

import {
  apnsOrigin,
  base64url,
  buildApnsHeaders,
  buildApnsJwt,
  buildApnsPayload,
  classifyApnsResponse,
  decidePushes,
  groupByStatus,
  isDispatchAuthorized,
  isQuietHour,
  istanbulClock,
  NEED_FOOD_DAILY_CAP,
  pemToDer,
  type PushRow,
  timingSafeEqual,
} from "./push_logic.ts";

function assertEquals(actual: unknown, expected: unknown, msg = ""): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg} expected ${e}, got ${a}`);
}
function assert(cond: unknown, msg = "assertion failed"): void {
  if (!cond) throw new Error(msg);
}

let seq = 0;
function row(over: Partial<PushRow> = {}): PushRow {
  seq++;
  return {
    id: `n${String(seq).padStart(3, "0")}`,
    user_id: "u1",
    kind: "need_food_nearby",
    title: "Yakınında yardım gerekiyor",
    body: 'Mama gerekli: "Moda İskelesi önü"',
    spot_id: "s1",
    need_id: null,
    created_at: `2026-11-04T10:00:${String(seq % 60).padStart(2, "0")}.000Z`,
    quiet_start: 22,
    quiet_end: 7,
    need_food_pushed_today: 0,
    tokens: ["tok-1"],
    ...over,
  };
}

// İstanbul = UTC+3 (yaz saati yok)
const at = (utc: string) => new Date(utc);

Deno.test("istanbulClock converts UTC to Europe/Istanbul", () => {
  assertEquals(istanbulClock(at("2026-11-04T19:00:00Z")), { day: "2026-11-04", hour: 22 });
  assertEquals(istanbulClock(at("2026-11-04T21:30:00Z")), { day: "2026-11-05", hour: 0 });
  assertEquals(istanbulClock(at("2026-11-04T03:59:59Z")), { day: "2026-11-04", hour: 6 });
});

Deno.test("isQuietHour: overnight window 22–7", () => {
  assertEquals(isQuietHour(21, 22, 7), false, "21");
  assertEquals(isQuietHour(22, 22, 7), true, "22");
  assertEquals(isQuietHour(0, 22, 7), true, "0");
  assertEquals(isQuietHour(6, 22, 7), true, "6");
  assertEquals(isQuietHour(7, 22, 7), false, "7");
});

Deno.test("isQuietHour: same-day window and disabled", () => {
  assertEquals(isQuietHour(12, 13, 15), false);
  assertEquals(isQuietHour(13, 13, 15), true);
  assertEquals(isQuietHour(14, 13, 15), true);
  assertEquals(isQuietHour(15, 13, 15), false);
  for (let h = 0; h < 24; h++) assertEquals(isQuietHour(h, 8, 8), false, `start==end h=${h}`);
});

Deno.test("decidePushes: quiet hours use Istanbul time, not UTC", () => {
  const r = row();
  // 18:59 UTC = 21:59 İstanbul → gönder; 19:00 UTC = 22:00 → sessiz
  assertEquals(decidePushes([r], at("2026-11-04T18:59:00Z")).get(r.id), "send");
  assertEquals(decidePushes([r], at("2026-11-04T19:00:00Z")).get(r.id), "quiet_hours");
  assertEquals(decidePushes([r], at("2026-11-04T04:00:00Z")).get(r.id), "send", "07:00 Istanbul");
});

Deno.test("decidePushes: max 3 need_food_nearby per user per day, counting earlier sends", () => {
  const noon = at("2026-11-04T09:00:00Z"); // 12:00 İstanbul
  const rows = [
    row({ need_food_pushed_today: 1 }),
    row({ need_food_pushed_today: 1 }),
    row({ need_food_pushed_today: 1 }),
    row({ need_food_pushed_today: 1, kind: "thanks_fed" }),
    row({ user_id: "u2", need_food_pushed_today: 0 }),
  ];
  const d = decidePushes(rows, noon);
  assertEquals(rows.map((r) => d.get(r.id)), ["send", "send", "daily_cap", "send", "send"]);
  assertEquals(NEED_FOOD_DAILY_CAP, 3);
});

Deno.test("decidePushes: evaluates in created_at order regardless of input order", () => {
  const noon = at("2026-11-04T09:00:00Z");
  const early = row({ need_food_pushed_today: 2, created_at: "2026-11-04T08:00:00Z" });
  const late = row({ need_food_pushed_today: 2, created_at: "2026-11-04T08:30:00Z" });
  const d = decidePushes([late, early], noon);
  assertEquals([d.get(early.id), d.get(late.id)], ["send", "daily_cap"]);
});

Deno.test("decidePushes: no token, and quiet hours do not consume the daily cap", () => {
  const night = at("2026-11-04T20:00:00Z"); // 23:00 İstanbul
  const a = row({ tokens: [] });
  const b = row();
  const d = decidePushes([a, b], night);
  assertEquals([d.get(a.id), d.get(b.id)], ["no_token", "quiet_hours"]);
  const c = row({ quiet_start: 0, quiet_end: 0, need_food_pushed_today: 2 });
  const e = row({ quiet_start: 0, quiet_end: 0, need_food_pushed_today: 2 });
  const d2 = decidePushes([c, e], night);
  assertEquals([d2.get(c.id), d2.get(e.id)], ["send", "daily_cap"]);
});

Deno.test("buildApnsJwt: ES256 JWT verifiable with the public key", async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const b64 = btoa(bin).replace(/(.{64})/g, "$1\n");
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`;

  for (const variant of [pem, pem.replace(/\n/g, "\\n")]) {
    const jwt = await buildApnsJwt({
      keyId: "ABC123DEFG",
      teamId: "TEAM123456",
      privateKeyPem: variant,
      issuedAt: 1_793_000_000,
    });
    const [h, p, s] = jwt.split(".");
    const decode = (x: string) => JSON.parse(atob(x.replace(/-/g, "+").replace(/_/g, "/")));
    assertEquals(decode(h), { alg: "ES256", kid: "ABC123DEFG" });
    assertEquals(decode(p), { iss: "TEAM123456", iat: 1_793_000_000 });
    const sigBin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - (s.length % 4)) % 4));
    const sig = new Uint8Array(sigBin.length);
    for (let i = 0; i < sigBin.length; i++) sig[i] = sigBin.charCodeAt(i);
    assertEquals(sig.length, 64, "raw r||s signature");
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pair.publicKey,
      sig,
      new TextEncoder().encode(`${h}.${p}`),
    );
    assert(ok, "signature verifies");
    assert(!/[+/=]/.test(jwt), "base64url without padding");
  }
});

Deno.test("pemToDer rejects empty key", () => {
  let threw = false;
  try {
    pemToDer("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----");
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("APNs helpers", () => {
  assertEquals(apnsOrigin("production"), "https://api.push.apple.com");
  assertEquals(apnsOrigin("sandbox"), "https://api.sandbox.push.apple.com");
  assertEquals(apnsOrigin(undefined), "https://api.sandbox.push.apple.com");
  assertEquals(classifyApnsResponse(200), "ok");
  assertEquals(classifyApnsResponse(410, "Unregistered"), "drop_token");
  assertEquals(classifyApnsResponse(400, "BadDeviceToken"), "drop_token");
  assertEquals(classifyApnsResponse(400, "DeviceTokenNotForTopic"), "drop_token");
  assertEquals(classifyApnsResponse(400, "BadTopic"), "error");
  assertEquals(classifyApnsResponse(403, "ExpiredProviderToken"), "error");
  assertEquals(classifyApnsResponse(429, "TooManyRequests"), "error");

  const r = row({ id: "nid", spot_id: "sid" });
  const payload = buildApnsPayload(r) as { aps: { alert: { title: string } }; notification_id: string };
  assertEquals(payload.aps.alert.title, r.title);
  assertEquals(payload.notification_id, "nid");
  const headers = buildApnsHeaders("jwt", "app.mamaharitasi", r, 100);
  assertEquals(headers["apns-topic"], "app.mamaharitasi");
  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers.authorization, "bearer jwt");
  assertEquals(headers["apns-expiration"], "3700");
  assertEquals(headers["apns-collapse-id"], "need_food_nearby:sid");
  assert(
    new TextEncoder().encode(`followed_spot_changed:${crypto.randomUUID()}`).length <= 64,
    "collapse id ≤ 64 bytes",
  );
  assertEquals(base64url("hi?>"), "aGk_Pg");
});

Deno.test("dispatch authorization: service role bearer or shared secret", () => {
  const secrets = { serviceRoleKey: "service-key", dispatchSecret: "s3cret" };
  assert(isDispatchAuthorized(new Headers({ authorization: "Bearer service-key" }), secrets));
  assert(isDispatchAuthorized(new Headers({ "x-dispatch-secret": "s3cret" }), secrets));
  assert(!isDispatchAuthorized(new Headers({ authorization: "Bearer anon-key" }), secrets));
  assert(!isDispatchAuthorized(new Headers({ "x-dispatch-secret": "wrong" }), secrets));
  assert(!isDispatchAuthorized(new Headers(), secrets));
  assert(!isDispatchAuthorized(new Headers({ "x-dispatch-secret": "" }), { serviceRoleKey: null, dispatchSecret: "" }));
  assert(timingSafeEqual("abc", "abc") && !timingSafeEqual("abc", "abd") && !timingSafeEqual("abc", "abcd"));
});

Deno.test("groupByStatus", () => {
  const g = groupByStatus([["a", "sent"], ["b", "quiet_hours"], ["c", "sent"]]);
  assertEquals(g.get("sent"), ["a", "c"]);
  assertEquals(g.get("quiet_hours"), ["b"]);
});
