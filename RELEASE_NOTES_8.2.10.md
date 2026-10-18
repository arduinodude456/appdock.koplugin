# AppDock 8.2.10

## AppDock-Dialoge im modernen Frostglas-Stil

Alle AppDock-eigenen Auswahl-, Bestätigungs-, Eingabe- und Infodialoge erhalten zentral abgerundete Flächen und Schaltflächen, Olivgrün als Akzent sowie eine leicht durchscheinende Frostglas-Überlagerung. Beschriftungen werden automatisch umbrochen; Buttons wachsen mit mehrzeiligen Texten. Wo KOReaders Renderer keine Alpha-Komposition unterstützt, bleibt ein kontrastreicher E‑Ink-Fallback aktiv. Eine echte Hintergrundunschärfe ist geräteabhängig und wird nicht von allen KOReader-Blitbuffern angeboten.

## Custom Widgets im Sleepscreen-Editor

Custom Widgets lassen sich im Editor auswählen, bearbeiten und direkt mit einer Sleepscreen-Ebene verbinden. Vorlagen unterstützen Uhrzeit, Datum, Akkustand, Gerät, Animationen, Zeitregeln und Wetter-Platzhalter. Open-Meteo kann ohne API-Schlüssel manuell für konfigurierbare Koordinaten abgefragt werden. Der Wetter-Cache wird lokal im Preset gespeichert; Renderer und Suspend-Pfad führen keine Netzwerkanfrage aus. Vor dem öffentlichen Teilen werden Wetterkoordinaten und Cachewerte in der Veröffentlichungsbestätigung offengelegt.

## Prüfung

Dialog-Regressionstests sowie die vollständige Sleepscreen-/AppStore-Testreihe laufen erfolgreich. Serverseitige Deno-Tests wurden mangels Deno-Laufzeit nicht ausgeführt.
