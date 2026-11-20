# AppDock 9.11.0

## Fixes
- **Settings:** the DockAI category was missing from the sidebar (it was defined but not part of any sidebar group). It now appears between Lockscreen and Storage.

## Performance
- New built-in profiler (`appdock_prof.lua`). It logs every slow step to `appdock_perf.log` in the KOReader data directory: loading of each AppDock module, homescreen build and page change, opening a DApp (pane build per DApp), dropdown, open apps and every screen repaint. Create an empty file `appdock_noprofile` in the data directory to disable it.
