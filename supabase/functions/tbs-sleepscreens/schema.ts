// Declarative Sleep-Screen package validation shared by the Edge Function and
// its tests.  This module deliberately has no database or Storage dependency.

export const MAX_ELEMENTS = 32;
export const MAX_CUSTOM_WIDGETS = 16;
export const MAX_WIDGET_FRAMES = 12;
export const MAX_ASSETS = 12;
export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;
export const MAX_FONT_BYTES = 1 * 1024 * 1024;
export const MAX_TOTAL_ASSET_BYTES = 6 * 1024 * 1024;
export const MAX_PACKAGE_BYTES = 9 * 1024 * 1024;

const ASSET_ID = /^[A-Za-z0-9_-]{1,64}$/;
const HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;
const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const CONTROL_KEY = /^(?:__proto__|prototype|constructor)$/i;
const URL_OR_ABSOLUTE_PATH = /(?:https?:\/\/|file:\/\/|(?:^|\s)\/[A-Za-z0-9_.~%+\-\/]+)/i;
const TEXT_TOKENS = /\{(?:time|date|battery|device|sleeping)\}/g;

export type AssetKind = "image" | "font";
export type AssetExtension = "png" | "jpg" | "jpeg" | "webp" | "ttf" | "otf";

export interface AssetDescriptor {
  id: string;
  kind: AssetKind;
  extension: AssetExtension;
}

export interface SleepElement {
  type: "text" | "card" | "widget" | "image";
  x: number;
  y: number;
  w: number;
  h: number;
  text?: string;
  font?: "cfont" | "infofont" | "smallinfofont" | `asset:${string}`;
  font_size?: number;
  color?: string;
  background?: string;
  background_alpha?: number;
  bold?: boolean;
  align?: "left" | "center" | "right";
  source?: "clock" | "date" | "battery" | "device";
  widget_id?: string;
  images?: string[];
  fit?: "contain" | "cover";
}

export interface SleepDefinition {
  schema_version: 1;
  name: string;
  description: string;
  background: string;
  elements: SleepElement[];
  assets: AssetDescriptor[];
  widgets: CustomWidget[];
}

export interface CustomWidget {
  id: string;
  name: string;
  text: string;
  frames?: { text: string; duration: number }[];
  schedule?: { from: string; to: string; text: string }[];
}

export interface ValidatedPackage {
  definition: SleepDefinition;
  // Decoded bytes never go into Postgres; callers upload them to private Storage.
  assets: Map<string, Uint8Array>;
}

export class PackageValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PackageValidationError";
  }
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function hasOnlySafeKeys(value: unknown, depth = 0): boolean {
  if (depth > 12) return false;
  if (Array.isArray(value)) return value.every((child) => hasOnlySafeKeys(child, depth + 1));
  const object = record(value);
  if (!object) return true;
  return Object.entries(object).every(([key, child]) => !CONTROL_KEY.test(key) && hasOnlySafeKeys(child, depth + 1));
}

function cleanText(value: unknown, maximum: number, label: string, required = false, multiline = false): string {
  if (value === undefined && !required) return "";
  if (typeof value !== "string") throw new PackageValidationError(required ? `${label} is required.` : `${label} is invalid.`);
  const text = multiline ? value.replace(/\r\n?/g, "\n") : value.trim();
  const controls = multiline ? /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/ : /[\u0000-\u001f\u007f]/;
  if ((required && text.trim().length === 0) || new TextEncoder().encode(text).length > maximum || controls.test(text)) {
    throw new PackageValidationError(`${label} is invalid.`);
  }
  // A declarative package cannot contain URL or local absolute-path references,
  // even in fields that ultimately render text.  Normal prose with a slash is OK.
  if (URL_OR_ABSOLUTE_PATH.test(text)) throw new PackageValidationError(`${label} must not contain a URL or local path.`);
  return text;
}

function numberInRange(value: unknown, minimum: number, maximum: number, label: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new PackageValidationError(`${label} is invalid.`);
  }
  return value;
}

function optionalColor(value: unknown, label: string): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !HEX_COLOR.test(value)) throw new PackageValidationError(`${label} is invalid.`);
  return value.toUpperCase();
}

function optionalBoolean(value: unknown, label: string): boolean | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "boolean") throw new PackageValidationError(`${label} is invalid.`);
  return value;
}

