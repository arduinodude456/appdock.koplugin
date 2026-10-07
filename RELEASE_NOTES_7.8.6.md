# AppDock 7.8.6

## Deutsch

### Blättertasten und Framebuffer-Stabilität

- Die Helligkeitsanzeige wird nach einem Blättertasten-Ereignis erst im nächsten KOReader-UI-Zyklus aufgebaut.
- Dadurch wird ein Race Condition zwischen physischer Tastaturverarbeitung und Framebuffer-Neuzeichnung vermieden, die auf manchen Geräten den Fehler `framebuffer.lua: attempt to index a nil value` auslösen konnte.
- Der native Helligkeitswechsel bleibt erhalten; ein temporär nicht verfügbarer Framebuffer kann die Tastaturaktion nicht mehr zum Absturz bringen.
- Aufbau und Ausblenden der Anzeige sind zusätzlich defensiv abgesichert.

### Qualitätssicherung

- Lua-Syntax aller Plugin-Dateien geprüft.
- Keyboard-, AppStore-, Browser-, DApp-, Ordering- und Setup-Assistant-Regressionstests erfolgreich ausgeführt.

## English

### Page keys and framebuffer stability

- The brightness indicator is now rebuilt in the next KOReader UI cycle after a page-key event.
- This avoids a race between physical-key processing and framebuffer repainting that could cause `framebuffer.lua: attempt to index a nil value` on some devices.
- Native brightness changes remain available; a temporarily unavailable framebuffer can no longer crash the key action.
- Showing and hiding the indicator are additionally guarded defensively.

### Quality assurance

- Lua syntax checked for all plugin files.
- Keyboard, AppStore, Browser, DApp, ordering, and setup-assistant regression tests pass.
