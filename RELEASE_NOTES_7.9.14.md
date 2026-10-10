# AppDock 7.9.14

## YouTube-Wiedergabe: Spitzen-Speicherbedarf senken

Der BWR2-Decoder brauchte während der Videowiedergabe mehrere zusätzliche, framegroße Arbeitskopien:
`output`, `delta`, `previous` und für zlib außerdem `z_input`. Bei großen Videoframes summierte sich das
zu mehreren Megabytes pro Arbeitskopie – zusätzlich zum gepackten Cacheframe und zum eigentlichen
Blitbuffer-Bild. Auf speicherbegrenzten Readern konnte das beim Abspielen zu KOReaders Meldung
„zu wenig Speicher“ führen.

- **BWR2 hält jetzt nur einen framegroßen Decoder-Arbeitspuffer** (`output`). Die vorherigen und Delta-
  FFI-Puffer entfielen; Deltas werden direkt im Ausgabepuffer gegen den bereits gecachten Frame XOR-
  dekodiert.
- **zlib liest direkt aus dem komprimierten Paketstring** statt eine weitere bis zu framegroße Kopie
  (`z_input`) zu belegen.
- **RLE wird direkt aus dem Paketstring dekodiert.** Es entstehen keine zusätzlichen Lua-Substring-
  Allokationen pro Literalbereich.
- **Wiederholungsframes geben den bereits gecachten Frame direkt zurück**, statt ihn ein zweites Mal in
  den Ausgabepuffer zu kopieren.

Der Container bleibt unverändert kompatibel mit BWR1, BWR2 und BRC2; die Bildqualität, Dateigröße,
Frame-Timing und Suchbarkeit ändern sich nicht. Für ein Frame von 2 MiB entfallen bis zu drei zusätzliche
2-MiB-Arbeitskopien (bis zu 6 MiB dauerhafte Arbeitsbereiche); zugleich fallen pro dekodiertem Paket
weniger temporäre Kopien an.

## Tests

`test_bwr.lua` prüft zusätzlich, dass der BWR2-Reader nur den einen Frame-Arbeitspuffer statt der
entfernten Vollframe-Kopien anlegt. BWR1-, BWR2-, BRC2- und zlib-Fallback-Tests laufen unverändert durch.
