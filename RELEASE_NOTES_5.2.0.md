# AppDock 5.2.0 — HTML Reader

AppDock 5.2.0 substantially improves the JavaScript-free Web Browser parser and its E-Ink reading layout.

## Better server-rendered pages

- A readable base stylesheet now covers hierarchical headings, ordered and unordered lists, quotations, definition lists, figures, captions, rules, highlights, and structured details blocks.
- `main`, `article`, `details`, `summary`, and line-break elements are normalized into compact, readable browser structures before MuPDF receives the document.
- Lazy-loaded images using `data-src`, `data-original`, `data-lazy-src`, `srcset`, or `data-srcset` can be normalized into the existing bounded local image-cache workflow.
- Existing table, image, HTTP(S)-link, and direct Google-result-card rendering remains in place.

## Stronger safe parsing

- The rendered document removes comments, document declarations, heads, scripts, frames, templates, embedded objects, metadata, base URLs, document forms, remote stylesheet tags, and inline event handlers.
- Unsafe `javascript:` links and `data:` image sources are removed before rendering.
- Inline styles are limited by the existing CSS filter; external resource loads, imports, fonts, expressions, legacy behavior, fixed overlays, and invisible-content declarations are removed.
- Simple safe GET forms remain exposed only through the existing native AppDock input action; active website forms are not embedded in the renderer.

## Verification

The update was checked with Lua 5.1 syntax validation, a byte-identical root/package browser mirror, rich nested HTML parser regression tests, lazy-image normalization tests, active-content rejection tests, existing CSS/form/table/Google-link tests, the AppDock core regression suite, archive validation, and a fresh public download/SHA-256 verification.
