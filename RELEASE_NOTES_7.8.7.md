# AppDock 7.8.7

## Deutsch

### Helligkeitsanzeige stabilisiert

- Der Helligkeitsindikator verwendet jetzt einen direkten, garantiert nicht-leeren `FrameContainer` mit einem direkten `VerticalGroup`-Kind.
- Die unnötige Verschachtelung aus `WidgetContainer`, `CenterContainer` und zusätzlichem `FrameContainer` wurde entfernt.
- Dadurch wird der fragile Paint-Pfad beseitigt, der auf manchen Geräten weiterhin den Fehler `framebuffer.lua: attempt to index a nil value` auslösen konnte.
- Die seitliche Prozent- und Balkenanzeige bleibt erhalten.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- Keyboard-, AppStore-, Browser-, DApp-, Ordering- und Setup-Assistant-Regressionstests erfolgreich ausgeführt.

## English

### Brightness indicator stabilized

- The brightness indicator now uses a direct, guaranteed non-empty `FrameContainer` with a direct `VerticalGroup` child.
- The unnecessary `WidgetContainer` → `CenterContainer` → `FrameContainer` nesting has been removed.
- This removes the fragile paint path that could still trigger `framebuffer.lua: attempt to index a nil value` on some devices.
- The side percentage and bar indicator remain available.

### Quality assurance

- Lua syntax checked for all plugin files.
- Keyboard, AppStore, Browser, DApp, ordering, and setup-assistant regression tests pass.
