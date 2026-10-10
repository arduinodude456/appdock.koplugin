# AppDock 7.8.41

## Einstellbarer Audio-Video-Offset

In den YouTube-Einstellungen kann nun frei festgelegt werden, wie viele Sekunden nach dem Audiostart das Video beginnen soll.

- Standard: `0 s`
- Erlaubt: `0` bis `60` Sekunden
- Dezimalwerte werden unterstützt, z. B. `0,25`, `0.5` oder `1,5`
- Gilt für GStreamer, aplay und andere Audio-Backends
- Ein positiver Wert verzögert nur den Videostart, nicht den Audiostart
