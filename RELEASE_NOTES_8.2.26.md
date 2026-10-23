# AppDock 8.2.26 — Shorts Playback und Ladefortschritt

## Behoben

- Shorts-Playback aktualisiert jetzt den tatsächlich gerenderten Canvas als Dirty-Widget. Dadurch werden neue BWR-Frames auf KOReader-Geräten zuverlässig sichtbar, statt auf dem ersten Bild stehenzubleiben.
- Playback-Fehler und fehlende, noch nicht fertige BWR-Dateien werden direkt im Shorts-Pane erklärt.
- Der Ladefortschritt ist jetzt als verständlicher Ablauf sichtbar: Suche, Download/Konvertierung und Audio-Extraktion werden mit Status und Prozentwert angezeigt.
- Schnelle Shorts-/Player-Refreshes erzwingen keinen globalen Voll-Repaint mehr. Das reduziert Flackern, vermeidet Refresh-Konflikte und verbessert E-Ink-Animationen.

## Prüfung

Die vollständige UI-Regression mit `bash scripts/test_appdock_ui.sh` ist erfolgreich durchgelaufen. Zusätzlich wurden alle installierbaren Lua-Dateien auf Syntaxfehler geprüft.
