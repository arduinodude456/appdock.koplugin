# AppDock 7.9.5 — Flüssigere Videowiedergabe

## Optimierung

- Der Player zieht die bereits verbrauchte Frame-Verarbeitungszeit jetzt vom nächsten Warteintervall ab. Zuvor begann das volle Intervall erst nach Dekompression, Frame-Erweiterung und Zeichnen; diese Zeit addierte sich pro Frame und senkte die effektive Framerate.
- Der Video-Framebuffer wird während der Wiedergabe wiederverwendet, statt pro Frame freigegeben und neu angelegt zu werden. Das reduziert große Speicherallokationen und Kopier-/Allocator-Aufwand bei Farb- und Schwarzweißvideos.
- Die BRC2-Farbpalette und die Anzeige der fünf reinen Farben bleiben unverändert. Die tatsächlich erreichbare Framerate hängt weiterhin von Geräteleistung und E-Ink-Aktualisierung ab.

## Prüfung

Alle 12 Lua-Regressionsdateien liefen erfolgreich; alle Lua-Quelldateien ließen sich mit LuaJIT kompilieren, und `git diff --check` ist sauber. Neue Tests prüfen die wiederverwendeten Framebuffer und dass Renderzeit vom nächsten Frameintervall abgezogen wird. Eine reale Kobo-Bildwiederholrate wurde in der Sandbox nicht gemessen.
