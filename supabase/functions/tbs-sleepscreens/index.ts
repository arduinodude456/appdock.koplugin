// Supabase Edge Function: tbs-sleepscreens
//
// Deploy only after supabase/migrations/20261017_sleepscreens.sql:
//   supabase functions deploy tbs-sleepscreens --no-verify-jwt
//
// This endpoint deliberately uses the service-role client only after it has
// authenticated a TBS device secret.  Browser/readers receive only a
// publishable project key; Storage has no direct anon/authenticated policy.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  encodeBase64,
  hasExpectedSignature,
  mimeFor,
  normalizeDefinition,
  PackageValidationError,
  type AssetDescriptor,
  type SleepDefinition,
  validatePackage,
} from "./schema.ts";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "apikey, authorization, content-type, x-client-info, x-tbs-account-id, x-tbs-device-id, x-tbs-device-secret",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

const BUCKET = "appdock-sleepscreens";
const MAX_REQUEST_BYTES = 9 * 1024 * 1024;
const MAX_QUERY_LENGTH = 80;
const MAX_LIST_LIMIT = 12;
const MAX_LIST_OFFSET = 10_000;
const ACCOUNT_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEVICE_ID_PATTERN = /^tbs_[A-Za-z0-9_-]{16,80}$/;
const DEVICE_SECRET_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

interface Identity { accountId: string; deviceId: string }
interface PresetRow {
  id: string;
  creator_account_id: string;
  name: string;
  description: string;
  definition: SleepDefinition;
  revision: number;
  published_at: string;
  current_asset_prefix?: string;
  creator?: { id?: string; display_name?: string } | { id?: string; display_name?: string }[] | null;
}

function reply(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: corsHeaders });
}

function fail(message: string, status = 400, code?: string): Response {
  return reply({ error: { message, ...(code ? { code } : {}) } }, status);
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function cleanText(value: unknown, maximum: number): string {
  return typeof value === "string" ? value.trim().replace(/[\u0000-\u001f\u007f]/g, "").slice(0, maximum) : "";
}

function asInteger(value: unknown, fallback: number, minimum: number, maximum: number): number | null {
  if (value === undefined || value === null || value === "") return fallback;
  const number = typeof value === "number" ? value : Number.NaN;
  return Number.isInteger(number) && number >= minimum && number <= maximum ? number : null;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && ACCOUNT_ID_PATTERN.test(value);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((part) => part.toString(16).padStart(2, "0")).join("");
}

async function readBoundedJson(request: Request): Promise<Record<string, unknown> | Response> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_REQUEST_BYTES) return fail("The request is too large.", 413);
  if (!request.body) return fail("Request body must be JSON.");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      length += value.byteLength;
      if (length > MAX_REQUEST_BYTES) {
        await reader.cancel();
        return fail("The request is too large.", 413);
      }
      chunks.push(value);
    }
  } catch {
    return fail("Request body could not be read.");
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  let parsed: unknown;
  try { parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); } catch { return fail("Request body must be JSON."); }
  const body = record(parsed);
  return body ?? fail("Request body must be an object.");
}

function credentials(request: Request): { accountId: string; deviceId: string; deviceSecret: string } | null {
  const accountId = cleanText(request.headers.get("x-tbs-account-id"), 80).toLowerCase();
  const deviceId = cleanText(request.headers.get("x-tbs-device-id"), 96);
  const deviceSecret = cleanText(request.headers.get("x-tbs-device-secret"), 160);
  if (!ACCOUNT_ID_PATTERN.test(accountId) || !DEVICE_ID_PATTERN.test(deviceId) || !DEVICE_SECRET_PATTERN.test(deviceSecret)) return null;
  return { accountId, deviceId, deviceSecret };
}

async function authenticateDevice(db: SupabaseClient, request: Request): Promise<Identity | null> {
  const provided = credentials(request);
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
  // A failed heartbeat must not turn a valid write into an arbitrary 5xx.
  await db.from("tbs_devices").update({ last_seen_at: new Date().toISOString() })
    .eq("account_id", provided.accountId).eq("device_id", provided.deviceId);
  return { accountId: provided.accountId, deviceId: provided.deviceId };
}

function creatorFrom(row: PresetRow): { account_id: string; display_name: string } {
  const relation = Array.isArray(row.creator) ? row.creator[0] : row.creator;
  return {
    account_id: row.creator_account_id,
    display_name: cleanText(relation?.display_name, 80) || "AppDock creator",
  };
}

function entryFrom(row: PresetRow) {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    creator: creatorFrom(row),
    revision: Number(row.revision),
    definition: row.definition,
  };
}

function storagePath(prefix: string, asset: AssetDescriptor): string {
  // prefix comes only from crypto.randomUUID and the SQL transaction; descriptor
  // IDs/extensions have already been canonicalised by validatePackage.
  return `${prefix}/${asset.id}.${asset.extension}`;
}

async function removeUploaded(db: SupabaseClient, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  try { await db.storage.from(BUCKET).remove(paths); } catch { /* best effort orphan cleanup */ }
}

