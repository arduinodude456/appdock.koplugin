# AppDock 2.1.0

## Local notifications

AppDock now includes a local, persistent notification inbox. DApps can create an E-Ink-friendly notification through the new `context.notify(payload)` contract. A valid payload requires `title` and `message`; it may also set `priority` to `normal` or `high` and optionally provide a source label.

Notifications are saved through AppDock's existing settings persistence, limited to 50 entries, and survive KOReader restarts. Invalid or empty payloads are rejected. AppDock limits titles to 72 characters and messages to 240 characters.

## Pop-ups and Quick Settings

Each valid notification requests a small non-animated toast at the bottom of the screen. The toast uses ordinary `ui` refreshes and closes after four seconds or on tap. It does not request a full E-Ink refresh and it starts no background service.

Quick Settings now contains a Notifications section with an unread counter, recent inbox entries, per-entry read state, **Read all**, and **Clear all**. Tapping an unread entry marks it read. On very small Quick Settings panes the inbox is intentionally omitted to keep Wi-Fi, night mode, refresh, edit, and brightness controls fully visible; the inbox remains available on normal reader layouts.

## Developer support

`DeveloperManual.md` documents `context.notify(payload)`, payload limits, source behavior, and the E-Ink-safe usage rule: notify only about a real result or error, never on every repaint or page change.

## Validation

Lua 5.1 syntax checks passed for all AppDock modules. Core, DApp, Quick Settings, File Manager, theme/AppStore, persistence, toast request, unread counter, mark-read, clear-all, normal layout, and compact-layout regressions passed.
