# AppDock 7.9.20

## Window Mode (Beta): Taskbar und mehrere Fenster

Der Beta-Fenstermodus erhält eine Taskleiste mit Startmenü. Darüber lassen sich weitere DApps starten, während bereits geöffnete Apps im Desktop-Fenstermodus geöffnet bleiben. Neue Fenster werden leicht versetzt angeordnet; pro App bleiben Position und Größe erhalten.

Taskbar-Einträge bringen ein Fenster in den Vordergrund und stellen minimierte Fenster wieder her. Fenster können einzeln minimiert oder geschlossen werden, ohne die übrigen Fenster zu beenden. Der Beta-Modus unterstützt bis zu acht gleichzeitig geöffnete Fenster. Vollbild bleibt pro Fenster möglich und blendet die Taskleiste vorübergehend aus.

## Tests

Alle 13 AppDock-LuaJIT-Regressionstests laufen durch. Die Tests decken Startmenü-Launch, mehrere offene Fenster, Taskbar-Fokus, Minimieren/Wiederherstellen, Einzel-Schließen und Vollbildwechsel ab. LuaJIT-Bytecodeprüfung und `git diff --check` sind sauber.
