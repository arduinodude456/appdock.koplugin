# AppDock 6.0.10 — Native Dialogs Restored

This release rolls back the experimental custom dialog and Grid Editor changes. AppDock again uses KOReader's standard `ButtonDialog`, `InputDialog` and `InfoMessage` implementations for dialog flows.

Only the AppDock-owned Quick Settings tiles were enhanced. Wi-Fi, Night Mode and Power Saving now display a compact Android-like switch surface inside the existing stable `QuickTile`/`FixedStack` rendering path. No new popup layer, dialog replacement or custom Grid Editor is included.

The original AppDock and VideoPlayer plugin baselines are restored before this focused Quick Settings change.
