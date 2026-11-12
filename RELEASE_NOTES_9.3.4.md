# AppDock 9.3.4

## Animation refresh fix

- Discards stale KOReader repaint and refresh queues before the first animation frame.
- Prevents the hidden pre-animation refresh that caused visible E-Ink flicker on the homescreen, dropdowns, and app views.
- Removes the redundant fast refresh when launching an app from the homescreen.
- Keeps the homescreen page transition's single full refresh after the animation completes.
