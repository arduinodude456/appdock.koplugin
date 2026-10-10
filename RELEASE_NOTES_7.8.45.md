# AppDock 7.8.45

## Startverzögerung nach Audiostart

Die frei einstellbare Videoverzögerung wird jetzt nach erfolgreichem Audiostart für alle Audio-Backends angewendet. In 7.8.44 war der Pfad für aplay/tinyplay versehentlich innerhalb des GStreamer-Zweigs verschachtelt und wurde daher ignoriert.

GStreamer wartet weiterhin auf sein Startsignal und danach auf den eingestellten Offset. Andere Audio-Backends starten den Offset-Timer direkt nach erfolgreichem Audio-Start.
