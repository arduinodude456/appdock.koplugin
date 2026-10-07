# AppDock 7.8.1

## Deutsch

### Schnelleinstellungen

- Das Dropdown hat jetzt eine klar umrandete Fläche und im normalen Modus einen sichtbaren Griff.
- Die Schnellkacheln verwenden aussagekräftige AppDock-Symbole statt Buchstaben-Platzhaltern.
- Die Schließen-Schaltfläche in der Kopfzeile funktioniert jetzt tatsächlich.
- Der Helligkeitsregler zeigt einen eigenen Schieberknopf; Touchpositionen werden korrekt relativ zur Bildschirmposition des Reglers ausgewertet.
- Der kompakte Simple Mode bleibt erhalten und bekommt ebenfalls Symbole, einen Schließen-Zugang und einen klar erkennbaren Helligkeitsregler.

### Qualitätssicherung

- Regressionen prüfen Symbole, Griff, Schließen-Aktion und Helligkeits-Touchpositionen in den relevanten Modi.
- Lua-Syntax und alle sechs verfügbaren Regressionstests erfolgreich geprüft. Der optionale BWR-Video-Testdatensatz war in der Testumgebung nicht vorhanden.

## English

### Quick Settings

- The dropdown now has a clearly outlined sheet and a visible grab handle in the normal mode.
- Quick tiles use meaningful AppDock icons instead of letter placeholders.
- The close control in the header now works as expected.
- The brightness slider displays its own thumb, and touch positions are correctly mapped relative to the slider's screen position.
- Simple Mode remains compact and also receives icons, a close action, and a clearly visible brightness thumb.

### Quality assurance

- Regression tests cover icons, the grab handle, the close action, and brightness touch positioning in the relevant modes.
- Lua syntax and all six available regression tests pass. The optional BWR Video test fixture was not present in the test environment.