function exactArray(value: unknown, label: string): unknown[] {
  if (Array.isArray(value)) return value;
  // Lua 5.1/cjson represents an empty table as `{}` unless the producer has a
  // tagged empty-array facility.  v1 permits empty elements/assets, so accept
  // only this unambiguous empty-object spelling and canonicalise it to `[]`.
  const object = record(value);
  if (object && Object.keys(object).length === 0) return [];
  throw new PackageValidationError(`${label} must be a list.`);
}

function normalizeDescriptor(value: unknown): AssetDescriptor {
  const input = record(value);
  if (!input) throw new PackageValidationError("An asset descriptor is invalid.");
  const id = cleanText(input.id, 64, "Asset ID", true);
  if (!ASSET_ID.test(id)) throw new PackageValidationError("Asset ID is invalid.");
  const kind = input.kind;
  const extension = input.extension;
  if (kind !== "image" && kind !== "font") throw new PackageValidationError("Asset kind is invalid.");
  if (extension !== "png" && extension !== "jpg" && extension !== "jpeg" && extension !== "webp" && extension !== "ttf" && extension !== "otf") {
    throw new PackageValidationError("Asset extension is invalid.");
  }
  if ((kind === "image" && !["png", "jpg", "jpeg", "webp"].includes(extension))
    || (kind === "font" && !["ttf", "otf"].includes(extension))) {
    throw new PackageValidationError("Asset kind and extension do not match.");
  }
  return { id, kind, extension };
}

function normalizeElement(value: unknown): SleepElement {
  const input = record(value);
  if (!input) throw new PackageValidationError("An element is invalid.");
  const type = input.type;
  if (type !== "text" && type !== "card" && type !== "widget" && type !== "image") {
    throw new PackageValidationError("Element type is invalid.");
  }
  const x = numberInRange(input.x, 0, 100, "Element x");
  const y = numberInRange(input.y, 0, 100, "Element y");
  const w = numberInRange(input.w, Number.MIN_VALUE, 100, "Element width");
  const h = numberInRange(input.h, Number.MIN_VALUE, 100, "Element height");
  if (x + w > 100 || y + h > 100) throw new PackageValidationError("Element bounds exceed the layout.");

  const element: SleepElement = { type, x, y, w, h };
  if (input.text !== undefined) element.text = cleanText(input.text, 2000, "Element text", false, true);
  if ((type === "text" || type === "card") && element.text === undefined) {
    throw new PackageValidationError("Text and card elements require text.");
  }
  if (input.font !== undefined) {
    if (typeof input.font !== "string" || !(/^(?:cfont|infofont|smallinfofont)$/.test(input.font) || /^asset:[A-Za-z0-9_-]{1,64}$/.test(input.font))) {
      throw new PackageValidationError("Element font is invalid.");
    }
    element.font = input.font as SleepElement["font"];
  }
  if (input.font_size !== undefined) {
    const size = numberInRange(input.font_size, 8, 96, "Font size");
    if (!Number.isInteger(size)) throw new PackageValidationError("Font size is invalid.");
    element.font_size = size;
  }
  const color = optionalColor(input.color, "Element color");
  const background = optionalColor(input.background, "Element background");
  if (color) element.color = color;
  if (background) element.background = background;
  if (input.background_alpha !== undefined) {
    element.background_alpha = numberInRange(input.background_alpha, 0, 1, "Element background opacity");
  }
  const bold = optionalBoolean(input.bold, "Element bold");
  if (bold !== undefined) element.bold = bold;
  if (input.align !== undefined) {
    if (input.align !== "left" && input.align !== "center" && input.align !== "right") throw new PackageValidationError("Element alignment is invalid.");
    element.align = input.align;
  }
  if (input.source !== undefined) {
    if (type !== "widget" || !["clock", "date", "battery", "device"].includes(String(input.source))) {
      throw new PackageValidationError("Widget source is invalid.");
    }
    element.source = input.source as SleepElement["source"];
  }
  if (input.widget_id !== undefined) {
    if (type !== "widget" || typeof input.widget_id !== "string" || !ASSET_ID.test(input.widget_id)) throw new PackageValidationError("Custom widget reference is invalid.");
    element.widget_id = input.widget_id;
  }
  if (type === "widget" && element.source === undefined && element.widget_id === undefined) throw new PackageValidationError("A widget source or custom widget is required.");
  if (input.images !== undefined) {
    if (type !== "image") throw new PackageValidationError("Only image elements may reference images.");
    const images = exactArray(input.images, "Element images");
    if (images.length < 1 || images.length > MAX_ASSETS || images.some((id) => typeof id !== "string" || !ASSET_ID.test(id))) {
      throw new PackageValidationError("Element image references are invalid.");
    }
    if (new Set(images as string[]).size !== images.length) throw new PackageValidationError("Element image references are duplicated.");
    element.images = images as string[];
  }
  if (type === "image" && !element.images) throw new PackageValidationError("An image element requires images.");
  if (input.fit !== undefined) {
    if (type !== "image" || (input.fit !== "contain" && input.fit !== "cover")) throw new PackageValidationError("Image fit is invalid.");
    element.fit = input.fit;
  }
  return element;
}

