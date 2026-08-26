# AppDock 4.2.1 — Layout

## Saubere Beschriftungen im gesamten System

AppDock nutzt jetzt eine zentrale, UTF-8-sichere Ein-Zeilen-Kürzung für lange UI-Texte. Beschriftungen werden innerhalb ihres Controls mit einer Auslassung gekürzt, statt mehrzeilig umgebrochen, unter einen Button geschoben oder über benachbarte Elemente gezeichnet zu werden.

## Betroffene Oberflächen

Die Korrektur deckt die DApp-Host-Aktionen und Recents-Karten, Einstellungszeilen und Kategorien, Quick-Settings-Kacheln und Benachrichtigungen, Homescreen-Kacheln und Infokarten, Dateimanager-Toolbar und Dateizeilen, AppStore-Karten, Browser-Toolbar sowie Speicherübersichten ab.

## Kompakte Panegrößen

Schriftgrößen, Innenabstände und Titel-/Untertitel-Offsets orientieren sich jetzt an der tatsächlichen Kontrollhöhe. Dadurch bleiben auch reduzierte Splitscreen-Panes lesbar und die Touchflächen unverändert erreichbar.

## Validierung

Lua-5.1-Syntax, Root-/Paketspiegelgleichheit, die bestehende DApp-Regression und neue Tests für einzeilige UTF-8-Kürzung sowie schmale Controls wurden vor dem Release ausgeführt.
