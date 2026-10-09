# AppDock 7.8.17

## YouTube: Installer- und Timeout-Fehler werden an die Oberfläche gemeldet

- Korrigiert den Detached-Launcher: Das Installationsskript lief bisher im selben Shell-Prozess wie der Exit-Marker. Bei `set -e` beendete ein fehlgeschlagener Befehl die Shell, bevor der Abschlussmarker geschrieben wurde. Dadurch konnte die Oberfläche auch nach Ablauf des 120-Sekunden-yt-dlp-Timeouts weiterhin den alten Status zeigen.
- Das Skript läuft nun in einer eigenen Subshell. Die äußere Shell kann den Statuscode immer speichern; zugleich werden Ausgaben des gesamten Skripts im Diagnose-Log gesammelt.
- Die Zeitbegrenzung aus 7.8.16 bleibt bestehen: Ein blockierter `yt-dlp --version`-Test wird nach 120 Sekunden abgebrochen und als Timeout angezeigt.

Ein Regressionstest deckt jetzt auch den Fehlerpfad eines `set -e`-Shellskripts ab und prüft, dass Exit-Marker und Diagnoseausgabe an AppDock zurückkommen.
