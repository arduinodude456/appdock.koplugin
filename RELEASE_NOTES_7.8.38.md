# AppDock 7.8.38

## YouTube-Synchronisation pro Video

Die feste 4-Sekunden-MTK-Korrektur aus 7.8.37 wurde entfernt, weil der Versatz je nach Video unterschiedlich war.

Die Audioextraktion normalisiert nun die erste Audiozeitbasis pro Quelle mit FFmpeg (`aresample=async=1:first_pts=0`). Dadurch werden unterschiedliche Audio-Startzeitstempel der YouTube-Quellen nicht mehr als pauschale Hardwarelatenz behandelt.

Die Raw-PCM-Ausgabepipeline bleibt unverändert. Bereits konvertierte WAV-Dateien werden nicht rückwirkend geändert; betroffene Videos müssen neu konvertiert werden.

Die zweispaltige YouTube-Watch-Oberfläche mit Hauptvideo, Up-next-Leiste, Suche, Aktionen und Navigation bleibt enthalten.
