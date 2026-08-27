# AppDock 6.0.3 „Continuity“

## Kompakteres Textlayout

AppDock 6.0.3 verdichtet die vertikalen Abstände innerhalb der normalen Standardoberfläche. Die Korrektur aus 6.0.2 bleibt vollständig erhalten: feste Controls messen weiterhin die tatsächliche, unpolsterte Glyphenhöhe, bevor sie Text zeichnen. Neu ist eine zentrale kompakte Rhythmusregel, die den angeforderten Zeilenabstand von AppDock-Textgruppen auf rund 55 Prozent reduziert und dabei mindestens einen sichtbaren Pixel Abstand beibehält.

Die Regel wirkt auf die normalen gemessenen Textstapel in **Homescreen**, **Settings**, **AppStore**, **Kontrollzentrum**, **Open Apps**, **Files** sowie der **DApp-Navigation**. Sie verändert weder die Schriftgröße noch die Touchflächen; sie verringert ausschließlich den freien vertikalen Abstand zwischen voneinander getrennten Textzeilen.

| Eigenschaft | Verhalten in 6.0.3 |
|---|---|
| Textsicherheit | Die unpolsterte Glyphenmessung und die sichere Einpassung in feste Flächen bleiben aktiv. |
| Lesbarkeit | Ein Mindestabstand von einem Gerätepixel bleibt zwischen Zeilen erhalten. |
| Kacheln | Kontrollzentrum-Kacheln behalten ihr vorheriges Verkleinern und optionales Ausblenden einer nicht passenden Detailzeile. |
| Bedienelemente | Touchbereiche, Buttonhöhen und Gesten verändern sich nicht. |
| Simple Mode | Bleibt ein eigener, unveränderter reduzierter Layoutpfad und verwendet die neue Standardregel nicht. |

## Qualitätssicherung

Die Core-Regression prüft die reduzierte Stapelhöhe, geordnete und begrenzte Zeilenpositionen, die Normalmodusoberflächen und die explizite Trennung des Simple Mode. Alle Quell- und Paket-Lua-Dateien wurden zusätzlich mit Lua 5.1 geprüft; die DApp- und Browser-Suiten laufen erfolgreich.

> **Hardware-Nachtest:** Bitte nach vollständigem KOReader-Neustart besonders Settings, Homescreen, AppStore und Kontrollzentrum ansehen. Die Beschriftungen müssen dichter stehen, dürfen aber weder kollidieren noch über ihre Karten hinausreichen.