async function uploadAssets(db: SupabaseClient, prefix: string, definition: SleepDefinition, assets: Map<string, Uint8Array>): Promise<string[] | null> {
  const uploaded: string[] = [];
  for (const descriptor of definition.assets) {
    const bytes = assets.get(descriptor.id);
    if (!bytes) { await removeUploaded(db, uploaded); return null; }
    const path = storagePath(prefix, descriptor);
    const { error } = await db.storage.from(BUCKET).upload(
      path,
      // validatePackage creates these bytes from atob, hence the backing buffer
      // is a plain ArrayBuffer (not a SharedArrayBuffer accepted by neither
      // Deno 2's BlobPart type nor Storage's upload overload).
      new Blob([bytes.buffer as ArrayBuffer], { type: mimeFor(descriptor) }),
      { upsert: false, contentType: mimeFor(descriptor), cacheControl: "31536000" },
    );
    if (error) { await removeUploaded(db, uploaded); return null; }
    uploaded.push(path);
  }
  return uploaded;
}

async function assemblePackage(db: SupabaseClient, row: PresetRow): Promise<{ definition: SleepDefinition; assets: Record<string, string> } | null> {
  if (!row.current_asset_prefix || !/^[0-9a-f-]{36}\/[1-9][0-9]*\/[0-9a-f-]{36}$/i.test(row.current_asset_prefix)) return null;
  const assets: Record<string, string> = {};
  let total = 0;
  for (const descriptor of row.definition.assets) {
    const { data, error } = await db.storage.from(BUCKET).download(storagePath(row.current_asset_prefix, descriptor));
    if (error || !data) return null;
    const bytes = new Uint8Array(await data.arrayBuffer());
    const perAssetLimit = descriptor.kind === "image" ? 2 * 1024 * 1024 : 1024 * 1024;
    if (bytes.byteLength === 0 || bytes.byteLength > perAssetLimit || !hasExpectedSignature(bytes, descriptor)) return null;
    total += bytes.byteLength;
    if (total > 6 * 1024 * 1024) return null;
    assets[descriptor.id] = encodeBase64(bytes);
  }
  return { definition: row.definition, assets };
}

function publicPresetSelect(includeAssets = false): string {
  const columns = "id, creator_account_id, name, description, definition, revision, published_at, creator:tbs_accounts!tbs_sleepscreen_presets_creator_account_id_fkey(id,display_name)";
  return includeAssets ? `${columns}, current_asset_prefix` : columns;
}

async function listPresets(db: SupabaseClient, body: Record<string, unknown>): Promise<Response> {
  const offset = asInteger(body.offset, 0, 0, MAX_LIST_OFFSET);
  const limit = asInteger(body.limit, MAX_LIST_LIMIT, 1, MAX_LIST_LIMIT);
  const query = cleanText(body.query, MAX_QUERY_LENGTH);
  if (offset === null || limit === null) return fail("Pagination is invalid.");
  let request = db.from("tbs_sleepscreen_presets").select(publicPresetSelect())
    .is("unpublished_at", null)
    .order("updated_at", { ascending: false })
    .order("id", { ascending: true })
    .range(offset, offset + limit);
  if (query) {
    // Escape PostgREST pattern characters; text has no SQL interpolation.
    const pattern = query.replace(/[%_\\]/g, (part) => `\\${part}`);
    request = request.ilike("name", `%${pattern}%`);
  }
  const { data, error } = await request;
  if (error || !data) return fail("The Sleep-Screen catalog is temporarily unavailable.", 503);
  const rows = data as unknown as PresetRow[];
  return reply({ entries: rows.slice(0, limit).map(entryFrom), has_more: rows.length > limit });
}

async function getPreset(db: SupabaseClient, body: Record<string, unknown>): Promise<Response> {
  const id = cleanText(body.id, 80).toLowerCase();
  if (!isUuid(id)) return fail("Preset ID is invalid.");
  const { data, error } = await db.from("tbs_sleepscreen_presets").select(publicPresetSelect(true))
    .eq("id", id).is("unpublished_at", null).maybeSingle();
  if (error) return fail("The Sleep-Screen could not be loaded.", 503);
  if (!data) return fail("The Sleep-Screen is not available.", 404);
  const row = data as unknown as PresetRow;
  // Rows are server-originated but are revalidated so a database/data migration
  // problem cannot turn into a malformed or unsafe package download.
  let definition: SleepDefinition;
  try { definition = normalizeDefinition(row.definition); } catch { return fail("The Sleep-Screen is temporarily unavailable.", 503); }
  row.definition = definition;
  const packageValue = await assemblePackage(db, row);
  if (!packageValue) return fail("The Sleep-Screen download is temporarily unavailable.", 503);
  return reply({ entry: entryFrom(row), package: packageValue });
}

