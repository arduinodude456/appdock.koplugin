# AppDock 6.2.0 — Flat Grid Editor

The App Grid editor has been rewritten as a deliberately flat AppDock surface. It uses one stable `InputContainer`, one rounded outer frame, static text rows and direct `GestureRange` touch regions.

The editor no longer uses the custom popup UI, nested switch widgets, popup reconstruction, delayed callbacks, negative-size layout elements or per-row native controls. Tapping a row directly changes the corresponding AppDock state and marks the editor for redraw.

This is the minimal drawing and touch path requested for Android/eInk stability.
