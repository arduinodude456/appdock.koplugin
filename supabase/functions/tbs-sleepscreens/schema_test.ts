import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  MAX_PACKAGE_BYTES,
  PackageValidationError,
  normalizeDefinition,
  validatePackage,
} from "./schema.ts";

const PNG_MAGIC_BASE64 = "iVBORw0KGgo=";

function validPackage(): any {
  return {
    definition: {
      schema_version: 1,
      name: "Paper clock",
      description: "A quiet public preview",
      background: "#fefefe",
      elements: [{
        type: "image", x: 0, y: 0, w: 100, h: 100,
        images: ["cover"], fit: "cover", ignored_by_v1: "dropped",
      }],
      assets: [{ id: "cover", kind: "image", extension: "png", unknown: true }],
      future_root_property: { never: "persisted" },
    },
    assets: { cover: PNG_MAGIC_BASE64 },
  };
}

Deno.test("canonical package strips unknown declarative fields without dropping real assets", () => {
  const packageValue = validatePackage(validPackage());
  assertEquals(packageValue.definition.background, "#FEFEFE");
  assertEquals(packageValue.definition.elements[0].images, ["cover"]);
  assertEquals((packageValue.definition.elements[0] as any).ignored_by_v1, undefined);
  assertEquals((packageValue.definition as unknown as Record<string, unknown>).future_root_property, undefined);
  assertEquals(packageValue.assets.get("cover")?.byteLength, 8);
});

Deno.test("empty Lua-cjson definition tables canonicalise to empty lists", () => {
  const definition = normalizeDefinition({
    schema_version: 1,
    name: "Blank",
    description: "",
    background: "#FFFFFF",
    elements: {},
    assets: {},
  });
  assertEquals(definition.elements, []);
  assertEquals(definition.assets, []);
  assertEquals(validatePackage({ definition, assets: {} }).assets.size, 0);
});

Deno.test("validator rejects paths, prototype/control keys, unused entries and invalid image headers", () => {
  const pathPackage = validPackage();
  pathPackage.definition.elements[0].text = "file:///mnt/onboard/private.png";
  assertThrows(() => validatePackage(pathPackage), PackageValidationError);

  const controlPackage = JSON.parse(JSON.stringify(validPackage()));
  controlPackage.definition.__proto__ = "poison";
  assertThrows(() => validatePackage(controlPackage), PackageValidationError);

  const unused = validPackage();
  unused.definition.assets.push({ id: "unused", kind: "image", extension: "png" });
  unused.assets.unused = PNG_MAGIC_BASE64;
  assertThrows(() => validatePackage(unused), PackageValidationError);

  const badHeader = validPackage();
  badHeader.assets.cover = "bm90IGEgcG5n";
  assertThrows(() => validatePackage(badHeader), PackageValidationError);
});

Deno.test("validator enforces v1 geometry and the 9 MiB package ceiling", () => {
  const outside = validPackage();
  outside.definition.elements[0].w = 101;
  assertThrows(() => validatePackage(outside), PackageValidationError);
  assert(MAX_PACKAGE_BYTES === 9 * 1024 * 1024);
});

Deno.test("reader text/card/widget packages support multiline text and matching UTF-8 limits", () => {
  const definition = {
    schema_version: 1, name: "Reader draft", description: "", background: "#FFFFFF",
    assets: {}, elements: [
      { type: "text", x: 8, y: 8, w: 84, h: 16, text: "Hello", font: "cfont", font_size: 20, color: "#000000", background: "#FFFFFF", align: "left", bold: false },
      { type: "card", x: 8, y: 30, w: 84, h: 24, text: "Battery: {battery}\nSleeping", font_size: 20 },
      { type: "widget", x: 8, y: 60, w: 84, h: 24, source: "clock", font_size: 20 },
    ],
  };
  assertEquals(validatePackage({ definition, assets: {} }).definition.elements[1].text, "Battery: {battery}\nSleeping");
  assertThrows(() => normalizeDefinition({ ...definition, name: "ä".repeat(41) }), PackageValidationError);
  assertThrows(() => normalizeDefinition({ ...definition, elements: [{ type: "card", x: 0, y: 0, w: 100, h: 20 }] }), PackageValidationError);
});
