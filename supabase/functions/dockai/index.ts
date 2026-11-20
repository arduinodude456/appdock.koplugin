import { createClient } from "npm:@supabase/supabase-js@2";
const headers = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "apikey, authorization, content-type, x-client-info, x-tbs-account-id, x-tbs-device-id, x-tbs-device-secret",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};
const DEVICE_ID = /^tbs_[A-Za-z0-9_-]{16,80}$/;
const ACCOUNT_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SECRET = /^[A-Za-z0-9_-]{32,128}$/;
const MODELS = new Set(["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b", "openai/gpt-oss-120b"]);
const reply = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers });
const fail = (message: string, status = 400, code?: string) => reply({ error: { message, ...(code ? { code } : {}) } }, status);
type Obj = Record<string, unknown>;
function record(value: unknown): Obj | null { return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Obj : null; }
function text(value: unknown, max: number): string { return typeof value === "string" ? value.trim().replace(/[\u0000-\u001f\u007f]/g, "").slice(0, max) : ""; }
async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
function b64bytes(value: string): Uint8Array { return Uint8Array.from(atob(value), (c) => c.charCodeAt(0)); }
async function verifyPassword(password: string, encoded: string): Promise<boolean> {
  const [kind, roundsRaw, salt64, expected64] = encoded.split("$");
  const rounds = Number(roundsRaw);
  if (kind !== "pbkdf2_sha256" || !Number.isInteger(rounds) || rounds < 200000 || rounds > 1000000) return false;
  try {
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
    const actual = new Uint8Array(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: b64bytes(salt64), iterations: rounds }, key, 256));
    const expected = b64bytes(expected64);
    return actual.length === expected.length && actual.every((part, i) => part === expected[i]);
  } catch { return false; }
}
async function readJson(request: Request): Promise<Obj | null> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > 96 * 1024) return null;
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      size += value.byteLength;
      if (size > 96 * 1024) { await reader.cancel(); return null; }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return record(JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)));
  } catch { return null; }
}
async function authenticate(db: ReturnType<typeof createClient>, request: Request): Promise<{ accountId: string; deviceId: string } | null> {
  const accountId = text(request.headers.get("x-tbs-account-id"), 80).toLowerCase();
  const deviceId = text(request.headers.get("x-tbs-device-id"), 96);
  const deviceSecret = text(request.headers.get("x-tbs-device-secret"), 160);
  if (!ACCOUNT_ID.test(accountId) || !DEVICE_ID.test(deviceId) || !SECRET.test(deviceSecret)) return null;
  const secretHash = await sha256(deviceSecret);
  const { data, error } = await db.from("tbs_devices").select("account_id, device_id, device_secret_hash, revoked_at")
    .eq("account_id", accountId).eq("device_id", deviceId).maybeSingle();
  if (error || !data || data.revoked_at || data.device_secret_hash !== secretHash) return null;
  await db.from("tbs_devices").update({ last_seen_at: new Date().toISOString() }).eq("device_id", deviceId);
  return { accountId, deviceId };
}
function usagePayload(row: Record<string, unknown>) {
  return { day_used: Number(row.day_used), week_used: Number(row.week_used), day_limit: Number(row.day_limit), week_limit: Number(row.week_limit),
    day_resets_at: Math.floor(new Date(String(row.day_resets_at)).getTime() / 1000),
    week_resets_at: Math.floor(new Date(String(row.week_resets_at)).getTime() / 1000), blocked: row.allowed ? null : row.reason };
}
Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return fail("Use POST.", 405);
  const body = await readJson(request);
  if (!body) return fail("Request must be a JSON object smaller than 96 KB.", 413);
  const url = Deno.env.get("SUPABASE_URL"), serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return fail("DockAI is not configured.", 503);
  const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const identity = await authenticate(db, request);
  if (!identity) return fail("Sign in to a TBS account to use DockAI.", 401, "auth_required");
  const action = text(body.action, 20);
  if (action === "usage") {
    const { data, error } = await db.from("dockai_device_usage").select("day_start, week_start, day_count, week_count").eq("device_id", identity.deviceId).maybeSingle();
    if (error) return fail("Usage is temporarily unavailable.", 503);
    const now = new Date();
    const dayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const mondayStart = new Date(dayStart); mondayStart.setUTCDate(dayStart.getUTCDate() - ((dayStart.getUTCDay() + 6) % 7));
    const dayCount = data?.day_start === dayStart.toISOString().slice(0, 10) ? Number(data.day_count) : 0;
    const weekCount = data?.week_start === mondayStart.toISOString().slice(0, 10) ? Number(data.week_count) : 0;
    return reply({ usage: { day_used: dayCount, week_used: weekCount, day_limit: 25, week_limit: 100, day_resets_at: Math.floor((dayStart.getTime() + 86400000) / 1000), week_resets_at: Math.floor((mondayStart.getTime() + 7 * 86400000) / 1000), blocked: weekCount >= 100 ? "week" : dayCount >= 25 ? "day" : null } });
  }
  if (action === "add_key") {
    const password = text(body.admin_password, 300);
    const key = text(body.api_key, 200);
    if (password.length < 12 || !/^[A-Za-z0-9_.-]{20,200}$/.test(key)) return fail("Admin password or API key is invalid.", 400, "invalid_input");
    const { data: config, error: configError } = await db.from("dockai_admin_config").select("password_hash").eq("singleton", true).maybeSingle();
    if (configError || !config) return fail("Admin verification is unavailable.", 503);
    if (!await verifyPassword(password, String(config.password_hash))) return fail("Admin password is incorrect.", 401, "admin_denied");
    const { error } = await db.from("dockai_api_keys").insert({ api_key: key });
    if (error?.code === "23505") return fail("This API key has already been added.", 409, "duplicate");
    if (error) return fail("The API key could not be saved.", 503);
    return reply({ added: true });
  }
  if (action !== "chat") return fail("Unknown DockAI action.");
  const model = text(body.model, 80);
  if (!MODELS.has(model)) return fail("This model is not allowed.", 400, "model");
  const input = Array.isArray(body.messages) ? body.messages.slice(-20) : [];
  const messages = input.flatMap((message) => {
    const item = record(message);
    if (!item || (item.role !== "user" && item.role !== "assistant") || typeof item.content !== "string") return [];
    const content = item.content.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").slice(0, 12000).trim();
    return content ? [{ role: item.role, content }] : [];
  });
  if (!messages.length || messages[messages.length - 1].role !== "user") return fail("A user message is required.");
  const { data: reserved, error: reserveError } = await db.rpc("dockai_reserve_usage", { p_device_id: identity.deviceId });
  const reservation = Array.isArray(reserved) ? reserved[0] : null;
  if (reserveError || !reservation) return fail("Usage could not be reserved.", 503);
  const usage = usagePayload(reservation);
  if (!reservation.allowed) return reply({ error: { code: "limit", message: "Usage limit reached." }, usage }, 429);
  const requestId = String(reservation.request_id);
  try {
    const { data: keyRows, error: keysError } = await db.from("dockai_api_keys").select("id, api_key").eq("disabled", false).order("id", { ascending: true });
    if (keysError || !keyRows?.length) { await db.rpc("dockai_finish_usage", { p_request_id: requestId, p_success: false }); return fail("DockAI has no active API key.", 503, "no_keys"); }
    let answer = "", lastStatus = 503;
    for (const keyRow of keyRows) {
      const provider = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST", headers: { authorization: `Bearer ${keyRow.api_key}`, "content-type": "application/json" },
        body: JSON.stringify({ model, messages: [{ role: "system", content: "You are DockAI, a helpful assistant inside AppDock on an e-reader. Reply in the user's language, clearly and fairly concisely. Use simple Markdown only when it helps." }, ...messages], temperature: 0.7, max_tokens: 1024 }),
        signal: AbortSignal.timeout(90000),
      });
      lastStatus = provider.status;
      const response = await provider.json().catch(() => null);
      if (provider.ok) { answer = text(response?.choices?.[0]?.message?.content, 16000); if (answer) break; }
      if (provider.status === 401 || provider.status === 403) await db.from("dockai_api_keys").update({ disabled: true }).eq("id", keyRow.id);
      else if (provider.status !== 429 && provider.status < 500) break;
    }
    if (!answer) { await db.rpc("dockai_finish_usage", { p_request_id: requestId, p_success: false }); return fail(lastStatus === 429 ? "Provider is busy; try again soon." : lastStatus === 401 || lastStatus === 403 ? "Provider key is invalid." : "Provider request failed.", lastStatus === 429 ? 503 : 502, "provider"); }
    await db.rpc("dockai_finish_usage", { p_request_id: requestId, p_success: true });
    return reply({ reply: answer, usage });
  } catch {
    await db.rpc("dockai_finish_usage", { p_request_id: requestId, p_success: false });
    return fail("Could not reach the provider.", 502, "network");
  }
});
