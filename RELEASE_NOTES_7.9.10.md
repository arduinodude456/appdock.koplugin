# AppDock 7.9.10

## YouTube-Farbvideos mit Mehrfarben-Fehlerdiffusion

Die Farbkonvertierung mischt nun über benachbarte Pixel mehr als zwei der fünf erlaubten Palettefarben. Zuvor wurde für jeden Quellpixel unabhängig nur das beste Farbpaar ausgewählt; Farbreste wurden nicht an Nachbarpixel weitergegeben. Ein serpentinischer Floyd–Steinberg-Schritt diffundiert diese Reste jetzt räumlich, sodass passende Bildbereiche beispielsweise Schwarz, Rot und Grün gemeinsam nutzen können. Die tatsächlichen Ausgabepixel bleiben weiterhin exakt Weiß, Schwarz, Rot, Grün oder Blau.

Die Palette begrenzt weiterhin den darstellbaren Farbumfang: Farben außerhalb ihres Mischbereichs – etwa leuchtendes Vollgelb – können nur angenähert werden, nicht exakt dargestellt werden.

## Audio endet beim Verlassen der App

AppDock signalisiert nun direkt die PID des laufenden GStreamer-Players, statt sich auf die möglicherweise abweichende Prozessgruppen-PID von `setsid` zu verlassen. Dadurch wird die Wiedergabe beim Verlassen der YouTube-App zuverlässig gestoppt; der PCM-Datenlieferant beendet sich anschließend ebenfalls.

## Validierung

Alle 12 Lua-Regressionstests bestehen; die Lua-Module kompilieren mit LuaJIT. Neue Farbtests prüfen eine tatsächliche Dreifarbmischung aus Schwarz, Rot und Grün.
