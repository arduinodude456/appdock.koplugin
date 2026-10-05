# AppDock 7.4.0 — Colorful Calm

Dieses Release optimiert AppDock für farbige und monochrome E-Ink-Geräte und führt eine ruhigere, visuell reichere Oberfläche ein.

## Änderungen

- **Keine Animationen für Apps und Recently-used-Drawer auf E-Ink**
  - Homescreen-Seiten wechseln direkt in den Zielzustand.
  - Der untere Drawer öffnet und schließt ohne Slide-Animation.
  - Dadurch entstehen weniger Zwischenbilder, weniger Ghosting und eine schnellere Bedienreaktion.
- **Echte farbige Rasterlogos**
  - Zehn KI-generierte PNG-Logos für AppDock, Browser, AppStore, Files, Settings, Help, Clock, Network, Display und Notes.
  - Die Logos werden als echte Rasterbilder skaliert und auf Geräten ohne Bildasset automatisch durch die bisherigen gezeichneten Fallback-Symbole ersetzt.
- **Neuer Lockscreen**
  - KI-generierter Paper-Cut-Hintergrund mit großzügiger heller Mitte.
  - Neue schwarze Statuskarte mit Uhrzeit und Datum.
  - Klarere Profilkarte, stärkere Konturen und besser lesbare PIN-, Pattern- und Swipe-Zustände.
  - Der Hintergrund bleibt auf monochromen E-Ink-Geräten durch starke Hell-Dunkel-Flächen lesbar.
- **Dokumentation aktualisiert**
  - Die integrierte Hilfe beschreibt nun direkte, animationsfreie E-Ink-Wechsel.

## Technisch geprüft

- Alle 21 Lua-Dateien erfolgreich geparst.
- `git diff --check` ohne Befund.
- Alle 10 Logo-PNGs und der Lockscreen-Hintergrund verifiziert.
