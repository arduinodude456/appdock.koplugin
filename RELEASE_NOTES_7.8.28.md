# AppDock 7.8.28

## Synchronisierter Wiedergabestart

Beim GStreamer-Backend galt das Starten des Hintergrundprozesses bisher schon als Audio-Start. Die Videouhr lief dadurch an, während GStreamer den Audio-Sink noch initialisierte; auf Geräten mit langsamer Initialisierung konnte der Ton mehrere Sekunden hinter dem Bild beginnen.

AppDock wartet jetzt auf GStreamers Meldung `New clock:` und startet erst dann die Videouhr. Das Warten wird über kurze UI-Ticks ausgeführt, die Oberfläche blockiert also nicht. Wird innerhalb von acht Sekunden keine Wiedergabebereitschaft bestätigt oder meldet GStreamer einen Fehler, beendet AppDock den verspäteten Audioprozess statt ihn später asynchron einsetzen zu lassen. `aplay` und `tinyplay` behalten ihren direkten Startpfad.

Regressionstests prüfen, dass der Videostart während der Initialisierung eingefroren bleibt, bei bestätigter Audiouhr freigegeben wird und bei Timeout kein verspäteter Ton nachläuft.
