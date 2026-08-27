# AppDock 5.0.0 — Antigravity

AppDock 5.0.0 is a feature release focused on clearer settings, more reliable reading and browsing, and a small local programming environment.

## Settings and DApp controls

- App search, black outlines, and the night-mode background-image option are now regular settings rather than Beta-labelled features.
- Beta features now include a validated manual launcher spacing input from 8 to 34 pixels and optional custom local image logos for non-DApp plugin tiles.
- Every DApp host now has a compact Control Center entry in its top bar. Quick Settings can therefore be opened while one or two DApps are visible.
- The Home, Open apps, and Close navigation symbols are raised inside their buttons to prevent baseline overlap on smaller screens.

## Browser and reading

- The Web Browser now combines its readable base styling with bounded, sanitized inline CSS and up to three safe external HTTP(S) stylesheets. Resource-loading CSS features, imports, fonts, and script-like CSS are removed.
- Simple `GET` forms with one text, search, or email field are available through a native AppDock input dialog. POST, JavaScript-driven, multipart, and active web forms stay disabled.
- HTML tables, captions, headers, and cells receive readable E-Ink borders and spacing.
- DReader 2.2.0 resolves Manga EPUB image resources through safe `../` and root-relative paths, including SVG `image` elements with `href` or `xlink:href`. It allows up to eight bounded images per spine item.

## New Store DApp: DBASIC 1.0.0

DBASIC is a fully local, deliberately limited BASIC editor and interpreter. It supports numbered programs; variables; expressions; `PRINT`; assignments; `IF … THEN`; `GOTO`; `FOR … NEXT`; and the graphics and touch commands `CLS`, `COLOR`, `PSET`, `LINE`, `RECT`, and `ON TOUCH GOTO`.

DBASIC does not execute Lua, access files or the network, run shell commands, accept dynamic code, or perform unbounded execution. Program size, output, variables, loop nesting, graphics instructions, and execution steps are all limited.

## Verification

The release was checked with Lua 5.1 syntax validation, byte-identical source/package mirrors, AppDock host/settings and Simple Mode regression checks, Browser CSS/form/table checks, DReader Manga EPUB fixture checks, DBASIC interpreter safety tests, archive validation, and a fresh public download/SHA-256 verification.
