# AppDock 6.1.2 — Popup Paint Crash Fix

AppDock 6.1.2 fixes an additional crash in the custom popup rendering path. Popup widgets now pass the active blitbuffer correctly to KOReader's input-container paint routine while still using AppDock-owned coordinates.

This prevents invalid native rendering state during App Grid editing and popup refresh. The stable switch widgets and synchronous callback changes from 6.1.1 remain included.
