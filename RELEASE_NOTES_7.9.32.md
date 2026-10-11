# AppDock 7.9.32

## Verbesserungen

- **DuckDuckGo:** Die Homescreen-Suche verwendet die DuckDuckGo-API und fällt bei leeren Instant-Answer-Ergebnissen auf die serverseitige DuckDuckGo-HTML-Suche zurück.
- **Update-Dialog:** Nach einem Update erscheint ein mehrseitiger Dialog mit bearbeitbaren Inhalten aus `appdock.koplugin/features.adf`.
- **Store-Designs:** Hintergrundbilder aus Store-Themes werden korrekt relativ zum Design aufgelöst, binär gespeichert und vor der Aktivierung validiert.
- **Kontrast:** Store-Farben wählen für Oberflächen und Varianten kontrastreiche Textfarben, damit Apps wie DChat besser lesbar bleiben.
- **Lautstärke:** In den Einstellungen gibt es eine gespeicherte Lautstärkeauswahl von 0 bis 100 Prozent.
- **Bluetooth:** Die Bluetooth-Einstellungen und der Bluetooth-Teil aus `audiobook.koplugin` wurden integriert. Die Herkunft wird in den Einstellungen und in `BLUETOOTH_LICENSE_NOTICE.md` ausdrücklich genannt; die übernommenen Dateien stehen unter AGPL-3.0.

## Lizenzhinweis

Diese Version enthält Bluetooth-Quellcode aus `audiobook.koplugin` von stradichenko. Vor einer kommerziellen Weitergabe sollte die Lizenzkombination des gesamten Plugins rechtlich geprüft werden.

## Validierung

- Lua-Syntaxprüfung aller Plugin-Module mit `luac -p`.
- Setup-Assistent-Regressionstest erfolgreich.
