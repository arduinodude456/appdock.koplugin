# AppDock 8.2.18 — Crash beim Scrollen öffentlicher Sleepscreens behoben

## Änderung

Der öffentliche Sleepscreen-Katalog registriert seinen `ScrollableContainer` jetzt korrekt als `cropping_widget` am aktiven KOReader-DApp-Host. Dadurch werden Repaints von Preview-, Renderer- und Bild-Widgets während des Scrollens auf den sichtbaren Katalogbereich begrenzt, statt an den gesamten Host weitergeleitet zu werden.

Beim Verlassen der Sleepscreen-Kategorie wird der veraltete Crop-Marker entfernt. Ein UI-Regressionstest prüft sowohl die Katalog- als auch die Host-Verknüpfung.

## Prüfung

Die Lua-Syntaxprüfung sowie die Sleepscreen-/AppStore-Regressionstests laufen erfolgreich. Serverseitige Deno-Tests wurden in der Sandbox nicht ausgeführt, da Deno dort nicht installiert ist.
