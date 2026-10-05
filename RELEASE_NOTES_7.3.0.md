# AppDock 7.3.0 „Material Motion"

## Recently used und Navigation

- Die normale Homescreen-Oberfläche zeigt eine größere, abgerundete App-Leiste mit großen, beschrifteten Kacheln.
- Nach dem ersten Start einer App heißt die Leiste **Recently used** und zeigt die zuletzt verwendeten Apps. Bei leerer Historie wird der angeheftete Fallback korrekt als **Quick access** bezeichnet.
- Ein Wisch vom unteren Bildschirmrand nach oben öffnet die App-Leiste als Drawer. Das funktioniert auf Homescreen, DApp-Host, Open Apps, Manage AppDock und Quick Settings.
- Der Drawer fährt in vier kurzen, E-Ink-tauglichen Fast-Refresh-Schritten ein und aktualisiert dabei nur den unteren Bildschirmbereich. Wischen nach unten oder Tippen außerhalb schließt ihn.
- Homescreen-Seiten lassen sich horizontal wischen. Der Seitenwechsel verwendet vier kurze Bewegungsframes statt eines harten Neuaufbaus.

## Android-artiges Kontrollzentrum

- Quick Settings verwendet im normalen Modus größere horizontale Icon-/Toggle-Kacheln mit runden Material-Flächen.
- Eine Datumszeile und eine eigene, größere Helligkeitskarte schaffen eine klarere Android-ähnliche Hierarchie.
- Der Helligkeitsregler behält schnelle regionale E-Ink-Aktualisierungen und die abschließende Synchronisierung des übrigen UI bei.

## Kompatibilität und Grenzen

- **Simple Mode bleibt unverändert:** Der reduzierte Homescreen, das reduzierte Kontrollzentrum und die fokussierte App-Auswahl erhalten keine neuen Drawer- oder Seitenwechsel-Gesten.
- Die Übergänge sind absichtlich kurz und begrenzt; es gibt keine kontinuierliche Animation, Unschärfe oder Transparenz.
- Die bestehenden DApp-, Widget-, Theme- und Plugin-Host-Verträge bleiben erhalten.

## Validierung

- Lua-5.1-Syntaxprüfung aller Paketmodule
- `test_appdock_keyboard.lua`
- `test_browser.lua`
- `test_dapps.lua`
- `test_ordering.lua`
- `test_setup_assistant.lua`
- Motion-Helper-Test für vier Frames, `fast`-Refresh und regionale Drawer-Geometrie
