# AppDock 9.1.2 — Quick Settings Crash Fix

AppDock 9.1.2 behebt einen Absturz beim Öffnen der Quick Settings. Die Glass-Backdrop-Erzeugung verwendet keine Live-Pixelabfragen mehr, die auf bestimmten KOReader-/Geräte-Blitbuffer-Implementierungen unsicher waren. Stattdessen wird der Bildschirm sicher kopiert und abgedunkelt; falls der Backdrop nicht erzeugt werden kann, öffnet sich das Menü weiterhin ohne Hintergrundbild.
