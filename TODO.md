# YouTube Shorts – Lieferstatus

## Shorts-DApp mit vertikalem Feed

- [x] Es gibt eine eigene AppDock-DApp „YouTube Shorts“ mit Shorts-orientierter Oberfläche: großer Player, Titel/Creator/Hashtags, Like-Aktion und „Als Nächstes“-Bereich.
- [x] Der Feed verwendet ausschließlich yt-dlp-Suchergebnisse für `#shorts` und verwirft Videos außerhalb der Shorts-Längenbegrenzung.
- [x] Während der aktuelle Clip abgespielt wird, wird der nächste Feed-Eintrag im Hintergrund heruntergeladen bzw. aus der lokalen Library vorgehalten.

## Lokale Empfehlungen und Likes

- [x] Ein Clip kann geliked und unliked werden; der Zustand bleibt lokal gespeichert und ist nach erneutem Öffnen wieder sichtbar.
- [x] Empfehlungen werden aus Hashtags/Titeln gelikter Clips und der Like-Häufigkeit gewichtet; der aktuelle Feed wird neu sortiert, ohne YouTube-Schreibzugriff zu benötigen.
- [x] Die UI erklärt, dass Likes und Personalisierung lokal auf dem Reader gespeichert werden.

## Tests und Integration

- [x] Die neue DApp ist im AppDock-DApp-Manager registriert und stoppt beim Schließen ihren Player/Prefetch-Job.
- [x] Reine Filter-, Hashtag-, Like- und Ranking-Helfer sind durch `test_shorts.lua` abgedeckt.

## Live-Mitteilungen bei Störungen

- [x] AppDock prüft `appdock_notice.json` beim Start und anschließend regelmäßig über HTTPS.
- [x] Eine neue Notice-ID öffnet ein Update-ähnliches Popup und legt zusätzlich eine lokale Inbox-Benachrichtigung an.
- [x] `enabled`, `priority`, `expires_at`, `title`, `message` und `details` sind dokumentiert; die Notice-Datei kann ohne Plugin-Release live geändert werden.
