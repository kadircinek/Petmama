// Mama Haritası — push-dispatch saf mantığı (ağ/DB yok; Deno ve Node 22'de test edilebilir).
//
// Kurallar (docs/backend-contract.md "Edge Functions"):
//  * Sessiz saat: kullanıcının quiet_start–quiet_end aralığı, Europe/Istanbul saatine göre.
//    quiet_start == quiet_end → sessiz saat kapalı. Aralık gece yarısını aşabilir (22–7).
//  * need_food_nearby için İstanbul günü başına en fazla 3 push. Limit YALNIZCA bu tür içindir;
//    Mahalle bildirimleri (community_comment, cover_volunteered) sessiz saate uyar ama limite takılmaz.
//  * Uygulanmayan (sessiz saat / limit / token yok) bildirimler ERTELENMEZ; uygulama içinde kalır,
//    push_status ile işaretlenir.

export const ISTANBUL_TZ = "Europe/Istanbul";
export const NEED_FOOD_DAILY_CAP = 3;
/** APNs sağlayıcı token'ı en fazla 60 dk geçerli; 20 dk'dan sık yenilemek de yasak. */
export const APNS_JWT_TTL_SECONDS = 50 * 60;

export type NotificationKind =
  | "need_food_nearby"
  | "followed_spot_changed"
  | "guardian_spot_unfed"
  | "need_resolved"
  | "thanks_fed"
  | "donation_delivered"
  | "community_comment"
  | "cover_volunteered";

/** `push_claim_batch` RPC'sinin döndürdüğü satır. */
export interface PushRow {
  id: string;
  user_id: string;
  kind: NotificationKind;
  title: string;
  body: string;
  spot_id: string | null;
  need_id: string | null;
  /** Mahalle bildirimlerinde (community_comment, cover_volunteered) dolu; uygulama paylaşımı açar. */
  post_id: string | null;
  created_at: string;
  quiet_start: number;
  quiet_end: number;
  need_food_pushed_today: number;
  /** production APNs token'ları (TestFlight / App Store). */
  tokens: string[];
  /** sandbox APNs token'ları (Xcode'dan kurulan Debug derlemeleri). */
  sandbox_tokens: string[];
}

export type Decision = "send" | "quiet_hours" | "daily_cap" | "no_token";

/** İstanbul'daki saat (0–23) ve gün (YYYY-MM-DD). */
export function istanbulClock(date: Date): { day: string; hour: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: ISTANBUL_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return { day: `${get("year")}-${get("month")}-${get("day")}`, hour: Number(get("hour")) % 24 };
}

/** [start, end) sessiz mi? Gece yarısını aşan aralıkları destekler; start == end → kapalı. */
export function isQuietHour(hour: number, start: number, end: number): boolean {
  if (start === end) return false;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}

/**
 * Bir partideki her satır için karar verir. Satırlar created_at sırasıyla değerlendirilir;
 * günlük need_food_nearby sayacı DB'deki bugünkü gönderimlerle başlar ve partide gönderildikçe artar.
 */
export function decidePushes(rows: PushRow[], now: Date): Map<string, Decision> {
  const { hour } = istanbulClock(now);
  const sentToday = new Map<string, number>();
  const decisions = new Map<string, Decision>();
  const ordered = [...rows].sort((a, b) =>
    a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : a.id.localeCompare(b.id)
  );

  for (const row of ordered) {
    if (!sentToday.has(row.user_id)) sentToday.set(row.user_id, row.need_food_pushed_today ?? 0);

    let decision: Decision;
    if ((row.tokens?.length ?? 0) + (row.sandbox_tokens?.length ?? 0) === 0) {
      decision = "no_token";
    } else if (isQuietHour(hour, row.quiet_start ?? 22, row.quiet_end ?? 7)) {
      decision = "quiet_hours";
    } else if (row.kind === "need_food_nearby" && (sentToday.get(row.user_id) ?? 0) >= NEED_FOOD_DAILY_CAP) {
      decision = "daily_cap";
    } else {
      decision = "send";
      if (row.kind === "need_food_nearby") sentToday.set(row.user_id, (sentToday.get(row.user_id) ?? 0) + 1);
    }
    decisions.set(row.id, decision);
  }
  return decisions;
}