function normalizeCustomWidget(value: unknown): CustomWidget {
  const input = record(value);
  if (!input || typeof input.id !== "string" || !ASSET_ID.test(input.id) || typeof input.name !== "string" || input.name.length < 1 || input.name.length > 60) {
    throw new PackageValidationError("Custom widget identity is invalid.");
  }
  const text = input.text === undefined ? "" : cleanText(input.text, 2000, "Custom widget text", false, true);
  const widget: CustomWidget = { id: input.id, name: input.name, text };
  if (input.frames !== undefined) {
    const frames = exactArray(input.frames, "Custom widget frames");
    if (frames.length < 1 || frames.length > MAX_WIDGET_FRAMES) throw new PackageValidationError("Custom widget frames are invalid.");
    widget.frames = frames.map((value) => {
      const frame = record(value);
      if (!frame || typeof frame.text !== "string" || frame.text.length > 2000) throw new PackageValidationError("Custom widget frame is invalid.");
      const duration = frame.duration === undefined ? 1 : numberInRange(frame.duration, 1, 60, "Custom widget frame duration");
      if (!Number.isInteger(duration)) throw new PackageValidationError("Custom widget frame duration is invalid.");
      return { text: frame.text, duration };
    });
  }
  if (input.schedule !== undefined) {
    const schedule = exactArray(input.schedule, "Custom widget schedule");
    if (schedule.length > 12) throw new PackageValidationError("Custom widget schedule is invalid.");
    widget.schedule = schedule.map((value) => {
      const rule = record(value);
      if (!rule || typeof rule.from !== "string" || typeof rule.to !== "string" || typeof rule.text !== "string"
        || !/^\d\d:[0-5]\d$/.test(rule.from) || !/^\d\d:[0-5]\d$/.test(rule.to) || Number(rule.from.slice(0, 2)) > 23 || Number(rule.to.slice(0, 2)) > 23) {
        throw new PackageValidationError("Custom widget time rule is invalid.");
      }
      return { from: rule.from, to: rule.to, text: rule.text };
    });
  }
  return widget;
}

export function normalizeDefinition(value: unknown): SleepDefinition {
  if (!hasOnlySafeKeys(value)) throw new PackageValidationError("Control keys are not allowed.");
  const input = record(value);
  if (!input) throw new PackageValidationError("Definition must be an object.");
  if (input.schema_version !== 1) throw new PackageValidationError("Unsupported schema version.");
  const name = cleanText(input.name, 80, "Name", true);
  const description = cleanText(input.description, 500, "Description");
  if (typeof input.background !== "string" || !HEX_COLOR.test(input.background)) throw new PackageValidationError("Background is invalid.");
  const rawElements = exactArray(input.elements, "Elements");
  const rawAssets = exactArray(input.assets, "Assets");
  const rawWidgets = exactArray(input.widgets ?? [], "Widgets");
  if (rawElements.length > MAX_ELEMENTS || rawAssets.length > MAX_ASSETS || rawWidgets.length > MAX_CUSTOM_WIDGETS) throw new PackageValidationError("The preset exceeds its element, widget, or asset limit.");
  const elements = rawElements.map(normalizeElement);
  const assets = rawAssets.map(normalizeDescriptor);
  const widgets = rawWidgets.map(normalizeCustomWidget);
  if (new Set(widgets.map((widget) => widget.id)).size !== widgets.length) throw new PackageValidationError("Custom widget IDs must be unique.");
  const widgetIds = new Set(widgets.map((widget) => widget.id));
  for (const element of elements) if (element.widget_id && !widgetIds.has(element.widget_id)) throw new PackageValidationError("A custom widget reference is missing.");
  if (new Set(assets.map((asset) => asset.id)).size !== assets.length) throw new PackageValidationError("Asset IDs must be unique.");

  const descriptors = new Map(assets.map((asset) => [asset.id, asset]));
  const referenced = new Set<string>();
  for (const element of elements) {
    if (element.font?.startsWith("asset:")) {
      const id = element.font.slice("asset:".length);
      if (descriptors.get(id)?.kind !== "font") throw new PackageValidationError("A font reference is missing or has the wrong kind.");
      referenced.add(id);
    }
    for (const id of element.images ?? []) {
      if (descriptors.get(id)?.kind !== "image") throw new PackageValidationError("An image reference is missing or has the wrong kind.");
      referenced.add(id);
    }
  }
  if (referenced.size !== assets.length) throw new PackageValidationError("Every declared asset must be referenced.");

  // Unknown declarative fields are intentionally not copied into the canonical
  // document.  This implements the v1 forward-compatibility contract safely.
  return { schema_version: 1, name, description, background: input.background.toUpperCase(), elements, assets, widgets };
}

