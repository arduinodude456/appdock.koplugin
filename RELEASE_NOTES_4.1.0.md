# AppDock 4.1.0 „Bueno"

AppDock 4.1.0 expands the JavaScript-free **Web Browser** DApp with safe rendering for static images in server-rendered HTML pages.

## Static image rendering

The browser now discovers `img` elements, resolves relative and protocol-relative sources against the current page, and fetches supported HTTP(S) images into a controlled temporary local cache. The rendered HTML is rewritten to reference only generated local filenames, and KOReader’s `ScrollHtmlWidget` receives that cache as its resource directory. MuPDF can therefore render local image resources without receiving arbitrary network or device paths from the original document.

Supported formats are PNG, JPEG, GIF and WebP when the server declares an `image/*` response and a supported raster type. CSS constrains rendered images to the readable width of the Browser pane.

## Safety and E-Ink limits

| Boundary | Limit |
|---|---|
| Per page | At most 8 images and 5 MiB of total image bytes. |
| Per image | At most 1.5 MiB, using the existing request timeout and redirect limit. |
| Sources | HTTP(S), relative, and protocol-relative sources only. `data:`, `javascript:`, local paths, SVG, active media, and unsupported response types are excluded. |
| Fallback | Unavailable, oversized, blocked, or unsupported images are rendered as safe Alt text so the article remains readable. |
| Lifecycle | Image files are removed on page replacement, Home, and closing the Web Browser DApp. |

JavaScript, WebSockets, forms, downloads, embedded media, and arbitrary local file access remain unavailable. This continues to be a reading-oriented browser rather than a full web platform.

## Verification

Regression coverage verifies relative and protocol-relative image URLs, local resource rewriting, cache handoff to `ScrollHtmlWidget`, `data:` rejection, cleanup on Home and session close, plus existing navigation, redirect, search, and HTML-sanitization behavior. The full Lua 5.1 syntax check and complete AppDock regression suite passed.