// ---------------------------------------------------------------------------
// APNs (HTTP/2, token tabanlı kimlik doğrulama)
// ---------------------------------------------------------------------------

export function apnsOrigin(env: string | undefined): string {
  return env === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
}

/** Her token kendi ortamının APNs adresine gider (token ortamı `device_tokens.apns_env`). */
export function apnsJobs(row: PushRow): { token: string; origin: string }[] {
  return [
    ...(row.tokens ?? []).map((token) => ({ token, origin: apnsOrigin("production") })),
    ...(row.sandbox_tokens ?? []).map((token) => ({ token, origin: apnsOrigin("sandbox") })),
  ];
}

export function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** .p8 PEM (PKCS#8) → DER. Sırlarda satır sonları "\n" olarak kaçışlanmış olabilir. */
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const b64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  if (!b64) throw new Error("APNS_PRIVATE_KEY is empty");
  const bin = atob(b64);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/**
 * ES256 sağlayıcı token'ı: header {alg: ES256, kid}, payload {iss: teamId, iat}.
 * WebCrypto ECDSA imzası zaten JWS'in beklediği ham r||s (64 bayt) biçimindedir.
 */
export async function buildApnsJwt(opts: {
  keyId: string;
  teamId: string;
  privateKeyPem: string;
  issuedAt: number; // saniye
}): Promise<string> {
  const header = base64url(JSON.stringify({ alg: "ES256", kid: opts.keyId }));
  const payload = base64url(JSON.stringify({ iss: opts.teamId, iat: opts.issuedAt }));
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

export function buildApnsPayload(row: PushRow): Record<string, unknown> {
  return {
    aps: {
      alert: { title: row.title, body: row.body },
      sound: "default",
      // Bildirim Merkezi'nde gruplama: paylaşım > nokta > tür
      "thread-id": row.post_id ?? row.spot_id ?? row.kind,
    },
    kind: row.kind,
    notification_id: row.id,
    spot_id: row.spot_id,
    need_id: row.need_id,
    post_id: row.post_id ?? null,
  };
}

export function buildApnsHeaders(
  jwt: string,
  bundleId: string,
  row: PushRow,
  nowSeconds: number,
): Record<string, string> {
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    "apns-topic": bundleId,
    "apns-push-type": "alert",
    "apns-priority": "10",
    // geç gelen "mama gerekli" anlamsız: 1 saat sonra APNs bırakır
    "apns-expiration": String(nowSeconds + 3600),
    "content-type": "application/json",
  };
  // aynı paylaşım / nokta için art arda gelen bildirimler kilit ekranında tek bildirimde birleşir (≤ 64 bayt)
  const subject = row.post_id ?? row.spot_id;
  if (subject) headers["apns-collapse-id"] = `${row.kind}:${subject}`;
  return headers;
}

export type ApnsOutcome = "ok" | "drop_token" | "error";

/** 410 Unregistered veya 400 BadDeviceToken/DeviceTokenNotForTopic → token silinir. */
export function classifyApnsResponse(status: number, reason?: string | null): ApnsOutcome {
  if (status === 200) return "ok";
  if (status === 410) return "drop_token";
  if (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic")) return "drop_token";
  return "error";
}

// ---------------------------------------------------------------------------
// Yetkilendirme: service-role bearer VEYA x-dispatch-secret
// ---------------------------------------------------------------------------

export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const n = Math.max(ea.length, eb.length);
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

export function isDispatchAuthorized(
  headers: Headers,
  secrets: { serviceRoleKey?: string | null; dispatchSecret?: string | null },
): boolean {
  const bearer = (headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  const shared = (headers.get("x-dispatch-secret") ?? "").trim();
  if (secrets.serviceRoleKey && bearer && timingSafeEqual(bearer, secrets.serviceRoleKey)) return true;
  if (secrets.dispatchSecret && shared && timingSafeEqual(shared, secrets.dispatchSecret)) return true;
  return false;
}

/** Kararları push_complete için durum → id listesine gruplar. */
export function groupByStatus(entries: Iterable<[string, string]>): Map<string, string[]> {
  const out = new Map<string, string[]>();
  for (const [id, status] of entries) {
    const list = out.get(status) ?? [];
    list.push(id);
    out.set(status, list);
  }
  return out;
}
