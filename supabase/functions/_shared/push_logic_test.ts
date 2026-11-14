// deno test supabase/functions/_shared/
// Harici bağımlılık yok (ağsız çalışır).

import {
  apnsJobs,
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
    post_id: null,
    created_at: `2026-11-04T10:00:${String(seq % 60).padStart(2, "0")}.000Z`,
    quiet_start: 22,
    quiet_end: 7,
    need_food_pushed_today: 0,
    tokens: ["tok-1"],
    sandbox_tokens: [],
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

Deno.test("decidePushes: community kinds obey quiet hours but never the need_food daily cap", () => {
  const community = (over: Partial<PushRow> = {}) =>
    row({ kind: "community_comment", spot_id: null, post_id: "p1", need_food_pushed_today: 3, ...over });

  // 12:00 İstanbul: need_food_nearby limiti dolu (3) olsa bile Mahalle bildirimleri gönderilir
  const noon = at("2026-11-04T09:00:00Z");
  const rows = [
    community(),
    community({ kind: "cover_volunteered", spot_id: "s1", post_id: "p2" }),
    community(),
    community(),
    community(),
    row({ need_food_pushed_today: 3 }),
  ];
  const d = decidePushes(rows, noon);
  assertEquals(rows.map((r) => d.get(r.id)), ["send", "send", "send", "send", "send", "daily_cap"]);

  // Mahalle push'ları need_food_nearby sayacını tüketmez
  const mixed = [
    community({ need_food_pushed_today: 2 }),
    community({ kind: "cover_volunteered", need_food_pushed_today: 2 }),
    row({ need_food_pushed_today: 2 }),
    row({ need_food_pushed_today: 2 }),
  ];
  const d2 = decidePushes(mixed, noon);
  assertEquals(mixed.map((r) => d2.get(r.id)), ["send", "send", "send", "daily_cap"]);

  // 23:00 İstanbul: sessiz saat Mahalle bildirimleri için de geçerli (ertelenmez, uygulama içinde kalır)
  const night = at("2026-11-04T20:00:00Z");
  const a = community();
  const b = community({ kind: "cover_volunteered" });
  const c = community({ quiet_start: 0, quiet_end: 0 });
  const e = community({ tokens: [] });
  const d3 = decidePushes([a, b, c, e], night);
  assertEquals([d3.get(a.id), d3.get(b.id), d3.get(c.id), d3.get(e.id)], ["quiet_hours", "quiet_hours", "send", "no_token"]);
});

Deno.test("buildApnsPayload / headers: post_id for community notifications", () => {
  const postId = "0b8f4c62-7a0e-4f0e-9f57-3d2a1c9e8b11";
  const spotId = "7f1c2f0e-9a51-4d7e-8a53-5a4f8c1d2e90";

  const comment = row({ id: "n-comment", kind: "community_comment", spot_id: null, post_id: postId });
  const payload = buildApnsPayload(comment) as {
    aps: { alert: { title: string; body: string }; "thread-id": string };
    kind: string;
    post_id: string | null;
    spot_id: string | null;
    need_id: string | null;
  };
  assertEquals(payload.post_id, postId, "payload post_id");
  assertEquals(payload.kind, "community_comment");
  assertEquals(payload.spot_id, null);
  assertEquals(payload.need_id, null);
  assertEquals(payload.aps["thread-id"], postId, "community notifications are threaded by post");
  const headers = buildApnsHeaders("jwt", "app.mamaharitasi", comment, 100);
  assertEquals(headers["apns-collapse-id"], `community_comment:${postId}`);

  const cover = row({ id: "n-cover", kind: "cover_volunteered", spot_id: spotId, post_id: postId });
  const coverPayload = buildApnsPayload(cover) as { post_id: string; spot_id: string; aps: { "thread-id": string } };
  assertEquals([coverPayload.post_id, coverPayload.spot_id], [postId, spotId], "cover_volunteered carries both ids");
  assertEquals(coverPayload.aps["thread-id"], postId);
  const coverHeaders = buildApnsHeaders("jwt", "app.mamaharitasi", cover, 100);
  assertEquals(coverHeaders["apns-collapse-id"], `cover_volunteered:${postId}`);
  for (const h of [headers, coverHeaders]) {
    assert(new TextEncoder().encode(h["apns-collapse-id"]).length <= 64, "collapse id ≤ 64 bytes");
  }

  // diğer türler: post_id her zaman anahtar olarak var ama null; davranış değişmedi
  const spotRow = row({ id: "n-spot", spot_id: "sid" });
  const spotPayload = buildApnsPayload(spotRow) as Record<string, unknown> & { aps: { "thread-id": string } };
  assert("post_id" in spotPayload, "post_id key always present");
  assertEquals(spotPayload.post_id, null);
  assertEquals(spotPayload.aps["thread-id"], "sid");
  assertEquals(buildApnsHeaders("jwt", "b", spotRow, 0)["apns-collapse-id"], "need_food_nearby:sid");
  const bare = row({ id: "n-bare", kind: "donation_delivered", spot_id: null });
  assertEquals((buildApnsPayload(bare) as { aps: { "thread-id": string } }).aps["thread-id"], "donation_delivered");
  assert(!("apns-collapse-id" in buildApnsHeaders("jwt", "b", bare, 0)), "no collapse id without post or spot");

  // push_claim_batch'in eski sürümünden gelen (post_id alanı olmayan) satır da güvenle işlenir
  const legacy = { ...row({ id: "n-legacy", spot_id: "sid" }) } as Partial<PushRow>;
  delete legacy.post_id;
  assertEquals((buildApnsPayload(legacy as PushRow) as { post_id: unknown }).post_id, null);
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

Deno.test("apnsJobs: each token goes to its own APNs environment", () => {
  const r = row({ tokens: ["prod-1", "prod-2"], sandbox_tokens: ["dev-1"] });
  assertEquals(apnsJobs(r), [
    { token: "prod-1", origin: "https://api.push.apple.com" },
    { token: "prod-2", origin: "https://api.push.apple.com" },
    { token: "dev-1", origin: "https://api.sandbox.push.apple.com" },
  ]);
});

Deno.test("decidePushes: sandbox-only device still gets the push", () => {
  const noon = at("2026-11-04T09:00:00Z");
  const r = row({ tokens: [], sandbox_tokens: ["dev-1"] });
  assertEquals(decidePushes([r], noon).get(r.id), "send");
});
