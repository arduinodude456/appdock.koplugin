# AppDock 4.2.2 — Controls

## Dropdown-Menü

Die Textzeilen in den Quick-Settings-Kacheln liegen enger zusammen. Dadurch bleiben Symbol, Titel und Untertitel auch auf kleineren Geräten innerhalb der jeweiligen Kachel.

## Splitscreen

Der sichtbare Mittelstreifen besitzt jetzt eine deutlich größere unsichtbare Touchzone. Ein Ziehen kann daher etwas oberhalb oder unterhalb des Streifens beginnen. Während des Ziehens merkt sich AppDock zudem die letzte gültige Y-Position und verwendet sie beim Loslassen, falls der Touch-Controller im Release-Ereignis keine Position liefert.

## Validierung

Die Korrektur wurde mit Lua-5.1-Syntaxprüfung, Root-/Paketspiegelvergleich und der DApp-Core-Regression geprüft. Der Test deckt neben dem Ziehen nun auch die breite Touchzone sowie den positionslosen Release-Fallback ab.
