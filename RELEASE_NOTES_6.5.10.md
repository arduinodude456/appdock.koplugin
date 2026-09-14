# AppDock 6.5.10

## Fehlerbehebungen

- Das Verschieben einer App an die erste oder letzte Stelle funktioniert jetzt auch dann, wenn die Zielposition mehrere Plätze entfernt ist.
- Bewegungen werden sicher an den Anfang bzw. das Ende der gespeicherten Reihenfolge begrenzt, statt still verworfen zu werden.
- Ungültige App-IDs und nicht-ganzzahlige oder leere Bewegungswerte verändern die Reihenfolge nicht.
- Die gemeinsame, dependency-freie Reihenfolgelogik wird durch Regressionstests für Aufwärts-, Abwärts-, Anfangs- und Endbewegungen abgedeckt.

## Technische Änderungen

- Die Bewegungslogik für Homescreen-Apps und Store-Widgets wurde in `appdock_order.lua` zentralisiert.
