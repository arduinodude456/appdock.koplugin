# AppDock 8.2.9

## Transparenz auf Kobo Libra Colour korrigiert

Element-Hintergründe werden nicht mehr über einen Alpha-Kanal in `ColorRGB32` gezeichnet. Stattdessen erstellt der Renderer einen opaken temporären Hintergrundpuffer und mischt ihn mit KOReaders `addblitFrom(..., opacity)` in den bereits gerenderten Sleepscreen-Puffer. Dadurch funktioniert `background_alpha` auch auf dem Kobo Libra Colour zuverlässig.

Der Fix betrifft sowohl die Live-Vorschau im Editor als auch den aktiven Sleepscreen. Ein Regressionstest prüft den tatsächlichen `addblitFrom`-Pfad.
