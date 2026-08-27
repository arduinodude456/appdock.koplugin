# AppDock 6.0.2 „Continuity“

## Rendererbasierter Text- und Ebenenfix

AppDock 6.0.2 korrigiert den fehlgeschlagenen Layoutansatz aus 6.0.1. Der vorherige Fix stützte sich zwar auf die Widgethöhe, berücksichtigte aber nicht, dass KOReaders `TextWidget` standardmäßig zusätzlich vertikales Padding in diese Höhe einrechnet. In niedrigen, festen Kacheln konnte der Text dadurch weiterhin über seine Fläche hinausragen; nachfolgende Buttonflächen übermalten ihn sichtbar.

6.0.2 legt deshalb für feste AppDock-Controls die Textwidget-Polsterung explizit auf null fest. Erst danach wird die reale Glyphenhöhe gemessen und innerhalb eines reservierten Innenabstands platziert. Mehrzeilige Kontrollzentrum-Kacheln verkleinern ihre Zeichen schrittweise; falls selbst die minimale lesbare Größe nicht in die Fläche passt, wird ausschließlich die Detailzeile ausgeblendet. Titel und Bedienbarkeit bleiben erhalten.

| Bereich | Korrektur |
|---|---|
| Kontrollzentrum | Symbol, Titel und Detailzeile nutzen unpolsterte gemessene Glyphen. Sie werden vor dem Zeichnen in die feste Kachelhöhe eingepasst. |
| AppStore | Karten- und Headerbeschriftungen verwenden unpolsterte gemessene Zeilen; die folgenden Flächen beginnen danach. |
| Open Apps und DApp-Host | Überschriften, Karten- und Aktionschips zeichnen ihre Vordergrundtexte nach ihren Hintergründen. Eine unmögliche Home-Beschriftung in der kompakten Navigation wurde entfernt; das Symbol bleibt als klare Aktion erhalten. |
| Homescreen, Files und Settings | Die normalen mehrzeiligen Informations-, Datei- und Einstellungsflächen verwenden unpolsterte Messwerte und feste Innenabstände. |

## Simple Mode

Der **Simple Mode bleibt unverändert reduziert**. Sein 4×3-Raster und die einfache Kontrollzentrale erhalten weder neue Materialflächen noch Änderungen an ihren visuellen Extras. Die 6.0.2-Korrektur betrifft nur die betroffenen Standardoberflächen.

## Qualitätssicherung

Alle geänderten Lua-Quellen und Paketspiegel wurden mit Lua 5.1 geprüft. Die DApp- und Browser-Regressionen testen die gemessene Stapelung, die Einpassung in feste Kacheln, einzelne Open-Apps-Kopftexte, die Simple-Mode-Grenze, Root-/Paketgleichheit und vorhandene DApp-Lebenszyklen.

> **Erneuter Hardware-Nachtest:** Bitte überprüfe nach vollständigem KOReader-Neustart erneut AppStore, Kontrollzentrum, Open Apps, normalen Homescreen und DApp-Navigation. Sende bei einem weiteren Versatz möglichst einen neuen Screenshot und die Displayauflösung des Readers.
