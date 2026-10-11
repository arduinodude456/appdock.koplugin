# AppDock 7.9.17

## YouTube Music: Suche per Enter und überarbeitete Startansicht

Die AppDock-Tastatur löst beim Absenden jetzt den YouTube-Music-Suchbutton aus. Beliebige Texteingaben werden als Suchanfrage behandelt; direkte Downloads bleiben für eingefügte YouTube-Links verfügbar. Fehlende Suchwerkzeuge und Fehler beim Starten einer Suche erscheinen in einer sichtbaren Diagnoseansicht.

Der leere Music-Startbildschirm wiederholt nicht mehr den Fenstertitel, zeigt keinen funktionslosen Play-Button und bietet stattdessen eine gestaltete Leerkartenansicht mit direktem Einstieg in die Suche.

## Tests

Alle 13 AppDock-LuaJIT-Testskripte laufen durch. `git diff --check` und die LuaJIT-Syntaxprüfung sind sauber.