function rpcEntry(data: unknown): PresetRow | null {
  const row = Array.isArray(data) ? data[0] : null;
  const input = record(row);
  if (!input || input.outcome !== "ok" || !isUuid(input.id) || !isUuid(input.creator_account_id)) return null;
  const definition = record(input.definition) as unknown as SleepDefinition | null;
  if (!definition) return null;
  return {
    id: input.id,
    creator_account_id: input.creator_account_id,
    name: cleanText(input.name, 80),
    description: cleanText(input.description, 500),
    definition,
    revision: Number(input.revision),
    published_at: typeof input.published_at === "string" ? input.published_at : "",
    creator: { id: input.creator_account_id, display_name: cleanText(input.creator_display_name, 80) },
  };
}

function rpcOutcome(data: unknown): string {
  return Array.isArray(data) && record(data[0]) && typeof record(data[0])?.outcome === "string"
    ? record(data[0])?.outcome as string
    : "";
}

function responseForOutcome(outcome: string): Response {
  if (outcome === "forbidden") return fail("You may only change your own Sleep-Screens.", 403);
  if (outcome === "not_found") return fail("The Sleep-Screen is not available.", 404);
  if (outcome === "conflict") return fail("A newer Sleep-Screen revision exists.", 409, "revision_conflict");
  if (outcome === "quota") return fail("This creator has reached the Sleep-Screen limit.", 429, "creator_quota");
  if (outcome === "rate_limited") return fail("Please wait before changing another Sleep-Screen.", 429, "rate_limited");
  return fail("The Sleep-Screen could not be saved.", 503);
}

async function publishPreset(db: SupabaseClient, request: Request, body: Record<string, unknown>): Promise<Response> {
  const identity = await authenticateDevice(db, request);
  if (!identity) return fail("TBS account authentication failed.", 401);
  let packageValue;
  try { packageValue = validatePackage(body.package); } catch (error) {
    return fail(error instanceof PackageValidationError ? error.message : "The package is invalid.");
  }
  const hasId = body.id !== undefined && body.id !== null && body.id !== "";
  const id = hasId ? cleanText(body.id, 80).toLowerCase() : crypto.randomUUID();
  const expectedRevision = hasId ? asInteger(body.expected_revision, -1, 1, Number.MAX_SAFE_INTEGER) : null;
  if (!isUuid(id) || (hasId && expectedRevision === null)) return fail("Preset ID or expected revision is invalid.");
  const nextRevision = hasId ? (expectedRevision as number) + 1 : 1;
  const prefix = `${id}/${nextRevision}/${crypto.randomUUID()}`;
  const uploaded = await uploadAssets(db, prefix, packageValue.definition, packageValue.assets);
  if (!uploaded) return fail("The Sleep-Screen assets could not be stored.", 503);

  const { data, error } = await db.rpc("tbs_publish_sleepscreen", {
    p_creator_account_id: identity.accountId,
    p_preset_id: id,
    p_expected_revision: expectedRevision,
    p_name: packageValue.definition.name,
    p_description: packageValue.definition.description,
    p_definition: packageValue.definition,
    p_asset_prefix: prefix,
    p_creating: !hasId,
  });
  if (error) { await removeUploaded(db, uploaded); return fail("The Sleep-Screen could not be saved.", 503); }
  const entry = rpcEntry(data);
  if (!entry) { await removeUploaded(db, uploaded); return responseForOutcome(rpcOutcome(data)); }
  return reply({ entry: entryFrom(entry) }, hasId ? 200 : 201);
}

async function unpublishPreset(db: SupabaseClient, request: Request, body: Record<string, unknown>): Promise<Response> {
  const identity = await authenticateDevice(db, request);
  if (!identity) return fail("TBS account authentication failed.", 401);
  const id = cleanText(body.id, 80).toLowerCase();
  const expectedRevision = asInteger(body.expected_revision, -1, 1, Number.MAX_SAFE_INTEGER);
  if (!isUuid(id) || expectedRevision === null) return fail("Preset ID or expected revision is invalid.");
  const { data, error } = await db.rpc("tbs_unpublish_sleepscreen", {
    p_creator_account_id: identity.accountId,
    p_preset_id: id,
    p_expected_revision: expectedRevision,
  });
  if (error) return fail("The Sleep-Screen could not be withdrawn.", 503);
  const outcome = rpcOutcome(data);
  if (outcome !== "ok") return responseForOutcome(outcome);
  return reply({ ok: true });
}

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return fail("Use POST.", 405);
  const bodyOrResponse = await readBoundedJson(request);
  if (bodyOrResponse instanceof Response) return bodyOrResponse;
  const action = cleanText(bodyOrResponse.action, 32);
  if (!["list", "get", "publish", "unpublish"].includes(action)) return fail("Unknown Sleep-Screen action.");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return fail("The Sleep-Screen service is not configured.", 503);
  const db = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  if (action === "list") return await listPresets(db, bodyOrResponse);
  if (action === "get") return await getPreset(db, bodyOrResponse);
  if (action === "publish") return await publishPreset(db, request, bodyOrResponse);
  return await unpublishPreset(db, request, bodyOrResponse);
}

if (import.meta.main) Deno.serve(handler);

export const _test = { MAX_REQUEST_BYTES, cleanText, readBoundedJson, storagePath, responseForOutcome };
