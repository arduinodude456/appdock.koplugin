# AppDock 7.8.0

## Deutsch

### Android-inspirierter Homescreen

- Der normale Homescreen wurde mit einer kompakten Statuszeile und einer breiten, einzeiligen DuckDuckGo-Suchleiste neu aufgebaut.
- Zuletzt verwendete Apps erscheinen als beschriftungsfreies Icon-Dock am unteren Rand. Ein gezeichnetes Raster-/Suchsymbol öffnet **Alle Apps**; die AppDock-Oberfläche verwendet keine Google-Logos oder -Marken.
- Geräte- und Lesekarten stehen als ruhige, abgerundete Info-Karten nebeneinander.
- Store-Widgets werden bei mehreren Installationen zweispaltig angeordnet. Eine vergrößerte Karte kann die gesamte Zeile einnehmen; die übrigen Widgets fließen darunter weiter.
- Im Editmodus werden nicht editierbare Blickfang-Karten vorübergehend ausgeblendet. Widget-Ziele berücksichtigen nun sowohl die horizontale als auch die vertikale Position.

### Qualitätssicherung

- Regressionen für Suchleiste, Icon-Dock, Widget-Spalten, Größenänderung, Zeilenumbruch und zweidimensionales Widget-Verschieben ergänzt.
- Lua-Syntax und alle sechs verfügbaren Regressionstests erfolgreich geprüft.

## English

### Android-inspired homescreen

- Rebuilt the normal homescreen around a compact status row and a wide, single-line DuckDuckGo search pill.
- Recently used apps appear in a label-free icon dock at the bottom. A custom drawn grid-and-search glyph opens **All apps**; the AppDock UI uses no Google logos or marks.
- Device and reading cards sit side by side as calm, rounded glance cards.
- Multiple Store widgets use a two-column layout. Enlarged cards can span the full row, with remaining widgets reflowing below.
- Non-editable glance cards temporarily yield space in edit mode. Widget drop targets now use both horizontal and vertical position.

### Quality assurance

- Added regression coverage for the search pill, icon dock, widget columns, resizing, reflow, and two-dimensional widget dragging.
- Lua syntax and all six available regression tests pass.
