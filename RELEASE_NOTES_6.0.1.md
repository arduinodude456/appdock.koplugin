# AppDock 6.0.1 „Continuity“

## Textgeometrie-Fix

Dieses Wartungsrelease behebt einen systematischen Fehler der vertikalen Textausrichtung, der besonders auf hochauflösenden E-Ink-Geräten sichtbar wurde. Titel, Untertitel, Symbole und Bedienflächen hatten zuvor teils unabhängig geschätzte Höhen. Dadurch konnten Beschriftungen in Kacheln, Kopfzeilen und Buttons übereinander liegen oder über ihre vorgesehenen Flächen ragen.

AppDock misst nun die tatsächliche Höhe seiner eigenen Textwidgets, bevor mehrzeilige Inhalte platziert werden. Die gemeinsame Berechnung führt sowohl einzeilige als auch zwei- und dreizeilige Textgruppen mit reserviertem Innenabstand zusammen.

| Oberfläche | Korrektur |
|---|---|
| AppStore | Gemessene Kopfzeile; nachfolgende Aktions-, Filter- und Listenreihen beginnen erst darunter. AppStore-Karten messen Titel und Statuszeile separat. |
| Kontrollzentrum | Eine gemessene Kopfzeile mit Zwischenraum vor der ersten Kachelreihe. Kacheln und Benachrichtigungen positionieren Symbol, Titel und Detailzeile einzeln. |
| Open Apps | Doppelt gezeichnete Überschriften im Material-Modus entfernt; Karten beginnen erst unter dem vollständigen Header. |
| Homescreen | Begrüßung und Datum bestimmen die tatsächliche Headerhöhe. Suchleiste, Statuskarten und App-Raster folgen danach. |
| DApp-Host und Navigation | Appbar zeichnet ihren Titel nur einmal. Aktionschips zentrieren Symbol und Beschriftung anhand ihrer gemessenen Höhe. |
| Files und Settings | Wiederverwendete Titel-/Untertitelzeilen verwenden dieselbe sichere, gemessene Stapelung. |

## Simple Mode

Der **Simple Mode bleibt unverändert reduziert**. Sein 4×3-Raster, die einfache Schnelleinstellung, seine bestehenden Abstände und seine Auswahl bleiben von den Material-Flächen und den erweiterten Normalmodus-Kopfbereichen getrennt. Die Korrektur verändert dort keine neuen Standarddekorationsflächen.

## Qualitätssicherung

Die Regression deckt die gemeinsame Textstapelberechnung, die einmalige Open-Apps-Überschrift, gemessene Header-/Kachelabstände, den normalen Homescreen und den getrennten Simple-Mode-Pfad ab. Ergänzend wurden alle Lua-Dateien mit Lua 5.1 geprüft; die DApp- und Browser-Suites laufen vollständig durch.

> **Hardware-Nachtest:** Bitte insbesondere AppStore, Kontrollzentrum, Open Apps, den normalen Homescreen sowie die untere DApp-Navigation auf dem eigenen Reader prüfen. Im aktiven Simple Mode müssen weiterhin keine Material-Pills oder zusätzlichen Standardflächen erscheinen.
