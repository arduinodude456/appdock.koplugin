# AppDock 2.6.0 — Settings-based arrangement

AppDock 2.6.0 refines the app and Store widget arrangement experience.

## One simple entry in Settings

Open the integrated **Settings** DApp and select **Arrange apps & widgets**. One compact dialog contains the pinned app list followed by the installed Store widget list. Each row provides only the necessary **↑** and **↓** actions plus a position counter. **Done** closes the editor.

## A simpler long-press manager

The long-press manager no longer contains arrangement sections or move controls. It is reserved for the short, high-frequency actions of enabling and disabling widgets, adding and removing pinned apps, and managing Store items.

## Persistence and E-Ink behavior

The existing local order remains stored in `G_reader_settings`; no user order is reset. Changes use the existing AppDock rebuild path and do not add network access, timers, background work, drag-and-drop tracking, or a full refresh.

System status and current-book dashboard cards retain their fixed placement. The Settings arrangement dialog controls pinned launcher apps and installed Store widgets.

## Validation

Lua-5.1 syntax, AppDock smoke, DApp, manager, Settings arrangement and existing UI regressions pass. The release should still receive a real-device check for text wrapping and three-button row spacing on small screens.
