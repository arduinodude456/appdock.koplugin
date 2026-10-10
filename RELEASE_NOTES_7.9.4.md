# AppDock 7.9.4 — Farbvideo-Wiedergabe beschleunigt

## Optimierung

- Die Expansion von BRC2-Farbframes arbeitet jetzt mit vorberechneten `ColorRGB32`-Paletteneinträgen und liest Indizes direkt über FFI. Damit entfallen die Lua-String-Abfrage und die Erzeugung eines Farb-Structs für jeden einzelnen Pixel. Die fünf exakten Palettenfarben sowie der Graustufen-Fallback bleiben unverändert.

## Prüfung

Alle 12 Lua-Regressionsdateien liefen erfolgreich; alle Lua-Dateien ließen sich mit LuaJIT kompilieren, und `git diff --check` ist sauber. Ein kontrollierter Sandbox-Mikrobenchmark der Expansion für 632×840 Pixel sank von ca. 123 ms auf ca. 1,08 ms pro Frame. Das misst ausschließlich die Frame-Expansion auf dem Sandbox-System, nicht die tatsächliche Bildwiederholrate eines Kobo-Geräts.
