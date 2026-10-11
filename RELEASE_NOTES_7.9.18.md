# AppDock 7.9.18

## Draw: Farbe auf Farbdisplays und RGB-Farbwahl

Draw erkennt nun die tatsächliche Hardware-Farbdisplay-Fähigkeit statt KOReaders globaler Einstellung „Color rendering“. Dadurch werden RGB-Farben auch dann an Draw übergeben, wenn die Dokument-Farbdarstellung global ausgeschaltet ist.

Die Werkzeugleiste enthält einen RGB-Farbwähler mit Vorschau. Farben können als `#RRGGBB` oder `R,G,B` eingegeben werden. Benutzerdefinierte Farben und die aktuelle Farbauswahl werden in Zeichnungsprojekten gespeichert. Bestehende `ADRAW1`-Projekte bleiben weiterhin ladbar.

## Tests

Alle 13 AppDock-LuaJIT-Testskripte laufen durch. LuaJIT-Bytecodeprüfung und `git diff --check` sind sauber.
