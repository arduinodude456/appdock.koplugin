# AppDock 7.8.32

## YouTube-Audio und Videostart

AppDock verwendet wieder den sofortigen, parallelen Audio-/Videostart aus Version 7.8.27. Die blockierende GStreamer-Startwartephase wurde entfernt, weil sie auf bestimmten Kobo-Geräten die Audioausgabe verhindert hat.

Zusätzlich gibt es in den YouTube-Einstellungen **Video start delay**. Damit lässt sich festlegen, wie viele Sekunden nach dem Audiostart das Video beginnen soll. Verfügbare Werte sind **sofort**, **0,1**, **0,25**, **0,5**, **1** und **2 Sekunden**.

Die bestehende Laufzeitkalibrierung für kleine Unterschiede zwischen BWR-Video und Companion-WAV bleibt erhalten.
