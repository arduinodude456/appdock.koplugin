# AppDock 8.2.19 — YouTube Shorts und Live-Statusmeldungen

## YouTube Shorts

AppDock enthält jetzt eine eigene **YouTube Shorts**-DApp mit vertikalem E-Ink-freundlichem Feed, großem Player, Creator-/Hashtag-Metadaten sowie Previous-/Next-Navigation.

Der Feed verwendet die bestehende yt-dlp-/ffmpeg-Pipeline, sucht über `#shorts` und begrenzt die Treffer auf maximal 180 Sekunden. Der aktuelle Clip und der nächste Feed-Eintrag werden über die lokale Videobibliothek verwaltet; der nächste Clip kann bereits während der Wiedergabe des aktuellen Clips vorgeladen werden.

Likes werden lokal auf dem Reader gespeichert. Hashtags gelikter Clips und Like-Häufigkeiten beeinflussen die lokale Empfehlungsreihenfolge. Es gibt keinen YouTube-OAuth-Schreibzugriff und keine Übertragung der Like-Daten.

## Live-Mitteilungen

Betreiber können technische Störungen und wichtige Hinweise jetzt ohne neues Plugin-Release veröffentlichen. AppDock ruft beim Start und anschließend alle drei Minuten die Datei `appdock_notice.json` aus dem `main`-Branch über HTTPS ab.

Eine neue, aktivierte Notice-ID erscheint als Update-ähnliches Popup und zusätzlich in der AppDock-Benachrichtigungs-Inbox. Meldungen werden lokal als gesehen gespeichert; `expires_at` und `enabled` erlauben zeitlich begrenzte oder deaktivierte Hinweise.

Die Bedienungsanleitung steht in [`APPDOCK_NOTICES.md`](APPDOCK_NOTICES.md).

## Prüfung

Die Notice-Datei wurde als gültiges JSON validiert und `git diff --check` läuft ohne Befund. Eine Lua-Syntax-/Regressionstest-Ausführung war in der Sandbox nicht möglich, da dort keine Lua-/LuaJIT-Laufzeit installiert ist.
