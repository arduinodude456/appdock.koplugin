# AppDock 7.9.1 — YouTube MiniPlayer, schnellere Farbe und Draw-Kachel

## Änderungen

- **YouTube-Oberfläche:** Stellt das Watch-Layout aus 7.8.51 wieder her. Videos aus der Bibliothek und „Up next“ öffnen standardmäßig im MiniPlayer; Vollbild bleibt über die ausdrückliche Vollbild-Aktion verfügbar.
- **Schnellere Farbumwandlung:** Der optionale Fünf-Farben-Pfad nutzt vor der Palette-Ditherung FFmpegs `fast_bilinear`-Scaler statt des rechenintensiveren Lanczos-Filters. Auflösung und Bildrate bleiben unverändert; die Ausgabe enthält weiterhin ausschließlich reines Rot, Grün, Blau, Schwarz und Weiß. Der schnellere Skalierer kann etwas weniger fein wirken.
- **Draw in Quick Settings:** Eine semantisch gezeichnete Draw-Kachel startet die integrierte Mal-DApp. Sie ist konfigurierbar und auch im Simple Mode verfügbar. Bestehende Kachel-Listen erhalten Draw einmalig; nach einer bewussten Entfernung wird die Kachel nicht automatisch wieder hinzugefügt.
- Die Wiedergabe-Timing-Verbesserung aus 7.9.0 bleibt erhalten; Änderungen an der MiniPlayer-UI setzen das unmittelbare Video-Startverhalten nicht zurück.

## Prüfung

Alle 11 Lua-Regressionsdateien liefen erfolgreich; sämtliche AppDock-Lua-Quelldateien ließen sich mit LuaJIT kompilieren und `git diff --check` meldete keine Formatfehler. Ein lokaler synthetischer FFmpeg-Skalierungstest (1280×720 → 600×800, 12 fps, 12 Sekunden) lief mit `fast_bilinear` in 0,174 s gegenüber 0,228 s mit Lanczos (rund 24 % schneller auf dieser Sandbox-CPU; tatsächliche Reader-Hardware kann abweichen).
