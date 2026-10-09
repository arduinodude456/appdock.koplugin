# AppDock 7.8.39

## Variable YouTube-Audio-Offsets

Die Audioextraktion entfernt nun pro Video automatisch führende Stille ab 50 ms und normalisiert anschließend die Zeitbasis mit `aresample=async=1:first_pts=0`.

Damit werden variable Start-Offsets der einzelnen Quellen nicht mehr durch eine feste Hardwareverzögerung behandelt. Die Raw-PCM-Wiedergabe bleibt unverändert.

Bereits konvertierte Videos enthalten weiterhin ihre alte WAV-Datei und müssen gelöscht sowie neu konvertiert werden.
