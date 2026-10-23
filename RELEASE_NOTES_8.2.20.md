# AppDock 8.2.20 — Hotfix für den Plugin-Start

## Behoben

Die neuen YouTube-Shorts- und Live-Statusmodule werden jetzt optional und fehlertolerant geladen. Falls eine optionale Komponente auf einem bestimmten KOReader-/Lua-Build nicht geladen werden kann, bleibt der AppDock-Kern trotzdem als Plugin verfügbar und kann normal gestartet werden.

Fehler beim Abruf einer Live-Statusmeldung werden zusätzlich abgefangen und können den Plugin-Start nicht mehr unterbrechen.

## Prüfung

Alle geänderten Lua-Dateien wurden mit einem Lua-5.1-kompatiblen Parser geprüft. Die Plugin-Metadaten enthalten Version `8.2.20`.
