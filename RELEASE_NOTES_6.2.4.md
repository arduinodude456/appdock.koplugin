# AppDock 6.2.4 — Safe Keyboard Close and eInk Motion

The AppDock keyboard now disappears after Done through a deferred UI-manager callback, after the touch dispatch has returned. This avoids destroying the active keyboard tree from inside its own Done handler.

AppDock 6.2.4 also adds a small deterministic motion helper for eInk surfaces. The Quick Settings switches animate their thumb across three short frames, and every frame invalidates the active widget with a `fast` refresh. Non-switch Quick Settings taps also receive a fast feedback refresh. The animation is deliberately short and does not modify KOReader standard dialogs.