function decodeBase64(value: unknown, id: string): Uint8Array {
  if (typeof value !== "string" || value.length === 0 || value.length > Math.ceil(MAX_IMAGE_BYTES * 4 / 3) + 8 || !BASE64.test(value)) {
    throw new PackageValidationError(`Asset ${id} is not valid base64.`);
  }
  try {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
    return bytes;
  } catch {
    throw new PackageValidationError(`Asset ${id} is not valid base64.`);
  }
}

function ascii(bytes: Uint8Array, start: number, length: number): string {
  if (bytes.length < start + length) return "";
  return String.fromCharCode(...bytes.slice(start, start + length));
}

export function hasExpectedSignature(bytes: Uint8Array, descriptor: AssetDescriptor): boolean {
  if (descriptor.extension === "png") return bytes.length >= 8 && ascii(bytes, 0, 8) === "\x89PNG\r\n\x1a\n";
  if (descriptor.extension === "jpg" || descriptor.extension === "jpeg") return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (descriptor.extension === "webp") return bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP";
  if (descriptor.extension === "ttf") {
    const tag = ascii(bytes, 0, 4);
    return tag === "\x00\x01\x00\x00" || tag === "true" || tag === "typ1";
  }
  return descriptor.extension === "otf" && ascii(bytes, 0, 4) === "OTTO";
}

export function mimeFor(descriptor: AssetDescriptor): string {
  switch (descriptor.extension) {
    case "png": return "image/png";
    case "jpg": case "jpeg": return "image/jpeg";
    case "webp": return "image/webp";
    case "ttf": return "font/ttf";
    case "otf": return "font/otf";
  }
}

export function encodedByteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

export function validatePackage(value: unknown): ValidatedPackage {
  if (!hasOnlySafeKeys(value)) throw new PackageValidationError("Control keys are not allowed.");
  if (encodedByteLength(value) > MAX_PACKAGE_BYTES) throw new PackageValidationError("The package is too large.");
  const input = record(value);
  if (!input) throw new PackageValidationError("Package must be an object.");
  const definition = normalizeDefinition(input.definition);
  const encodedAssets = record(input.assets);
  if (!encodedAssets) throw new PackageValidationError("Package assets must be an object.");
  const expectedIds = new Set(definition.assets.map((asset) => asset.id));
  const givenIds = Object.keys(encodedAssets);
  if (givenIds.length !== expectedIds.size || givenIds.some((id) => !expectedIds.has(id))) {
    throw new PackageValidationError("Package assets do not match the definition.");
  }

  const assets = new Map<string, Uint8Array>();
  let total = 0;
  for (const descriptor of definition.assets) {
    const bytes = decodeBase64(encodedAssets[descriptor.id], descriptor.id);
    const perAssetLimit = descriptor.kind === "image" ? MAX_IMAGE_BYTES : MAX_FONT_BYTES;
    if (bytes.byteLength === 0 || bytes.byteLength > perAssetLimit || !hasExpectedSignature(bytes, descriptor)) {
      throw new PackageValidationError(`Asset ${descriptor.id} is invalid.`);
    }
    total += bytes.byteLength;
    if (total > MAX_TOTAL_ASSET_BYTES) throw new PackageValidationError("Assets exceed the total size limit.");
    assets.set(descriptor.id, bytes);
  }
  return { definition, assets };
}

export function encodeBase64(bytes: Uint8Array): string {
  // Chunking avoids argument-count limits for package downloads near 6 MiB.
  const chunks: string[] = [];
  for (let index = 0; index < bytes.length; index += 0x8000) {
    chunks.push(String.fromCharCode(...bytes.subarray(index, Math.min(index + 0x8000, bytes.length))));
  }
  return btoa(chunks.join(""));
}

export const _test = { cleanText, hasOnlySafeKeys, TEXT_TOKENS };
