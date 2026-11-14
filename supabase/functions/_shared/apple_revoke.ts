// Mama Haritası — Sign in with Apple token iptali (App Store 5.1.1(v): hesap silmede Apple token'ları iptal edilir).
//
// Supabase'in yerel Apple girişi (signInWithIdToken) Apple refresh token'ını saklamaz. Bu yüzden istemci, silmeden
// hemen önce Apple ile yeniden onay alır ve tek kullanımlık `authorizationCode`'u (5 dk geçerli) gönderir:
//   1) POST /auth/token  (grant_type=authorization_code) → refresh_token / access_token
//   2) POST /auth/revoke (token, token_type_hint)
// İstemci sırrı, Sign in with Apple anahtarıyla (.p8) imzalanmış kısa ömürlü ES256 JWT'dir.
//
// Gerekli sırlar: APPLE_TEAM_ID, APPLE_SIWA_KEY_ID, APPLE_SIWA_PRIVATE_KEY (.p8 PEM), APPLE_CLIENT_ID (bundle id).

import { base64url, pemToDer } from "./push_logic.ts";

export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_AUDIENCE = "https://appleid.apple.com";
const CLIENT_SECRET_TTL_SECONDS = 300;

export interface AppleRevokeConfig {
  teamId: string;
  keyId: string;
  privateKeyPem: string;
  clientId: string;
}

/** Sırlardan biri eksikse `null` (iptal atlanır ve loglanır). */
export function appleRevokeConfig(env: (key: string) => string | undefined): AppleRevokeConfig | null {
  const teamId = env("APPLE_TEAM_ID");
  const keyId = env("APPLE_SIWA_KEY_ID");
  const privateKeyPem = env("APPLE_SIWA_PRIVATE_KEY");
  const clientId = env("APPLE_CLIENT_ID");
  if (!teamId || !keyId || !privateKeyPem || !clientId) return null;
  return { teamId, keyId, privateKeyPem, clientId };
}

/** Supabase kullanıcısı Apple ile mi bağlı? */
export function isAppleUser(
  user: { identities?: { provider?: string }[] | null; app_metadata?: { provider?: string } | null } | null,
): boolean {
  if (!user) return false;
  return (user.identities ?? []).some((i) => i.provider === "apple") || user.app_metadata?.provider === "apple";
}

/** Apple istemci sırrı: header {alg: ES256, kid}, payload {iss, iat, exp, aud, sub}. */
export async function buildAppleClientSecret(opts: AppleRevokeConfig & { issuedAt: number }): Promise<string> {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: opts.keyId }));
  const payload = base64url(JSON.stringify({
    iss: opts.teamId,
    iat: opts.issuedAt,
    exp: opts.issuedAt + CLIENT_SECRET_TTL_SECONDS,
    aud: APPLE_AUDIENCE,
    sub: opts.clientId,
  }));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(opts.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)),
  );
  return `${signingInput}.${base64url(sig)}`;
}

/**
 * revoked      : Apple token'ı iptal edildi
 * invalid_code : kod geçersiz / süresi dolmuş / kullanılmış (istemci yeniden onay almalı)
 * failed       : Apple'a ulaşılamadı veya beklenmeyen yanıt (silme devam eder, loglanır)
 */
export type AppleRevokeResult = "revoked" | "invalid_code" | "failed";

export async function revokeAppleTokens(
  authorizationCode: string,
  config: AppleRevokeConfig,
  fetchFn: typeof fetch,
  nowSeconds: number,
): Promise<AppleRevokeResult> {
  const clientSecret = await buildAppleClientSecret({ ...config, issuedAt: nowSeconds });
  const form = { "content-type": "application/x-www-form-urlencoded" };

  const tokenRes = await fetchFn(APPLE_TOKEN_URL, {
    method: "POST",
    headers: form,
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: clientSecret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }).toString(),
  });
  let tokens: { refresh_token?: string; access_token?: string; error?: string } = {};
  try {
    tokens = await tokenRes.json();
  } catch {
    tokens = {};
  }
  if (tokenRes.status === 400 && tokens.error === "invalid_grant") return "invalid_code";
  if (!tokenRes.ok) return "failed";

  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) return "failed";
  const revokeRes = await fetchFn(APPLE_REVOKE_URL, {
    method: "POST",
    headers: form,
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: clientSecret,
      token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }).toString(),
  });
  await revokeRes.body?.cancel();
  return revokeRes.ok ? "revoked" : "failed";
}
