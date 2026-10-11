# External sources consulted

- `https://github.com/arduinodude456/DApps` (cloned on 2026-10-11, `81d331d`): catalogue includes five declarative Store designs and `dchat.lua` v1.8.6.
- DuckDuckGo endpoint checks on 2026-10-11:
  - `https://api.duckduckgo.com/?format=json&no_html=1&skip_disambig=1&q=KOReader` returned HTTP 200 but only an Instant Answer payload.
  - `https://html.duckduckgo.com/html/?q=KOReader` returned HTTP 200 and ten `result__a` result links.
  - `https://lite.duckduckgo.com/lite/?q=KOReader` returned HTTP 200 and ten `result-link` result links.

These sources establish that the Instant Answer API is not a full web-search endpoint, while the DuckDuckGo HTML endpoint returns ordinary result pages suitable for the JavaScript-free browser.
