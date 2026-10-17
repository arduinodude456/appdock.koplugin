# AppDock 8.2.1

A small bug-fix release for the Sleep-Screen catalog and editor.

- Fixes the AppStore Sleepscreens tab when KOReader's Lua module search path points at other plugins.
- Fixes the Settings → Other → Sleepscreen editor crash caused by failing to resolve AppDock's local preset and editor modules.
- Adds regression coverage that runs the catalog and editor with unrelated plugin paths in `package.path`.
