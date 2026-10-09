# AppDock 7.8.14

## Fehlerbehebung: YouTube-Ersteinrichtung

Behebt den Absturz, der beim Nachladen von yt-dlp/ffmpeg im Fortschritts-Tick der YouTube-DApp auftreten konnte. Der asynchrone Callback rief `hostIsActive(context)` auf, obwohl der Helper erst später im Lua-Modul als lokale Funktion deklariert war; dadurch löste Lua einen Aufruf der nicht vorhandenen globalen Funktion aus. Der Helper steht nun vor der Bootstrap-Funktion und ist lexikalisch für deren Callbacks sichtbar.

Der Regressionstest startet die automatische Erstkonfiguration, führt den ersten noch laufenden Hintergrund-Tick aus und prüft, dass dieser ohne Fehler die Fortschrittsansicht aktualisiert. Der bestehende Download-, Integritätsprüfungs- und Wiederholungsablauf bleibt unverändert.

## Qualitätssicherung

- Syntaxprüfung für alle Lua-Dateien.
- YouTube-Regressionstest einschließlich simuliertem asynchronem Setup-Fortschritt erfolgreich.
- AppDock-Keyboard-, AppStore-, Browser-, BWR1-, DApp-, Ordering- und Setup-Assistant-Tests erfolgreich.
