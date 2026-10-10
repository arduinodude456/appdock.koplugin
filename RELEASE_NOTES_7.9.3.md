# AppDock 7.9.3 — Stabilität bei gehaltenen Blättertasten

## Fehlerkorrektur

- Das Page-Key-Hold-Verhalten aus **7.8.51** bleibt erhalten. Der Powerdialog beziehungsweise der Screensaver wird jetzt erst im nächsten UI-Zyklus geöffnet, nachdem KOReader den aktuellen Hardware-Tastenwiederholungs-Callback abgeschlossen hat.
- Ein AppDock-Dialog oder der animierte Screensaver verbraucht weitere Wiederholungen der Taste, die den Hold ausgelöst hat. So wird während eines laufenden Holds kein zweiter UI-Wechsel in einem neu aufgebauten Widget-Baum ausgelöst.

## Prüfung

Alle 11 Lua-Regressionsdateien liefen erfolgreich. Sämtliche AppDock-Lua-Quelldateien ließen sich mit LuaJIT kompilieren; `git diff --check` meldete keine Formatfehler.
