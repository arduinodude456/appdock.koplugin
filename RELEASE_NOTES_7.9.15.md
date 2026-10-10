# AppDock 7.9.15

## YouTube Music: Suche zuverlässiger und Player näher am Original

- **Teiltreffer bleiben sichtbar:** Liefert `yt-dlp` bereits brauchbare Suchtreffer, werden diese auch dann angezeigt, wenn einzelne YouTube-Einträge fehlschlagen und der Prozess deshalb einen Fehlerstatus zurückgibt.
- **Metadatensuche statt Mediendownload:** Die Suche bleibt auf eine begrenzte Trefferliste beschränkt und lädt keine Audio-/Videodateien herunter. Socket-Timeouts, begrenzte Wiederholungen und ein UI-Timeout schützen vor festhängenden Suchläufen.
- **Bessere Diagnose:** Bei leeren Ergebnissen werden relevante yt-dlp-Fehlerhinweise in der App angezeigt. Vollfarbige Ergebnisminiaturen werden in den lokalen Cache übernommen.
- **Überarbeiteter Player:** Die Wiedergabeansicht orientiert sich stärker an YouTube Music – dunkle Fläche, großes quadratisches Cover, Künstlername, Like-/Infoaktionen, getrennte verstrichene und gesamte Laufzeit sowie Shuffle-, Zurück-, Play/Pause-, Weiter- und Repeat-Steuerung.
- **Wiedergabe minimieren:** Der Abwärtspfeil bringt zurück zur Mediathek, ohne die laufende Musik anzuhalten.
- **Künstler bleibt erhalten:** Der Kanal-/Künstlername aus dem Suchtreffer wird lokal neben der WAV-Datei gespeichert und in Bibliothek und Player wieder angezeigt.

## Tests

`test_ytmusic.lua`, `test_youtube.lua`, `test_draw.lua` und `test_dapps.lua` laufen unter LuaJIT durch. Die geänderten Lua-Dateien bestehen Syntaxprüfungen; `git diff --check` meldet keine Formatfehler.
