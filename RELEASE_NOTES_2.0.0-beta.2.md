# AppDock 2.0.0-beta.2

This is the second AppDock 2.0.0 pre-release for real-device testing. It is not the final stable 2.0.0 release.

## New in beta.2

- Added a two-choice AppDock UI language setting: German or English. KOReader's official language API is used and a restart is requested when the choice changes.
- Added an optional `Open AppDock on startup` setting. When enabled, AppDock opens on the next KOReader startup through the normal UI event loop.
- Fixed the Library launcher path by scheduling a UI refresh after the KOReader file manager is opened.
- Retained the beta.1 Storage category, launcher spacing presets, Rounded Box / Circle logo shapes, and optional app search.
- Added a safe fallback around the storage scan so an unavailable data directory cannot crash the Settings DApp.

## Hardware test focus

Please test both language choices and restart KOReader after changing the language. Test the startup option with it enabled and disabled. Open Library from the AppDock homescreen and verify that the file manager is visibly redrawn. Also retest Storage, launcher layout, app search, widgets, app launch, return to homescreen, and both monochrome and color-capable devices where available.

## Deliberately excluded

The requested Splitscreen bug fix is not included in beta.2. DReader 2.0 and its additional file-format support are also not included. Both remain planned for a later, separately tested change.
