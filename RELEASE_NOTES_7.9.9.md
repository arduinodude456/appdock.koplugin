# AppDock 7.9.9

## Weniger Speicher für YouTube-Audio

Die YouTube-DApp erzeugt neue Begleit-Audiospuren nun mit **22,05 kHz mono** statt 44,1 kHz stereo. Die Datei bleibt unkomprimiertes, gut unterstütztes PCM-WAV und funktioniert weiterhin mit dem AppDock-Player, inklusive Zeitabgleich und Such-/Sprungfunktion. Durch die halbe Abtastrate und nur einen Kanal benötigt die WAV-Spur rund **75 % weniger Speicherplatz** (44,1 kB/s statt 176,4 kB/s).

Die BWR2/BRC2-Videodaten, Bildrate und Auflösung bleiben unverändert. Bereits vorhandene Videos und WAV-Dateien werden nicht automatisch verändert; die Ersparnis gilt für neu konvertierte Videos.

Ein echter FFmpeg-Regressionstest prüft WAV-Abtastrate, Mono-Kanalzahl und die erwartete maximale Dateigröße.
