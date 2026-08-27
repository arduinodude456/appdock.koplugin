# AppDock 6.0.4 „Continuity“

## Sichtbare Kompaktgeometrie

Dieses Release korrigiert den Umstand, dass 6.0.3 vor allem den **inneren Abstand zwischen Textzeilen** reduziert hat, während die sichtbaren Containerhöhen nahezu gleich blieben. AppDock 6.0.4 verkleinert deshalb zusätzlich die tatsächlichen Reihen-, Karten-, Header- und Außenabstände der normalen Standardoberfläche. Die sichere unpolsterte Glyphenmessung aus 6.0.2 bleibt unverändert aktiv.

| Oberfläche | Sichtbare Verdichtung |
|---|---|
| Settings | Kategorien werden maximal 58 statt 70 Einheiten hoch; Standardreihen maximal 50 statt 62 Einheiten. Der Abstand zwischen Reihen sinkt von 8 auf 4 Einheiten. |
| Open Apps | Standardkarten werden 64 statt 82 Einheiten hoch, die Liste verwendet 6 statt 14 Einheiten Abstand und einen deutlich kleineren Header. |
| Kontrollzentrum | Im normalen Modus sinken Header, Kacheln, Slider-Abstände und Außenränder; große Standardkacheln werden 68 statt 82 Einheiten hoch. |
| Homescreen | Header, Suchleiste, Infokarten, App-Labelbereiche, Reihenabstände und der Freiraum vor dem App-Raster werden sichtbar reduziert. |
| AppStore | Header, Aktionsflächen, Filter und Katalogkarten werden kompakter; Katalogkarten sind 58 statt 68 Einheiten hoch. |
| Files | Dateireihen sind 54 statt 64 Einheiten hoch und der Listenabstand ist reduziert. |

Die Änderungen betreffen die **wirklich gerenderten Rechtecke und deren Platzierung**, nicht nur einen unsichtbaren Textmesswert. Touchbereiche bleiben an ihre sichtbaren Flächen gekoppelt, und die bestehende Einpassung verhindert weiter Überläufe.

## Simple Mode

Der **Simple Mode bleibt unverändert**. Sein 4×3-Raster, seine Labels, die reduzierte Kontrollzentrale und seine eigenen Abstände verwenden weiterhin ihren bestehenden separaten Aufbau.

## Qualitätssicherung

Die Lua-5.1-Regression prüft die kleineren sichtbaren Settings-, Open-Apps-, Kontrollzentrum-, AppStore-, Homescreen- und Fileswerte sowie die unveränderte Simple-Mode-Geometrie. DApp- und Browser-Suiten, Root-/Paketspiegel und formale Diff-Prüfungen werden vor dem Release ausgeführt.

> **Hardware-Nachtest:** Nach vollständigem KOReader-Neustart müssen die Zeilen und Karten auf Settings, Homescreen, AppStore und Kontrollzentrum sichtbar dichter stehen. Texte dürfen weder kollidieren noch über ihre Flächen ragen.
