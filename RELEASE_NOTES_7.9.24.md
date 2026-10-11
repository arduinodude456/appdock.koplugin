# AppDock 7.9.24

## Draw: KOReader-Stiftfreigabe und Druckverlauf korrigiert

KOReader liefert das Abheben des Stifts im `registerStylusCallback`-Pfad als Slot mit `id == -1`. Draw behandelt diesen Slot jetzt ausdrücklich als Ende des Kontakts und niemals als Zeichenpunkt. Dadurch werden getrennte Stylus-Kontakte nicht mehr miteinander verbunden.

Die Pinselstärke wird außerdem für jeden Stylus-Sample neu aus dem aktuellen Druckwert berechnet. Der Druck bleibt damit während eines laufenden Strichs wirksam, statt nur beim ersten Punkt berücksichtigt zu werden.

## Tests

Die Regressionstests prüfen den echten KOReader-Lift-Slot, getrennte Kontakte, den Rohdruckfallback und den Druckverlauf. Draw-Tests, LuaJIT-Syntaxprüfung und `git diff --check` sind sauber.
