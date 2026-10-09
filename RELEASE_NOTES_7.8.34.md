# AppDock 7.8.34

## YouTube-Audio-/Video-Synchronisation

Diese Version basiert auf der funktionierenden Audioausgabe von AppDock 7.8.26. Die Raw-PCM-GStreamer-Pipeline bleibt unverändert.

Ergänzt wurde ausschließlich eine Laufzeitkalibrierung: Kleine Unterschiede zwischen der BWR-Videolänge und der Companion-WAV-Länge werden beim Videotakt berücksichtigt. Audio startet weiterhin sofort parallel zum Video; es gibt keine GStreamer-Startwartephase.
