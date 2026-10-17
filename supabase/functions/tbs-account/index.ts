// Supabase Edge Function: tbs-account
//
// Deploy in the same Supabase project as DChat DM:
//   supabase functions deploy tbs-account --no-verify-jwt
//
// Required function secrets are provided automatically by Supabase for hosted
// functions. For local development set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
// The reader only receives the project's publishable key plus an opaque account
// ID/device secret pair. It never receives a service-role key.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "apikey, authorization, content-type, x-client-info, x-tbs-account-id, x-tbs-device-id, x-tbs-device-secret",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

const MAX_STATE_BYTES = 128 * 1024;
const MAX_PERSONALIZATION_BYTES = 32 * 1024;
const ACCOUNT_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEVICE_ID_PATTERN = /^tbs_[A-Za-z0-9_-]{16,80}$/;
const DEVICE_SECRET_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

function reply(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: corsHeaders });
}

function fail(message: string, status = 400): Response {
  return reply({ error: { message } }, status);
}

function cleanText(value: unknown, maximum: number): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/[\u0000-\u001f\u007f]/g, "").slice(0, maximum);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function byteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).length;
}

function randomHex(bytes: number): string {
  const values = new Uint8Array(bytes);
  crypto.getRandomValues(values);
  return [...values].map((value) => value.toString(16).padStart(2, "0")).join("");
}

function randomBase64Url(bytes: number): string {
  const values = new Uint8Array(bytes);
  crypto.getRandomValues(values);
  let binary = "";
  for (const value of values) binary += String.fromCharCode(value);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, "0")).join("");
}

function formatRecoveryCode(hex: string): string {
  const code = hex.toUpperCase();
  return `TBS-${code.slice(0, 8)}-${code.slice(8, 16)}-${code.slice(16, 24)}-${code.slice(24, 32)}`;
}

function normaliseRecoveryCode(value: unknown): string {
  return cleanText(value, 80).toUpperCase().replace(/^TBS[-\s]*/, "").replace(/[^A-F0-9]/g, "");
}

function credentials(request: Request, body: Record<string, unknown>) {
  const accountId = cleanText(request.headers.get("x-tbs-account-id") ?? body.accountId, 80).toLowerCase();
  const deviceId = cleanText(request.headers.get("x-tbs-device-id") ?? body.deviceId, 96);
  const deviceSecret = cleanText(request.headers.get("x-tbs-device-secret") ?? body.deviceSecret, 160);
  if (!ACCOUNT_ID_PATTERN.test(accountId) || !DEVICE_ID_PATTERN.test(deviceId) || !DEVICE_SECRET_PATTERN.test(deviceSecret)) {
    return null;
  }
  return { accountId, deviceId, deviceSecret };
}

async function authenticateDevice(
  db: ReturnType<typeof createClient>,
  request: Request,
  body: Record<string, unknown>,
): Promise<{ accountId: string; deviceId: string } | null> {
  const provided = credentials(request, body);
  if (!provided) return null;
  const deviceSecretHash = await sha256(provided.deviceSecret);
  const { data, error } = await db
    .from("tbs_devices")
    .select("account_id, device_id, revoked_at")
    .eq("account_id", provided.accountId)
    .eq("device_id", provided.deviceId)
    .eq("device_secret_hash", deviceSecretHash)
    .maybeSingle();
  if (error || !data || data.revoked_at) return null;
  await db.from("tbs_devices").update({ last_seen_at: new Date().toISOString() }).eq("account_id", provided.accountId).eq("device_id", provided.deviceId);
  return { accountId: provided.accountId, deviceId: provided.deviceId };
}

