// Mama Haritası — push-dispatch
//
// Tetikleyici: pg_cron her dakika (private.invoke_push_dispatch → pg_net) veya elle.
// Yetki: `Authorization: Bearer <service_role key>` VEYA `x-dispatch-secret: <PUSH_DISPATCH_SECRET>`.
//        config.toml'da verify_jwt = false; kontrol burada yapılır.
//
// Akış: push_claim_batch (FOR UPDATE SKIP LOCKED, pushed_at doldurulur) → kurallar (_shared/push_logic.ts)
//       → APNs HTTP/2 → push_complete (push_status) → push_drop_tokens (410 / BadDeviceToken).
// Sessiz saat ve günlük limit: push GÖNDERİLMEZ, ertelenmez; bildirim uygulama içinde kalır
// (push_status = quiet_hours | daily_cap). Günlük limit yalnızca need_food_nearby içindir.
// Payload: kind, notification_id, spot_id, need_id, post_id (Mahalle bildirimleri → paylaşım açılır).
//
// Gerekli sırlar: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (.p8 PEM), APNS_BUNDLE_ID, PUSH_DISPATCH_SECRET.
// APNs ortamı (sandbox | production) token başına `device_tokens.apns_env`'den gelir; APNS_ENV kullanılmaz.
// Supabase otomatik sağlar: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import {
  APNS_JWT_TTL_SECONDS,
  apnsJobs,
  buildApnsHeaders,
  buildApnsJwt,
  buildApnsPayload,
  classifyApnsResponse,
  decidePushes,
  groupByStatus,
  isDispatchAuthorized,
  type PushRow,
} from "../_shared/push_logic.ts";

const BATCH_SIZE = 200;
const CONCURRENCY = 8;

let cachedJwt: { token: string; issuedAt: number } | null = null;

async function providerToken(nowSeconds: number): Promise<string> {
  if (cachedJwt && nowSeconds - cachedJwt.issuedAt < APNS_JWT_TTL_SECONDS) return cachedJwt.token;
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKeyPem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !privateKeyPem) throw new Error("APNs secrets are not configured");
  const token = await buildApnsJwt({ keyId, teamId, privateKeyPem, issuedAt: nowSeconds });
  cachedJwt = { token, issuedAt: nowSeconds };
  return token;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i]);
    }
  });
  await Promise.all(workers);
  return results;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!isDispatchAuthorized(req.headers, { serviceRoleKey, dispatchSecret: Deno.env.get("PUSH_DISPATCH_SECRET") })) {
    return json({ error: "unauthorized" }, 401);
  }
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "server_misconfigured" }, 500);

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await db.rpc("push_claim_batch", { p_limit: BATCH_SIZE });
  if (error) return json({ error: "claim_failed", detail: error.message }, 500);
  const rows = (data ?? []) as PushRow[];
  if (rows.length === 0) return json({ status: "ok", claimed: 0 });

  const now = new Date();
  const nowSeconds = Math.floor(now.getTime() / 1000);
  const decisions = decidePushes(rows, now);
  const final = new Map<string, string>();
  const dropTokens = new Set<string>();
  const toSend = rows.filter((r) => decisions.get(r.id) === "send");
  for (const r of rows) if (decisions.get(r.id) !== "send") final.set(r.id, decisions.get(r.id)!);

  if (toSend.length > 0) {
    const bundleId = Deno.env.get("APNS_BUNDLE_ID");
    let jwt: string | null = null;
    try {
      if (!bundleId) throw new Error("APNS_BUNDLE_ID is not configured");
      jwt = await providerToken(nowSeconds);
    } catch (e) {
      console.error("push-dispatch: APNs not configured:", (e as Error).message);
    }

    if (!jwt || !bundleId) {
      for (const r of toSend) final.set(r.id, "failed");
    } else {
      const jobs = toSend.flatMap((row) => apnsJobs(row).map(({ token, origin }) => ({ row, token, origin })));
      const outcomes = await mapLimit(jobs, CONCURRENCY, async ({ row, token, origin }) => {
        try {
          // Deno fetch, https üzerinde ALPN ile HTTP/2 kullanır (APNs yalnızca HTTP/2 kabul eder)
          const res = await fetch(`${origin}/3/device/${encodeURIComponent(token)}`, {
            method: "POST",
            headers: buildApnsHeaders(jwt!, bundleId, row, nowSeconds),
            body: JSON.stringify(buildApnsPayload(row)),
          });
          let reason: string | null = null;
          if (res.status !== 200) {
            try {
              reason = ((await res.json()) as { reason?: string }).reason ?? null;
            } catch {
              reason = null;
            }
          } else {
            await res.body?.cancel();
          }
          if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") cachedJwt = null;
          return { row, token, outcome: classifyApnsResponse(res.status, reason), status: res.status, reason };
        } catch (e) {
          return { row, token, outcome: "error" as const, status: 0, reason: (e as Error).message };
        }
      });

      const sentRows = new Set<string>();
      for (const o of outcomes) {
        if (o.outcome === "ok") sentRows.add(o.row.id);
        if (o.outcome === "drop_token") dropTokens.add(o.token);
        if (o.outcome === "error") console.warn("push-dispatch: APNs error", o.status, o.reason);
      }
      for (const r of toSend) final.set(r.id, sentRows.has(r.id) ? "sent" : "failed");
    }
  }

  const summary: Record<string, number> = {};
  for (const [status, ids] of groupByStatus(final.entries())) {
    summary[status] = ids.length;
    const { error: e } = await db.rpc("push_complete", { p_ids: ids, p_status: status });
    if (e) console.error("push-dispatch: push_complete failed", status, e.message);
  }
  if (dropTokens.size > 0) {
    const { error: e } = await db.rpc("push_drop_tokens", { p_tokens: [...dropTokens] });
    if (e) console.error("push-dispatch: push_drop_tokens failed", e.message);
  }

  return json({ status: "ok", claimed: rows.length, results: summary, dropped_tokens: dropTokens.size });
});
