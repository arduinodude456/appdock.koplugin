# AppDock 7.8.23

## YouTube-Downloads korrigiert

Die YouTube-DApp verwendet jetzt ausdrücklich den Android-Player-Client von yt-dlp. Damit umgeht sie bei unterstützten Videos die zuletzt häufiger abgewiesenen Browser-Client-Streams. Die Einstellung betrifft Video-Downloads; Suche und lokale Konvertierung bleiben unverändert.

Bei Fehlern nennt die Fortschrittsansicht jetzt die erkannte Ursache – darunter Bot-/Anmeldeprüfungen, HTTP 403, fehlende kompatible Formate, PO-Token-Anforderungen und Netzwerkprobleme. Die yt-dlp-Ausgabe bleibt als Diagnose sichtbar. Anmelde- oder Bot-Prüfungen werden nicht umgangen.

## Verifikation

Die Lua-Syntax aller 26 Plugin-Dateien und die vollständige lokale Regressionstestsuite liefen erfolgreich. Der YouTube-Test deckt die Client-Auswahl und die verständlichen Fehlermeldungen ab. Die optionale externe BWR-Video-Fixture war in der lokalen Umgebung nicht vorhanden. Die Netzwerk-Reproduktion zeigte außerdem, dass YouTube je nach Sitzung die Anmeldung zur Bot-Prüfung verlangen kann; dies kann ein Clientwechsel nicht beheben.
