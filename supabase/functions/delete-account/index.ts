// Mama Haritası — delete-account (PRD 9.5)
//
// İstemci kendi oturum JWT'si ile çağırır: POST /functions/v1/delete-account, Authorization: Bearer <access_token>
// 1) JWT doğrulanır (gateway verify_jwt + auth.getUser ile kullanıcı hâlâ var mı)
// 1b) Apple ile bağlı hesapta: gövdedeki `apple_authorization_code` ile Apple token'ı iptal edilir
//     (App Store 5.1.1(v)). Kod yoksa / geçersizse 400 apple_reauth_required (istemci yeniden Apple onayı alır).
//     Apple'a ulaşılamazsa silme yine yapılır (kullanıcının silme hakkı önce gelir), hata loglanır.
//     Sırlar: APPLE_TEAM_ID, APPLE_SIWA_KEY_ID, APPLE_SIWA_PRIVATE_KEY, APPLE_CLIENT_ID (_shared/apple_revoke.ts).
// 2) photos/{uid}/... storage klasörü silinir
// 3) auth.admin.deleteUser(uid) — FK'lar kişisel tabloları siler (cascade), nokta/hayvan/check-in/ihtiyaç
//    kayıtları created_by/user_id = null ile anonim kalır; trigger o klasöre işaret eden foto URL'lerini temizler.
//
// Kullanıcı id'si asla istek gövdesinden alınmaz.

import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import { chunk, collectStoragePaths } from "../_shared/storage_paths.ts";
import { appleRevokeConfig, isAppleUser, revokeAppleTokens } from "../_shared/apple_revoke.ts";

const BUCKET = "photos";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, DELETE, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST" && req.method !== "DELETE") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return json({ error: "server_misconfigured" }, 500);

  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return json({ error: "unauthorized" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const uid = userData?.user?.id;
  if (userError || !uid) return json({ error: "unauthorized" }, 401);

  // 1b) Apple token iptali
  if (isAppleUser(userData.user)) {
    let code = "";
    try {
      const body = (await req.json()) as { apple_authorization_code?: unknown };
      if (typeof body?.apple_authorization_code === "string") code = body.apple_authorization_code.trim();
    } catch {
      code = "";
    }
    if (!code) return json({ error: "apple_reauth_required" }, 400);
    const config = appleRevokeConfig((k) => Deno.env.get(k));
    if (!config) {
      console.error("delete-account: Apple revoke secrets are not configured; token not revoked");
    } else {
      const result = await revokeAppleTokens(code, config, fetch, Math.floor(Date.now() / 1000));
      if (result === "invalid_code") return json({ error: "apple_reauth_required" }, 400);
      if (result === "failed") console.error("delete-account: Apple token revoke failed; continuing with deletion");
    }
  }

  // 2) storage klasörü
  let removed = 0;
  try {
    const storage = admin.storage.from(BUCKET);
    const paths = await collectStoragePaths(async (prefix, limit, offset) => {
      const { data, error } = await storage.list(prefix, { limit, offset, sortBy: { column: "name", order: "asc" } });
      if (error) throw error;
      return (data ?? []).map((o) => ({ name: o.name, id: o.id ?? null }));
    }, uid);
    for (const part of chunk(paths, 100)) {
      const { error } = await storage.remove(part);
      if (error) throw error;
      removed += part.length;
    }
  } catch (e) {
    console.error("delete-account: storage cleanup failed", (e as Error).message);
    return json({ error: "storage_cleanup_failed" }, 500);
  }

  // 3) kullanıcı (kişisel veriler FK cascade ile)
  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("delete-account: deleteUser failed", deleteError.message);
    return json({ error: "delete_failed" }, 500);
  }

  return json({ status: "deleted", removed_files: removed });
});
