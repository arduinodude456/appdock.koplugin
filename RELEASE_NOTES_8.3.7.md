# AppDock 8.3.7 — Stabilität beim Sleepscreen-Scrollen

Die öffentliche Sleepscreen-Liste erstellt beim Laden keine vollständigen Renderer- und Bild-Widgetbäume mehr für jede Karte. Sie zeigt leichte Platzhalter; die validierte vollständige Vorschau wird erst geladen, wenn ein öffentlicher Sleepscreen geöffnet wird. Das reduziert die gleichzeitige Widget- und Bildlast im KOReader-Scroller und verhindert Abstürze beim Durchblättern öffentlicher Einträge.

Die Regression deckt eine volle, scrollbar lange Seite mit zwölf öffentlichen Ergebnissen ab und prüft, dass Listenansicht und Detailvorschau getrennte Renderpfade verwenden.
