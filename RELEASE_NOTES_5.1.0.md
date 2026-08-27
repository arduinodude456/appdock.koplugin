# AppDock 5.1.0 — Google Search

AppDock 5.1.0 improves the Web Browser with a direct Google-search path designed for the JavaScript-free, E-Ink-focused browser engine.

## Direct Google search

- The browser home and toolbar now include a **Google** action.
- A query is URL-encoded and sent directly to `google.com/search` using a normal HTTP(S) GET request. AppDock does not use a search API or intermediate results service.
- When Google returns readable result markup, AppDock extracts up to ten external result links and renders compact E-Ink cards containing the title and destination address.
- Google redirect links are resolved to their original HTTP(S) targets before navigation.

## Transparent service limits

Google can respond with a JavaScript request, CAPTCHA, or verification page for server-rendered browser requests. AppDock detects these responses and explains the limitation in the browser instead of attempting to bypass Google protection. The existing direct DuckDuckGo HTML search code remains available internally as a fallback path.

## Verification

The release was checked with Lua 5.1 syntax validation, a byte-identical root/package browser mirror, direct Google URL and redirect tests, result-card rendering tests, verification-page detection tests, existing Browser CSS/form/table tests, the AppDock core regression suite, archive validation, and a fresh public download/SHA-256 verification.