function serialiseState(row: Record<string, unknown> | null) {
  return {
    schemaVersion: Number(row?.schema_version ?? 1),
    revision: Number(row?.revision ?? 0),
    state: asRecord(row?.state) ?? {},
    personalization: asRecord(row?.personalization) ?? {},
    updatedAt: typeof row?.updated_at === "string" ? row.updated_at : null,
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return fail("Use POST.", 405);

  let body: Record<string, unknown> | null = null;
  try { body = asRecord(await request.json()); } catch { return fail("Request body must be JSON."); }
  if (!body) return fail("Request body must be an object.");

  const action = cleanText(body.action, 32);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return fail("TBS account service is not configured.", 503);
  const db = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

  if (action === "register") {
    const displayName = cleanText(body.displayName, 80);
    const deviceName = cleanText(body.deviceName, 80) || "AppDock reader";
    if (!displayName) return fail("Enter a display name.");

    const recoveryRaw = randomHex(16);
    const recoveryCode = formatRecoveryCode(recoveryRaw);
    const { data: account, error: accountError } = await db
      .from("tbs_accounts")
      .insert({ display_name: displayName, recovery_code_hash: await sha256(recoveryRaw) })
      .select("id, display_name")
      .single();
    if (accountError || !account) return fail("The account could not be created.", 503);

    const deviceId = `tbs_${randomBase64Url(18)}`;
    const deviceSecret = randomBase64Url(32);
    const { error: deviceError } = await db.from("tbs_devices").insert({
      account_id: account.id,
      device_id: deviceId,
      device_secret_hash: await sha256(deviceSecret),
      device_name: deviceName,
    });
    if (deviceError) {
      await db.from("tbs_accounts").delete().eq("id", account.id);
      return fail("The account device could not be registered.", 503);
    }
    const { error: stateError } = await db.from("tbs_account_state").insert({ account_id: account.id });
    if (stateError) return fail("The account state could not be prepared.", 503);
    return reply({
      accountId: account.id,
      displayName: account.display_name,
      deviceId,
      deviceSecret,
      recoveryCode,
      snapshot: { schemaVersion: 1, revision: 0, state: {}, personalization: {} },
    }, 201);
  }

  if (action === "migrate") {
    const accountId = cleanText(body.accountId, 80).toLowerCase();
    const recoveryRaw = normaliseRecoveryCode(body.recoveryCode);
    const deviceName = cleanText(body.deviceName, 80) || "AppDock reader";
    if (!ACCOUNT_ID_PATTERN.test(accountId) || !/^[A-F0-9]{32}$/.test(recoveryRaw)) {
      return fail("Check the account ID and recovery code.", 401);
    }
    const { data: account, error } = await db.from("tbs_accounts").select("id, display_name, recovery_code_hash").eq("id", accountId).maybeSingle();
    if (error || !account || account.recovery_code_hash !== await sha256(recoveryRaw.toLowerCase())) {
      return fail("Check the account ID and recovery code.", 401);
    }
    const deviceId = `tbs_${randomBase64Url(18)}`;
    const deviceSecret = randomBase64Url(32);
    const { error: deviceError } = await db.from("tbs_devices").insert({
      account_id: account.id,
      device_id: deviceId,
      device_secret_hash: await sha256(deviceSecret),
      device_name: deviceName,
    });
    if (deviceError) return fail("The new reader could not be linked.", 503);
    const { data: state } = await db.from("tbs_account_state").select("schema_version, revision, state, personalization, updated_at").eq("account_id", account.id).maybeSingle();
    return reply({ accountId: account.id, displayName: account.display_name, deviceId, deviceSecret, snapshot: serialiseState(state) });
  }

  const identity = await authenticateDevice(db, request, body);
  if (!identity) return fail("TBS account authentication failed.", 401);

  if (action === "state") {
    const { data, error } = await db.from("tbs_account_state").select("schema_version, revision, state, personalization, updated_at").eq("account_id", identity.accountId).maybeSingle();
    if (error) return fail("The TBS account state could not be read.", 503);
    return reply({ snapshot: serialiseState(data) });
  }

  if (action === "sync") {
    const state = asRecord(body.state);
    const personalization = asRecord(body.personalization) ?? {};
    const schemaVersion = Number(body.schemaVersion);
    const expectedRevision = Number(body.expectedRevision);
    if (!state || !Number.isInteger(schemaVersion) || schemaVersion < 1 || schemaVersion > 1000 || !Number.isInteger(expectedRevision) || expectedRevision < 0) {
      return fail("The account state is invalid.");
    }
    if (byteLength(state) > MAX_STATE_BYTES || byteLength(personalization) > MAX_PERSONALIZATION_BYTES) {
      return fail("The account state is too large.", 413);
    }
    // The revision condition is part of the UPDATE itself. This is an atomic
    // compare-and-swap, so two readers cannot both overwrite revision N.
    const { data, error } = await db.from("tbs_account_state").update({
      schema_version: schemaVersion,
      revision: expectedRevision + 1,
      state,
      personalization,
    }).eq("account_id", identity.accountId).eq("revision", expectedRevision)
      .select("schema_version, revision, state, personalization, updated_at").maybeSingle();
    if (error) return fail("The account state could not be saved.", 503);
    if (!data) {
      const { data: latest } = await db.from("tbs_account_state").select("schema_version, revision, state, personalization, updated_at").eq("account_id", identity.accountId).maybeSingle();
      return reply({ error: { message: "A newer account state exists.", code: "revision_conflict" }, snapshot: serialiseState(latest) }, 409);
    }
    return reply({ snapshot: serialiseState(data) });
  }

  return fail("Unknown TBS account action.");
});
