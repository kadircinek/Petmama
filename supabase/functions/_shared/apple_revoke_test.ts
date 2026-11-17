// deno test supabase/functions/_shared/
// Ağsız: Apple uç noktaları sahte fetch ile taklit edilir.

import {
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  appleRevokeConfig,
  buildAppleClientSecret,
  isAppleUser,
  revokeAppleTokens,
} from "./apple_revoke.ts";

function assertEquals(actual: unknown, expected: unknown, msg = ""): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg} expected ${e}, got ${a}`);
}
function assert(cond: unknown, msg = "assertion failed"): void {
  if (!cond) throw new Error(msg);
}

async function testKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----\n`;
  return { pem, publicKey: pair.publicKey };
}

function decodePart(part: string): Record<string, unknown> {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)));
}

function b64urlToBytes(part: string): Uint8Array<ArrayBuffer> {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

Deno.test("buildAppleClientSecret: ES256 JWT with Apple's required claims", async () => {
  const { pem, publicKey } = await testKey();
  const jwt = await buildAppleClientSecret({
    teamId: "TEAM123456",
    keyId: "KEY1234567",
    clientId: "app.petmama.mamaharitasi",
    privateKeyPem: pem,
    issuedAt: 1_800_000_000,
  });
  const [h, p, s] = jwt.split(".");
  assertEquals(decodePart(h), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(decodePart(p), {
    iss: "TEAM123456",
    iat: 1_800_000_000,
    exp: 1_800_000_300,
    aud: "https://appleid.apple.com",
    sub: "app.petmama.mamaharitasi",
  });
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    b64urlToBytes(s),
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert(ok, "signature verifies");
});

Deno.test("appleRevokeConfig: null unless all secrets are set", () => {
  const full = { APPLE_TEAM_ID: "T", APPLE_SIWA_KEY_ID: "K", APPLE_SIWA_PRIVATE_KEY: "P", APPLE_CLIENT_ID: "C" };
  assertEquals(appleRevokeConfig((k) => full[k as keyof typeof full]), {
    teamId: "T",
    keyId: "K",
    privateKeyPem: "P",
    clientId: "C",
  });
  assertEquals(appleRevokeConfig((k) => ({ ...full, APPLE_CLIENT_ID: undefined })[k as keyof typeof full]), null);
});

Deno.test("isAppleUser: identities or app_metadata.provider", () => {
  assert(isAppleUser({ identities: [{ provider: "email" }, { provider: "apple" }] }));
  assert(isAppleUser({ app_metadata: { provider: "apple" } }));
  assert(!isAppleUser({ identities: [{ provider: "email" }], app_metadata: { provider: "email" } }));
  assert(!isAppleUser(null));
});

type Call = { url: string; body: URLSearchParams };

function fakeFetch(responses: Record<string, Response>): { fetch: typeof fetch; calls: Call[] } {
  const calls: Call[] = [];
  const f = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, body: new URLSearchParams(String(init?.body ?? "")) });
    return responses[url] ?? new Response("not found", { status: 404 });
  }) as typeof fetch;
  return { fetch: f, calls };
}

async function config() {
  const { pem } = await testKey();
  return { teamId: "T", keyId: "K", privateKeyPem: pem, clientId: "app.petmama.mamaharitasi" };
}

Deno.test("revokeAppleTokens: exchanges code, then revokes the refresh token", async () => {
  const { fetch, calls } = fakeFetch({
    [APPLE_TOKEN_URL]: Response.json({ access_token: "acc", refresh_token: "ref" }),
    [APPLE_REVOKE_URL]: new Response(null, { status: 200 }),
  });
  const result = await revokeAppleTokens("auth-code", await config(), fetch, 1_800_000_000);
  assertEquals(result, "revoked");
  assertEquals(calls.map((c) => c.url), [APPLE_TOKEN_URL, APPLE_REVOKE_URL]);
  assertEquals(calls[0].body.get("grant_type"), "authorization_code");
  assertEquals(calls[0].body.get("code"), "auth-code");
  assertEquals(calls[0].body.get("client_id"), "app.petmama.mamaharitasi");
  assert((calls[0].body.get("client_secret") ?? "").split(".").length === 3, "client_secret is a JWT");
  assertEquals(calls[1].body.get("token"), "ref");
  assertEquals(calls[1].body.get("token_type_hint"), "refresh_token");
});

Deno.test("revokeAppleTokens: expired or reused code is invalid_code", async () => {
  const { fetch, calls } = fakeFetch({
    [APPLE_TOKEN_URL]: Response.json({ error: "invalid_grant" }, { status: 400 }),
  });
  assertEquals(await revokeAppleTokens("old", await config(), fetch, 1_800_000_000), "invalid_code");
  assertEquals(calls.length, 1, "revoke not attempted");
});

Deno.test("revokeAppleTokens: Apple outage is failed (deletion proceeds, logged)", async () => {
  const { fetch } = fakeFetch({
    [APPLE_TOKEN_URL]: Response.json({ access_token: "acc" }),
    [APPLE_REVOKE_URL]: new Response("oops", { status: 503 }),
  });
  assertEquals(await revokeAppleTokens("c", await config(), fetch, 1_800_000_000), "failed");
});
