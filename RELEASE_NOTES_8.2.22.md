# AppDock 8.2.22 — YouTube-Shorts-Release

## Neu

AppDock enthält jetzt eine eigene **YouTube Shorts**-DApp. Sie basiert auf der vorhandenen yt-dlp-/ffmpeg-/BWR-Pipeline und dem integrierten E-Ink-Player.

- Die Suche ergänzt automatisch `#shorts` und akzeptiert ausschließlich Ergebnisse bis maximal 180 Sekunden.
- Die Oberfläche verwendet einen vertikalen Shorts-Feed mit Like-, Next- und Hashtag-Aktionen.
- Likes und zuletzt verwendete Hashtags werden lokal als Empfehlungssignale gespeichert.
- Das nächste Video wird nach dem Start der aktuellen Wiedergabe im Hintergrund vorbereitet.
- Die bestehende YouTube-DApp bleibt unverändert verfügbar.

## Prüfung

Die Shorts-DApp ist als `youtube_shorts` in `appdock_dapps.lua` registriert. Die Versionsangaben in `_meta.lua` und `main.lua` sind auf `8.2.22` gesetzt. Die bestehende GitHub-Actions-Prüfung wird nach dem Push ausgeführt.
