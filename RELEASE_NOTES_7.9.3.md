# AppDock 7.9.3 — Stabilität und Bedienbarkeit

## Fehlerkorrekturen

- Das Page-Key-Hold-Verhalten aus **7.8.51** bleibt erhalten. Powerdialog und Screensaver werden erst im nächsten UI-Zyklus geöffnet, nachdem KOReader den aktuellen Hardware-Tastenwiederholungs-Callback abgeschlossen hat. Dialog und Screensaver verbrauchen verbleibende Wiederholungen der gehaltenen Taste.
- AppDock-eigene Auswahl-, Eingabe-, Bestätigungs- und Statusdialoge verwenden ihre eigene Tap-Geometrie korrekt. Das beseitigt den Absturz beim Zeichnen eines Dialogs, der entstehen konnte, wenn KOReader eine GestureRange-Callbackfunktion als Geometrie behandelte. AppDock-WLAN-Statusmeldungen bleiben im eigenen Overlay.
- Draw startet auch auf Geräten, deren Screen-API `getSize()` statt `getWidth()`/`getHeight()` anbietet. Außerdem folgen Canvas und Werkzeug-Buttons mit ihren Touch-Bereichen jetzt den tatsächlichen Bildschirmkoordinaten.
- Die fehlerhafte **Draw**-Schnellkachel ist durch **Rotate** ersetzt. Die neue Kachel wechselt die von KOReader unterstützten Bildschirmausrichtungen; vorhandene gespeicherte Draw-Kacheln werden bei der nächsten Konfiguration einmalig in eine Rotate-Kachel umgewandelt.

## Prüfung

Alle 12 Lua-Regressionsdateien liefen erfolgreich. Die Tests enthalten jetzt gezielte Prüfungen für den echten Draw-DApp-Hoststart, getSize-only-Geräte, absolute Touch-Geometrie, eigene Dialogaktionen und Tastatureingabe, die Migration der Kachel sowie den `SetRotationMode`-Event. Alle Lua-Quelldateien lassen sich mit LuaJIT kompilieren; `git diff --check` ist sauber.
