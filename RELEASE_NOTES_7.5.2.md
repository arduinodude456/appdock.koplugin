# AppDock 7.5.2

## Scroll- und Suchaktualisierung

- Der AppStore-Scroller reserviert seine Scrollbarbreite zusätzlich zur nutzbaren Zeilenbreite. Dadurch bleiben Karten- und Installationsaktionen beim Scrollen sichtbar statt unter der Scrollbar abgeschnitten zu werden.
- Nach einer über die DuckDuckGo-Homescreenleiste gestarteten Suche wird nach dem Browser-Neuaufbau ein vollständiger E-Ink-Bildschirmrefresh eingeplant.
- Regressionstests prüfen den Full-Refresh-Pfad; AppStore- und DApp-Tests berücksichtigen die reservierte Scrollbar.
