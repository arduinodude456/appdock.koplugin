# AppDock 7.9.30

Diese Version konzentriert sich auf **verlässliche Downloads**, **bessere Lesbarkeit** und klarere E‑Ink-Oberflächen.

## Themes und Designs

- Theme-Paletten wählen für Text, Schaltflächen und Oberflächen automatisch eine ausreichend kontrastreiche Vordergrundfarbe.
- Beim Installieren eines Store-Designs wird ein Hintergrundbild vor der Aktivierung klein dekodiert. Fehlerseiten oder beschädigte Downloads können dadurch kein funktionierendes Hintergrundbild überschreiben.

## YouTube

- Download- und Konvertierungsjobs prüfen Eingaben, Arbeitsordner, Schreibrechte, leere Quelldateien sowie fehlerhafte Prozessausgaben defensiv.
- BWR-Videos werden zunächst als temporäre Datei geschrieben und erst nach erfolgreichem Abschluss atomar in die Bibliothek verschoben. Abgebrochene Konvertierungen erscheinen somit nicht als spielbare Videos.
- Hintergrundprozesse, Encoder, Pipes und Bibliotheksscans behandeln Fehler kontrolliert statt die DApp zu beenden.

## Lockscreen

- Der Lockscreen wurde als ruhige, kontrastreiche E‑Ink-Oberfläche neu gestaltet: Uhrzeit, Status, Profilkarte und klar erkennbare PIN-/Muster-/Wischaktion.
- Lokale Profilbilder bleiben optional. Der Screen schützt weiterhin **nur AppDock**, nicht die Gerätespeicherung.

## DuckDuckGo und Files

- Die Homescreen-Suche ruft nun die **DuckDuckGo-JSON-API** auf und rendert ausschließlich sichere Instant-Answer-Links, statt eine Suchergebnis-Webseite zu laden.
- „Sort my files“ scannt jeden Ordner nur einmal, überspringt Symlinks, behält die Dateipfade unverändert und gruppiert Dateien stabil nach Kategorie und Name.

## Enthaltene DApp-Updates

- **AI Chat Agent 1.5.3:** lokale Runtime-Dateien werden anhand exakter Größe und ELF-Kennung geprüft; der POSIX-Launcher setzt `LD_LIBRARY_PATH`, verwendet sichere Exit-Marker und startet mit eindeutigen Arbeitsdateien.
- **Geometry Dash 1.0.3:** vier auswählbare Levels, Warm-up als leichter Start, reduziertes Tempo sowie weniger hohe Plattformen und Dreifachspikes.

## Validierung

- Lua-Syntaxprüfung aller DApps und AppDock-Module.
- Regressionstests für Browser, Themes, Files-Sortierung, YouTube-Konvertierung, DApp-Integration, AI-Chat-Download/Runtime und Geometry-Dash-Level.
