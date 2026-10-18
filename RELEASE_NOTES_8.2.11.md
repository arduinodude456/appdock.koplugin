# AppDock 8.2.11

## Dialog-Akzentfarbe auf RGB-Geräten

Primäre Aktionen werden wieder sichtbar in Olivgrün hervorgehoben und erhalten kontrastreiche weiße Beschriftung. Der Dialogrenderer verwendet KOReaders `paintRectRGB32` für RGB-Füllungen; deaktivierte und sekundäre Aktionen bleiben klar unterscheidbar.

## Absturz beim Aktivieren von Wetter behoben

Der Sleepscreen-Widget-Editor überschattete beim Neuaufbau nach dem Einschalten von Open-Meteo eine Übersetzungsfunktion mit einer Schleifenvariable. Die Variable ist umbenannt; ein UI-Regressionstest aktiviert den Wetter-Schalter und prüft, dass die Wetterfelder ohne Absturz erscheinen.

## Prüfung

Dialog- und Wetter-UI-Regressionstests sowie die vollständige Sleepscreen-Testreihe laufen erfolgreich. Die optionalen serverseitigen Deno-Tests sind nur verfügbar, wenn Deno installiert ist.
