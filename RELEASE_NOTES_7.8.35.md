# AppDock 7.8.35

## YouTube-Audio-/Video-Synchronisation

Die unveränderte Raw-PCM-Audiopipeline aus AppDock 7.8.26 bleibt erhalten. Der Player wartet nun auf das tatsächliche GStreamer-Signal `New clock:` des MTK-Audio-Sinks, bevor er das erste Videobild startet.

Damit wird nicht mehr mit einer festen Verzögerung geraten: Das Video startet anhand des real gemeldeten Audio-Clock-Starts. Wenn eine Kobo-Firmware dieses optionale Logsignal nicht ausgibt, bleibt die Audioausgabe aktiv und der Player startet nach dem Fallback-Timeout.
