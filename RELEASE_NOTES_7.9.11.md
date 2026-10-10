# AppDock 7.9.11

## Deutlich schnellere YouTube-Farbkonvertierung

Die Farbpackung ersetzt die pixelweise Fehlerdiffusion durch vorberechnete 8×8-Muster. Dadurch muss Lua pro Pixel keine drei Farbfehler mehr berechnen und weitergeben. Farben innerhalb des darstellbaren Palettenbereichs können weiterhin mit mehreren – bei Bedarf allen fünf – exakten Farben Weiß, Schwarz, Rot, Grün und Blau gemischt werden. Neutrale Grautöne und Farben außerhalb des Palettenbereichs behalten die bisherige Paarzuordnung.

Das neue geordnete Muster ersetzt die serpentinische Floyd–Steinberg-Textur durch ein regelmäßiges 8×8-Dithermuster. Im isolierten LuaJIT-Benchmark der Farbpackstufe sank die Bearbeitungszeit eines 632×840-Frames in der Entwicklungsumgebung von 28,9 ms auf 1,1 ms (25,6× schneller, nach einmaligem Aufbau der Lookup-Tabellen). Das ist kein End-to-End-Wert für Download, FFmpeg-Decodierung und Dateischreiben; deren Laufzeit hängt weiterhin von Quelle und Gerät ab.

## Lesbare Draw-Werkzeugleiste

Die Mal-App verwendet jetzt KOReaders natives Button-Widget statt selbst gezeichneter Kleinstbeschriftungen. Größere, fette Schrift auf einer hellgrauen Fläche verbessert den Kontrast; die Werkzeugaktionen und Touchbereiche bleiben erhalten.

## Validierung

Alle 12 Lua-Regressionstests bestehen; alle Plugin-Lua-Module kompilieren mit LuaJIT. Der DApp-Test meldet zusätzlich, dass sein optionales externes BWR-Video-Fixture in dieser Umgebung nicht installiert ist.
