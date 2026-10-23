# AppDock 8.2.21 — Stabiler Recovery-Release

## Behoben

Die fehlerhafte Shorts-/Live-Status-Startup-Integration aus 8.2.19 und 8.2.20 wurde vollständig aus dem installierbaren Plugin entfernt. `main.lua` und `appdock_dapps.lua` entsprechen wieder dem letzten nachweislich funktionierenden Plugin-Kern aus 8.2.18.

Damit werden die experimentellen Module nicht mehr beim AppDock-Start geladen und können weder die KOReader-Plugin-Erkennung noch den Recovery-Startpfad unterbrechen.

## Wichtig

Diese Version ist bewusst ein stabiler Recovery-Release. YouTube Shorts und der Remote-Statuskanal sind nicht Bestandteil von 8.2.21. Sie werden erst nach separater KOReader-Laufzeittestung erneut integriert.

## Prüfung

Die Versionsstellen in `_meta.lua` und `main.lua` sind konsistent auf `8.2.21` gesetzt. Die installierbaren Kern-Dateien wurden auf den Stand von `v8.2.18` zurückgesetzt; die neuen Shorts-/Statusmodule sind nicht mehr im Plugin enthalten.
