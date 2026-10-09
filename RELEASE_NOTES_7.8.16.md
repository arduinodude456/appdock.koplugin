# AppDock 7.8.16

## YouTube: begrenzter yt-dlp-Starttest

- Der erste `yt-dlp --version`-Kompatibilitätstest hat nun ein eigenes Zeitlimit von 120 Sekunden. Wenn die Binärdatei auf dem Reader nicht startet oder nicht zurückkehrt, bricht AppDock den Test ab und zeigt „yt-dlp compatibility check timed out after 120 seconds“ statt den Setup-Bildschirm bis zum allgemeinen 30-Minuten-Limit festzuhalten.
- Ein schnell zurückkehrender Fehler bleibt davon unterschieden und wird weiterhin als inkompatible oder nicht ausführbare Binärdatei gemeldet.

Die Kobo-v5-Ausgabe von KOReader ist im v2026.07-Release als 32-Bit-ARM-ELF-Build enthalten; AppDock verwendet auf dem Libra Colour daher den ARMv7-yt-dlp-Pfad. Die vorhandene ARMv7-Archivkorrektur aus 7.8.15 bleibt enthalten. Der Timeout verhindert unbegrenztes Warten, ersetzt aber keine Ursachenanalyse, falls der Starttest auf einem Gerät ausläuft.
