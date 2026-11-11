# AppDock 9.1.3 — Quick Settings Mutex Crash Fix

AppDock 9.1.3 entfernt den nativen Backdrop-Puffer aus Quick Settings. Auf bestimmten Android-/KOReader-Geräten konnte dessen Lebenszyklus mit einer noch ausstehenden UI-Neuzeichnung kollidieren und einen nativen `pthread_mutex_lock`-Fehler auf einem bereits zerstörten Mutex auslösen. Quick Settings verwendet weiterhin die Glass-Kacheln und Slider, zeichnet aber keinen zusätzlichen Backdrop-Blitbuffer mehr.
