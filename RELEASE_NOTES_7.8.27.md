# AppDock 7.8.27

## Audio/Video-Wiedergabe korrigiert

- Der Player liest WAV-Dateien jetzt über ihre RIFF-Chunks statt einen festen 44-Byte-Header anzunehmen. So werden auch von FFmpeg erzeugte WAVs mit vorgeschalteten `LIST`-Metadaten korrekt erkannt; Seek-Clips beginnen am angeforderten Audio-Sample.
- Pause, Stop und Seek signalisieren jetzt die tatsächlich gestartete Audio-Backend-PID. Zuvor wurde teilweise eine nicht vorhandene Prozessgruppe signalisiert, sodass Audio nach Pause oder Sprung weiterlaufen und aus dem Takt geraten konnte.
- Kleine Laufzeitunterschiede zwischen Framezahl und Companion-WAV (bis 3 %) werden beim Wiedergabetakt berücksichtigt; bei deutlich abweichenden Tracks wird nicht automatisch gestreckt.
- Der Player findet die Companion-WAV auch bei einer großgeschriebenen `.BWR`-Endung.

## Komprimiertes BWR2-Videoformat

- Neue Konvertierungen schreiben weiterhin `.bwr`, aber nun **BWR2**: komprimierte Keyframes plus XOR-Deltas, Wiederholungsmarker und Null-Lauf-Kompression. Der Keyframe-Index begrenzt zufälliges Suchen standardmäßig auf höchstens 11 Delta-Decodierungen.
- **Bestehende BWR1-Videos bleiben in AppDock abspielbar.** Externe Player, die nur BWR1 unterstützen, verstehen BWR2 nicht.
- BWR2 nutzt System-zlib, wenn sie vorhanden ist, und fällt andernfalls auf eingebaute Codecs zurück. Neue zusätzliche ausführbare Werkzeuge sind nicht erforderlich.
- Sandbox-Messung auf synthetischem bewegtem 600×800-`testsrc2`, 36 Frames: 150.044 Byte statt 2.160.000 Byte roher Frame-Daten (93,1 % kleiner). Die tatsächliche Größe hängt stark vom Videoinhalt ab; dies ist kein allgemeines Kompressionsversprechen.
- Der Decoder liest und expandiert nur den benötigten Frame. Die Kompression verändert die Bildqualität oder das Dithering nicht.

## Prüfung

BWR1/BWR2-Roundtrips und Zufallszugriffe, Audio-Prozesssignale und WAV-Seeking hinter einem `LIST`-Chunk sowie der echte FFmpeg-Konvertierungs- und Player-Ladepfad werden durch Regressionstests abgedeckt.

Das detaillierte Containerlayout steht in [`BWR2_FORMAT.md`](BWR2_FORMAT.md).
