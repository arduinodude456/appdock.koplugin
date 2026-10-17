import { assertEquals } from "jsr:@std/assert@1";
import { handler } from "./index.ts";

Deno.test("handler answers CORS preflight without database or environment access", async () => {
  const response = await handler(new Request("https://example.test/functions/v1/tbs-sleepscreens", { method: "OPTIONS" }));
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("access-control-allow-methods"), "POST, OPTIONS");
});

Deno.test("handler rejects non-POST and unknown actions before service initialisation", async () => {
  const methodResponse = await handler(new Request("https://example.test/functions/v1/tbs-sleepscreens", { method: "GET" }));
  assertEquals(methodResponse.status, 405);

  const actionResponse = await handler(new Request("https://example.test/functions/v1/tbs-sleepscreens", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "register", deviceSecret: "must never be accepted here" }),
  }));
  assertEquals(actionResponse.status, 400);
  assertEquals((await actionResponse.json()).error.message, "Unknown Sleep-Screen action.");
});

Deno.test("handler rejects requests over the 9 MiB wire bound before parsing or service access", async () => {
  const response = await handler(new Request("https://example.test/functions/v1/tbs-sleepscreens", {
    method: "POST",
    headers: { "content-type": "application/json", "content-length": String(9 * 1024 * 1024 + 1) },
    body: "{}",
  }));
  assertEquals(response.status, 413);
});
