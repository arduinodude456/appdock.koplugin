# AppDock 4.0.2 „Bueno“

This patch repairs the remaining central mistake in the 4.0 Plugin-in-DApp Beta: opening a plugin tile created an AppDock host but left the user on a passive action list, even when the original KOReader plugin had exactly one primary action that normally starts immediately.

## Direct single-action plugin start

After an AppDock plugin-host session is fully constructed, AppDock now checks its published main-menu actions. When there is exactly one action, it invokes that action on KOReader’s next UI cycle. The host has already been registered in **Open apps** at that point, so it remains a non-splittable AppDock session while the plugin opens its own UI.

| Real plugin | 4.0.2 behavior |
|---|---|
| **Text editor** | Its sole dynamic root menu opens immediately. The local TouchMenu adapter then supports the plugin’s `item_table`, `page`, and `updateItems()` lifecycle for settings, file history, and the return from editing. |
| **AppStore.koplugin** | Its sole direct callback runs immediately after the host opens, starting the AppStore browser without requiring a second AppDock tap. |

## Boundaries retained

Plugin hosts remain excluded from split screen at every entry point. A plugin with multiple published actions still opens an explicit AppDock action list; AppDock does not guess which action to run. AppDock also does not rewrite third-party widgets into panes: `buildAppDockPane(context)` remains the opt-in contract for a true local plugin-owned pane.

## Verification

The regression suite now covers the complete host-open-to-action path for a real Text editor-style dynamic root menu and for an AppStore-style direct callback, in addition to the previous dynamic-menu, notification, Open Apps, lifecycle, and split-screen checks. The complete Lua 5.1 syntax and existing AppDock test suite passed.
