# AppDock 7.9.6 — Gleichmäßigere Videowiedergabe

## Fehlerkorrektur

- Wenn die Wiedergabe durch einen langsamen Frame hinterherhinkt und der Player zu einem späteren Frame springt, setzt der BWR2/BRC2-Reader seine Decodierung innerhalb derselben Keyframe-Gruppe jetzt beim letzten zwischengespeicherten Frame fort. Zuvor begann er bei solchen Vorwärtssprüngen erneut am Gruppen-Keyframe und decodierte bereits verarbeitete Frames nochmals. Das kann zusätzliche, schwankende Arbeit beim Aufholen verursachen.
- Dateiformat, fünf reine Farben und Audio-/Video-Taktung bleiben unverändert.

## Prüfung

Alle 12 Lua-Regressionsdateien liefen erfolgreich; alle Lua-Quelldateien ließen sich mit LuaJIT kompilieren, und `git diff --check` ist sauber. Ein neuer Regressionstest prüft einen Vorwärtssprung innerhalb einer Keyframe-Gruppe und stellt sicher, dass keine bereits decodierten Pakete erneut gelesen werden. Eine reale Kobo-Bildwiederholrate wurde nicht gemessen.
