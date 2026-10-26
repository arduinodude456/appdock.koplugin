# AppDock 8.5.6 — Games im AppStore

Der AppStore besitzt jetzt eine eigene **Games**-Sektion. Spiele werden aus dem separaten `games.txt`-Katalog geladen und zeigen neben ihrer Lua-DApp auch das zugehörige ZIP-Paket.

Nach sichtbarer Installationsbestätigung prüft AppDock das ZIP-Archiv, weist absolute und unsichere Pfade zurück und entpackt den Paketinhalt in das KOReader-Geräteverzeichnis `.adds`. Damit können Spiele wie Midless ihre nativen Dateien und Assets gemeinsam mit der Lua-Oberfläche installieren.

Der DApps-Katalog enthält dafür `midless.lua`, `games.txt` und `midless.zip`. Die bestehenden App-, Widget-, Design- und Sleepscreen-Kategorien bleiben erhalten.
